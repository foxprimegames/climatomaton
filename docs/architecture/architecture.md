# Architecture Specification: Climatomaton

## 1. System Overview

**Climatomaton** is an automated, stateless Discord bot designed to manage the "climate" of the Nomic-style game Nomicron. It operates by **monitoring Discord** for incoming data (via Gateway events), reading game history to establish state, and evaluating an externally provided ruleset to process end-of-turn (EOT) reports.

### Core Constraints & Solutions

* **Statelessness (No Database):** State is treated as an ephemeral cache. Upon startup, the bot rebuilds its current state by utilizing Discord channel history to locate the most recent valid Climatomaton report.
* **No Inbound Network Connectivity:** The system does not expose any web servers or open ports to the internet. All interaction with Discord is initiated outbound.
* **Decoupled Architecture:** Communication with the Pluggable Rules Module (PRM) and Pluggable Environment Modules (PEMs) is handled via socketless, file-based Interprocess Communication (IPC).

---

## 2. High-Level Architecture & Shared Data Models

Climatomaton consists of the **Core Daemon**, its **Pluggable Subprocesses** (PRM and PEMs), and a set of shared data objects.

### 2.1 Shared Data Objects

1. **`ClimateReport`:** Encapsulates the descriptive logic for the climate state. Contains the `format()` method (to generate the natural English string with the Oxford comma for Discord) and the `parse()` method (to extract the round, turn, numeric value, and tags from a historical message).
2. **`EOTSummary`:** Encapsulates the extracted data from an end-of-turn report (round number, turn number, and proposal status counts) used to populate the `proposals.` namespace.
3. **`Transaction`:** Encapsulates the diffs/mutations applied to any mutable namespace during rule evaluation, standardizing how data is sent to PEMs for acknowledgment.
4. **`RuleAST`:** The compiled Abstract Syntax Tree representation of a rule, ensuring conditions and actions are evaluated consistently.

### 2.2 Core System Components

To prevent high-latency REST API calls from blocking critical WebSocket heartbeats, Discord network interactions are separated into two distinct components:

1. **Discord Gateway Listener (DGL):** Maintains the outbound WebSocket connection for real-time channel monitoring and command listening. It is strictly non-blocking to preserve connection health.
2. **Discord API Client (DAC):** Handles all asynchronous HTTP REST operations, including sending messages, queueing DMs, and paginating channel history.
3. **State Rehydrator:** A high-level logic process that calls the DAC to fetch historical messages and passes them to the `ClimateReport` object to establish the initial `climate.` namespace.
4. **Command Parser:** Intercepts slash commands (`/climate`) and DMs from the DGL. Differentiates between standard Discord command payloads and the streamlined DM syntax.
5. **EOT Parser:** Identifies end-of-turn reports in the channel, extracts the required game data into an `EOTSummary` object, and triggers the climate update workflow.
6. **Environment Manager:** Scaffolds the environments. It selectively duplicates explicitly registered mutable variables into the `new.` transaction environment.
7. **Rules Engine:** Evaluates rule conditions against the environments and applies actions.
8. **File-Based IPC Broker:** Manages local communication with the PRM and PEMs via shared container volumes and file system event watchers (`inotify`).

---

## 3. Communication Protocols (File-Based IPC)

Climatomaton uses **File-Based IPC via Shared Volumes**. Modules communicate by writing atomic JSON payloads to directories.

### 3.1 PRM Protocol (Rules Module)

* **`push_rules` (PRM -> Core):** The PRM writes a new compiled JSON ruleset to `/shared/prm/active_rules.json.tmp`, then atomically renames it.
* **Core Processing:** The Core parses the new rules into `RuleAST` objects in the background, validates them, and atomically swaps the active rules pointer.

### 3.2 PEM Protocol (Environment Module)

* **Schema Registration & Heartbeat (PEM -> Core):** PEMs write their schema and state payload to `/shared/pems/{namespace}.json`. PEMs must periodically update this file to indicate they are alive.
* **Transaction Commit (Core -> PEM):** If rules mutate a PEM namespace, the Core writes a diff to `/shared/tx/req_{tx_id}_{namespace}.json`.
* **Acknowledgment:** The PEM processes the transaction and writes `/shared/tx/ack_{tx_id}_{namespace}.json`.
* **Cleanup:** Once the Core receives the ACK and successfully posts the Discord report, the Core deletes both the `req` and `ack` files.
* **PEM Deregistration/Cleanup:** If a PEM crashes and fails to update its file within a TTL (Time-To-Live), the Core automatically unloads the schema and deletes the stale `{namespace}.json` file.

### 3.3 Notification Protocol

* **`notify_admin`:** PRM or PEMs drop files into `/shared/notifications/{timestamp}_{id}.json`. The Core queues a DM to Admins and **immediately deletes the file**.

---

## 4. Environment & Execution Workflows

### 4.1 State Rehydration Workflow

Because historical rulesets are unknown, Climatomaton **does not** automatically process historical EOT reports during recovery.
Upon startup, or if memory is cleared:

1. The State Rehydrator requests the DAC to fetch channel history, paginating backward.
2. Messages are passed to the `ClimateReport` object's `parse()` method.
3. If a valid report is parsed successfully, the `climate` environment is populated with the corresponding round, turn, value, and tags.
4. If the search hits a "Turn 1" EOT report first, it initializes to `0` and `Mild`.
5. If any EOTs occurred between the last parsed climate report and the present, the system remains in its parsed state. It is up to climate administrators to manually calculate missing updates and apply them via the `reset` command.

### 4.2 Handling Missing PEM Data

If an EOT arrives, but the PRM rules rely on a PEM namespace that has not initialized or is missing data:

1. **Suspension:** The Core places the parsed EOT into the "Pending EOT" queue.
2. **Notification:** It fires a DM to administrators detailing the missing required PEM data.
3. **Resolution:** Once the missing PEM writes its schema/data to the shared volume, the Core **restarts the processing of the EOT** from the beginning to ensure the newly provided data actually satisfies the missing keys and rules evaluation requirements.

### 4.3 Rules Execution Workflow

Triggered when an EOT message is identified and all required PEM data is validated.

1. **Environment Initialization:**
* `climate.*`, `proposals.*`, and `{pem_namespace}.*` are loaded from cache.
* `var.*` initialized (names auto-initialize to `0` upon first call).
* `new.*` is populated as a clone of **only** the explicitly registered mutable fields.


2. **Rules Processing (Ordered):**
* **Climate Rules:** Evaluate and mutate `new.climate.value`, `var.*`, or **any other mutable numeric field** mapped in `new.*`.
* **Tag Rules:** Evaluate and mutate `new.climate.tags`, or **any other mutable tag-list field** mapped in `new.*`.


3. **Commit & Report:**
* Write `Transaction` diffs to `/shared/tx/` and wait for PEM ACKs.
* Use the `ClimateReport` object to generate the formatted string and post via DAC.



### 4.4 Natural English List Formatting

When the `ClimateReport` object formats the string, it applies standard English list rules:

* **0 Tags:** "The climate after round X turn Y is now Z."
* **1 Tag:** "...is now Z and is Mild."
* **2 Tags:** "...is now Z and is Greenhouse and Windy."
* **3+ Tags:** "...is now Z and is Greenhouse, Windy, and Unstable."

---

## 5. Command Interface

Admins interact via `/climate` commands or DMs. For streamlined DMs, positional optional arguments can be omitted from right-to-left. To omit an earlier positional argument while providing a subsequent one, a placeholder (`-`) must be used. Tags are comma-separated.

### 5.1 System Control Commands

* **`pause`**
* Suspends automatic EOT processing. Any EOT reports posted to the channel while the system is paused are ignored, granting administrators time to manually calculate and apply rule updates.


* **`unpause`**
* Resumes automatic EOT processing for any newly posted EOT reports.



### 5.2 Data Management Commands

* **`reset [round] [turn] [value] [tags...]`**
* *No arguments:* Returns an error.
* `reset default` $\rightarrow$ Resets to Value `0`, Tags `["Mild"]`, with Round/Turn cleared or set to baseline.
* `reset 4 2 15` $\rightarrow$ Updates internal state to Round 4, Turn 2, Value 15. The `tags` argument is omitted, so the current tags remain unchanged.
* `reset - - - Greenhouse Effect, High Winds` $\rightarrow$ Round, Turn, and Value remain unchanged. Tags are replaced.
* `reset 5 1 12 Stable` $\rightarrow$ State updated to Round 5, Turn 1, Value 12. Tags replaced with `["Stable"]`.


* **`process <message>`**
* *Required argument:* `<message>` (ID or URL).
* Parses the target message and runs the EOT workflow immediately.



---

---

### Responses to Your Issues

**1. Discord Component Separation (Gateway vs. API):**
You are completely right to flip-flop here; it's a known and dangerous pitfall in bot architecture. A single thread trying to maintain a WebSocket connection will invariably drop heartbeats (causing frequent reconnects or "ghost" sessions) if it gets blocked waiting on a rate-limited REST API call (like paginating through hundreds of historical messages). I have updated Section 2.2 to explicitly split Discord interactions into two components: the **Discord Gateway Listener (DGL)**, which strictly handles the non-blocking real-time event stream, and the **Discord API Client (DAC)**, which handles all asynchronous, potentially blocking REST HTTP requests.

**2. Unknown Historical Rulesets during Recovery:**
This is a critical insight. If a ruleset changed on Turn 3, and the bot crashed on Turn 2 and wakes up on Turn 5, processing the historical backlog with Turn 5's ruleset would corrupt the game state. I have entirely removed the "forward scanning/queue recovery" logic from Section 4.1. The system now strictly halts at the last known `ClimateReport` it parses. Catching up on missed EOTs is now explicitly designated as a manual administrative task.

**3. `reset` Command Signature (Round & Turn):**
Based on your observation in #2, the `reset` command must reflect the structure of a `ClimateReport`. I have updated the signature in Section 5.2 to `reset [round] [turn] [value] [tags...]`. This gives administrators full control over establishing the precise mathematical and temporal state of the climate after manually calculating missed updates.

**4. `pause` and `unpause` Commands:**
To facilitate the manual calculations mentioned above, I have added a "System Control Commands" section (5.1) featuring `pause` and `unpause`. This allows admins to safely halt the bot's automated listening, run their manual overrides via `reset`, and then resume normal operations without race conditions from new EOTs dropping in the middle of their work.

**5. Missing PEM Data Re-evaluation:**
I have updated Section 4.2 to explicitly state that the system "restarts the processing of the EOT" from the beginning. Your reasoning is perfectly sound: just because a PEM updated its data file and triggered the file watcher doesn't guarantee the *specific keys* the rules engine was looking for are actually present. Re-evaluating the rule dependencies from the top ensures absolute validity before proceeding.
