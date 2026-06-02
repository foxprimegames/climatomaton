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

1. **Discord Gateway Listener (DGL):** Maintains the outbound WebSocket connection for real-time channel monitoring. It acts strictly as an event producer, pushing raw payloads to the Internal Event Bus. Specific Discord intents and permissions required for this component will be detailed in the DGL design document.
2. **Discord API Client (DAC):** Handles all asynchronous HTTP REST operations, including sending messages, queueing DMs, and paginating channel history. Specific OAuth2 scopes required for this component will be detailed in the DAC design document.
3. **Internal Event Bus:** An in-memory Pub/Sub broker that routes all asynchronous events within the Core Daemon, decoupling all I/O operations from logic execution.
4. **Command Parser:** Intercepts slash commands (`/climate`) and DMs. Differentiates between standard Discord command payloads and the streamlined DM syntax.
5. **EOT Parser:** Receives potential end-of-turn reports, uses pattern matching to verify them, extracts the required game data into an `EOTSummary` object, and triggers the Rules Engine workflow.
6. **Environment Manager:** Scaffolds the environments during rule evaluation. It selectively duplicates explicitly registered mutable variables into the `new.` transaction environment.
7. **Rules Engine:** Evaluates rule conditions against the environments, applies actions, coordinates with the IPC Broker for PEM acknowledgments, and dispatches outbound messages.
8. **State Rehydrator:** A high-level logic process that calls the DAC to fetch historical messages on startup and passes them to the `ClimateReport` object to establish the initial `climate.` namespace.
9. **File-Based IPC Broker:** Manage local communication with the PRM and PEMs via shared container volumes. It utilizes file system event watchers (`inotify`) to detect changes and translates them into internal events.
10. **Logging & Observability Manager:** A centralized component that ingests all logs, observability metrics, and notifications from the Core Daemon, PRM, and PEMs. It formats these for the local system and selectively routes high-severity alerts to Discord administrators.

---

## 3. Internal Event Bus Specification

To guarantee the DGL never blocks and to maintain a fully event-driven execution model, the Core Daemon relies on a central Pub/Sub topic architecture. All core engine operations are asynchronous with respect to the Internal Event Bus; no component may block other components from publishing or receiving events.

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

Climatomaton uses **File-Based IPC via Shared Volumes**. Modules communicate by writing JSON payloads to directories using the atomic write protocol. The atomic write protocol will be defined in the shared volume design document. All file paths are strictly relative to the shared volume root. All timestamping for file names and internal operations must strictly utilize the **UTC timezone**.

### 4.1 PRM Protocol (Rules Module)

* **Push Rules:** The PRM writes a new compiled JSON-IR ruleset to its final filename on the shared volume using the atomic write protocol. The specific structure and format of this JSON-IR ruleset are defined in the Rules Language Design Document.
* **Immediate Validation Pass:** The IPC Broker actively monitors the rules folder and the schemas folder on the shared volume. It triggers the Rules Engine to proactively parse and type-check incoming JSON-IR files immediately upon modification of the rules file, or whenever a PEM schema is added, updated, or deleted.
* **Validation Error Recovery Policy:**
  * **LKG Fallback:** If a newly watched JSON-IR file fails semantic or static verification, the Rules Engine discards it, retains the prior working version (Last-Known-Good), logs the trace, and dispatches an admin alert via the Logging Manager.
  * **PAUSED Fallback:** If an environment change (such as a PEM deletion) renders the active rules invalid, there is no last-known-good ruleset to fall back to. The Core Daemon must immediately drop into a **PAUSED** state, halt EOT reporting, and notify the administrators.
* **Rules Engine Processing:** The IPC Broker detects the rename and fires an `ipc.rules_updated` event. The Rules Engine then parses the new rules into `RuleAST` objects in the background, validates them, and atomically swaps the active rules pointer.

### 4.2 PEM Protocol (Environment Module)

* **Schema Registration & Heartbeat:** As soon as the PEM starts up, it must write a static schema description file to `pems/{pem_namespace}.schema.json` on the shared volume, which the IPC Broker monitors. This file dictates the type schema and designates the read-only versus mutable state for the data the PEM will provide. The PEM must periodically update this file at an interval no greater than a defined maximum limit to indicate it is alive. Updates must be performed using the atomic write protocol. The exact structure and semantics are defined in the Pluggable Environment Module (PEM) Design Document.
* **Environment Data Publication:** As soon as practical after the schema file is written, and whenever the represented content changes thereafter, the PEM must write its structured environment data (excluding the PEM's namespace prefix itself) to `pems/{pem_namespace}.json` on the shared volume. Updates must be performed using the atomic write protocol to ensure the Rules Engine never reads partial state. The exact specification of this environment file will be defined in the Pluggable Environment Module (PEM) Design Document.
* **Transaction Commit:** If rules mutate a PEM namespace, the Rules Engine generates a diff and writes it to `tx/req_{tx_id}_{namespace}.json` on the shared volume. The specific format of this transaction diff file is defined in the Pluggable Environment Module (PEM) Design Document.
* **Acknowledgment:** The PEM detects and processes the transaction request from the shared volume, then writes an acknowledgment to `tx/ack_{tx_id}_{namespace}.json`. The specific format of this acknowledgment file is also defined in the PEM Design Document.
* **Transaction Cleanup:** The IPC Broker detects the ACK file and fires an `ipc.pem_ack` event. Once the Rules Engine successfully posts the Discord report via the DAC, the IPC Broker deletes both the `req` and `ack` files from the volume.
* **PEM Deregistration/Cleanup:** If a PEM crashes and fails to update its schema file within the heartbeat TTL (Time-To-Live), the Environment Manager automatically unloads the schema from memory, and the IPC Broker deletes both the stale `{pem_namespace}.schema.json` and `{pem_namespace}.json` files from the volume.

### 4.3 Logging & Notification Protocol

* **IPC Logging Constraints:** To prevent excessive disk I/O on the shared volume, PEMs and PRMs should **only** drop JSON payloads into `logs/{timestamp}_{id}.json` (where timestamp is UTC) for events of `WARNING` severity or higher. Routine `DEBUG` and `INFO` events generated by PEMs/PRMs must be written directly to their respective container's standard output.
* **High-Priority Notifications:** Modules may drop explicitly formatted notification requests into `notifications/{timestamp}_{id}.json` (where timestamp is UTC).
* **Processing:** The IPC Broker detects the files, pushes the respective `sys.log` or `sys.notification` events to the Event Bus, and **immediately deletes the files**.

### 4.4 IPC File Validation & Schemas

* **Schemas:** PEMs are responsible for publishing and adhering to their own schemas. The PRM's compiled output must strictly follow a rule schema that will be defined in the PRM component design document and maintained as a static asset in the project.
* **File Size Limits:** To prevent a malfunctioning module from crashing the Core Daemon via massive payloads, maximum file size limits may be required. These exact limits are left as an implementation detail, but they will vary by module type (e.g., PRM rule files may remain unlimited or have very high limits, while PEM environment objects will likely require lower, stricter caps).

---

## 5. Observability & Logging

To ensure a robust audit trail and timely administrative action without overwhelming Discord channels, observability events funnel through the **Logging & Observability Manager**.

### 5.1 Log Levels & Routing

* **DEBUG & INFO:** Routine operations (e.g., heartbeats received, successful cache rehydration). Routed **only** to the local system log. PEMs/PRMs output these directly to their own stdout; the Logging Manager routes internal Core Daemon logs to stdout.
* **WARNING:** Non-fatal issues requiring attention but not halting execution (e.g., missed PEM heartbeat). Routed to the local system log and queued as a notification to Discord administrators (subject to rate limiting).
* **ERROR & FATAL:** Critical failures aborting processing (e.g., unhandled rule exception). Routed to the local system log and immediately dispatched as a high-priority notification to Discord administrators.

### 5.2 Local System Logging & Debug Cache

The Logging & Observability Manager uses a language-native logger configured to output structured JSON to standard output/standard error (`stdout`/`stderr`). This ensures logs are highly portable and easily aggregated by any container orchestration platform. Additionally, the manager maintains a lightweight, in-memory ring buffer of the last N log events (e.g., 100 events). This provides a stateless mechanism for administrators to query recent system health directly via Discord (e.g., via a potential `/climate debug` command) without accessing the host logging dashboard.

### 5.3 Notification Rate Limiting

* **Per-Source Rate Limiting:** Identical or highly similar warnings/errors from the same source are deduplicated and throttled. After an initial alert, subsequent identical alerts are suppressed for a cooldown period, optionally sending a single summary message after the cooldown.
* **Overall Rate Limiting:** A global token bucket or hard cap prevents the bot from dispatching more than a predefined maximum number of direct messages per minute, prioritizing `FATAL` over `WARNING` events if the queue fills.

---

## 6. Environment & Execution Workflows

### 6.1 State Rehydration & Startup Workflow

Because historical rulesets are unknown, Climatomaton **does not** automatically process historical EOT reports during recovery. Upon startup, or if memory is cleared, the following sequence occurs:

1. **Stale IPC File Cleanup:** The IPC Broker explicitly purges all lingering, in-flight transaction files (e.g., `req_*`, `ack_*`, `.tmp`) from the shared volume to guarantee a clean slate.
2. **History Fetch:** The State Rehydrator requests the DAC to fetch channel history, paginating backward.
3. **Parsing:** Messages are passed to the `ClimateReport` object's `parse()` method.
4. **Initialization:** If a valid report is parsed successfully, the `climate` environment is populated. If the search hits a "Turn 1" EOT report first, it initializes to `0` and `Mild`.
5. **Historical EOT Detection:** If the EOT Parser detects *any* end-of-turn reports that occurred *after* the most recently established climate report, the Core Daemon will immediately transition to a **PAUSED** state and dispatch a high-priority `sys.notification` event. Administrators must then manually evaluate the game history and recover the state via the `reset` command before unpausing.

### 6.2 Handling Missing PEM Data

If a **new, live** EOT arrives, but the PRM rules rely on a PEM namespace that has not initialized or is missing data:

1. **Suspension:** The Rules Engine places the parsed EOT into a temporary "Pending EOT" state.
2. **Notification:** The Rules Engine fires a `sys.notification` event detailing the missing required PEM data.
3. **Resolution:** Once the missing PEM writes its schema and data files to the shared volume, the Rules Engine restarts the processing of the pending EOT from the beginning to ensure the newly provided data satisfies the rules evaluation requirements.

### 6.3 Rules Execution Workflow

Triggered when a `game.eot_detected` event is received and all required PEM data is validated.

1. **Environment Initialization:** `climate.*`, `proposals.*`, and `{pem_namespace}.*` are loaded from cache. `var.*` fields auto-initialize to their typed default values (`false` for booleans, `0` for numbers, the empty string `""` for strings, and the empty list `[]` for tag lists) upon first call. `new.*` is populated by the Environment Manager as a clone of only the explicitly registered mutable fields.
2. **Execution Constraints:** Rules are evaluated strictly in numeric order. Syntax strictly requires spaces for keywords (e.g., "climate rule", "tag rule").
3. **Strict Error Handling:** If a namespace path resolution fails, or any other execution error occurs, all rule processing is immediately aborted. The failure is logged, a `sys.notification` event is fired to alert administrators, and no default values are assumed.
4. **Mutations:** Climate rules mutate `new.climate.value`, `var.*`, or other mapped numeric fields. Tag rules mutate `new.climate.tags` or other mapped tag-list fields.
5. **Commit & Report:** Transaction diffs are written by the Rules Engine to `tx/` awaiting asynchronous PEM ACKs. The `ClimateReport` object generates the formatted string, and a `network.outbound` event is fired.

### 6.4 Natural English List Formatting

When the `ClimateReport` object formats the string, it applies standard English list rules:

* **0 Tags:** "The climate after round X turn Y is now Z."
* **1 Tag:** "...is now Z and is Mild."
* **2 Tags:** "...is now Z and is Greenhouse and Windy."
* **3+ Tags:** "...is now Z and is Greenhouse, Windy, and Unstable."

---

## 7. Command Interface

Admins interact via a unified Discord slash command (`/climate`) or via direct messages to the bot. For DMs, the specific sub-commands can be used directly without the slash prefix. Positional optional arguments can be omitted from right-to-left. To omit an earlier positional argument while providing a subsequent one, a placeholder (`-`) must be used. Tags are comma-separated.

### 7.1 Command Listing

* **`pause`**: Suspends automatic EOT processing. Any EOT reports posted to the channel while paused are ignored, granting administrators time to manually calculate updates.
* **`unpause`**: Resumes automatic EOT processing for any newly posted EOT reports.
* **`reset [round] [turn] [value] [tags...]`**: Updates internal state. Calling without arguments returns an error.
* **`reset default`**: Resets to Value `0`, Tags `["Mild"]`, with Round/Turn cleared or set to baseline. The `default` keyword is passed directly into the `value` argument position.
* **`reset 4 2 15`**: Updates internal state to Round 4, Turn 2, Value 15. The current tags remain unchanged.
* **`reset - - - Greenhouse Effect, High Winds`**: Round, Turn, and Value remain unchanged. Tags are replaced.
* **`reset 5 1 12 Stable`**: State updated to Round 5, Turn 1, Value 12. Tags replaced with `["Stable"]`.
* **`process <message>`**: Parses the target message (ID or URL) and runs the EOT workflow immediately.

### 7.2 Authorization

The specific mechanism for identifying and authorizing Administrators (e.g., verifying against specific injected Discord Role IDs, Discord server permissions, or a hardcoded list of user IDs) is left as a design and implementation detail to be defined during component-level specification.

---

## 8. Deployment Architecture Requirements

While the specific hosting environment is not yet defined, the deployment strategy will strictly utilize OCI-compliant containers. Any target environment must support the following base requirements:

1. **Shared Volume Mounting:** The orchestration layer must support mounting a common, high-speed, POSIX-compliant shared volume across multiple containers (the Core Daemon, PRM, and PEMs) to facilitate the file-based IPC routing.
2. **Secrets Management:** Sensitive configurations (e.g., Discord Bot Tokens, Admin User IDs, Target Channel IDs) must be injected safely into the containers strictly via environment variables. The running containers cannot rely on the existence of, or integration with, a secret management system at runtime.
3. **Configuration Management:** Non-secret application configurations (e.g., standardizing internal operations and logging to the UTC timezone, logging verbosity, maximum IPC file size limits, expected PEM modules) will be managed via a standard configuration file mounted at a known, fixed location within the container filesystem.
4. **Container Lifecycle & Health Checks:** The environment should be capable of automatically restarting failed subprocesses (PEMs/PRMs). The Core Daemon relies on external orchestration to keep the pluggable modules running if they crash.
5. **Log Aggregation:** Because the Logging Manager writes all local observability data to `stdout`/`stderr` using a native logger, the deployment environment must feature an agent or mechanism to capture, rotate, and aggregate standard output logs.
6. **Graceful Shutdown Signals:** The environment must issue standard termination signals (`SIGTERM`) and provide a brief grace period to allow the Event Bus and Rules Engine to finalize any in-flight file writes and network requests before exiting.
7. **Testing Environment:** Functional testing of the integrated system will be performed against a dedicated staging or private testing-only Discord server to ensure live Nomicron gameplay is completely isolated from development.

---

### Discussion & Notes

* **Atomic Write Protocol Implementation:** The references to specific file renaming steps (like `.tmp` files) have been generalized to the "atomic write protocol" in sections 4, 4.1, and 4.2. As stated in Section 4, the exact mechanics of this protocol will need to be thoroughly outlined in the forthcoming Shared Volume Design Document.
* **Section 6.1 Clarification:** In Section 6.1 (State Rehydration & Startup Workflow), I left the reference to `.tmp` files under the stale IPC file cleanup since the atomic write protocol itself will likely produce temporary files that require cleanup in the event of a crash. Let me know if you would like that abstracted away as well.
* **Memory Swaps:** In section 4.1, the phrase "atomically swaps the active rules pointer" was retained since it refers to an internal memory reference within the Rules Engine, rather than a file system operation.
