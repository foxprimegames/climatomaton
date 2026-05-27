# Discord Gateway & Ingestion Engine Design Document

This document defines the complete architectural implementation for the core engine. It details the isolated components responsible for interfacing with external systems (Discord, Shared Volume), the encapsulated data objects that ferry information between layers, and the internal transaction pipeline that orchestrates game logic execution.

## 1. Encapsulated System Data Objects

To guarantee safe data transit and adhere to strict Object-Oriented principles, all shared data structures are fully encapsulated. External components **do not** parse raw text into these objects; instead, they pass raw text to the objects' own static factory or constructor methods, which encapsulate their specific regex, validation, and instantiation logic.

* **`DiscordMessage`**
* *State:* `messageId` (String), `channelId` (String), `authorId` (String), `rawContent` (String), `isDirectMessage` (Boolean).
* *Instantiation:* `static fromGatewayPayload(jsonPayload)` – parses the raw Discord WebSocket event into the object properties.
* *Methods:* `isFromAuthorizedAdmin(adminList)` (Evaluates `authorId` against the injected config array).


* **`ProposalReport`**
* *State:* `turn` (Integer), `count` (Integer), `passed` (Integer), `failed` (Integer).
* *Instantiation:* `static tryParse(rawContent)` – Encapsulates the specific regex required to identify a proposal report. If the string does not match the strict format, or if negative integers are parsed, it throws a `ParseException` or returns `null`.
* *Methods:* `isTurnOne()` (Returns true if `turn == 1`), `getMetricsGraph()` (Returns an immutable JSON-style dictionary mapping exactly to the engine's `proposals` memory namespace).


* **`ClimateState`**
* *State:* `value` (Float), `tags` (Set of Strings).
* *Instantiation:* `static tryParseAnchor(rawContent)` – Encapsulates the regex logic to scan historical bot/admin messages for the "The climate is now X and is Y" string format.
* *Methods:* `mutate(newValue, newTags)` (The only permitted way to alter state, used by the transaction pipeline), `generateReportString()` (Encapsulates the plain-English grammar formatting logic based on tag counts).


* **`CommandPayload`**
* *State:* `intent` (Enum: `REPROCESS`, `RESET`), `arguments` (Map<String, String> resolved from positional logic).
* *Instantiation:* `static parseFromInput(rawStringArray)` – Encapsulates the positional logic, mapping array indexes to named arguments, handling the hyphen (`-`) placeholder token for omitted arguments, and mapping the literal string `default` into the intent map.
* *Methods:* `getIntent()`, `getArgument(key)`.



---

## 2. Gateway & Network Layer

This layer acts as the physical boundary of the application, managing raw I/O without understanding the game's internal mechanics.

### **Component: `DiscordGatewayConnector**`

Manages the persistent inbound stream from the Discord network.

* **Responsibilities:** Maintains the WebSocket lifecycle, handles heartbeats, and declares the `GUILD_MESSAGES` and `MESSAGE_CONTENT` intents. Maps raw `MESSAGE_CREATE` and `INTERACTION_CREATE` JSON payloads into `DiscordMessage` objects and pushes them as asynchronous tasks to the runtime's event loop, immediately returning to listen for new events.
* **Error Handling:** * *Network Drops:* Automatically executes Discord's documented resume/reconnect backoff loops.
* *Authentication Failures:* If the token is invalid (HTTP 401), it logs a `CRITICAL` error to the local terminal and safely kills the container process (as recovery is impossible without configuration changes).



### **Component: `OutboxIPCWorker**`

Manages asynchronous outbound notifications to prevent blocking the internal execution thread.

* **Responsibilities:** Continuously polls the `outbox/` directory on the shared volume. Sorts discovered JSON event files alphabetically, parses them, and executes stateless HTTP POST requests to Discord REST APIs. Limits queue depth and enforces Time-to-Live (TTL) pruning for stale events.
* **Error Handling:**
* *Rate Limiting (HTTP 429):* Parses the `Retry-After` header, pauses the worker thread, and safely leaves the file in the outbox.
* *Malformed Outbox Files:* If a JSON file cannot be parsed, it logs a local warning and unlinks (deletes) the file to prevent pipeline clogging.



---

## 3. Ingestion & Command Layer

This layer translates network events into actionable game triggers. It runs asynchronously in the background via the event loop, shielding the Gateway from traffic bursts.

### **Component: `CommandIngestionWrapper**`

Normalizes structured interactions and unstructured DMs into uniform payloads.

* **Responsibilities:** Intercepts `/climate` slash commands and DM text. Validates authorization via `DiscordMessage.isFromAuthorizedAdmin()`. Strips prefixes, tokenizes the text into a string array, and attempts to instantiate a `CommandPayload`.
* **Error Handling:**
* *Invalid Syntax/Parsing Failure:* If `CommandPayload.parseFromInput()` throws an exception, the wrapper intercepts it and immediately dispatches a direct message back to the `authorId` containing a syntax usage guide. The command is dropped.
* *Unauthorized Access:* Drops the event silently and logs a security warning to the terminal.



### **Component: `ProposalFilterEngine**`

The silent listener for game events.

* **Responsibilities:** Receives every public channel `DiscordMessage`. Attempts to instantiate a `ProposalReport` by calling `ProposalReport.tryParse(message.rawContent)`. If successful, the object is placed into the core engine's execution queue.
* **Error Handling:**
* *Non-matching Strings:* `tryParse` returns null. The filter engine discards the message silently (standard behavior for normal chat).



---

## 4. State Recovery & Initialization

### **Component: `StateBootstrapper**`

Reconstructs the memory state upon container startup before the engine accepts live events.

* **Responsibilities:** Issues stateless REST calls to fetch channel history backward. It passes each message's text to both `ClimateState.tryParseAnchor()` and `ProposalReport.tryParse()`.
* **Logic Clarification & Constraints:** The bootstrapper parses proposal reports solely for metadata inspection, **never** for execution.
* If a `ClimateState` anchor is successfully parsed, it hydrates memory and terminates the boot process.
* If a `ProposalReport` is parsed, it checks `report.isTurnOne()`. If true, it signifies a round boundary collision; it terminates the backward scan and initializes the `default` baseline state. If `false` (Turn > 1), the bootstrapper explicitly ignores the report, applies no updates to the climate, and continues scanning backward for the true anchor.


* **Error Handling:**
* *Discord API Outage during Boot:* Logs a `CRITICAL` error and crashes the container. The bot cannot operate without a verified initial state; it relies on Docker's restart policies to try again later.



---

## 5. Core Execution Engine & Synchronization Pipeline

This is the central nervous system, orchestrating the file watcher, staging updates, and executing the mathematical game logic.

### **Component: `DirectorySynchronizationWatcher**`

Manages the shared volume transition lifecycle.

* **Responsibilities:** Polls `rules.commit` (using relative paths). Upon change, it extracts dynamic dependencies (via AST inspection), waits for required `.json` modules, and verifies syntax via the parser. If valid, it triggers an atomic memory pointer swap to the new `rules-YYYYMMDD-HHMMSS/` directory and queues old directories for garbage collection.
* **Error Handling:**
* *Validation/Timeout Failure:* Immediately halts the staging process, reverts `rules.commit` to the previous directory path, and dispatches a dual-delivery log (Terminal + Discord via Outbox) detailing the missing dependencies or syntax errors.



### **Component: `TransactionManager**`

Executes the Three-Phase Pipeline (Phase 0, 1, and 2) upon receiving a `ProposalReport` or `CommandPayload` override.

* **Responsibilities:**
* *Phase 0 (Rehydration):* Reads all active `.json` files from the committed directory and attaches them to a read-only environment graph.
* *Phase 1 & 2 (Execution):* Instantiates the mutable `new` namespace buffer. Iterates over the sorted AST (provided by the parser in strict numeric order), evaluating conditionals against the Phase 0 graph, and writing mutations to the `new` buffer.
* *Commitment:* If successful, invokes `ClimateState.mutate()` to finalize the values, then writes a standard output notification file to the `outbox/` queue for delivery.


* **Error Handling:**
* *Execution Abort Policy:* If any AST node fails (e.g., namespace path resolution failure, divide-by-zero), the `TransactionManager` catches the runtime exception. It instantly discards the mutable `new` buffer (preventing partial state writes), aborts the entire transaction cycle, and generates a dual-delivery log containing the failed Rule ID and the triggering message payload. No default values are assumed; all rule processing is aborted.
