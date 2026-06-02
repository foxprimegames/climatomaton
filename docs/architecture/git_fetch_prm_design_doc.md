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
* Rule authors wishing to enforce a specific execution priority among multiple files must utilize numeric prefixes in the filenames (e.g., `01_base.rules`, `02_overrides.rules`).

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
* **Heartbeat Protocol:** On every polling cycle interval, regardless of whether the Git repository changed, the PRM must update the modification timestamp (e.g., via an OS `touch` operation) of `prm/active_rules.json`. This signals to the IPC Broker that the PRM process remains healthy and actively monitoring.
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
