# Architecture Specification: Climatomaton

## 1. System Overview

**Climatomaton** is an automated, stateless Discord bot designed to manage the "climate" of the Nomic-style game Nomicron. It operates entirely by observing outbound connections to Discord, reading game history to establish state, and evaluating an externally provided ruleset to process end-of-turn (EOT) reports.

### Core Constraints & Solutions

* **Statelessness (No Database):** State is treated as an ephemeral cache. Upon startup, the bot rebuilds current state by traversing the Discord channel history backward to locate the most recent valid Climatomaton report.
* **No Inbound Network Connectivity:** The bot connects to Discord via the Discord Gateway (an outbound WebSocket connection). It observes the channel by listening to the incoming event stream over this established outbound connection.
* **Decoupled Architecture:** Communication with the Pluggable Rules Module (PRM) and Pluggable Environment Modules (PEMs) is handled via socketless Interprocess Communication (IPC).

---

## 2. High-Level Component Architecture

Climatomaton consists of the **Core Daemon** and its **Pluggable Subprocesses** (PRM and PEMs).

### 2.1 Core System Components

1. **Discord Gateway Interface (DGI):** Manages the outbound WebSocket connection to Discord, listens for message events in the target channel, and handles outgoing messages/DMs via the Discord REST API.
2. **State Rehydrator:** Scans channel history backward upon startup or manual trigger to locate the most recent Climate Report or the "Turn 1" EOT report to establish the current `climate` namespace.
3. **Command Parser:** Intercepts slash commands (`/climate`) and DMs. Differentiates between standard Discord command payloads and the streamlined DM syntax, applying specific rules for optional arguments.
4. **EOT Parser:** Uses regex matching to parse EOT reports for round number, turn number, and proposal outcomes (`#3[0-9]+` identifiers).
5. **Environment Manager:** Scaffolds the `climate`, `proposals`, `var`, and external PEM namespaces. It selectively duplicates only explicitly registered mutable variables into the `new.` transaction environment.
6. **Rules Engine:** Compiles and evaluates rule conditions against the environments and applies actions to the transaction and variable environments.
7. **IPC Broker (File-System/Shared-Memory Based):** Manages local, socketless communication with the PRM and PEMs via memory-mapped shared volumes and `inotify` file watchers.

---

## 3. Communication Protocols (Non-Socket IPC)

Because inbound networking is prohibited and standard sockets/STDIO introduce either network stacks or tight synchronous coupling, Climatomaton uses **Memory-Mapped File System IPC** (POSIX Shared Memory via `/dev/shm` or standard Docker shared volumes).

Modules communicate by writing atomic JSON payloads to specific directories. The Core Daemon uses highly efficient kernel-level file watchers (e.g., `inotify` on Linux) to react to changes asynchronously.

### 3.1 PRM Protocol (Rules Module)

* **`push_rules` (PRM -> Core):** The PRM writes a new compiled JSON ruleset to `/shared/prm/active_rules.json.tmp`, then atomically renames it to `active_rules.json`.
* **Core Processing:** The Core's file watcher detects the rename, parses the new rules into an AST in the background, validates it against known schemas, and atomically swaps the active rules pointer.
* **Rule Identification:** Each rule in the payload contains a `rule_id`. If an execution error occurs, this ID is passed to the Notification system.

### 3.2 PEM Protocol (Environment Module)

PEMs manage external namespaces and register directly at the top level (e.g., a weather PEM registers as `weather.` rather than `ext.weather.`).

* **Schema Registration & Data Push (PEM -> Core):** PEMs write their schema (defining which variables are read-only vs. mutable) and their current state payload to `/shared/pems/{namespace}.json`.
* **Transaction Commit (Core -> PEM):** If rules mutate a PEM namespace (via `new.{namespace}.{var}`), the Core writes a diff file to `/shared/tx/req_{tx_id}_{namespace}.json`.
* **Acknowledgment:** The PEM processes the transaction and writes `/shared/tx/ack_{tx_id}_{namespace}.json`. The Core waits for this ACK asynchronously before posting the final Discord report.

### 3.3 Notification Protocol

* **`notify_admin`:** PRM or PEMs can drop files into a `/shared/notifications/` directory with a `level` and `message`. The Core consumes these files, logs them, and queues direct messages to Admin Discord IDs.

---

## 4. Environment & Execution Workflows

### 4.1 State Rehydration Workflow

Upon startup, or if memory is cleared:

1. Core queries the Discord API for target channel messages, paginating backward.
2. It looks for its own messages matching the format: *"The climate after round [X] turn [Y] is now [Z] and is [Tags]."*
3. If found, `climate.value = Z` and `climate.tags = [Tags]`.
4. If it hits a "Turn 1" EOT report first, it initializes to `0` and `Mild`.

### 4.2 Handling Missing PEM Data

If an EOT arrives, but the PRM rules rely on a PEM namespace that has not initialized or is missing data, the Core **cannot assume default values**.

1. **Suspension:** The Core places the parsed EOT into an internal "Pending EOT" queue.
2. **Notification:** It immediately fires a DM to administrators: *"EOT [Round X, Turn Y] processing suspended. Missing required PEM data for namespace: [{namespace}]. The system will wait for data."*
3. **Resolution:** The Core continues to watch the IPC directory. Once the missing PEM writes its data, the Core automatically un-suspends the EOT and continues processing. Alternatively, an admin can manually trigger a retry later using the `/climate process` command.

### 4.3 Rules Execution Workflow

Triggered when an EOT message is identified and all required PEM data is validated.

1. **Environment Initialization:**
* `climate.*` loaded from cache.
* `proposals.*` loaded from parser.
* `{pem_namespace}.*` loaded from latest PEM caches.
* `var.*` initialized (names auto-initialize to `0` upon first call).
* `new.*` populated as a clone of **only** the explicitly registered mutable fields from `climate` and PEM namespaces.


2. **Rules Processing (Ordered):** Climate rules evaluate and mutate `new.climate.value` or `var.*`. Tag rules evaluate and mutate `new.climate.tags`.
3. **Commit & Report:**
* Write `new.{pem_namespace}.*` diffs to `/shared/tx/`.
* Wait for PEM ACKs.
* Generate the formatted report and post to Discord.



### 4.4 Natural English List Formatting

When generating the final report string, the system applies standard English list rules (including the Oxford comma) for tags:

* **0 Tags:** "The climate after round X turn Y is now Z."
* **1 Tag:** "...is now Z and is Mild."
* **2 Tags:** "...is now Z and is Greenhouse and Windy."
* **3+ Tags:** "...is now Z and is Greenhouse, Windy, and Unstable."

---

## 5. Command Interface

Admins interact via `/climate` channel commands or direct messages.

### 5.1 DM Streamlined Syntax & Optional Arguments

For streamlined DMs, commands follow a strict positional structure to resolve ambiguity with optional arguments: `[command] [optional_value] [optional_tags...]`

**Rules for Optional Arguments:**

* Positional optional arguments can be omitted from right-to-left simply by leaving them out.
* To omit an earlier positional argument while providing a subsequent one, a placeholder character (`-`) must be used.
* Tags are separated by commas to allow spaces within the tag names.

**Command Definitions:**

* **`reset`**
* *No arguments:* Ignored/Returns an error (e.g., *"Error: reset requires arguments. Use `reset default` or provide values."*)
* `reset default` $\rightarrow$ Resets `climate.value` to `0` and `climate.tags` to `["Mild"]`.
* `reset 15` $\rightarrow$ Sets value to 15. Tags are omitted (preserved as-is).
* `reset - Greenhouse Effect, High Winds` $\rightarrow$ Value is omitted (preserved as-is). Tags are replaced.
* `reset 12 Stable` $\rightarrow$ Value is set to 12. Tags are replaced with `["Stable"]`.


* **`process [message]`**
* `process 112233445566778899` (ID) or `process https://discord.com/channels/...` (URL).
* Required argument. Parses the target message and runs the EOT workflow immediately.



---

---

### Responses to Your Issues

**1. IPC Alternatives:**
You are completely right, and I apologize for the oversight. HTTP and ZeroMQ rely on network sockets (even if restricted to loopback), and STDIO creates tight synchronous coupling that blocks the core engine. I have updated the architecture document (Section 3) to use **Memory-Mapped File System IPC** (e.g., POSIX Shared Memory `/dev/shm` or standard Docker shared volumes) combined with `inotify` (file system events). This is a truly socketless approach that relies on atomic file operations. It completely decouples the processes, allowing the PRM and PEMs to run and push data entirely on their own asynchronous loops without adding blocking latency to the Core Engine's EOT response time.

**2. Handling Missing PEM Defaults:**
Spot on. Assuming defaults (like `0`) for complex external systems like an economy or weather namespace would instantly break the rules execution. In Section 4.2, I introduced a **Suspend and Queue** protocol. If the Core tries to process an EOT report but lacks the necessary PEM data to resolve the namespace paths in the rules, it pauses the EOT processing, drops the EOT report into a pending queue, and sends an alert to the admins. Once the PEM pushes the missing data via IPC, the Core automatically resumes the EOT processing. This prevents invalid state computation while ensuring the EOT is not ignored.

**3. Optional Command Arguments:**
I have explicitly defined the parsing rules for optional arguments in Section 5.1. Because the `reset` command needs to handle resetting *just* the value, *just* the tags, or *both*, I implemented a right-to-left omission rule with a placeholder requirement. If you want to omit an earlier argument (like the numeric value) but provide a later argument (like the tags), you must use a placeholder (like `-`). Otherwise, optional arguments can simply be left off the end. I also explicitly included the `reset default` keyword to handle resetting to the initial state, rather than defaulting to it when no arguments are provided.
