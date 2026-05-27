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
| `sys.notification` | IPC Broker, Rules Engine | DAC | `severity_level`, `message_text` |
| `network.outbound` | Rules Engine, Core Daemon | DAC | `formatted_message`, `target_destination` (channel/user ID) |

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

### 4.3 Notification Protocol

* **`notify_admin`:** PRM or PEMs drop files into `notifications/{timestamp}_{id}.json`. The IPC Broker detects the file, pushes a `sys.notification` event, and **immediately deletes the file**.

---

## 5. Environment & Execution Workflows

### 5.1 State Rehydration Workflow

Because historical rulesets are unknown, Climatomaton **does not** automatically process historical EOT reports during recovery.
Upon startup, or if memory is cleared:

1. The State Rehydrator requests the DAC to fetch channel history, paginating backward.
2. Messages are passed to the `ClimateReport` object's `parse()` method.
3. If a valid report is parsed successfully, the `climate` environment is populated with the corresponding round, turn, value, and tags.
4. If the search hits a "Turn 1" EOT report first, it initializes to `0` and `Mild`.
5. If any EOTs occurred between the last parsed climate report and the present, the system remains in its parsed state. It is up to climate administrators to manually calculate missing updates and apply them via the `reset` command.

### 5.2 Handling Missing PEM Data

If an EOT arrives, but the PRM rules rely on a PEM namespace that has not initialized or is missing data:

1. **Suspension:** The Core places the parsed EOT into the "Pending EOT" queue.
2. **Notification:** It fires a `sys.notification` event detailing the missing required PEM data.
3. **Resolution:** Once the missing PEM writes its schema/data to the shared volume, the Core **restarts the processing of the EOT** from the beginning to ensure the newly provided data actually satisfies the missing keys and rules evaluation requirements.

### 5.3 Rules Execution Workflow

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



### 5.4 Natural English List Formatting

When the `ClimateReport` object formats the string, it applies standard English list rules:

* **0 Tags:** "The climate after round X turn Y is now Z."
* **1 Tag:** "...is now Z and is Mild."
* **2 Tags:** "...is now Z and is Greenhouse and Windy."
* **3+ Tags:** "...is now Z and is Greenhouse, Windy, and Unstable."

---

## 6. Command Interface

Admins interact via a unified Discord slash command (`/climate`) or via direct messages to the bot. For DMs, the specific sub-commands can be used directly without the slash prefix. Positional optional arguments can be omitted from right-to-left. To omit an earlier positional argument while providing a subsequent one, a placeholder (`-`) must be used. Tags are comma-separated.

### 6.1 System Control Commands

* **`pause`**
* Suspends automatic EOT processing. Any EOT reports posted to the channel while the system is paused are ignored, granting administrators time to manually calculate and apply rule updates.


* **`unpause`**
* Resumes automatic EOT processing for any newly posted EOT reports.



### 6.2 Data Management Commands

* **`reset [round] [turn] [value] [tags...]`**
* *No arguments:* Returns an error.
* `reset default` $\rightarrow$ Resets to Value `0`, Tags `["Mild"]`, with Round/Turn cleared or set to baseline. Note: `default` is passed directly into the `value` argument position.
* `reset 4 2 15` $\rightarrow$ Updates internal state to Round 4, Turn 2, Value 15. The `tags` argument is omitted, so the current tags remain unchanged.
* `reset - - - Greenhouse Effect, High Winds` $\rightarrow$ Round, Turn, and Value remain unchanged. Tags are replaced.
* `reset 5 1 12 Stable` $\rightarrow$ State updated to Round 5, Turn 1, Value 12. Tags replaced with `["Stable"]`.


* **`process <message>`**
* *Required argument:* `<message>` (ID or URL).
* Parses the target message and runs the EOT workflow immediately.



---

### Potential Missing Elements for Discussion

The document establishes a highly robust software architecture, but before diving into the detailed component design, there are a few operational and organizational gaps we should consider defining:

1. **Deployment Strategy:** The architecture relies heavily on shared volumes for IPC, which implies a specific containerization strategy. We need a section detailing how Docker (or a similar runtime) will orchestrate the Core Daemon alongside the PRM/PEMs, and how the staging and production environments will differ.
2. **Observability & Logging:** We have `sys.notification` for immediate admin alerts, but the system lacks a defined logging strategy. Should we designate specific Discord channels for standard logging, monitoring, and audit trails?
3. **Project Organization:** How do we want to map this architecture into actionable development tasks? Breaking this down into Agile epics or sub-projects (e.g., separating the Event Bus infrastructure from the Rules Engine execution) would help sequence the upcoming design documents.

Would you like to draft a new section encompassing the deployment strategy and observability first, or would you prefer to break the existing architecture down into Agile epics?
