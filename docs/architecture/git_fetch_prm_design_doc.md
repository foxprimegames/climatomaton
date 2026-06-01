# Git-Fetch Pluggable Rules Module (PRM) Design Document

## 1. System Overview

The Git-Fetch Pluggable Rules Module (PRM) is a stateless, independent container process within the Climatomaton architecture. While other PRM implementations may be developed in the future, this specific module is explicitly responsible for synchronizing Nomicron game rules from an external, publicly-accessible Git repository, parsing the human-readable source files, and compiling them into a unified JSON Intermediate Representation (JSON-IR).

To strictly maintain the system constraint of having no exposed inbound connectivity endpoints, the PRM relies on a continuous outbound polling loop rather than incoming webhooks.

## 2. Git Synchronization & Configuration

The Git-Fetch PRM retrieves rule source files from a remote repository. To optimize performance, eliminate the dependency on a system-level executable, and maintain a highly secure container image, the PRM utilizes the `dulwich` library. As a pure-Python implementation of the Git protocol, `dulwich` supports true 100% in-memory repository operations, avoiding the need for local disk staging.

### 2.1 Configuration Parameters

The PRM container requires the following parameters, injected strictly via environment variables at runtime:

* `GIT_REPO_URL`: The full URL to the target public repository.
* `GIT_BRANCH`: (Optional) The specific named branch to track. Defaults to `main`.
* `GIT_TARGET_DIR`: The specific directory path within the repository where the rules are stored (e.g., `rules/`).
* `POLL_INTERVAL`: The integer duration (in seconds) between outbound fetch attempts.
* `SYNC_FAILURE_THRESHOLD`: (Optional) The number of consecutive failed sync attempts permitted before generating an administrative alert. Defaults to `3`.

### 2.2 Synchronization Workflow

1. **Initial Clone:** Upon startup, the PRM performs an in-memory shallow clone of the configured `GIT_BRANCH` from the `GIT_REPO_URL`.
2. **Polling Loop:** The PRM enters a sleep cycle determined by `POLL_INTERVAL`.
3. **Fetch & Compare:** Upon waking, the PRM performs a fetch operation. It compares the local HEAD commit hash against the remote branch's HEAD commit hash.
   * If the hashes match, no changes have occurred. The PRM returns to sleep.
   * If the hashes differ, the PRM explicitly updates its in-memory tree to the remote branch tip. This gracefully handles scenarios where the branch has changed in a way that causes a standard fast-forward merge to fail (e.g., a forced push or history rewrite).
   * Following the update, the PRM triggers the File Discovery and Compilation phases.

## 3. File Discovery & Filtering

The target Git directory may contain non-rule assets. The PRM must isolate valid rule source files from a flat directory structure.

### 3.1 Filtering Protocol

* The PRM scans the directory specified by `GIT_TARGET_DIR`. Deep directory scanning or recursive globbing is not supported; the scan is strictly flat.
* It explicitly filters the directory contents, exclusively selecting files that end with the `.rules` extension. Any file without this extension is ignored.

### 3.2 Deterministic Ordering

To ensure consistent execution logic across deployments, the PRM compiles rules based on an explicit, deterministic sequence:

* The filtered list of `.rules` files is sorted alphabetically by filename in ascending order.
* Rule authors wishing to enforce a specific execution priority among multiple files must utilize numeric prefixes in the filenames (e.g., `01_base.rules`, `02_overrides.rules`).

## 4. Compilation & JSON-IR Generation

The PRM is responsible for translating the human-readable `.rules` files into the Core Daemon's JSON-IR. The compilation process utilizes a standard compiler frontend pipeline to guarantee syntactic correctness before emission.

### 4.1 Parser Architecture

The PRM implements a three-stage parsing pipeline: Lexical Analysis, Syntactic Analysis, and IR Emission. It utilizes a robust Python-based parsing library capable of directly consuming the established EBNF grammar, ensuring the parser remains strictly synchronized with the language specification.

### 4.2 Lexical Analysis (Tokenization)

The lexer scans the raw text of the `.rules` files and converts it into a stream of recognized tokens.

* **Keywords & Identifiers:** Extracts keywords (e.g., `climate rule`, `when`, `then`) using case-insensitive matching, alongside variable/namespace identifiers.
* **Strings & Literals:** Safely captures string literals, honoring escape sequences for internal quotes and backslashes.
* **Comment Stripping:** Explicitly identifies and strips all text enclosed within square brackets `[` `]`. These comments are completely discarded at the lexer stage and do not pass to the parser.
* **Source Tracking:** The lexer attaches file origin and line number metadata to every emitted token. This is critical for constructing the required `source` tracking string for the final JSON-IR payload.

### 4.3 Syntactic Analysis (AST Generation)

The parser consumes the token stream and constructs an in-memory Abstract Syntax Tree (AST) representing the logical structure of the rules.

* **Grammar Enforcement:** The parser rigidly applies the EBNF rules. If the token stream violates the grammar, the parser throws a fatal syntax exception.
* **Syntactic Sugar Unrolling:** During AST construction, the parser identifies natural language shortcuts (e.g., `<target> includes all of <expr>`) and translates them directly into their equivalent foundational function nodes. Chained actions linked by `and` are also unrolled into distinct mutation nodes at this stage.

### 4.4 IR Emission & Segregation

A final pass traverses the generated AST to serialize the data into the strict JSON-IR schema.

* **Node Translation:** AST nodes are mapped exactly to their JSON-IR counterparts, explicitly declaring their `kind` attributes.
* **Array Segregation:** As the emitter processes the AST, it evaluates the root rule type. It appends `climate rule` blocks to the internal Climate array and `tag rule` blocks to the internal Tag array, preserving the deterministic alphabetical/line ordering established during file discovery.

## 5. IPC File Delivery

Once the JSON-IR payload is generated, the PRM delivers it to the Core Daemon via File-Based IPC using UTC timestamps.

* **Atomic Write Protocol:** The PRM strictly follows the system-wide atomic write protocol defined in the Shared Volume Design Document. The final compiled JSON-IR ruleset will be delivered to the path `prm/active_rules.json`.
* **Local Cleanup:** While the IPC Broker handles stale transaction files upon core engine startup, the PRM is explicitly responsible for managing its own temporary files. During its own startup and graceful shutdown phases, the PRM will arbitrarily remove any temporary files it uses to ensure a clean operational state.

## 6. Error Handling & Observability

The PRM delegates all format structuring and reporting logic to the central Observability, Health Checking, and Logging design document.

### 6.1 Synchronization Failures

If an outbound Git operation fails, the PRM logs an error locally without modifying the active rules payload. If synchronization fails consecutively and exceeds the `SYNC_FAILURE_THRESHOLD`, the PRM dispatches an alert payload to the `notifications/` directory on the shared volume to warn administrators of prolonged repository disconnection.

### 6.2 Compilation Failures

If the parser encounters a syntax error or invalid token within any `.rules` file:

1. **Abort Compilation:** The PRM immediately halts compilation.
2. **State Preservation:** The PRM intentionally bypasses IPC delivery, ensuring the Core Daemon continues running the Last-Known-Good ruleset uninterrupted.
3. **Observability Alert:** The PRM dispatches a high-priority alert payload to the `notifications/` directory detailing the exact file, line number, and syntax error.

---

### Comments, New Issues, Discussion Points, and Questions

**Git Implementation: Dulwich over pygit2**
You made an excellent point regarding the Git implementation. While `pygit2` is exceptionally fast, it relies heavily on native C-libraries and its virtual/in-memory object database support is notoriously complex to configure properly. `Dulwich`, being a pure-Python library, natively features a `MemoryRepo` class that perfectly fulfills our requirement of keeping the filesystem untouched. I have updated the document to reflect `Dulwich` as the chosen implementation.

**PRM Heartbeat: JSON-IR `id` Field vs. Dedicated `.heartbeat` File**
Your proposal to inject an `id` field (like a UUID or commit hash) into the JSON-IR payload to act as the heartbeat is a clever way to reduce the number of files on the shared volume. However, it introduces a few architectural friction points worth discussing:

* **File I/O and Parsing Overhead:** For the IPC Broker to know the PRM is still alive, the PRM must prove it is functioning at a regular interval (e.g., every 60 seconds). If we use `active_rules.json` as the heartbeat mechanism, the PRM would have to regenerate and write the entire ruleset payload to the shared volume every 60 seconds, even if the Git repository hasn't changed (just to update the `id` field). Consequently, the IPC Broker would have to load and parse the potentially large JSON file every 60 seconds just to check if the `id` changed or the timestamp updated.
* **Separation of Concerns:** Mixing ephemeral liveness state (heartbeats) with persistent application state (rules logic) can complicate debugging.
* **The File Mod-Time Advantage:** With a dedicated, empty `.heartbeat` file, the PRM simply updates the file's modification timestamp (a near-zero cost OS operation). The IPC Broker can check liveness purely by reading the file's metadata (`os.stat().st_mtime`) without ever opening or parsing a file.

**Recommendation:** While adding an `id` or `hash` to the JSON-IR is an excellent idea for tracking *which* Git commit is currently active (and we should probably add that to the JSON-IR schema anyway for observability!), I recommend sticking to a dedicated `.heartbeat` file strictly for the liveness checks to save on disk I/O and JSON parsing overhead. Let me know which direction you'd prefer to formalize.

---

### Pending Updates for Other Documents

#### 1. Shared Volume Design Document (New Document)

* **Atomic Write Protocol:** Formally define the system-wide atomic write protocol here. Specify that all files written to the shared volume must first be written to a temporary file, followed by a system rename operation. Grant processes explicit permission to arbitrarily remove any existing temporary files they strictly own before overwriting them.
* **Volume Topology:** Detail the directory structure of the shared volume (e.g., `prm/`, `tx/`, `logs/`, `notifications/`).
* **Decentralized Schemas:** State that this document outlines the mechanical rules of engagement, but the specific JSON schemas for the payloads remain owned by the component design documents generating them.

#### 2. Deployment Architecture Document

* **Shared Volume Requirements:** Specify that the deployed shared volume used to accommodate the IPC mechanisms must support the underlying file system operations required by the atomic write protocol (details to be finalized in the Shared Volume Design Document).
* **PRM Configuration Definitions:** Include required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`).

#### 3. Observability, Health Checking, and Logging Design Document (New Document)

* **Centralization:** Standardize observability. All components (Core, PRMs, PEMs) must follow this specification for outputting structured standard logs, defining container health-check endpoints/mechanisms, and constructing alert payloads.

#### 4. IPC Broker Design Document

* **Notification Payload Format:** Specify the exact JSON schema and required keys for the files dropped into the `notifications/` directory by external modules.
* **Heartbeat Monitoring (PEMs):** Implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs update their schema file timestamps every 30 seconds, the IPC Broker checks every 60 seconds. A PEM missing two consecutive checks (120 seconds) is considered dead, prompting the Broker to purge its stale files.
* **Heartbeat Monitoring (PRMs):** (Pending final decision from discussion above) Define the monitoring strategy for PRM liveness, detailing the exact mechanism and the resulting system event (e.g., dropping the Core Engine into a PAUSED state) if the PRM dies.

#### 5. Central Architecture Document

* **Cleanup:** Remove the atomic write procedure specifics from this document, delegating them entirely to the new Shared Volume Design Document.

#### 6. Rules Engine Design Document

* **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for loaded PEM schemas. Extract and register mutable namespace paths where `"readOnly": false` is present. Strictly map JSON schema `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
* **Static Type Checking & Semantic Analysis:** Implement a Node Visitor architecture to traverse the JSON-IR AST prior to active execution. Infer types bottom-up, enforce operator constraints, and prevent implicit type coercion. Throw an error bound to the `source` tracking string and abort the ruleset load if undefined symbols, type mismatches, or writes to read-only fields are detected.
* **Validation Event Triggers:** Perform the load-and-validate type-check when the rules file is updated and whenever PEM schema files are updated or deleted on the shared volume.

#### 7. Rules Language Guide

* **File Extension Convention:** Update documentation to explicitly state that all rule files must use the `.rules` extension to be detected by the Git-Fetch PRM.

#### 8. DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

* **Discord Integration Specifics:** Define exact Discord intents/permissions (DGL) and OAuth2 scopes (DAC).
* **Rate Limiting:** The DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
