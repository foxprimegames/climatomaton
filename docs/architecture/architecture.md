# Climatomaton: Comprehensive Architecture & Specification Document

This document defines the complete system architecture, grammar specification, environment extensibility model, and execution lifecycle for the containerized, database-less Discord game engine, Climatomaton.

## 1. System Overview & Deployment Model

Climatomaton is a stateless, event-driven game engine that maintains an in-memory "climate" state (a numeric value and a unique set of string tags) by listening to structured proposal reports in a specific Discord channel.

### Containerization & Environment Configuration

The engine is deployed as a single process inside a Docker container. It exposes no inbound network ports or webhooks, rendering it fully isolated from external network attacks. All operational parameters are injected at runtime via process environment variables. These configuration parameters must supply:

* **Authentication Credentials**: The cryptographic token required to securely connect and authenticate with the Discord Gateway.
* **Target Location Identifiers**: The specific server (guild) and channel identifiers where proposals are monitored and output updates are posted.
* **Authorized Administrator Identifiers**: A list of authorized administrator user IDs permitted to issue manual, direct climate modifications, administrative DMs, and bypass controls.
* **Optional Discord Logging Destination**: An optional target identifier (such as a specific Discord channel ID or administrator's DM snowflake ID) used for secondary routing of core engine logs.
* **Execution Tuning Parameters**: General runtime parameters, intervals, verbose logging flags, or threshold settings that govern background processing loops, timing behaviors, or resource limits not specified elsewhere.

---

## 2. Climate and Tag Rules Specification

Rules govern how proposals and environmental changes mutate the climate's numerical state and active tags. They are written in a custom, human-readable Domain-Specific Language (DSL) and are split into two execution scopes: climate rules and tag rules.

### Formal Extended Backus-Naur Form (EBNF) Syntax

```
File          ::= ( ClimateRule | TagRule )*
ClimateRule   ::= "climate" "rule" String "when" Expression "then" ClimateActions "end"
TagRule       ::= "tag" "rule" String "when" Expression "then" TagActions "end"
Expression    ::= LogicalOr
LogicalOr     ::= LogicalAnd ( "or" LogicalAnd )*
LogicalAnd    ::= Inversion ( "and" Inversion )*
Inversion     ::= [ "not" ] Relational
Relational    ::= ArithExpr RelOp ArithExpr [ RelOp ArithExpr ]               
                | NamespacePath "contains" String
ArithExpr     ::= Term ( ( "+" | "-" ) Term )*
Term          ::= Factor ( ( "*" | "/" ) Factor )*
Factor        ::= Number | NamespacePath | "(" ArithExpr ")"
NamespacePath ::= Identifier ( "." Identifier )*
RelOp         ::= "==" | "!=" | ">" | "<" | ">=" | "<="
ClimateActions::= ( NamespacePath ( "+=" | "-=" | "=" ) ArithExpr ";" )+
TagActions    ::= ( ( "include" | "exclude" ) TagList ";" )+
TagList       ::= String ( "," String )*
```

### Grammar Example

```
climate rule "Greenhouse Acceleration"
when proposals.passed > 3 and (0 < climate.value <= 90)
then
    climate.value += proposals.passed * 1.5;
end

tag rule "Atmospheric Desolation"
when climate.value >= 85 or economy.inflation > 10.0
then
    include "volatile", "scorched";
    exclude "temperate", "hospitable";
end
```

* **`include` Semantics:** Evaluates each string in the comma-separated list. If the tag is missing from the active set, it is added. If it is already present, it is safely ignored.
* **`exclude` Semantics:** Evaluates each string in the comma-separated list. If the tag exists in the active set, it is removed. If it does not exist, it is safely ignored.

---

## 3. Rules Files Handling Specification

This section defines how the core engine reads, parses, orders, and identifies rules split across multiple physical files on disk. Precedence and execution order are derived deterministically from the filesystem layout.

### The Commit Manifest

Before the core engine can discover, parse, or execute rules, the active execution environment must be resolved. This is managed by a **Commit Manifest**.

The Commit Manifest is a dedicated coordination component that acts as a globally accessible pointer. It resides at the fixed, static path `rules.commit` relative to the root of the shared volume and serves as the atomic single source of truth for the active system path. While its specific serialization format is defined separately, the Commit Manifest is required to convey the following information:

* **The Target Directory Path**: The manifest must contain a payload that explicitly defines the filesystem path of the directory (specified relative to the root of the shared volume) containing the complete, validated rule files and associated environmental structures for the active operational cycle.
* **System Readiness Signal**: The atomic completion of writing or updating the manifest acts as a system-wide trigger, indicating that all background file updates are finished and the target directory is fully structured and ready for processing.

### Directory Structure Example

```
[shared volume root]/
├── rules-20260520-143022/    # Legacy directory (deleted by engine after swap)
├── rules-20260520-225718/    # Active directory currently read by the engine
│   ├── 101-base.rules        # Rule file
│   ├── economy.json          # Pluggable environment module state file
│   └── factions.json         # Pluggable environment module state file
└── rules.commit              # Atomic manifest file pointing to the live path
```

### File Naming Convention

All rule configuration files must reside within the directory specified by the current contents of the Commit Manifest and must conform to the following filename standard:

* Files must use the `.rules` extension.
* Files must begin with an integer prefix (the `FileNumber`), immediately followed by a hyphen, and end with a descriptive identifier string.
* *Syntax format:* `[FileNumber]-[Descriptor].rules` (e.g., `101-base.rules`, `101-expansion.rules`, `102-custom.rules`).

### How Filenames Are Used

The system parses the physical filenames on disk to organize the logical priority and execution order of the compilation units:

1. **Primary Grouping:** The engine extracts the leading numeric characters (`FileNumber`) as an integer. This integer represents the rule set's primary execution tier.
2. **Deterministic Tie-Breaking:** If multiple rule files share the exact same `FileNumber` integer prefix (representing modular sub-sets or expansions), the engine sorts those specific files alphabetically (lexicographically) by their full filename. This ensures that `101-base.rules` is consistently compiled before `101-expansion.rules`.

### Multi-File Collation & Merging Algorithm

To support splitting rules seamlessly across several files sharing a prefix, the compiler executes a strict collation and sequential indexing sequence:

1. **Sort Compilation Targets:** Collect all active `.rules` files in the directory. Sort them ascending by their numeric `FileNumber`. For matching prefixes, apply secondary alphabetical sorting on the filename string.
2. **Continuous Rule Indexing:** Initialize independent sequential counters starting at `1` for each of the two rule scopes: Climate Rules and Tag Rules.
3. **Sequential Processing:** Iterate through the sorted files. For each file encountered, parse the rules sequentially.
4. **ID Allocation:** Assign each parsed rule a permanent string identifier matching the format:

   ```
   Rule ID = FileNumber-RuleIndex
   ```

   * **`FileNumber`**: The primary prefix of the current file.
   * **`RuleIndex`**: The running sequential index for that rule's scope. The counter increments continuously across file boundaries within files sharing the identical `FileNumber` prefix. The counter resets back to `1` only when the compiler transitions to a file with a *new* numeric `FileNumber` prefix.

#### Compilation and Sorting Matrix Example

Consider three files sharing a compilation folder: `101-base.rules`, `101-expansion.rules`, and `102-custom.rules`. The files are grouped and ordered as follows:

```
Group 101 Files (Merged):
  1st: 101-base.rules
  2nd: 101-expansion.rules

Group 102 Files:
  1st: 102-custom.rules
```

This merges and compiles the rules into the following deterministic execution sequence:

| **Physical Source File** | **Rule Text Sequence Block** | **Scope** | **Assigned ID** | **Execution Sequence** |
| :--- | :--- | :--- | :--- | :--- |
| `101-base.rules` | `climate rule "First Base"...` | Climate | `101-1` | 1st in Climate Scope |
| `101-base.rules` | `climate rule "Second Base"...` | Climate | `101-2` | 2nd in Climate Scope |
| `101-base.rules` | `climate rule "Third Base"...` | Climate | `101-3` | 3rd in Climate Scope |
| `101-expansion.rules` | `climate rule "First Expansion"...` | Climate | `101-4` | 4th in Climate Scope |
| `102-custom.rules` | `climate rule "First Custom"...` | Climate | `102-1` | 5th in Climate Scope |

### Hierarchical Sorter Execution

During execution, rules within each isolated scope (Climate Rules in Phase 1, Tag Rules in Phase 2) are processed sequentially. Their execution order is resolved by comparing their identifier components as numeric integers:

* First, compare the `FileNumber` numerically. Rules with a lower file number prefix execute first.
* Second, if the file numbers are identical, compare the `RuleIndex` numerically. Rules with a lower index execute first.

---

## 4. Pluggable Rules Modules Specification

A **Pluggable Rules Module** is an external system or compilation pipeline responsible for generating, updating, and exporting rule configurations to the shared volume.

### Activation & Scaling Bound

* **Exactly one** pluggable rules module must be active and operational within the system landscape at any given time. This rules module acts as the sole, authoritative source of game mechanics and logic constraints.

### Contract for Pluggable Rules Modules

To interface successfully with the Climatomaton core engine, the active rules module must adhere to the following contract:

1. **Directory Isolation:** The rules module must write all updated rule files into a brand-new, uniquely named directory (e.g., `rules-YYYYMMDD-HHMMSS/` relative to the root of the shared volume) to guarantee write isolation.
2. **File Standards:** All generated rule files must end with the `.rules` extension and strictly conform to the specifications outlined in Section 3 and the EBNF grammar defined in Section 2.
3. **Atomic Manifest Write:** The module must not modify active rules in place. It must fully write, flush, and close all files in the new staging folder *before* updating the Commit Manifest.
4. **Commit Notification with Atomic Write-and-Rename:** The module must signal readiness to the rest of the application by updating the Commit Manifest (defined in Section 3) with a payload denoting the path of the newly populated directory relative to the shared volume root. To prevent other modules or the core engine from reading a partially updated path, the module must follow this operational sequence:
   * Write the relative target directory path payload to a hidden temporary manifest file at the root of the shared volume (e.g., `.rules.commit.tmp` relative to the shared volume root).
   * Flush all file handles and close the temporary file on disk.
   * Perform an atomic OS-level rename operation to replace the Commit Manifest at its defined static path (`rules.commit` relative to the shared volume root).

---

## 5. Pluggable Environment Modules Specification

A **Pluggable Environment Module** is an independent, external script or database-less microservice that models and manages secondary environmental variables (such as an economy system, a faction status tracker, or local weather states).

### Activation & Scaling Bound

* **Zero or more** pluggable environment modules may be active at any given time. The core engine does not hardcode, register, or maintain ahead-of-time knowledge of these modules, allowing them to be dynamically introduced or decommissioned.

### Contract for Pluggable Environment Modules

To integrate safely without leaking stale state data across container lifecycles, every pluggable environment module must conform to the following contract:

1. **Manifest Observation:** The module must continuously monitor the Commit Manifest at its defined static path (specified in Section 3 as `rules.commit` relative to the shared volume root) for updates.
2. **Dynamic Redirection:** Upon detecting a new path via the Commit Manifest, the module must immediately direct its snapshot-writing routines to dump its active state data file into that newly specified folder.
3. **Strict Namespace Matching:** The state file must be exported as a valid, flat or nested JSON structure. The filename must match the exact top-level namespace the module intends to capture (e.g., the file `economy.json` maps directly to the `economy` namespace on the core engine's memory graph).
4. **Atomic Write-and-Rename Protocol:** To ensure the core engine never reads a partially written JSON payload during a busy execution tick, the module must follow this operational sequence:
   * Write its fresh state snapshot to a hidden temporary file inside the target folder (e.g., `.economy.json.tmp`).
   * Flush all file handles and close the file on disk.
   * Perform an atomic OS-level rename operation to move `.economy.json.tmp` to its final name `economy.json`.

---

## 6. Dynamic Rule & Environment Synchronization Protocol

To completely eliminate the risk of stale data building up when an external feature module is decommissioned, both the rule configuration files and the pluggable environmental snapshot files share a single, unified folder lifecycle using an atomic directory rotation protocol across a shared Docker volume.

### The Synchronization & Directory Rotation Lifecycle

The active rules module, the pluggable environment modules, and the Climatomaton engine thread coordinate on a shared volume according to this sequential timeline:

1. **Staging Generation:** The single active rules module compiles rules, creates a new isolated directory relative to the shared volume root, and writes `.rules` files there.
2. **Staging Commit:** The rules module updates the Commit Manifest with the relative path to the new directory using the *Atomic Write-and-Rename* protocol.
3. **Pluggable Module Migration:** All active environment modules (zero or more) detect the update in the Commit Manifest. They immediately migrate their tracking and write their state files into the new directory using the *Atomic Write-and-Rename* protocol (`.json.tmp` -> `.json`).
4. **Dynamic Dependency Extraction, Validation, and Swap:** The Climatomaton background thread detects the change in the Commit Manifest and targets the staging directory. It executes a three-part validation pipeline:
   * **Dynamic Dependency Extraction:** The engine parses all `.rules` files in the staging folder and scans them for references to any `NamespacePath` (e.g., `economy.inflation`). Any external top-level namespace identified (excluding the native `climate` and `proposals` namespaces) is added to a dynamically compiled **Required Modules List** (e.g., requiring the file `economy.json`).
   * **Atomic Presence Verification:** The engine validates that all `.rules` files pass syntax checks, and then polls the folder. It will *only* proceed once *every* file on the dynamically compiled "Required Modules List" physically exists in its final, renamed state (e.g., `economy.json`).
   * **Staged Pointer Swap:** If any files are missing, the engine aborts the active cycle, logs a trace status, and waits for the next polling interval. Once all validations and dynamic dependencies are fully met, it loads the rules into `StagingRegistry` and executes an atomic memory pointer swap to activate the new directory.
5. **Garbage Collection & Stale Pruning:** With the old directory completely unlinked from the live memory pointer, Climatomaton issues a file system command to recursively delete the previous folder. Because a decommissioned environment module would never write to the *new* directory, its old files are purged automatically, eliminating data leakage.

---

## 7. Data Environment & Base Objects Specification

The runtime evaluation environment is managed as a dynamic, nested in-memory object graph. To prevent code inflation when underlying components introduce new fields, the engine resolves paths by inspecting properties dynamically at runtime.

### Base Object Structure

The core environment guarantees two foundational top-level object spaces:

* **`climate`**: Tracks engine-managed states (`value`, `tags`).
* **`proposals`**: Tracks event metadata compiled from the incoming Discord proposal report (`count`, `passed`, `failed`).

---

## 8. Bootstrapping & State Recovery Engine

Because Climatomaton maintains its data strictly in memory, it reconstructs its climate state upon startup by scanning the target Discord channel's history logs backward from the present moment. This scan relies on a chronological layout to safely capture human administrative updates and anchor state boundaries.

### Chronological Lookback Algorithm

1. **Ingest Log Stream (Discord History API):** The engine connects to the target channel and requests message blocks, moving backward chronologically from the present.
2. **Evaluate for State Report (Pattern Match Evaluation):** The engine checks each message against the climate report signature. To allow for human intervention if the container experiences downtime, the message is recognized as valid if it originates either from Climatomaton's own active user identity or from an identity configured inside the authorized administrative user list.
3. **Hydrate Memory State (State Anchor Found):** The very first matching climate report encountered breaks the lookback loop. Because messages are scanned backward, this report is guaranteed to be the most recent state. The engine parses the numeric value and the text-formatted tag array directly into memory, terminates the scan, and completes bootup silently.
4. **Intercept Round Edge (Boundary Collision Detection):** If the engine encounters a proposal report indicating *Turn 1* of a round, or a proposal report belonging to a *previous* round number before finding a climate report, it implies that a fresh round has started and no climate data has been generated yet.
5. **Bootstrap Default Clean State (System Baseline Reset):** Upon hitting a round boundary collision or reaching the end of the channel history without a match, the loop terminates immediately. Climatomaton initializes its clean baseline state for the active round (`climate.value = 0` and `climate.tags = []`) and finishes booting silently.

### Administrative Failure Recovery via Direct Message

To resolve processing failures without relying on volatile in-memory history (which is lost if the bot crashes or restarts), the engine implements a persistent direct-message retrieval protocol:

* **Command Interface**: Authorized administrators (identified by the authorized user list defined in Section 1) can send a Direct Message (DM) to the bot containing a structured manual execution command (e.g., `reprocess [Proposals-Message-ID]`).
* **Stateless Message Retrieval**: Upon receipt of this command, the bot extracts the target Discord Message ID (snowflake) of the failed proposal report. Because it cannot rely on active memory, the bot issues a stateless call to the Discord API to fetch the specified message directly from the historical log of the monitored proposals channel.
* **Transaction Execution**: Once the target message is successfully retrieved, the bot parses its content, parses the metadata into the `proposals` namespace, and forces a sequential transaction execution loop directly against the active in-memory state, writing the updated outputs to the channel upon successful processing.

---

## 9. Two-Stage Batch Execution Pipeline

When a new proposal report is received via the Discord gateway during normal live runtime operations, the evaluation engine locks the transaction pipeline and processes the state changes through three precise sequential phases.

* **Phase 0: Dynamic Environment Rehydration:** Before evaluating any rules, Climatomaton opens the current active directory (as declared by the Commit Manifest). It reads all valid `.json` files present in that folder. The filename maps directly to the root namespace (e.g., if `economy.json` is read, its parsed data structural hierarchy is instantly attached to the in-memory data graph under the `economy` namespace), ensuring that real-time pluggable metrics are fully up to date for this transaction cycle.
* **Phase 1: Climate Processing Batch:** The engine gathers all compiled climate rules across all files, sorts them using the hierarchical numeric sorting rules (`101-1` -> `101-2` -> `101-3` -> `101-4`), and begins evaluation. All arithmetic actions (`=`, `+=`, `-=`) apply sequentially to a temporary numerical floating-point buffer. Once every climate rule has been processed, the finalized number is written permanently to `climate.value`.
* **Phase 2: Tag Processing Batch:** The engine freezes the updated `climate.value` and gathers all compiled tag rules across all files, sorting them using the hierarchical numeric sorting rules. It evaluates their conditions against the settled environment data graph. Tag mutations (`include`, `exclude`) modify an in-memory unique string array.

### Global Failure and Transaction Abort Protocol

To guarantee mathematical consistency and prevent partial state mutations, the core engine treats rule evaluation as a single atomic transaction.

If *any* rule execution fails—including path resolution failures (e.g., an unresolvable `NamespacePath` in a rule condition or action) or syntax interpretation issues:

1. **Immediate Execution Termination**: The engine halts the active evaluation cycle immediately and discards all pending modifications. No rules beyond the point of failure are processed.
2. **Transaction Rollback**: The active, in-memory climate state is completely rolled back. **No changes are written to the live variables** (`climate.value` and `climate.tags` remain exactly as they were prior to the transaction).
3. **Core Engine Dual-Delivery Logging**: The failure is reported immediately via the core engine's dual-delivery log pipeline. The log message must simultaneously output to:
   * **The Local Process Terminal**: Standard output and error streams (`stdout`/`stderr`) of the container process.
   * **The Discord Logging Target**: An optional dedicated Discord logging channel or administrator DM target configured at runtime (if configured).
4. **Failure Message Payload**: The emitted log message must include:
   * The unresolvable path or error traceback.
   * The specific Rule ID where the execution failed.
   * **The exact proposals report (Message ID, raw content, and parsed metadata)** that triggered the failed evaluation, allowing administrators to inspect the exact input payload that broke the transaction pipeline.

---

## 10. Output Notification Specification

During standard live runtime operations, every processed proposal report triggers an evaluation cycle and a matching chat report in the channel, regardless of whether the numbers or tags actually shifted. Active tags are automatically sorted alphabetically before the output string is assembled.

The engine prints plain English prose using a strict grammatical layout determined by the number of active tags:

* **Case A: Empty Tag Arrays**
  If there are no tags currently in memory, the trailing conjunction clause is omitted.
  ```
  The climate is now 52.5.
  ```
* **Case B: Exactly One Active Tag**
  ```
  The climate is now 60.0 and is stable.
  ```
* **Case C: Exactly Two Active Tags**
  ```
  The climate is now 45.0 and is arid and cold.
  ```
* **Case D: Three or More Active Tags (Serial Comma Layout)**
  ```
  The climate is now 81.2 and is advanced, industrialized, and volatile.
  ```

---

## 11. Staging and Production Deployment Strategy

To ensure system stability, Climatomaton utilizes separate, isolated environments for development validation and live game play.

### Staging vs. Production Environment Matrices

```
[Staging System Configuration]                       [Production System Configuration]
  - Test Guild & Dev Channels                         - Main Play Guild & Public Channels
  - Verbose Debug Logging Target                       - Production Logging Channel/DM
  - Rules Watcher: Verbose Flag True                  - Rules Watcher: Verbose Flag False
```

Deployment boundaries are enforced strictly by injecting differing process environment parameters across environments.

#### The Staging Environment

The staging system mirrors production but targets test infrastructure to facilitate continuous integration checks and dry-run rule executions:

* **Target Redirection**: Configured with credentials and target IDs pointing to a dedicated developer Discord server (test guild) and isolated sandbox channels.
* **Core Engine Dual-Logging**: Configured to route error tracebacks and transactional outputs to a private developer Discord channel or private developer direct message.

#### Verbose Logging Configurations

In the staging environment, the engine can be configured to enable verbose logging. When activated, the engine writes supplementary tracking logs to both local output streams and the Discord logging target. These verbose logs include:

* **Rule Compilation Dumps**: Emitting logs whenever rules are compiled, indexing sequences are changed, or rules directories are swapped via the Commit Manifest (detailing the list of compiled rule IDs and file groupings).
* **Execution Environment Snapshots**: Dumping the complete, parsed JSON data graph (`climate` values, compiled `proposals` metrics, and the fully rehydrated namespaces from pluggable environmental JSON structures) used during each transaction cycle, giving developers a complete view of inputs and outputs for every execution step.
