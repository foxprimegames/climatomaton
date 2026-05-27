# Discord Gateway & Ingestion Engine Design Document

This document defines the architectural implementation for the Discord Gateway & Ingestion Engine. It outlines the isolated components responsible for interfacing with the Discord network, parsing inbound commands, managing execution state recovery, and dispatching outbound asynchronous notifications.

To maintain strict separation of concerns, the system is divided into discrete, specialized modules communicating via strongly typed, encapsulated data objects.

---

## 1. System Data Objects (OOP Encapsulation)

To guarantee safe data transit between isolated processing components and the execution pipeline, all shared data is encapsulated into strictly typed, object-oriented structures. These objects encapsulate their validation logic and expose read-only properties to prevent state mutation during transit.

* **`DiscordMessage`**: Encapsulates raw inbound Discord message data.
* *Properties*: `MessageID` (Snowflake), `ChannelID` (Snowflake), `AuthorID` (Snowflake), `RawContent` (String), `IsDirectMessage` (Boolean).
* *Methods*: `getAuthorIdentity()`, `isFromAuthorizedAdmin(adminList)`.


* **`ProposalReport`**: Represents a validated, parsed set of proposal metrics.
* *Properties*: `count` (Integer), `passed` (Integer), `failed` (Integer).
* *Methods*: `getMetrics()` (Returns an immutable dictionary mapping to the `proposals` namespace), `isValid()` (Validates no negative integers).


* **`CommandPayload`**: Encapsulates the fully resolved intent of an administrative command, divorced from its original UI origin (Slash or DM).
* *Properties*: `CommandType` (Enum: `REPROCESS`, `RESET`), `PositionalArgs` (Array of Strings).
* *Methods*: `getArgumentAt(index)`, `hasArgument(index)`.


* **`ClimateState`**: The strictly encapsulated memory anchor for the active engine.
* *Properties*: `value` (Float), `tags` (Set of Strings).
* *Methods*: `updateState(newValue, newTags)`, `getSnapshot()` (Returns an immutable copy of the state for the rules pipeline).



---

## 2. Gateway Connection & Channel Monitoring Infrastructure

**Component:** `DiscordGatewayConnector`

This component manages the persistent inbound data stream from the Discord network. It is explicitly responsible for maintaining the WebSocket lifecycle and routing inbound events to the appropriate ingestion layers.

* **Connection Management:** Initiates the connection, handles gateway heartbeats, and automatically manages session resumes or reconnects upon network interruption.
* **Intent Declaration:** Authenticates with the required Privileged Gateway Intents (`GUILD_MESSAGES`, `MESSAGE_CONTENT`) to ensure the bot can actively monitor message strings in the designated public game channel.
* **Event Routing:** Operates purely as a dispatcher. It does not parse game logic. It intercepts `MESSAGE_CREATE` and `INTERACTION_CREATE` events, maps them into `DiscordMessage` objects, and pushes them to either the `CommandIngestionWrapper` or the `ProposalFilterEngine`.

---

## 3. Discord Command Registration & Ingestion Layer

**Component:** `CommandIngestionWrapper`

This layer normalizes administrative inputs from vastly different Discord UI features into a single, standardized format.

* **Global Registration:** Executes the one-time Discord REST API calls during startup to globally register the `/climate` slash command and its nested subcommands (`reprocess`, `reset`) with the Discord UI.
* **Slash Command Ingestion (`INTERACTION_CREATE`):** Intercepts native UI slash commands (e.g., `/climate reset value:10`). It strips the `/climate` prefix and extracts the named UI options into a sequential string array.
* **Direct Message Ingestion (`MESSAGE_CREATE`):** Intercepts private DMs from authorized administrators. It validates the `AuthorID` against the injected environment configuration. It expects no command prefix (e.g., `reset 10`) and tokenizes the raw text by space delimiters.
* **Normalization:** Both flows output a clean array of strings (e.g., `["reset", "10"]`) which is passed synchronously to the Unified Command Parser.

---

## 4. Inbound Proposal Ingestion

**Component:** `ProposalFilterEngine`

This component is dedicated to silently monitoring the public game channel and intercepting valid mechanical triggers.

* **Pattern Matching Pipeline:** Subscribes to the `DiscordGatewayConnector`. For every `DiscordMessage` originating from the target channel, it applies strict regex-based pattern matching to determine if the text constitutes a formatted proposal report.
* **Encapsulation:** If a match is found, the regex capture groups are extracted, type-cast to integers, and encapsulated into a `ProposalReport` object.
* **Execution Trigger:** The instantiated `ProposalReport` is handed off to the Two-Stage Batch Execution Pipeline (defined in the core architecture) to initiate a transaction cycle. Unmatched messages are immediately discarded to conserve memory.

---

## 5. Bootstrap Flow & State Recovery Engine

**Component:** `StateBootstrapper`

Because Climatomaton operates without a database, this component reconstructs the operational `ClimateState` upon container startup using Discord's history as an immutable ledger.

* **Chronological Lookback:** Upon initialization, the bootstrapper utilizes stateless Discord REST API calls to fetch message blocks from the target channel, traversing backward chronologically from the present.
* **Anchor Resolution:** It searches for a valid climate report matching the bot's output signature (or an authorized admin's signature).
* **Startup Sequence Constraints:** During this initial backward scan, the engine's primary objective is locating the baseline anchor. If the scan encounters proposal reports during this lookup phase, **it must explicitly ignore them and make no updates to the climate state based on those proposal reports.** The engine relies entirely on administrative oversight or the definitive climate report anchor to establish the active state.
* **Collision Detection:** If a proposal report indicating *Turn 1* is encountered before a climate anchor, the engine halts the scan and initializes a clean baseline state (`climate.value = 0`, `climate.tags = []`).

---

## 6. Unified Command Parser (Pure Text & Logic Processing Layer)

**Component:** `UnifiedCommandParser`

This is a pure logic component. It receives normalized string arrays from the `CommandIngestionWrapper`, resolves them into `CommandPayload` objects, and executes the requested system overrides.

* **Positional Argument Mapping:** Evaluates arguments strictly by their index position. Multi-word strings (like comma-separated tag lists) are parsed as single index strings.
* **Omitted Argument Handling (`-` Token):** If a string array contains the hyphen token (`-`), the parser identifies this as an intentionally omitted optional parameter, preserving the index sequence for subsequent arguments.
* **The `reprocess` Execution:** Extracts the target message identifier (Snowflake or URL). It issues a stateless outbound Discord REST API call to fetch the exact message payload, processes it into a `ProposalReport`, and forces it through the execution pipeline.
* **The `reset` Execution:** * Evaluates argument 1 (`value`). If the specific string `default` is passed, the parser immediately flushes the in-memory state to the baseline (`climate.value = 0`, `climate.tags = []`), ignoring subsequent arguments.
* If numeric values or string tag arrays are provided, it forcibly overwrites the encapsulated `ClimateState`.
* Upon successful mutation, it triggers an outbound broadcast of the plain-English status report.



---

## 7. Outbox IPC Worker

**Component:** `OutboxIPCWorker`

This component manages all asynchronous, outbound notifications generated by the Core Engine or modular components, ensuring reliable delivery without blocking internal transaction loops.

* **Shared Volume Polling:** Continuously monitors the `outbox/` directory via filesystem polling.
* **Chronological Sorting:** Enforces alphabetical sorting of discovered JSON event files to guarantee chronological processing of sequential events.
* **Outbound API Integration:** While the `DiscordGatewayConnector` handles the persistent WebSocket, the `OutboxIPCWorker` independently formats and executes outbound stateless HTTP POST requests to the Discord REST APIs to deliver the notification payloads.
* **Atomic Cleanup:** Upon receiving a successful `200 OK` HTTP response from Discord, the worker unlinks (deletes) the event file from the shared volume. If rate-limited (`429 Too Many Requests`), it pauses its polling cycle, respecting the `Retry-After` header before reattempting delivery.
