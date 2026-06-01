You are spot on with both points.

Using a bare clone and reading blobs directly from the tree object is the most idiomatic and efficient way to use a library like `dulwich` in memory, completely bypassing the need for a working tree. And yes, this is *exactly* the right level of detail for a component architecture document. It tells the developers *how* the system should interact with the data conceptually, without micromanaging the specific lines of Python code.

Regarding the heartbeat: I completely misunderstood your previous proposal. Updating the `mtime` of the file while relying on the IPC Broker to parse the `id` to distinguish between a heartbeat and a true update elegantly solves the problem without creating new file formats.

Here is the updated design document reflecting these architectural refinements.

# Git-Fetch Pluggable Rules Module (PRM) Design Document

## 1. System Overview

The Git-Fetch Pluggable Rules Module (PRM) is a stateless, independent container process within the Climatomaton architecture. While other PRM implementations may be developed in the future, this specific module is explicitly responsible for synchronizing Nomicron game rules from an external, publicly-accessible Git repository, parsing the human-readable source files, and compiling them into a unified JSON Intermediate Representation (JSON-IR).

To strictly maintain the system constraint of having no exposed inbound connectivity endpoints, the PRM relies on a continuous outbound polling loop rather than incoming webhooks.

## 2. Git Synchronization & Configuration

The Git-Fetch PRM retrieves rule source files from a remote repository. To optimize performance, eliminate the dependency on a system-level executable, and maintain a highly secure container image, the PRM utilizes the `dulwich` library. As a pure-Python implementation of the Git protocol, `dulwich` supports true 100% in-memory repository operations.

### 2.1 Configuration Parameters

The PRM container requires the following parameters, injected strictly via environment variables at runtime:

* `GIT_REPO_URL`: The full URL to the target public repository.
* `GIT_BRANCH`: (Optional) The specific named branch to track. Defaults to `main`.
* `GIT_TARGET_DIR`: The specific directory path within the repository where the rules are stored (e.g., `rules/`).
* `POLL_INTERVAL`: The integer duration (in seconds) between outbound fetch attempts.
* `SYNC_FAILURE_THRESHOLD`: (Optional) The number of consecutive failed sync attempts permitted before generating an administrative alert. Defaults to `3`.

### 2.2 Synchronization Workflow

1. **Initial Clone:** Upon startup, the PRM performs an in-memory "bare" clone of the configured `GIT_BRANCH` from the `GIT_REPO_URL`. A working tree is neither created nor required.
2. **Polling Loop:** The PRM enters a sleep cycle determined by `POLL_INTERVAL`.
3. **Fetch & Compare:** Upon waking, the PRM performs a fetch operation. It resolves the remote HEAD commit hash and compares it against its local in-memory HEAD.
   * If the hashes match, no repository changes have occurred. The PRM proceeds directly to the Heartbeat phase (see Section 5).
   * If the hashes differ, the PRM updates its local bare repository references to the new remote tip. This natively bypasses fast-forward merge conflicts since there is no working tree to reconcile. Following the reference update, the PRM triggers the File Discovery and Compilation phases.

## 3. File Discovery & Filtering

Because the PRM operates on a bare repository, it does not scan a local filesystem. Instead, it utilizes underlying Git object traversal to read file contents directly from the object database.

### 3.1 Filtering Protocol

* The PRM resolves the tree object associated with the current HEAD commit.
* It traverses the specific tree path defined by `GIT_TARGET_DIR`. Deep directory scanning is not supported; the traversal is strictly flat within that designated tree.
* It filters the tree entries, selecting only those whose names end with the `.rules` extension.
* The PRM retrieves the blob contents (the raw text) for the matched entries directly from the in-memory object database.

### 3.2 Deterministic Ordering

To ensure consistent execution logic across deployments, the PRM compiles rules based on an explicit, deterministic sequence:

* The filtered list of `.rules` files is sorted alphabetically by filename in ascending order.
* Rule authors wishing to enforce a specific execution priority among multiple files must utilize numeric prefixes in the filenames (e.g., `01_base.rules`, `02_overrides.rules`).

## 4. Compilation & JSON-IR Generation

The PRM is responsible for translating the retrieved blob contents into the Core Daemon's JSON-IR. The compilation process utilizes a standard compiler frontend pipeline to guarantee syntactic correctness before emission.

### 4.1 Parser Architecture

The PRM implements a three-stage parsing pipeline: Lexical Analysis, Syntactic Analysis, and IR Emission. It utilizes a robust Python-based parsing library capable of directly consuming the established EBNF grammar, ensuring the parser remains strictly synchronized with the language specification.

### 4.2 Lexical Analysis (Tokenization)

The lexer scans the raw text of the `.rules` blobs and converts them into a stream of recognized tokens.

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

* **Ruleset Identification:** The emitter injects a top-level `id` field into the JSON-IR root object, populated with the exact Git commit hash from which the rules were generated.
* **Node Translation:** AST nodes are mapped exactly to their JSON-IR counterparts, explicitly declaring their `kind` attributes.
* **Array Segregation:** As the emitter processes the AST, it evaluates the root rule type. It appends `climate rule` blocks to the internal Climate array and `tag rule` blocks to the internal Tag array, preserving the deterministic alphabetical/line ordering established during file discovery.

## 5. IPC File Delivery & Heartbeat

The PRM communicates with the Core Daemon via File-Based IPC on a shared volume. It utilizes the primary rules file to act as both the state payload and the lifecycle heartbeat.

* **Atomic Write Protocol:** When the repository has changed and a new JSON-IR payload is compiled, the PRM strictly follows the system-wide atomic write protocol defined in the Shared Volume Design Document. The final compiled JSON-IR ruleset is delivered to the path `prm/active_rules.json`.
* **Heartbeat Protocol:** On *every* polling cycle interval, regardless of whether the Git repository changed, the PRM must update the modification timestamp (e.g., via an OS `touch` operation) of `prm/active_rules.json`. This signals to the IPC Broker that the PRM process remains healthy and actively monitoring.
* **Local Cleanup:** During its own startup and graceful shutdown phases, the PRM will arbitrarily remove any temporary files it uses to ensure a clean operational state.

## 6. Error Handling & Observability

The PRM delegates all format structuring and reporting logic to the central Observability, Health Checking, and Logging design document.

### 6.1 Synchronization Failures

If an outbound Git operation fails, the PRM logs an error locally without modifying or touching the active rules payload. If synchronization fails consecutively and exceeds the `SYNC_FAILURE_THRESHOLD`, the PRM dispatches an alert payload to the `notifications/` directory on the shared volume to warn administrators of prolonged repository disconnection.

### 6.2 Compilation Failures

If the parser encounters a syntax error or invalid token within any `.rules` file:

1. **Abort Compilation:** The PRM immediately halts compilation.
2. **State Preservation:** The PRM intentionally bypasses IPC delivery, ensuring the Core Daemon continues running the Last-Known-Good ruleset uninterrupted.
3. **Observability Alert:** The PRM dispatches a high-priority alert payload to the `notifications/` directory detailing the exact file, line number, and syntax error.

---

### Comments, New Issues, Discussion Points, and Questions

* **Level of Detail on Git Implementation:** To answer your first question directly: yes, specifying a bare clone, utilizing `dulwich`, and detailing the retrieval of blobs directly from the tree object is precisely the right level of detail for this document. It restricts the implementation team to a highly efficient, diskless architecture without dictating the exact Python function calls they must write.
* **Heartbeat via File Modification:** Your clarification on the `id` field makes perfect sense. By injecting the commit hash into the JSON-IR `id` field, the PRM can indiscriminately `touch` the `active_rules.json` file on every cycle. The IPC Broker will detect the `mtime` change via `inotify`, parse the JSON, and simply compare the parsed `id` against its in-memory ruleset `id`. If they match, it acts purely as a heartbeat update. If they differ, it triggers a ruleset reload. This keeps the volume clean and centralizes the liveness check. This logic has been pushed to the "Pending Updates" section for the IPC Broker.

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
* **Heartbeat Monitoring (PRMs):** Implement monitoring for the PRM liveness. The PRM will update the modified timestamp of `prm/active_rules.json` on a regular interval. The IPC Broker must detect this timestamp change. Upon detection, it must read the file and check the root `id` field. If the `id` matches the current active ruleset, the Broker merely updates the PRM's last-seen timestamp. If the PRM misses two consecutive heartbeat intervals, the IPC Broker must emit a system event to drop the Core Engine into a PAUSED state.
* **Ruleset Update Event:** Specify that the `ipc.rules_updated` event is only fired if the parsed `id` from the `prm/active_rules.json` file differs from the currently loaded ruleset.

#### 5. Central Architecture Document

* **Cleanup:** Remove the atomic write procedure specifics from this document, delegating them entirely to the new Shared Volume Design Document.

#### 6. Rules Engine Design Document

* **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for loaded PEM schemas. Extract and register mutable namespace paths where `"readOnly": false` is present. Strictly map JSON schema `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
* **Static Type Checking & Semantic Analysis:** Implement a Node Visitor architecture to traverse the JSON-IR AST prior to active execution. Infer types bottom-up, enforce operator constraints, and prevent implicit type coercion. Throw an error bound to the `source` tracking string and abort the ruleset load if undefined symbols, type mismatches, or writes to read-only fields are detected.
* **Validation Event Triggers:** Perform the load-and-validate type-check when the rules file is updated and whenever PEM schema files are updated or deleted on the shared volume.

#### 7. Rules Language Guide

* **File Extension Convention:** Update documentation to explicitly state that all rule files must use the `.rules` extension to be detected by the Git-Fetch PRM.

#### 8. Rules Intermediate Representation Design Document

* **Schema Update:** Update the JSON-IR JSON Schema definition (Draft 2020-12) to include a required string field `id` at the root document level, alongside `kind`, `climate_rules`, and `tag_rules`.

#### 9. DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

* **Discord Integration Specifics:** Define exact Discord intents/permissions (DGL) and OAuth2 scopes (DAC).
* **Rate Limiting:** The DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
