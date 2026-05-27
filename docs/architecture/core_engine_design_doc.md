# Discord Gateway & Ingestion Engine Design Document (Pub/Sub Architecture)

This document defines the architectural design for the core engine of Climatomaton. It details the internal event-driven architecture using an in-memory Pub/Sub broker for decoupled, non-blocking component communication within a single Python container process. The design preserves the shared filesystem volume as the external integration contract while enforcing a strict synchronous initialization phase to guarantee state integrity before real-time event routing begins.

---

## 1. Internal Pub/Sub Broker Specification

The core runtime engine utilizes an asynchronous, in-memory Pub/Sub broker (`InternalEventBroker`) implemented natively in Python using `asyncio`. Components register as anonymous subscribers to specific string-based topics. The broker maintains a thread-safe registry of asynchronous callback routines and handles task scheduling without exposing component instances to one another.

### Defined Core Event Topics

* **`bot/inbound_traffic`**: Carries raw, unverified `DiscordMessage` objects harvested by the gateway.
* **`engine/command_trigger`**: Carries validated, fully normalized `CommandPayload` objects.
* **`engine/proposal_report`**: Carries validated `ProposalReport` objects derived from channel traffic.
* **`engine/state_mutation`**: Carries mutated `ClimateState` snapshots post-execution to trigger disk synchronization.

---

## 2. Encapsulated System Data Objects

To guarantee safe data transit across the Pub/Sub bus and enforce strict Object-Oriented principles, data structures are fully encapsulated. External components never parse text into these objects; instantiation logic, validation rules, and regex pattern matching reside exclusively within the objects' own factory methods.

### `DiscordMessage`

* **State:** `message_id` (str), `channel_id` (str), `author_id` (str), `raw_content` (str), `is_direct_message` (bool).
* **Instantiation:**
* `@classmethod from_gateway_payload(cls, json_payload: dict) -> 'DiscordMessage'`: Parses raw Discord WebSocket payloads into a standardized message object.


* **Methods:**
* `is_from_authorized_admin(self, admin_list: list) -> bool`: Verifies identity against configuration.



### `ProposalReport`

* **State:** `turn` (int), `count` (int), `passed` (int), `failed` (int).
* **Instantiation:**
* `@classmethod try_parse(cls, raw_content: str) -> 'ProposalReport' | None`: Encapsulates the specific regex required to identify a proposal report. Returns `None` if the string does not match the strict layout. Throws a `ValueError` if metrics contain negative numbers.


* **Methods:**
* `is_turn_one(self) -> bool`: Evaluates boundary collision logic.
* `get_metrics_graph(self) -> dict`: Returns an immutable dictionary mapping directly to the `proposals` memory namespace (`count`, `passed`, `failed`).



### `ClimateState`

* **State:** `value` (float), `tags` (Set[str]).
* **Instantiation:**
* `@classmethod try_parse_anchor(cls, raw_content: str) -> 'ClimateState' | None`: Encapsulates the regex logic required to find historical anchors matching the signature: `"The climate is now X and is Y"`.


* **Methods:**
* `mutate(self, new_value: float, new_tags: Set[str]) -> None`: Performs in-memory state modifications.
* `generate_report_string(self) -> str`: Formats the plain-English grammar report matching the active state.



### `CommandPayload`

* **State:** `intent` (Enum: `REPROCESS`, `RESET`), `arguments` (Dict[str, str]).
* **Instantiation:**
* `@classmethod parse_from_input(cls, raw_tokens: list) -> 'CommandPayload'`: Evaluates a string array sequentially. Maps array indexes to named parameters, interprets the hyphen (`-`) placeholder token as an intentionally omitted optional parameter, and explicitly handles the literal string `default` within the `value` argument.



---

## 3. System Initialization & State Recovery (The Startup Gate)

To prevent race conditions between incoming live traffic and historical state recovery, the system enforces a strict, synchronous lifecycle phase known as the Startup Gate. The `StateBootstrapper` operates entirely independently of the Pub/Sub broker and must complete its execution before the real-time event loop is permitted to start.

### Component: `StateBootstrapper`

* **Role:** Synchronously reconstructs baseline memory states upon container initialization, acting as a blocking gateway.
* **The Synchronous Workflow:**
1. **Process Launch:** The container starts and executes the initialization sequence.
2. **Historical Lookback (Blocking):** The bootstrapper executes backward chronological HTTP REST queries (`GET /channels/{channel_id}/messages`) to fetch historical channel message blocks.
3. **Anchor Resolution:**
* If a `ClimateState` anchor matches via `ClimateState.try_parse_anchor()`, it captures the state.
* If a `ProposalReport` matches via `ProposalReport.try_parse()`, it checks `report.is_turn_one()`. If True, it signifies a round boundary collision; the lookback terminates and defaults to a baseline state (`value = 0`, `tags = []`). If False, it explicitly ignores the report (applying no state updates) and continues scanning backward.


4. **Memory Hydration:** The verified state is written permanently into the engine's core memory reference.
5. **Termination:** The `StateBootstrapper` terminates.
6. **Broker Unlock:** Only after step 5 is the `InternalEventBroker` instantiated, and the real-time networking components (Gateway, Ingestion) are spawned to begin processing live traffic.


* **Error Handling:**
* *History Isolation Failure / Network Loss:* If the API is unreachable during this synchronous phase, the system logs a `CRITICAL` boot initialization error to the terminal and forces a process death (`sys.exit(1)`). The engine refuses to start without a verified state.



---

## 4. Component Architecture & Event Routing Layer

Once the Startup Gate concludes, the following components are instantiated. They exist as fully isolated entities that interact with the application solely by publishing to or subscribing from the `InternalEventBroker`.

```text
[Discord Network]
       │ (WebSocket)
       ▼
┌──────────────────────────────┐
│   DiscordGatewayConnector    │
└──────────────┬───────────────┘
               │ (Publish)
               ▼ Topic: bot/inbound_traffic
 🔔  [InternalEventBroker] 🔔
       │               │
       ├───────────────┼──────────────────────────────┐
       │ (Subscribe)   │ (Subscribe)                  │
       ▼               ▼                              │
┌──────────────┐┌──────────────┐                      │
│ProposalFilter││CommandIngest │                      │
│    Engine    ││   Wrapper    │                      │
└──────┬───────┘└──────┬───────┘                      │
       │               │                              │
       │ (Publish)     │ (Publish)                    │
       │ engine/       │ engine/                      │
       │ proposals     │ commands                     │
       ▼               ▼                              │
 🔔  [InternalEventBroker] 🔔                         │
       │               │                              │
       └───────┬───────┘                              │
               │ (Subscribe - Prefetch 1)             │
               ▼                                      │
┌──────────────────────────────┐                      │
│      TransactionManager      │                      │
└──────────────┬───────────────┘                      │
               │ (Publish) Topic: engine/state_mutation
               ▼                                      │
 🔔  [InternalEventBroker] 🔔                         │
       │                                              │
       ▼ (Subscribe)                                  │
┌──────────────────────────────┐              ┌───────┴──────────────────────┐
│    NotificationDiskWriter    │              │        OutboxIPCWorker       │
└──────────────┬───────────────┘              └──────────────┬───────────────┘
               │ (Atomic Write)                              │ (Poll)
               ▼                                             ▼
       [Shared Volume: outbox/] ◄────────────────────────────┘
               │
               ▼ (Stateless POST)
        [Discord REST API]

```

### Component: `DiscordGatewayConnector`

* **Role:** Manages the persistent inbound network stream via a dedicated Python `asyncio` task.
* **Workflow:** Establishes the WebSocket connection with required intents (`GUILD_MESSAGES`, `MESSAGE_CONTENT`). Upon capturing a `MESSAGE_CREATE` or `INTERACTION_CREATE` event, it invokes `DiscordMessage.from_gateway_payload()` and immediately executes `broker.publish("bot/inbound_traffic", message)`. It returns instantly to process heartbeats.
* **Error Handling:**
* *Network Timeout/Drop:* Catches WebSocket exceptions and initiates standard exponential backoff reconnect loops.
* *Invalid Gateway Token (HTTP 401):* Logs a `CRITICAL` traceback directly to stderr and issues a process termination code to trigger a Docker restart.



### Component: `ProposalFilterEngine`

* **Role:** Non-blocking asynchronous sieve for public channel conversation.
* **Workflow:** Subscribes to `bot/inbound_traffic`. Evaluates every incoming message payload. If `message.is_direct_message` is False and `message.channel_id` matches the configured public target, it invokes `ProposalReport.try_parse(message.raw_content)`. If a valid object is returned, it executes `broker.publish("engine/proposal_report", report)`.
* **Error Handling:**
* *Regex Parse Failure:* Discards messages silently when `try_parse` returns `None`.
* *Validation Boundary Failure (`ValueError`):* Logs a `WARNING` indicating a malformed proposal format with negative values, logs the offending message ID, and discards the task.



### Component: `CommandIngestionWrapper`

* **Role:** Ingests and normalizes administrative inputs.
* **Workflow:** Subscribes to `bot/inbound_traffic`.
* *Slash Commands:* Intercepts UI interactions targeting the registered `/climate` slash command, strips the prefix, and maps options into an ordered token list.
* *Direct Messages:* Intercepts private DMs. Validates access using `message.is_from_authorized_admin()`. Tokenizes the raw content string by spaces.
* Both pipelines deliver the parsed string list to `CommandPayload.parse_from_input()` and publish the resulting object to `engine/command_trigger`.


* **Error Handling:**
* *Unauthorized Command Attempt:* Drops the message immediately and publishes an audit warning to the system terminal.
* *Invalid Syntax Exception:* Catches formatting issues, halts execution, and generates a direct message response back to the author containing a plain-text usage manual.



### Component: `TransactionManager`

* **Role:** Serialized coordinator of the game engine's transaction processing cycle.
* **Workflow:** Subscribes to both `engine/proposal_report` and `engine/command_trigger`. To guarantee thread safety and eliminate race conditions, the broker delivers these messages sequentially (using a prefetch serialization lock).
* *Phase 0 (Rehydration):* Evaluates the active directory path from the relative `rules.commit` file on the shared volume. Reads compiled `.json` modules into a read-only environment graph.
* *Phase 1 & 2 (Evaluation & Mutation):* Evaluates rules compiled from the active target directory in strict numeric order. Conditionals are evaluated against the read-only graph. Successful actions write mutations to a temporary `new` namespace buffer.
* *Commitment:* Invokes the active `ClimateState.mutate()` method with the updated buffer values and publishes the final snapshot to `engine/state_mutation`.


* **Error Handling:**
* *Rule Evaluation/Runtime Exceptions:* If any failure occurs (e.g., namespace path resolution error, divide-by-zero), it catches the exception, logs the precise Rule ID and triggering message payload, fully discards the temporary `new` buffer, and aborts all rule processing. No default values are written to memory.



### Component: `NotificationDiskWriter`

* **Role:** Decouples disk-writing operations from the transaction execution loop.
* **Workflow:** Subscribes to `engine/state_mutation`. Upon message receipt, it converts the mutated state and plain-English report string into a structured JSON notification payload. It exports this payload to the `outbox/` directory on the shared volume using the strict **Atomic File Update Protocol** (`Serialize` to `.tmp` $\rightarrow$ `Flush` via `fsync()` $\rightarrow$ `Rename`).
* **Error Handling:**
* *Disk I/O / Permissions Block:* Logs an `ERROR` to the container terminal if write access is denied. Retries the operation with exponential backoff, holding the message in the broker queue until successful.



### Component: `OutboxIPCWorker`

* **Role:** Background worker handling asynchronous outbound Discord REST communications.
* **Workflow:** Operates completely independently of the internal broker's topics. Continually polls the shared volume's `outbox/` directory. Collects payload files, sorts them alphabetically to enforce chronological order, and transmits them to the Discord REST endpoint via stateless HTTP POST calls.
* **Error Handling:**
* *Rate Limiting (HTTP 429):* Extracts the `Retry-After` window, suspends the polling routine, and leaves the target file on disk to preserve state.
* *Stale File Pruning:* Inspects file creation timestamps. If a file is older than 1 hour or if the queue depth exceeds a configured maximum limit, the file is unlinked, and a warning is logged to prevent stale notification bursts.
* *Verified Delivery:* Calls an OS-level file `unlink()` only after an HTTP `200 OK` is returned from Discord.
