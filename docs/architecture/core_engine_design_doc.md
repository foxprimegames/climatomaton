That clarification completely validates your earlier concerns and perfectly highlights why the separation of concerns in the architecture is strictly necessary, even with a low event-execution frequency.

Even if the *game logic* only fires once a week, the **Gateway** is operating in a live, noisy environment 24/7. If the Gateway and the parsing logic were tightly coupled, a sudden burst of regular conversation in the public channel could monopolize the execution thread and choke out the WebSocket heartbeat.

Here is how the event-loop architecture gracefully handles that specific "chatter" reality:

### The Asynchronous Sieve

1. **The Scoop:** The `DiscordGatewayConnector` receives a burst of 10 random chat messages. It does no evaluation; it simply wraps them in `DiscordMessage` objects and dispatches them to the runtime's event loop instantly. The Gateway goes right back to listening.
2. **The Sieve:** The `ProposalFilterEngine` picks up those tasks in the background. Its only job is to run the `ProposalReport.tryParse()` regex against the text.
3. **The Drop:** For 99.9% of that constant traffic, the regex instantly fails. The `ProposalFilterEngine` silently drops the object. Memory is freed, and the event loop moves on.

Because the runtime scheduler manages this handoff, the Gateway remains entirely shielded from the volume of the chatter. The core `TransactionManager` remains completely dormant, consuming zero CPU until the `ProposalFilterEngine` finally hits that one-in-a-week positive regex match and wakes it up.

This setup gives you the exact resilience you need: it processes the constant low-level noise without dropping the network connection, and it isolates the heavy mathematical lifting for when it actually matters.

With the Gateway, Ingestion, and Execution pipelines now fully aligned with your actual traffic reality, are you ready to move on to the next design document on your list, or are there any other edge cases in the Core Engine you want to pressure-test first?
