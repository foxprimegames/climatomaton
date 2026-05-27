Here is the architecture specification for **Climatomaton**, designed to meet your requirements for a stateless, reactive, and highly modular Discord bot.

---

# Architecture Specification: Climatomaton

## 1. System Overview

**Climatomaton** is an automated, completely stateless Discord bot designed to manage the "climate" of the Nomic-style game Nomicron. It operates entirely by observing outbound connections to Discord, reading game history to establish state, and evaluating an externally provided ruleset to process end-of-turn (EOT) reports.

### Core Constraints & Solutions

* **Statelessness (No Database):** State is treated as an ephemeral cache. If the bot restarts, it rebuilds the current climate state by reading backward through the Discord channel history to find the most recent valid Climatomaton report.
* **No Inbound Network Connectivity:** The bot connects to Discord via the Discord Gateway (outbound WebSocket connection). It cannot accept incoming webhooks. Interprocess communication (IPC) is used to communicate with the Pluggable Rules Module (PRM) and Pluggable Environment Modules (PEMs).

---

## 2. High-Level Component Architecture

Climatomaton consists of the **Core Daemon** and its **Pluggable Subprocesses** (PRM and PEMs).

### 2.1 Core System Components

1. **Discord Gateway Interface (DGI):** Manages the outbound WebSocket connection to Discord, listens for message events in the target channel, and handles outgoing messages/DMs via the Discord REST API.
2. **State Rehydrator:** Scans channel history backward upon startup or manual trigger to locate the most recent Climate Report or the "Turn 1" EOT report to establish the current `climate` namespace.
3. **Command Parser:** Intercepts slash commands (`/climate`) and DMs. Differentiates between standard Discord command payloads and the streamlined DM syntax.
4. **EOT Parser:** Uses regex matching to parse EOT reports for round number, turn number, and proposal outcomes (`#3[0-9]+` identifiers).
5. **Environment Manager:** Scaffolds the `climate`, `proposals`, `var`, and `ext` (PEM) namespaces. It also duplicates read-only data into the `new.` transaction environment.
6. **Rules Engine:** Compiles and evaluates rule conditions (boolean/arithmetic ASTs) and applies actions to the transaction and variable environments.
7. **IPC Broker:** Manages standard local communication (via UNIX Domain Sockets or Named Pipes) with the PRM and PEMs, handling atomic updates and outbound notifications.

---

## 3. Communication Protocols

Because inbound networking is prohibited, climatomaton relies on local IPC. **JSON-RPC 2.0 over UNIX Domain Sockets (or Windows Named Pipes)** is the chosen protocol. It allows bidirectional, asynchronous communication between the Core and its modules.

### 3.1 PRM Protocol (Rules Module)

The PRM runs as an external process. It monitors external rule sources and pushes updates to the Core.

* **`push_rules` (PRM -> Core):** The PRM sends a new JSON ruleset. The core parses this ruleset into memory. To guarantee atomic, non-blocking updates, the Core uses a pointer swap: it builds the new rule ASTs in the background, and once compiled, swaps the active rules reference. Any currently executing EOT process finishes using the old reference.
* **Rule Identification:** Each rule in the payload must contain a `rule_id` and `source_line` or `source_hash`. If the Rules Engine encounters an execution error, this ID is passed to the Notification system for admin debugging.

### 3.2 PEM Protocol (Environment Module)

PEMs manage external namespaces (e.g., player stats, economy).

* **`push_namespace` (PEM -> Core):** Similar to rules, PEMs push updated structured data asynchronously. The Core caches this atomically under the specific PEM's namespace prefix (e.g., `ext.economy.`).
* **`commit_transaction` (Core -> PEM):** If a tag or climate rule mutates a namespace belonging to a PEM (via `new.ext...`), the Core sends a JSON-RPC request back to the PEM after rules processing containing only the diff/mutated values. The PEM must respond with a success acknowledgment before Climatomaton posts the final report to Discord.

### 3.3 Notification Protocol

* **`notify_admin` (PRM/PEM -> Core):** Modules can invoke this IPC method with a `level` (Info, Warn, Error) and a `message`. The Core logs this to standard out and queues a direct message to the configured Admin Discord IDs.
* **Internal Notifications:** The Rules Engine will internally call this same routine if an expression fails to evaluate or if Discord API limits are hit.

---

## 4. Environment & Execution Workflows

### 4.1 State Rehydration Workflow

When Climatomaton starts, or if a rule requests `climate` data but memory is blank:

1. Core queries Discord API for messages in the target channel, starting from the present and paginating backward.
2. It looks for a message authored by itself matching the descriptive format: `The climate after round [X] turn [Y] is now [Z] and is [Tags].`
3. If found, `climate.value = Z` and `climate.tags = [Tags]`.
4. If the search hits a message explicitly identified as "Turn 1" EOT report without finding a prior climate report, it initializes to `0` and `Mild`.

### 4.2 Rules Execution Workflow

Triggered when an EOT message is identified by the DGI or manually via `process`.

1. **Parsing:** Extract round, turn, and count proposals (`proposals.count`, `.passed`, `.failed`).
2. **Environment Initialization:**
* `climate.*` loaded from cache (or rehydrated).
* `proposals.*` loaded from parser.
* `ext.[pem_name].*` loaded from latest PEM pushes.
* `var.*` initialized as empty (names auto-initialize to `0` upon first evaluation request).
* `new.*` populated as a deep clone of mutable namespaces (`climate`, `ext`).


3. **Climate Rules Processing (Ordered):**
* Iterate through climate rules. Evaluate conditions against the environment.
* If `true`, execute actions modifying `new.climate.value` or `var.*`.


4. **Tag Rules Processing (Ordered):**
* Iterate through tag rules. Evaluate conditions.
* If `true`, execute `includes` / `excludes` actions on `new.climate.tags`.


5. **Commit & Report:**
* Send `new.ext.*` diffs to respective PEMs.
* Generate descriptive report string: *"The climate after round [X] turn [Y] is now [new.climate.value] and is [new.climate.tags.join(' and ')]."*
* Post to Discord.
* Update local ephemeral cache with new state.



---

## 5. Command Interface

Climatomaton accepts commands from designated administrators.

### 5.1 Slash Commands (Channel/Guild level)

Follows strict Discord Interaction data structures:

* `/climate reset [value: integer] [tags: string]`
* `/climate process [message: string (ID or URL)]`

### 5.2 DM Streamlined Syntax

Because DMs don't strictly require the interaction UI, admins can type commands in raw text.

* **Parser Rules for Streamlined Syntax:** * Arguments are space-separated. Quotes (`"`) can group strings with spaces.
* **Omission Logic:** Optional arguments must be positional. If `reset` is called with no arguments, it implies `reset 0 Mild`. If one argument is passed, it is strictly typed as the `value` (meaning tags remain unchanged or fall back to an empty set, depending on admin preference—suggesting the former). If tags are provided, a value *must* precede them.


* **Examples:**
* `reset` -> Sets to `0` and `Mild`.
* `reset 15` -> Sets value to 15, clears tags.
* `reset 12 Greenhouse Windy` -> Sets value to 12, tags to `Greenhouse` and `Windy`.
* `process 112233445566778899` -> Immediately runs the EOT workflow on that message ID.
* `process https://discord.com/channels/...` -> Parses URL for message ID and processes.



---

## 6. Expression & Rule Structure Overview

Rules will be compiled into an Abstract Syntax Tree (AST) to allow arbitrarily complex logic.

* **Arithmetic AST Nodes:** Add, Subtract, Multiply, Divide, Modulo, Exponentiate, Grouping `()`. Functions like `abs()`, `max()`, `min()`.
* **Boolean AST Nodes:** And, Or, Not, `<`, `>`, `<=`, `>=`, `==`, `!=`. Range syntax (e.g., `value in [10..20]`).
* **Variables:** Any identifier starting with `var.` that does not exist in the environment lookup table instantly returns `0` and is added to the mutable variable map.

*(Note: The exact grammar (e.g., EBNF) for the custom rules language can be designed in the next phase, but the system will use a standard lexer/parser approach to convert the string formulas from the PRM into executable closures.)*
