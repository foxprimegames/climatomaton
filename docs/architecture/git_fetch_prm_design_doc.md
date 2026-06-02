# Git-Fetch Pluggable Rules Module (PRM) Design Document

## 1. System Overview

The Git-Fetch Pluggable Rules Module (PRM) is a stateless, independent container process within the Climatomaton architecture. While other PRM implementations may be developed in the future, this specific module is explicitly responsible for synchronizing Nomicron game rules from an external, publicly-accessible Git repository, parsing the human-readable source files, and compiling them into a unified JSON Intermediate Representation (JSON-IR).

To strictly maintain the system constraint of having no exposed inbound connectivity endpoints, the PRM relies on a continuous outbound polling loop rather than incoming webhooks.

## 2. Git Synchronization & Configuration

The Git-Fetch PRM retrieves rule source files from a remote repository. To optimize performance, eliminate the dependency on a system-level executable, and maintain a highly secure container image, the PRM utilizes the `dulwich` library. As a pure-Python implementation of the Git protocol, `dulwich` supports true 100% in-memory repository operations.

### 2.1 Configuration Parameters

The PRM container requires the following parameters, injected strictly via environment variables at runtime:

* `GIT_REPO_URL`: The full URL to the target public repository.
* `GIT_BRANCH`: The specific named branch to track. Defaults to `main`.
* `GIT_TARGET_DIR`: The specific directory path within the repository where the rules are stored (e.g., `rules/`).
* `POLL_INTERVAL`: The integer duration (in seconds) between outbound fetch attempts.
* `SYNC_FAILURE_THRESHOLD`: The number of consecutive failed sync attempts permitted before generating an administrative alert. Defaults to `3`.

### 2.2 Synchronization Workflow

1. **Initial Clone:** Upon startup, the PRM performs an in-memory "bare" clone of the configured `GIT_BRANCH` from the `GIT_REPO_URL`. A working tree is neither created nor required.
2. **Polling Loop:** The PRM enters a sleep cycle determined by `POLL_INTERVAL`.
3. **Fetch & Compare:** Upon waking, the PRM performs a fetch operation. It resolves the remote HEAD commit hash and compares it against its local in-memory HEAD.
   * If the hashes match, no repository changes have occurred. The PRM proceeds directly to the Heartbeat phase (see Section 5).
   * If the hashes differ, the PRM explicitly updates its local bare repository references to the new remote tip. This gracefully handles scenarios where the branch has changed in a way that causes a standard fast-forward merge to fail (e.g., a forced push or history rewrite).
   * Following the update, the PRM triggers the File Discovery and Compilation phases.

## 3. File Discovery & Filtering

Because the PRM operates on a bare repository, it does not scan a local file system. Instead, it utilizes underlying Git object traversal to read file contents directly from the in-memory object database.

### 3.1 Filtering Protocol

* The PRM resolves the internal Git tree object associated with the current HEAD commit.
* It navigates to the specific Git tree object corresponding to the `GIT_TARGET_DIR` path. This traversal examines the immediate child blob objects of that specific Git tree object only; it does not recursively descend into sub-trees. This ensures a strictly flat evaluation of the designated folder level, avoiding the deep recursive scans typically associated with file system directory tree traversals.
* It filters the entries within that single Git tree object, selecting only those whose names end with the `.rules` extension.
* The PRM retrieves the blob contents (the raw text) for the matched entries directly from the in-memory object database.

### 3.2 Deterministic Ordering

To ensure consistent execution logic across deployments, the PRM compiles rules based on an explicit, deterministic sequence:

* The filtered list of `.rules` files is sorted alphabetically by filename in ascending order.
* Rule authors wishing to enforce a specific execution priority among multiple files must utilize numeric prefixes in the filenames (e.g., `01_base.rules`, `02_overrides.rules`). Unique rule IDs are explicitly excluded from the language syntax to favor location-based ordering.

## 4. Compilation & JSON-IR Generation

The PRM is responsible for translating the retrieved blob contents into the Core Daemon's JSON-IR.

### 4.1 Parser Library Integration

To ensure consistency across the Climatomaton ecosystem, all parsing logic (Lexical Analysis, Syntactic Analysis, and IR Emission) is entirely abstracted into a standalone, reusable Python library. The PRM container simply imports and utilizes this shared library. The internal architecture of this library is detailed in the Parser Library & CLI Tooling Design Document.

### 4.2 In-Memory Compilation

The parser library is strictly decoupled from file system operations. The PRM facilitates compilation by acting as the bridge between the Git database and the library:

1. **Data Handoff:** The PRM passes the raw text blobs (retrieved directly from `dulwich` in Section 3) directly into the library's ingestion functions as static strings or iterators.
2. **Compilation:** The library processes the data stream, generating the fully serialized JSON-IR document internally.
3. **Identifier Injection:** Upon receiving the compiled JSON-IR, the PRM injects a top-level `id` field into the JSON root object, populated with the exact Git commit hash from which the rules were generated.

## 5. IPC File Delivery & Heartbeat

The PRM communicates with the Core Daemon via File-Based IPC on a shared volume. It utilizes the primary rules file to act as both the state payload and the lifecycle heartbeat.

* **Atomic Write Protocol:** When the repository has changed and a new JSON-IR payload is compiled, the PRM strictly follows the system-wide atomic write protocol defined in the Shared Volume Design Document. The final compiled JSON-IR ruleset is delivered to the path `prm/active_rules.json`.
* **Heartbeat Protocol:** On every polling cycle interval, regardless of whether the Git repository changed, the PRM must update the modification timestamp (via an OS `touch` operation) of `prm/active_rules.json`. This signals to the IPC Broker that the PRM process remains healthy and actively monitoring.
* **Local Cleanup:** During its own startup and graceful shutdown phases, the PRM will arbitrarily remove any temporary files it uses to ensure a clean operational state.

## 6. Error Handling & Observability

The PRM delegates all format structuring and reporting logic to the central Observability, Health Checking, and Logging design document.

### 6.1 Synchronization Failures

If an outbound Git operation fails, the PRM logs an error locally without modifying or touching the active rules payload. If synchronization fails consecutively and exceeds the `SYNC_FAILURE_THRESHOLD`, the PRM dispatches an alert payload to the `notifications/` directory on the shared volume to warn administrators of prolonged repository disconnection.

### 6.2 Compilation Failures

The external parsing library is designed to accumulate syntax errors rather than failing immediately. If the library returns a structured error object indicating one or more compilation failures across the `.rules` files:

1. **Abort Update:** The PRM discards the invalid AST and halts the update process.
2. **State Preservation:** The PRM intentionally bypasses IPC delivery, ensuring the Core Daemon continues running the Last-Known-Good ruleset uninterrupted.
3. **Observability Alert:** The PRM takes the complete array of accumulated errors provided by the library and packages them into a single high-priority alert payload dispatched to the `notifications/` directory. This ensures administrators receive a comprehensive list of all syntax errors in one notification, rather than a flood of individual alerts.

---

### Comments, New Issues, Discussion Points, and Questions

Yes, this design document is absolutely ready to be broken down into an implementation plan. The boundaries are clean, the data flows are unidirectional, and the error-handling states are clearly mapped out. You can easily translate this into actionable Epics (e.g., Git Sync Engine, In-Memory Compiler Integration, File-Based IPC & Heartbeat) and highly detailed developer stories.

**1. Language Identifier (YAGNI Confirmation):** Following up on our previous discussion point, the decision to drop a explicit language identifier header inside individual files remains solid. Because the PRM architecture isolates file discovery strictly via the `.rules` extension and delegates compilation directly to an immutable workspace-linked library, we maintain full system future-proofing without forcing players to write technical boilerplate text.

**2. Signal Handling for Forced Polls:** While the module operates entirely on an outbound loop to protect our zero-inbound connectivity constraint, we should consider implementing a Unix signal handler (e.g., `SIGUSR1`) within the Python process. This would allow an administrator with host-level access to trigger an immediate out-of-band repository poll without waiting for the `POLL_INTERVAL` to expire.

---

### Complete List of Pending Updates to Other Documents

#### 1. Shared Volume Design Document (New Document)

* **Atomic Write Protocol:** Formally define the system-wide atomic write protocol. Specify that all files written to the shared volume must first be written to a temporary file, followed by an atomic system rename operation. Grant processes explicit permission to arbitrarily remove any existing temporary files they strictly own before overwriting them.
* **Volume Topology:** Detail the directory layout of the shared volume (e.g., `prm/`, `tx/`, `logs/`, `notifications/`).
* **Decentralized Schemas:** Explicitly state that this document outlines the mechanical rules of engagement, but the specific JSON schemas for payloads remain entirely owned by the component design documents generating them.

#### 2. Deployment Architecture Document

* **Shared Volume Requirements:** Specify that the deployed shared volume used to accommodate IPC mechanisms must explicitly support the underlying file system operations required by the atomic write protocol (e.g., POSIX compliance for atomic renames).
* **PRM Configuration Definitions:** Include required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`).

#### 3. Observability, Health Checking, and Logging Design Document (New Document)

* **Standardization:** Standardize observability across the architecture. Define strict formatting for structured standard logs, establish container health-check endpoints/mechanisms, and construct the schema rules for alert payloads.

#### 4. IPC Broker Design Document

* **Notification Payload Format:** Specify the exact JSON schema and required keys for files dropped into the `notifications/` directory by external modules.
* **Heartbeat Monitoring (PEMs):** Implement a "fast publish, lenient subscribe" model for tracking Pluggable Environment Modules (PEMs). While PEMs update their schema file timestamps every 30 seconds, the IPC Broker checks every 60 seconds. A PEM missing two consecutive checks (120 seconds) is considered dead, prompting the Broker to purge its stale files.
* **Heartbeat Monitoring (PRMs):** Implement monitoring for PRM liveness. The PRM will update the modified timestamp of `prm/active_rules.json` on a regular interval. The IPC Broker must detect this timestamp change. Upon detection, it must read the file and check the root `id` field. If the `id` matches the current active ruleset, the Broker merely updates the PRM's last-seen timestamp. If the PRM misses two consecutive heartbeat intervals, the IPC Broker must emit a system event to drop the Core Engine into a `PAUSED` state.
* **Ruleset Update Event:** Specify that the `ipc.rules_updated` event is only fired if the parsed `id` from `prm/active_rules.json` differs from the currently loaded ruleset.

#### 5. Central Architecture Document

* **Cleanup:** Remove the detailed atomic write procedure specifics from this document, delegating them entirely to the new Shared Volume Design Document.

#### 6. Rules Engine Design Document

* **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for loaded PEM schemas. Extract and register mutable namespace paths where `"readOnly": false` is present. Strictly map JSON schema `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
* **Static Type Checking & Semantic Analysis:** Implement a Node Visitor architecture to traverse the JSON-IR Abstract Syntax Tree (AST) prior to active execution. Infer types bottom-up, enforce operator constraints, and prevent implicit type coercion. Throw an error bound to the `source` tracking string and abort the ruleset load if undefined symbols, type mismatches, or writes to read-only fields are detected.
* **Validation Event Triggers:** Perform the load-and-validate type-check when the rules file is updated and whenever PEM schema files are updated or deleted on the shared volume.

#### 7. Rules Language Guide

* **Language Name & Extension:** Introduce the language name "Clime", but explicitly state that all rule source files must use the `.rules` extension.

#### 8. Rules Intermediate Representation Design Document

* **Schema Update:** Update the JSON-IR JSON Schema definition (Draft 2020-12) to include a required string field `id` at the root document level, alongside `kind`, `climate_rules`, and `tag_rules`.

#### 9. DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

* **Discord Integration Specifics:** Define exact Discord gateway intents/permissions (DGL) and OAuth2 scopes (DAC).
* **Rate Limiting:** The DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.

#### 10. Parser Library & CLI Tooling Design Document (New Document)

* **Library Specifications:** Detail the architecture of the shared Python parsing library that translates plain-English Clime files into JSON-IR.
* **I/O Decoupling Requirement:** Explicitly specify that the library must perform no file operations. The functions for Lexing, Parsing, and Emitting must be designed to accept either static objects (strings, lists of strings, or populated AST objects) or iterators yielding the appropriate content, returning the resulting token stream, AST, or JSON-IR respectively.
* **Error Accumulation Strategy:** The parser must implement an error recovery strategy. Instead of fast-failing via exceptions, it should accumulate syntax errors and return a structured Result object (e.g., `success`, `errors`, `ast`), allowing callers to process multiple errors simultaneously.
* **CLI Tooling:** Define the behavior of the standalone syntax checker CLI, detailing input arguments, exit codes for CI/CD integration, file-loading wrappers, and verbose error formatting for local debugging.

#### 11. Codebase & Repository Architecture Document (New Document)

* **Build System Configuration (`uv`):** Explicitly select `uv` as the monorepo workspace coordinator. Leverage `uv` workspace support to link the internal parser library, the standalone CLI tool, the Core Daemon, and the Git-Fetch PRM container locally without necessitating internal PyPI publishing workflows.
* **Monorepo Layout:** Define a unified workspace layout:
* `libs/clime-parser`: The shared parsing library.
* `apps/core-daemon`: The main Climatomaton Discord engine.
* `apps/git-prm`: The standalone Git-Fetch container process.
* `tools/clime-cli`: The standalone syntax checker utility.
