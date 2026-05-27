# Architecture Specification: Climatomaton

## 1. System Overview

**Climatomaton** is an automated, stateless Discord bot designed to manage the "climate" of the Nomic-style game Nomicron. It operates by monitoring Discord for incoming data (via Gateway events), reading game history to establish state, and evaluating an externally provided ruleset to process end-of-turn (EOT) reports.

### Core Constraints & Solutions

* **Statelessness (No Database):** State is treated as an ephemeral cache. Upon startup, the bot rebuilds its current state by utilizing Discord channel history to locate the most recent valid Climatomaton report.
* **No Inbound Network Connectivity:** The system does not expose any web servers or open ports to the internet. All interaction with Discord is initiated outbound.
* **Decoupled Architecture:** Communication with the Pluggable Rules Module (PRM) and Pluggable Environment Modules (PEMs) is handled via socketless, file-based Interprocess Communication (IPC).

---

## 2. High-Level Architecture & Shared Data Models

Climatomaton consists of the **Core Daemon** and its **Pluggable Subprocesses** (PRM and PEMs), all of which share a set of common data object types.

### 2.1 Shared Data Objects

1. **`ClimateReport`:** Encapsulates the descriptive logic for the climate state. Contains the `format()` method (to generate the natural English string with the Oxford comma for Discord) and the `parse()` method (to extract the round, turn, numeric value, and tags from a historical message).
2. **`EOTSummary`:** Encapsulates the extracted data from an end-of-turn report (round number, turn number, and proposal status counts) used to populate the `proposals.` namespace.
3. **`Transaction`:** Encapsulates the diffs/mutations applied to any mutable namespace during rule evaluation, standardizing how data is sent to PEMs for acknowledgment.
4. **`RuleAST`:** The compiled Abstract Syntax Tree representation of a rule, ensuring conditions and actions are evaluated consistently.

### 2.2 Core System Components

1. **Discord Gateway Listener (DGL):** Maintains the outbound WebSocket connection for real-time channel monitoring. It acts strictly as an event producer, pushing raw payloads to the Internal Event Bus.
2. **Discord API Client (DAC):** Handles all asynchronous HTTP REST operations, including sending messages, queueing DMs, and paginating channel history.
3. **Internal Event Bus:** An in-memory Pub/Sub broker that routes all asynchronous events within the Core Daemon, decoupling all I/O operations from logic execution.
4. **Command Parser:** Intercepts slash commands (`/climate`) and DMs. Differentiates between standard Discord command payloads and the streamlined DM syntax.
5. **EOT Parser:** Receives potential end-of-turn reports, uses pattern matching to verify them, extracts the required game data into an `EOTSummary` object, and triggers the Rules Engine workflow.
6. **Environment Manager:** Scaffolds the environments during rule evaluation. It selectively duplicates explicitly registered mutable variables into the `new.` transaction environment.
7. **Rules Engine:** Evaluates rule conditions against the environments, applies actions, coordinates with the IPC Broker for PEM acknowledgments, and dispatches outbound messages.
8. **State Rehydrator:** A high-level logic process that calls the DAC to fetch historical messages on startup and passes them to the `ClimateReport` object to establish the initial `climate.` namespace.
9. **File-Based IPC Broker:** Manages local communication with the PRM and PEMs via shared container volumes. It utilizes file system event watchers (`inotify`) to detect changes and translates them into internal events.
10. **Logging & Observability Manager:** A centralized component that ingests all logs, observability metrics, and notifications from the Core Daemon, PRM, and PEMs. It formats these for the local system and selectively routes high-severity alerts to Discord administrators.

---

## 3. Internal Event Bus Specification

To guarantee the DGL never blocks and to maintain a fully event-driven execution model, the Core Daemon relies on a central Pub/Sub topic architecture.

| Topic | Publisher | Subscriber(s) | Payload / Data Communicated |
| --- | --- | --- | --- |
| `network.inbound` | DGL | Command Parser, EOT Parser | `raw_json_payload`, `source` (channel/DM) |
| `game.eot_detected` | EOT Parser | Rules Engine | `EOTSummary` object |
| `game.command` | Command Parser | Core Daemon, Rules Engine | `command_action` (e.g., reset, pause), `parsed_args` |
| `ipc.rules_updated` | IPC Broker | Rules Engine | `file_path` (relative to shared volume) |
| `ipc.pem_ack` | IPC Broker | Rules Engine | `tx_id`, `namespace` |
| `sys.log` | All Components, IPC Broker | Logging Manager | `level`, `source`, `message`, `metadata` |
| `sys.notification` | All Components, IPC Broker | Logging Manager | `level`, `message_text`, `admin_ids` |
| `network.outbound` | Rules Engine, Logging Manager | DAC | `formatted_message`, `target_destination` (channel/user ID) |

---

## 4. Communication Protocols (File-Based IPC)

Climatomaton uses **File-Based IPC via Shared Volumes**. Modules communicate by writing atomic JSON payloads to directories. All file paths are strictly relative to the shared volume root.

### 4.1 PRM Protocol (Rules Module)

* **`push_rules` (PRM -> Core):** The PRM writes a new compiled JSON ruleset to `prm/active_rules.json.tmp`, then atomically renames it.
* **Core Processing:** The IPC Broker detects the rename, fires an `ipc.rules_updated` event. The Core then parses the new rules into `RuleAST` objects in the background, validates them, and atomically swaps the active rules pointer.

### 4.2 PEM Protocol (Environment Module)

* **Schema Registration & Heartbeat (PEM -> Core):** PEMs write their schema and state payload to `pems/{namespace}.json`. PEMs must periodically update this file to indicate they are alive.
* **Transaction Commit (Core -> PEM):** If rules mutate a PEM namespace, the Core writes a diff to `tx/req_{tx_id}_{namespace}.json`.
* **Acknowledgment:** The PEM processes the transaction and writes `tx/ack_{tx_id}_{namespace}.json`.
* **Cleanup:** The IPC Broker detects the ACK file, fires an `ipc.pem_ack` event, and once the Core successfully posts the Discord report, it deletes both the `req` and `ack` files.
* **PEM Deregistration/Cleanup:** If a PEM crashes and fails to update its file within a TTL (Time-To-Live), the Core automatically unloads the schema and deletes the stale `{namespace}.json` file.

### 4.3 Logging & Notification Protocol

* **IPC Logging Constraints:** To prevent excessive disk I/O on the shared volume, PEMs and PRMs should **only** drop JSON payloads into `logs/{timestamp}_{id}.json` for events of `WARNING` severity or higher. Routine `DEBUG` and `INFO` events generated by PEMs/PRMs must be written directly to their respective container's standard output.
* **High-Priority Notifications:** Modules may drop explicitly formatted notification requests into `notifications/{timestamp}_{id}.json`.
* **Processing:** The IPC Broker detects the files, pushes the respective `sys.log` or `sys.notification` events to the Event Bus, and **immediately deletes the files**.

### 4.4 IPC File Validation & Schemas

Because the IPC mechanism relies on external processes writing data to the shared volume, the Core Daemon must enforce structural integrity:

* **Schemas:** PEMs are responsible for publishing and adhering to their own schemas. The PRM's compiled output must strictly follow a rule schema that will be defined in the PRM component design document and maintained as a static asset in the project.
* **File Size Limits:** To prevent a malfunctioning module from crashing the Core Daemon via massive payloads, maximum file size limits may be required. These exact limits are left as an implementation detail, but they will vary by module type (e.g., PRM rule files may remain unlimited or have very high limits, while PEM environment objects will likely require lower, stricter caps).

---

## 5. Observability & Logging

To ensure a robust audit trail and timely administrative action without overwhelming Discord channels, observability events funnel through the **Logging & Observability Manager**.

### 5.1 Log Levels & Routing

The system categorizes all log and observability events into standard severity levels:

* **DEBUG & INFO:** Routine operations (e.g., heartbeats received, successful cache rehydration, parsed command detected).
* *Routing:* Sent **only** to the local system log. (PEMs/PRMs route these directly to their own stdout; Core routes them internally to the logging manager).


* **WARNING:** Non-fatal issues that require attention but do not halt execution (e.g., a PEM missed a heartbeat but hasn't expired, rate limit backoff triggered by Discord).
* *Routing:* Sent to the local system log. Queued as a notification to Discord administrators (subject to rate limiting).


* **ERROR & FATAL:** Critical failures that abort processing (e.g., network failure, unhandled rule execution exception, missing required PEM data for an EOT).
* *Routing:* Sent to the local system log. Immediately dispatched as a high-priority notification to Discord administrators.



### 5.2 Local System Logging & Debug Cache

The Logging & Observability Manager uses a language-native logger configured to output structured JSON to standard output/standard error (`stdout`/`stderr`). This ensures logs are highly portable and easily aggregated by any container orchestration platform.

Additionally, the manager maintains a lightweight, in-memory **ring buffer** of the last N log events (e.g., 100 events). This cache provides a stateless mechanism for administrators to query recent system health directly via Discord (e.g., via a potential `/climate debug` command) without needing access to the host orchestration platform's logging dashboard.

### 5.3 Notification Rate Limiting

To prevent hitting Discord's API rate limits or spamming administrators during failure loops (e.g., a crashing PEM emitting continuous errors), the Logging Manager implements strict deduplication and throttling:

* **Per-Source Rate Limiting:** Identical or highly similar warnings/errors from the same source (e.g., the same PEM or same internal function) are deduplicated and throttled. After an initial alert, subsequent identical alerts are suppressed for a cooldown period (e.g., 5-15 minutes), optionally sending a single "X similar errors occurred" summary after the cooldown.
* **Overall Rate Limiting:** A global token bucket or hard cap prevents the bot from dispatching more than a predefined maximum number of direct messages per minute, prioritizing `FATAL` over `WARNING` events if the queue fills.

---

## 6. Environment & Execution Workflows

### 6.1 State Rehydration Workflow

Because historical rulesets are unknown, Climatomaton **does not** automatically process historical EOT reports during recovery.
Upon startup, or if memory is cleared:

1. The State Rehydrator requests the DAC to fetch channel history, paginating backward.
2. Messages are passed to the `ClimateReport` object's `parse()` method.
3. If a valid report is parsed successfully, the `climate` environment is populated with the corresponding round, turn, value, and tags.
4. If the search hits a "Turn 1" EOT report first, it initializes to `0` and `Mild`.
5. **Historical EOT Detection:** If the parser detects *any* end-of-turn reports that occurred *after* the most recently established climate report, the system cannot safely process them due to unknown historical rulesets. Instead, the Core Daemon will immediately transition to a **PAUSED** state and dispatch a high-priority `sys.notification` event. This alerts administrators to manually evaluate the game history and recover the state via the `reset` command before unpausing.

### 6.2 Handling Missing PEM Data

If a **new, live** EOT arrives, but the PRM rules rely on a PEM namespace that has not initialized or is missing data:

1. **Suspension:** The Core places the parsed EOT into a temporary "Pending EOT" state.
2. **Notification:** It fires a `sys.notification` event detailing the missing required PEM data.
3. **Resolution:** Once the missing PEM writes its schema/data to the shared volume, the Core **restarts the processing of the pending EOT** from the beginning to ensure the newly provided data satisfies the rules evaluation requirements.

### 6.3 Rules Execution Workflow

Triggered when a `game.eot_detected` event is received and all required PEM data is validated.

1. **Environment Initialization:**
* `climate.*`, `proposals.*`, and `{pem_namespace}.*` are loaded from cache.
* `var.*` initialized (names auto-initialize to `0` upon first call).
* `new.*` is populated as a clone of **only** the explicitly registered mutable fields.


2. **Rules Processing:**
* **Execution Constraints:** Rules are evaluated **strictly in numeric order**. Syntax requires spaces for keywords (e.g., "climate rule", "tag rule").
* **Strict Error Handling:** If a namespace path resolution fails, or any other execution error occurs, **all rule processing is immediately aborted**. The failure is logged, and a `sys.notification` event is fired to alert administrators. No default values are ever assumed.
* **Climate Rules:** Evaluate and mutate `new.climate.value`, `var.*`, or **any other mutable numeric field** mapped in `new.*`.
* **Tag Rules:** Evaluate and mutate `new.climate.tags`, or **any other mutable tag-list field** mapped in `new.*`.


3. **Commit & Report:**
* Write `Transaction` diffs to `tx/` and wait for PEM ACKs asynchronously.
* Use the `ClimateReport` object to generate the formatted string and fire a `network.outbound` event.



### 6.4 Natural English List Formatting

When the `ClimateReport` object formats the string, it applies standard English list rules:

* **0 Tags:** "The climate after round X turn Y is now Z."
* **1 Tag:** "...is now Z and is Mild."
* **2 Tags:** "...is now Z and is Greenhouse and Windy."
* **3+ Tags:** "...is now Z and is Greenhouse, Windy, and Unstable."

---

## 7. Command Interface

Admins interact via a unified Discord slash command (`/climate`) or via direct messages to the bot. For DMs, the specific sub-commands can be used directly without the slash prefix. Positional optional arguments can be omitted from right-to-left. To omit an earlier positional argument while providing a subsequent one, a placeholder (`-`) must be used. Tags are comma-separated.

### 7.1 System Control Commands

* **`pause`**
* Suspends automatic EOT processing. Any EOT reports posted to the channel while the system is paused are ignored, granting administrators time to manually calculate and apply rule updates.


* **`unpause`**
* Resumes automatic EOT processing for any newly posted EOT reports.



### 7.2 Data Management Commands

* **`reset [round] [turn] [value] [tags...]`**
* *No arguments:* Returns an error.
* `reset default` $\rightarrow$ Resets to Value `0`, Tags `["Mild"]`, with Round/Turn cleared or set to baseline. Note: `default` is passed directly into the `value` argument position.
* `reset 4 2 15` $\rightarrow$ Updates internal state to Round 4, Turn 2, Value 15. The `tags` argument is omitted, so the current tags remain unchanged.
* `reset - - - Greenhouse Effect, High Winds` $\rightarrow$ Round, Turn, and Value remain unchanged. Tags are replaced.
* `reset 5 1 12 Stable` $\rightarrow$ State updated to Round 5, Turn 1, Value 12. Tags replaced with `["Stable"]`.


* **`process <message>`**
* *Required argument:* `<message>` (ID or URL).
* Parses the target message and runs the EOT workflow immediately.



### 7.3 Authorization

The specific mechanism for identifying and authorizing Administrators (e.g., verifying against specific injected Discord Role IDs, Discord server permissions, or a hardcoded list of user IDs) is left as a design and implementation detail to be defined during component-level specification.

---

## 8. Deployment Architecture Requirements

While the specific hosting environment is not yet defined, the deployment strategy will strictly utilize OCI-compliant containers. Any target environment must support the following base requirements:

1. **Shared Volume Mounting:** The orchestration layer must support mounting a common, high-speed, POSIX-compliant shared volume across multiple containers (the Core Daemon, PRM, and PEMs) to facilitate the file-based IPC routing.
2. **Environment Variable Injection:** Sensitive configurations (e.g., Discord Bot Tokens, Admin User IDs, Target Channel IDs) must be injected safely into the containers strictly via environment variables. The running containers cannot rely on the existence of, or integration with, a secret management system at runtime.
3. **Container Lifecycle & Health Checks:** The environment should be capable of automatically restarting failed subprocesses (PEMs/PRMs). The Core Daemon relies on external orchestration to keep the pluggable modules running if they crash.
4. **Log Aggregation:** Because the Core Daemon writes all local observability data to `stdout`/`stderr` using a native logger, the deployment environment must feature an agent or mechanism to capture, rotate, and aggregate standard output logs.
5. **Graceful Shutdown Signals:** The environment must issue standard termination signals (`SIGTERM`) and provide a brief grace period. The Event Bus and Rules Engine require this to finalize any in-flight file writes and Discord network requests before exiting.

---

---

### Issues & Suggestions for Discussion

This architecture document is looking extremely solid. Since we will tackle component sequencing in new conversations, there is only one minor operational edge case I’d suggest clarifying before we finalize this document:

* **Stale IPC File Cleanup on Startup:** If the Core Daemon or a PEM experiences a hard crash mid-transaction (e.g., before `SIGTERM` can finish graceful shutdown), orphaned `req_`, `ack_`, or `.tmp` files may be left lingering in the shared IPC volume. Should the architecture explicitly require the IPC Broker to purge all in-flight transaction files during startup to ensure a completely clean slate, or should it attempt to resume them? (My recommendation is to purge, given the stateless design).
