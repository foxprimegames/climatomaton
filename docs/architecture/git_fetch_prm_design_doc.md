# Git-Fetch Pluggable Rules Module (PRM) Design Document

## 1. System Overview

The Git-Fetch Pluggable Rules Module (PRM) is a stateless, independent container process within the Climatomaton architecture. While other PRM implementations may be developed in the future, this specific module is explicitly responsible for synchronizing Nomicron game rules from an external Git repository, parsing the human-readable source files, and compiling them into a unified JSON Intermediate Representation (JSON-IR).

To strictly maintain the system constraint of having no exposed inbound connectivity endpoints, the PRM relies on a continuous outbound polling loop rather than incoming webhooks.

## 2. Git Synchronization & Configuration

The Git-Fetch PRM retrieves rule source files from a remote repository using standard Git protocol operations.

### 2.1 Configuration Parameters

The PRM container requires the following parameters, injected strictly via environment variables at runtime:

* `GIT_REPO_URL`: The full URL to the target repository.
* `GIT_BRANCH`: (Optional) The specific named branch to track. Defaults to `main`.
* `GIT_TARGET_DIR`: The specific directory path within the repository where the rules are stored (e.g., `rules/`).
* `GIT_AUTH_TOKEN`: (Optional) Personal Access Token or SSH key for private repositories.
* `POLL_INTERVAL`: The integer duration (in seconds) between outbound fetch attempts.
* `SYNC_FAILURE_THRESHOLD`: (Optional) The number of consecutive failed sync attempts permitted before generating an administrative alert. Defaults to `3`.

### 2.2 Synchronization Workflow

1. **Initial Clone:** Upon startup, the PRM performs a shallow clone of the configured `GIT_BRANCH` from the `GIT_REPO_URL`.
2. **Polling Loop:** The PRM enters a sleep cycle determined by `POLL_INTERVAL`.
3. **Fetch & Compare:** Upon waking, the PRM performs a `git fetch`. It compares the local HEAD commit hash against the remote branch's HEAD commit hash.
   * If the hashes match, no changes have occurred. The PRM returns to sleep.
   * If the hashes differ, the PRM explicitly performs a hard reset to the remote branch tip (e.g., `git reset --hard origin/<branch>`). This guarantees the local filesystem strictly mirrors the remote state, gracefully handling scenarios where the branch has changed in a way that causes a standard fast-forward merge to fail (e.g., a forced push or history rewrite).
   * Following the reset, the PRM triggers the File Discovery and Compilation phases.

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

The PRM iterates through the sorted `.rules` files to parse the grammar into the standardized JSON-IR expected by the Core Daemon.

### 4.1 Parsing Source Files

* The PRM utilizes a lexer and parser built strictly against the defined Extended Backus-Naur Form (EBNF) grammar.
* As it parses, it constructs the required `source` tracking string for each rule (e.g., `prm://repository/rules/01_base.rules:line_15`).

### 4.2 Aggregation and Segregation

The PRM segregates rules into an ordered array of `climate_rules` and an ordered array of `tag_rules`.

* As the PRM reads the sorted files, it evaluates the rule type declaration.
* It appends climate rules to the internal Climate array and tag rules to the internal Tag array, ensuring all rules execute in their combined alphabetical/line order.

## 5. IPC File Delivery

Once the JSON-IR payload is generated, the PRM delivers it to the Core Daemon via File-Based IPC using UTC timestamps.

1. **Atomic Write:** The PRM writes the payload to a temporary file on the shared volume: `prm/active_rules.json.tmp`.
2. **Commit:** The PRM executes an atomic system rename, moving the temporary file to `prm/active_rules.json`.

## 6. Error Handling & Observability

### 6.1 Synchronization Failures

If an outbound Git operation fails (e.g., network timeout, authentication error), the PRM logs an `ERROR` to standard output without modifying the active rules payload. If synchronization fails consecutively across multiple polling cycles and exceeds the defined `SYNC_FAILURE_THRESHOLD`, the PRM must drop a specifically formatted JSON payload into the `notifications/{timestamp}_{id}.json` folder on the shared volume. This ensures Discord administrators are alerted to prolonged repository connection issues.

### 6.2 Compilation Failures

If the parser encounters a syntax error or invalid token within any `.rules` file:

1. **Abort Compilation:** The PRM immediately halts compilation.
2. **State Preservation:** The PRM intentionally bypasses IPC delivery, ensuring the Core Daemon continues running the Last-Known-Good ruleset uninterrupted.
3. **Observability Alert:** The PRM drops a JSON payload into the `notifications/{timestamp}_{id}.json` folder on the shared volume detailing the exact file, line number, and syntax error.

---

### Comments, New Issues, Discussion Points, and Questions

* **Notification Rate Limiting for Compilations:** Since the PRM will continue to fail compilation on every polling cycle until the repository is fixed, it should maintain an internal cache of the last failed commit hash. It should only emit a `sys.notification` payload for a broken compilation once per unique commit to prevent flooding the administrative Discord channel.
* **Alert Deduplication:** For synchronization failures, the Core Engine's Logging & Observability Manager already handles deduplication of identical alerts, but adding the `SYNC_FAILURE_THRESHOLD` prevents transient network blips from immediately queuing an alert.

### Pending Updates for Other Documents

#### Rules Language Guide

1. **File Extension Convention:** Update the documentation to explicitly state that all rule files must use the `.rules` extension to be detected by the Git-Fetch PRM.

#### IPC Broker Design Document

1. **Heartbeat Monitoring & Cleanup:** The IPC Broker must implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs are required to update their schema file timestamps every 30 seconds, the IPC Broker should check these timestamps every 60 seconds. A PEM is only considered offline if it misses two consecutive checks (i.e., the file has not been touched in over 120 seconds). Upon detecting a dead PEM, the IPC Broker must automatically purge the stale schema and data files from the shared volume.

#### Rules Engine Design Document

1. **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. During initialization, the engine must traverse the parsed schema dictionaries to dynamically extract and register mutable namespace paths strictly where the `"readOnly": false` attribute is present. The engine must also strictly map `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints, resolving function signatures, and guaranteeing no implicit type coercion takes place. If an undefined symbol, a type mismatch, or a write operation to a `readOnly: true` field is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.
3. **Validation Event Triggers:** The rules engine must perform the load-and-validate type-check both when the rules file is updated and whenever the PEM schema files are updated or deleted on the shared volume.

#### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration Specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.

#### Deployment Architecture Document

1. **PRM Configuration Definitions:** The deployment specifications must be updated to include the required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `GIT_AUTH_TOKEN`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`), ensuring secrets management handles `GIT_AUTH_TOKEN` securely at deployment time.
