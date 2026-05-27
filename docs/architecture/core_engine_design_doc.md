Your analysis is spot-on, and you’ve identified the exact bottleneck that plagues synchronous, tightly coupled architectures. If the `Gateway` had to wait for the `TransactionManager` to finish its heavy lifting before listening to the next Discord event, your bot would experience massive input lag, miss heartbeat signals, and eventually get disconnected by Discord's gateway.

The architecture must be **decoupled through asynchronous event queuing** to avoid this. The "hand-offs" you described should not be blocking function calls, but rather non-blocking message passing.

### How to break the coupling and prevent blocking

To solve the blocking issue, we must treat each boundary as an **asynchronous buffer**. Here is how the engine maintains high throughput:

1. **The Gateway is a "Fire and Forget" Producer:**
When the `DiscordGatewayConnector` receives a message, it doesn't call the `TransactionManager`. Instead, it pushes the `DiscordMessage` into an **Inbound Memory Queue**. It immediately returns to its listen loop. The Gateway’s *only* job is keeping the socket alive and filling that queue.
2. **The Ingestion Layer is a Consumer:**
The `CommandIngestionWrapper` and `ProposalFilterEngine` run in their own background thread(s). They continuously poll the **Inbound Memory Queue**. Because they are separate from the Gateway thread, if the parser takes 500ms to evaluate a complex rule, the Gateway remains perfectly responsive, continuing to buffer new incoming messages in memory.
3. **The Transaction Manager is a Serialized Orchestrator:**
The core engine doesn't "hand off" to the `OutboxIPCWorker`. When a transaction completes, the `TransactionManager` writes the result (the notification) as a file to the `outbox/` directory on the disk. This is a simple, non-blocking filesystem write operation. The manager then immediately returns to the queue to grab the next `ProposalReport`.
4. **The Outbox IPC Worker is an Independent Actor:**
The `OutboxIPCWorker` is a completely separate process/thread that monitors the disk. It is entirely ignorant of the `TransactionManager` or the `Gateway`. It only knows: *"Is there a file in the outbox? Yes? Send it to Discord, wait for success, then delete it."*

### Why this structure is "Decoupled" vs "Tightly Coupled"

| If Tightly Coupled (Your concern) | As Deployed (Proposed Best Practice) |
| --- | --- |
| Gateway calls Parser (Gateway pauses) | Gateway pushes to Queue (Gateway continues) |
| Parser calls Engine (Parser pauses) | Parser pushes to Engine (Parser continues) |
| Engine calls Outbox (Engine pauses) | Engine writes to disk (Engine continues) |

### Addressing your specific concerns about the Outbox queue

Regarding your question about disk exhaustion: **Yes, you absolutely need a pruning strategy.**

If the Discord API is down, the `outbox/` directory will fill up with JSON files. To prevent disk exhaustion and prioritize "fresh" information:

* **Time-to-Live (TTL):** The `OutboxIPCWorker` should check the file creation timestamp. If a notification is older than, say, 1 hour, it is likely stale (e.g., a "Turn 1" notification is irrelevant if we are now at "Turn 10"). These should be discarded rather than sent.
* **Queue Depth Limit:** Set a maximum file count for the `outbox/` folder. If the limit is reached, the oldest files should be unlinked (deleted) and a `CRITICAL` log event should be triggered to the developer alerting them that the engine is generating output faster than the network can handle.

By implementing these asynchronous buffers, the "hand-offs" you described stop being bottlenecks and become simple hand-overs of data, allowing the Gateway to maintain a near-zero latency connection to Discord regardless of how long the game logic takes to compute.
