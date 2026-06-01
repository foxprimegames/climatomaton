You are completely right, and I apologize for missing that. Between your previous directive to drop the authentication requirement and the details already firmly established in the core architecture specification, those "missing" issues were already solved.

By removing the authentication requirement and utilizing native Python bindings for Git operations, the tooling ambiguity is resolved. Furthermore, the core architecture document explicitly defines the JSON schemas for logging and notifications, delegates `.tmp` file cleanup to the IPC Broker, and handles alert deduplication globally. This means the PRM can remain safely stateless without flooding the administrators.

Here is the updated design document with those architectural realities properly integrated.

# Git-Fetch Pluggable Rules Module (PRM) Design Document

## 1. System Overview

The Git-Fetch Pluggable Rules Module (PRM) is a stateless, independent container process within the Climatomaton architecture. While other PRM implementations may be developed in the future, this specific module is explicitly responsible for synchronizing Nomicron game rules from an external, publicly-accessible Git repository, parsing the human-readable source files, and compiling them into a unified JSON Intermediate Representation (JSON-IR).

To strictly maintain the system constraint of having no exposed inbound connectivity endpoints, the PRM relies on a continuous outbound polling loop rather than incoming webhooks.

## 2. Git Synchronization & Configuration

The Git-Fetch PRM retrieves rule source files from a remote repository. To optimize performance and avoid standard CLI overhead, the PRM utilizes native Python bindings (`pygit2` / `libgit2`) to execute all Git protocol operations directly in memory.

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
   * If the hashes differ, the PRM explicitly performs a hard reset to the remote branch tip. This guarantees the local filesystem strictly mirrors the remote state, gracefully handling scenarios where the branch has changed in a way that causes a standard fast-forward merge to fail (e.g., a forced push or history rewrite).
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
* **Syntactic Sugar Unrolling:** During AST construction, the parser identifies natural language shortcuts (e.g., `<target> includes all of <expr>`) and translates them directly into their equivalent foundational function nodes (e.g., `has_all(<target>, <expr>)`). Chained actions linked by `and` are also unrolled into distinct mutation nodes at this stage.

### 4.4 IR Emission & Segregation

A final pass traverses the generated AST to serialize the data into the strict JSON-IR schema.

* **Node Translation:** AST nodes are mapped exactly to their JSON-IR counterparts (e.g., Operator Nodes, Function Nodes, Reference Nodes), explicitly declaring their `kind` attributes.
* **Array Segregation:** As the emitter processes the AST, it evaluates the root rule type. It appends `climate rule` blocks to the internal Climate array and `tag rule` blocks to the internal Tag array, preserving the deterministic alphabetical/line ordering established during file discovery.

## 5. IPC File Delivery

Once the JSON-IR payload is generated, the PRM delivers it to the Core Daemon via File-Based IPC using UTC timestamps.

1. **Atomic Write:** The PRM writes the payload to a temporary file on the shared volume: `prm/active_rules.json.tmp`.
2. **Commit:** The PRM executes an atomic system rename, moving the temporary file to `prm/active_rules.json`.
3. **Orphaned File Handling:** The PRM does not need to manage stale `.tmp` files resulting from process crashes. The Core Daemon's IPC Broker is architecturally responsible for purging all lingering in-flight transaction and temporary files from the shared volume upon startup.

## 6. Error Handling & Observability

To seamlessly integrate with the Core Daemon's Logging & Observability Manager, the PRM outputs structured JSON logs to standard output and writes high-priority alerts to the shared IPC volume.

### 6.1 Structured Local Logging

For all operational events (e.g., successful fetch, parsing started) and non-fatal errors, the PRM outputs a single-line JSON string to standard output matching the established `sys.log` payload specification:

```json
{
  "level": "INFO", 
  "source": "git-fetch-prm",
  "message": "Successfully synchronized and compiled 4 rule files.",
  "metadata": {"commit_hash": "a1b2c3d"}
}

```

### 6.2 Synchronization Failures

If an outbound Git operation fails, the PRM logs an `ERROR` to standard output without modifying the active rules payload. If synchronization fails consecutively and exceeds the `SYNC_FAILURE_THRESHOLD`, the PRM writes an alert to `notifications/{timestamp}_{id}.json` matching the established `sys.notification` payload:

```json
{
  "level": "ERROR",
  "message_text": "Git-Fetch PRM exceeded failure threshold. Repository unreachable.",
  "admin_ids": []
}

```

Because the central Logging Manager natively deduplicates and throttles identical alerts per-source, the PRM does not need to maintain complex state or cooldown timers across container restarts. It can safely fire the notification file upon breaching the threshold, relying on the Core Daemon to prevent Discord channel flooding.

### 6.3 Compilation Failures

If the parser encounters a syntax error or invalid token within any `.rules` file:

1. **Abort Compilation:** The PRM immediately halts compilation.
2. **State Preservation:** The PRM intentionally bypasses IPC delivery, ensuring the Core Daemon continues running the Last-Known-Good ruleset uninterrupted.
3. **Observability Alert:** The PRM writes a `sys.notification` payload to the IPC volume detailing the exact file, line number, and syntax error as a `FATAL` level event to ensure administrators are alerted immediately.

---

### Comments, New Issues, Discussion Points, and Questions

* **Container Health Checking:** With the previous architectural ambiguities resolved, the only remaining gap before implementation is defining how the Docker/container orchestrator proves the PRM process is healthy. Since the PRM doesn't expose a web port for a `/health` endpoint and doesn't participate in the IPC heartbeat protocol like PEMs do, the DevOps team will likely need to rely on tracking process uptime or creating a simple touch-file mechanism in the container shell for the liveness probe. This is an infrastructure decision rather than a core architecture blocker, but it should be noted for the deployment epics.

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

1. **PRM Configuration Definitions:** The deployment specifications must be updated to include the required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`), reflecting the deprecation of authentication credentials for the current implementation phase.
