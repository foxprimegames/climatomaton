# Pluggable Rules Module (PRM) Design Document

## 1. System Overview

The Pluggable Rules Module (PRM) is a stateless, independent container process within the Climatomaton architecture. Its exclusive responsibility is to synchronize Nomicron game rules from an external Git repository, parse the human-readable source files according to the defined grammar, and compile them into a unified JSON Intermediate Representation (JSON-IR).

To strictly maintain the system constraint of having no exposed inbound connectivity endpoints, the PRM cannot rely on Git webhooks. Instead, it operates on a continuous outbound polling loop, ensuring the system remains completely isolated from incoming internet traffic.

## 2. Git Synchronization & Configuration

The PRM retrieves rule source files from a remote Git repository using standard Git protocol operations over outbound connections.

### 2.1 Configuration Parameters

The PRM container requires the following parameters, injected strictly via environment variables at runtime to ensure sensitive data is not baked into the image:

* `GIT_REPO_URL`: The full URL to the target repository.
* `GIT_BRANCH`: The specific named branch to track (e.g., `main`, `production`).
* `GIT_TARGET_DIR`: The specific directory path within the repository where the rules are stored (e.g., `rules/`).
* `GIT_AUTH_TOKEN`: (Optional) Personal Access Token or SSH key for private repositories.
* `POLL_INTERVAL`: The integer duration (in seconds) between outbound fetch attempts.

### 2.2 Synchronization Workflow

1. **Initial Clone:** Upon startup, the PRM performs a shallow clone (`depth=1`) of the specified `GIT_BRANCH` from the `GIT_REPO_URL`.
2. **Polling Loop:** The PRM enters a sleep cycle determined by `POLL_INTERVAL`.
3. **Fetch & Compare:** Upon waking, the PRM performs a `git fetch`. It compares the local HEAD commit hash against the remote branch's HEAD commit hash.
   * If the hashes match, no changes have occurred. The PRM returns to sleep.
   * If the hashes differ, the PRM executes a `git pull` (or hard reset to the remote HEAD) to synchronize the local filesystem, then triggers the File Discovery and Compilation phases.

## 3. File Discovery & Filtering

Because the target Git repository may contain non-rule assets (such as `README.md` files, documentation, or CI/CD configurations), the PRM must isolate the valid rule source files before compilation.

### 3.1 Filtering Protocol

* The PRM scans the directory specified by `GIT_TARGET_DIR`.
* It explicitly filters the directory contents, exclusively selecting files that end with the `.rule` extension. Any file without this extension is entirely ignored.

### 3.2 Deterministic Ordering

To ensure consistent execution logic across deployments, the PRM compiles rules based on an explicit, deterministic sequence:

* The filtered list of `.rule` files is sorted alphabetically by filename in ascending order.
* If a rule author wishes to enforce a specific execution priority among multiple files, they must utilize numeric prefixes in the filenames (e.g., `01_base.rule`, `02_overrides.rule`).

## 4. Compilation & JSON-IR Generation

Once the sorted list of `.rule` files is established, the PRM iterates through the files to parse the plain-English grammar into the standardized JSON-IR syntax expected by the Core Daemon.

### 4.1 Parsing Source Files

* The PRM utilizes a lexer and parser built strictly against the Extended Backus-Naur Form (EBNF) grammar defined in the language reference.
* As it parses, it maintains strict tracking of the origin of every parsed rule, recording the repository URL, file path, and exact line number to construct the required `source` tracking string (e.g., `prm://repository/rules/01_base.rule:line_15`).

### 4.2 Aggregation and Segregation

The core JSON-IR specification requires the root document to segregate rules into an ordered array of `climate_rules` and an ordered array of `tag_rules`.

* As the PRM reads through the sorted files sequentially, it evaluates the `RuleType` declaration of each rule.
* It appends `climate rule` blocks to the internal Climate array and `tag rule` blocks to the internal Tag array.
* This ensures that all Climate rules from all files execute in their combined alphabetical/line order, followed by all Tag rules in their combined alphabetical/line order.

## 5. IPC File Delivery

Once the complete JSON-IR payload is generated in memory, the PRM must deliver it to the Core Daemon via the File-Based IPC protocol. All timestamp operations must utilize the UTC timezone.

1. **Atomic Write:** The PRM writes the serialized JSON-IR payload to a temporary file on the shared volume: `prm/active_rules.json.tmp`.
2. **Commit:** The PRM executes an atomic system rename operation, moving `prm/active_rules.json.tmp` to `prm/active_rules.json`.
3. This atomic rename guarantees the Core Daemon's IPC Broker will never attempt to process a partially written ruleset file.

## 6. Error Handling & Observability

If the PRM encounters any failures during synchronization or compilation, it must act defensively to preserve the current state of the Nomicron game.

### 6.1 Synchronization Failures

If the outbound Git operation fails (e.g., due to network timeout or authentication errors), the PRM logs an `ERROR` to standard output. It does not modify the IPC shared volume. The polling loop will simply reattempt on the next interval.

### 6.2 Compilation Failures

If the parser encounters a syntax error or invalid token within any `.rule` file during the compilation phase:

1. **Abort Compilation:** The PRM immediately halts the compilation process. It does not attempt to "guess" intentions or apply default assumptions.
2. **State Preservation:** The PRM intentionally bypasses the IPC File Delivery phase. By not updating `active_rules.json`, it guarantees the Core Daemon will continue running the Last-Known-Good ruleset uninterrupted.
3. **Observability Alert:** The PRM drops a highly specific JSON payload into the `notifications/{timestamp}_{id}.json` folder on the shared volume. This payload details the exact file, line number, and syntax error. The IPC Broker will ingest this file, fire a `sys.notification` event, and route an alert directly to Discord administrators so they can fix the repository.

---

### Comments, New Issues, Discussion Points, and Questions

* **File Extension Convention:** The document establishes `.rule` as the required file extension to distinguish Nomicron rules from generic repository files. We should ensure the `rules_language_guide.md` is updated to reflect this convention so Nomicron players name their files correctly.
* **Git Rate Limiting:** Because we are entirely reliant on outbound polling, we should establish a sensible default for `POLL_INTERVAL` (e.g., 60 or 120 seconds). Aggressive polling against hosted providers like GitHub or Codeberg without webhooks may trigger API rate limits.
* **Deep Directory Scanning:** Currently, the design implies a flat scan of `GIT_TARGET_DIR`. If rule authors wish to organize rules into subdirectories, the PRM would need to implement recursive globbing (e.g., searching `*` `*` `/*.rule`). Does the core architecture need to support nested rule folders, or is a flat directory sufficient for current Nomicron needs?
* **Notification Flooding:** If a syntax error is pushed to the repo, the PRM will fail to compile it on every polling cycle. To prevent flooding the Discord admins with duplicate alerts every 60 seconds, the PRM should track the last failing commit hash in memory and only dispatch a `sys.notification` once per unique broken commit.

### Pending Updates for Other Documents

#### IPC Broker Design Document

1. **Heartbeat Monitoring & Cleanup:** The IPC Broker must implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs are required to update their schema file timestamps every 30 seconds, the IPC Broker should check these timestamps every 60 seconds. A PEM is only considered offline if it misses two consecutive checks (i.e., the file has not been touched in over 120 seconds). Upon detecting a dead PEM, the IPC Broker must automatically purge the stale schema and data files from the shared volume.

#### Rules Engine Design Document

1. **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. Because the system utilizes standard JSON Schema (Draft 2020-12), the engine must incorporate a compliant JSON Schema library (e.g., `jsonschema` in Python) to load these files. During initialization, the engine must traverse the parsed schema dictionaries to dynamically extract and register mutable namespace paths strictly where the `"readOnly": false` attribute is present. The engine must also strictly map `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints, resolving function signatures, and guaranteeing no implicit type coercion takes place. If an undefined symbol, a type mismatch, or a write operation to a `readOnly: true` field is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.
3. **Validation Event Triggers:** The rules engine must perform the load-and-validate type-check both when the rules file is updated and whenever the PEM schema files are updated or deleted on the shared volume.

#### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration Specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.

#### Deployment Architecture Document (New Addition)

1. **PRM Configuration Definitions:** The deployment specifications must be updated to include the required environment variables for the PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `GIT_AUTH_TOKEN`, `POLL_INTERVAL`), ensuring secrets management handles `GIT_AUTH_TOKEN` securely at deployment time.
