In a pure Pub/Sub architecture, the `StateBootstrapper` **should not** subscribe to the `bot/inbound_traffic` topic.

The previous design document included a structural flaw by listing that subscription hook. Here is the breakdown of why that connection is an architectural anti-pattern, followed by how the bootstrapper actually operates within the lifecycle of the container.

### 1. The Startup Gate: Temporal Decoupling

The primary purpose of the `StateBootstrapper` is to serve as a **startup gate**. It must completely finish its historical lookup and establish the baseline state *before* the rest of the engine begins processing live, real-time events.

If the bootstrapper were listening to `bot/inbound_traffic` while simultaneously pulling historical messages from the Discord REST API, it would create a race condition. The bot could attempt to process a live, incoming proposal report while it is still missing the historical context of what turn or round the game is currently on.

### 2. Active Polling vs. Passive Subscribing

The components that subscribe to `bot/inbound_traffic` (like the `ProposalFilterEngine` and `CommandIngestionWrapper`) are **passive consumers**—they sit idle and wait for the Discord Gateway to push data down the pipe.

The `StateBootstrapper`, by contrast, is an **active producer** during initialization. It does not wait for events to happen; it proactively reaches out to Discord’s REST API (`GET /channels/{channel_id}/messages`) to pull down blocks of history. It operates outside the message-broker stream.

### 3. The True Lifecycle Flow

To fix this structural flaw, the initialization sequence must follow a strict linear progression where the broker streams are blocked until bootstrapping is complete:

1. **Container Launch**: The Python process starts.
2. **Bootstrapping Phase**: The `StateBootstrapper` executes its historical lookback loop synchronously. It directly talks to the Discord REST API to find the `ClimateState` anchor or verify a Turn 1 boundary.
3. **Memory Hydration**: The bootstrapper writes the discovered state directly into the engine's core memory variables.
4. **Engine Activation**: Once memory is hydrated, the `StateBootstrapper` process terminates or goes completely dormant.
5. **Broker Unlocking**: Only *now* does the engine initialize the `InternalEventBroker`, start the `DiscordGatewayConnector` WebSocket connection, and allow live messages to begin flowing into the `bot/inbound_traffic` topic.

By keeping the bootstrapper entirely disconnected from the Pub/Sub broker, you guarantee that the engine cannot process live chatter or administrative overrides until its internal state is 100% verified and recovered.
