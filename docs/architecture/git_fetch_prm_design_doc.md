You are absolutely right. I bypassed the requested discussion phase in favor of dictating an implementation, and I overstepped by hardcoding those JSON payloads (complete with trailing spaces). Let's course-correct.

I have stripped the preemptive decisions out of the document, aligned the error handling with the new central observability strategy you proposed, updated the IPC delivery section to rely on a central atomic write protocol, and detailed the requested discussions below.

Here is the updated Git-Fetch PRM design document.

# Git-Fetch Pluggable Rules Module (PRM) Design Document

## 1. System Overview

The Git-Fetch Pluggable Rules Module (PRM) is a stateless, independent container process within the Climatomaton architecture. While other PRM implementations may be developed in the future, this specific module is explicitly responsible for synchronizing Nomicron game rules from an external, publicly-accessible Git repository, parsing the human-readable source files, and compiling them into a unified JSON Intermediate Representation (JSON-IR).

To strictly maintain the system constraint of having no exposed inbound connectivity endpoints, the PRM relies on a continuous outbound polling loop rather than incoming webhooks.

## 2. Git Synchronization & Configuration

The Git-Fetch PRM retrieves rule source files from a remote repository. The specific underlying technical implementation for executing Git protocol operations is pending final architectural review.

### 2.1 Configuration Parameters

The PRM container requires the following parameters, injected strictly via environment variables at runtime:

* `GIT_REPO_URL`: The full URL to the target public repository.
* `GIT_BRANCH`: (Optional) The specific named branch to track. Defaults to `main`.
* `GIT_TARGET_DIR`: The specific directory path within the repository where the rules are stored (e.g., `rules/`).
* `POLL_INTERVAL`: The integer duration (in seconds) between outbound fetch attempts.
* `SYNC_FAILURE_THRESHOLD`: (Optional) The number of consecutive failed sync attempts permitted before generating an administrative alert. Defaults to `3`.

### 2.2 Synchronization Workflow

1. **Initial Clone:** Upon startup, the PRM performs a shallow clone of the configured `GIT_BRANCH` from the `GIT_REPO_URL`.
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
* **Syntactic Sugar Unrolling:** During AST construction, the parser identifies natural language shortcuts (e.g., `<target> includes all of <expr>`) and translates them directly into their equivalent foundational function nodes. Chained actions linked by `and` are also unrolled into distinct mutation nodes at this stage.

### 4.4 IR Emission & Segregation

A final pass traverses the generated AST to serialize the data into the strict JSON-IR schema.

* **Node Translation:** AST nodes are mapped exactly to their JSON-IR counterparts, explicitly declaring their `kind` attributes.
* **Array Segregation:** As the emitter processes the AST, it evaluates the root rule type. It appends `climate rule` blocks to the internal Climate array and `tag rule` blocks to the internal Tag array, preserving the deterministic alphabetical/line ordering established during file discovery.

## 5. IPC File Delivery

Once the JSON-IR payload is generated, the PRM delivers it to the Core Daemon via File-Based IPC using UTC timestamps.

* **Atomic Write Protocol:** The PRM strictly follows the system-wide atomic write procedure defined in the central architecture document. It writes the payload to `prm/active_rules.json.tmp` and executes a system rename to `prm/active_rules.json`.
* **Local Cleanup:** While the IPC Broker handles stale transaction files upon core engine startup, the PRM is explicitly responsible for managing its own temporary files. During its own startup and graceful shutdown phases, the PRM will arbitrarily remove any existing `prm/active_rules.json.tmp` file to ensure a clean operational state.

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

**1. Git Implementation Recommendation**
We have three primary paths for implementing the Git operations in Python.

* **Option A: `GitPython**` (Wrapper)
  * *Pros:* Very pythonic API, widely adopted, straightforward documentation.
  * *Cons:* It is fundamentally a wrapper around the system's `git` binary. It requires a full Git installation inside the Docker container and runs operations via subprocess calls, which can be marginally slower and introduces a theoretical command-injection surface if inputs aren't sanitized.
* **Option B: `pygit2**` (libgit2 Bindings)
  * *Pros:* Native C-bindings. It is exceptionally fast, highly memory efficient, and does not require the system `git` executable to be installed in the container at all, shrinking the image size and attack surface.
  * *Cons:* The API is highly un-pythonic and verbose (closer to C). It can occasionally be finicky to build if pre-compiled wheels aren't available for the target architecture.
* **Option C: Direct `subprocess.run(['git', ...])**`
  * *Pros:* Zero external Python dependencies. You know exactly what commands are running.
  * *Cons:* Highly brittle. Parsing standard output/error strings manually to determine merge states or hash differences is error-prone. Requires `git` binary.


* **Recommendation:** **`pygit2`**. For a stateless, background-polling Docker container, removing the dependency on a system-level executable and relying on direct memory bindings is the safest and most performant architecture, despite the steeper developer learning curve.

**3. Shared Volume Contract vs. Decentralized Ownership**
Should we create a monolithic "Shared Volume Contract" document, or leave file schemas to the components?

* *Pros of a Central Contract:* A single source of truth makes it extremely easy for a new developer to see all data structures flowing across the IPC boundary in one place. It enforces consistency across naming conventions and timestamps.
* *Pros of Decentralized Ownership:* High cohesion. The team building a specific PEM doesn't need to consult a central document to understand their own module's file requirements.
* *Recommendation:* A Hybrid Approach. The Central Architecture Document should define the *directory structure* (e.g., `prms/`, `tx/`, `logs/`) and the mechanical rules of engagement (the Atomic Write Protocol). However, the actual JSON schemas and data shapes should remain decentralized and owned by the design documents of the components that generate them.

**6. Proposal: PRM Heartbeat Requirement**
Your proposal to require the PRM to periodically update a timestamp file (mirroring the PEM heartbeat) is an excellent catch. Currently, if the Git-Fetch PRM container silently crashes, the active rules file just sits there. The Nomicron game continues advancing, but the core engine will endlessly execute the *old* ruleset without anyone knowing the PRM died. By enforcing a heartbeat (e.g., `prm/.heartbeat`), the IPC Broker can detect the PRM's death and pause the system, preventing invalid state mutations. I've added this to the pending updates.

---

### Pending Updates for Other Documents

#### 1. Central Architecture Document

* **Atomic Write Procedure:** Formally define the system-wide atomic write protocol. Specify that all files written to the shared volume must first be written to a `.tmp` file, followed by a system rename operation. Crucially, grant processes explicit permission to arbitrarily remove any existing `.tmp` files they strictly own (e.g., during their own startup/shutdown cleanup phases) before overwriting them.

#### 2. Observability, Health Checking, and Logging Design Document (New Document)

* **Centralization:** Create a new design document to standardize observability. All components (Core, PRMs, PEMs) must follow this specification for outputting structured standard logs, defining container health-check endpoints/mechanisms, and constructing alert payloads.

#### 3. IPC Broker Design Document

* **Notification Payload Format:** Specify the exact JSON schema and required keys for the files dropped into the `notifications/` directory by external modules.
* **Heartbeat Monitoring (PEMs):** Implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs update their schema file timestamps every 30 seconds, the IPC Broker checks every 60 seconds. A PEM missing two consecutive checks (120 seconds) is considered dead, prompting the Broker to purge its stale files from the volume.
* **Heartbeat Monitoring (PRMs):** Implement a requirement for PRMs to periodically update a designated heartbeat file (e.g., `prm/.heartbeat`). The IPC Broker must monitor this file using the same lenient subscribe model used for PEMs. If the PRM heartbeat fails, the IPC Broker must emit a system event to drop the Core Engine into a PAUSED state and dispatch an administrative notification.

#### 4. Rules Engine Design Document

* **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for loaded PEM schemas (`*.schema.json`) and internal schemas. Extract and register mutable namespace paths where `"readOnly": false` is present. Strictly map JSON schema `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
* **Static Type Checking & Semantic Analysis:** Implement a Node Visitor architecture to traverse the JSON-IR AST prior to active execution. Infer types bottom-up, enforce operator constraints, and prevent implicit type coercion. Throw an error bound to the `source` tracking string and abort the ruleset load if undefined symbols, type mismatches, or writes to read-only fields are detected.
* **Validation Event Triggers:** Perform the load-and-validate type-check when the rules file is updated and whenever PEM schema files are updated or deleted on the shared volume.

#### 5. Rules Language Guide

* **File Extension Convention:** Update documentation to explicitly state that all rule files must use the `.rules` extension to be detected by the Git-Fetch PRM.

#### 6. DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

* **Discord Integration Specifics:** Define exact Discord intents/permissions (DGL) and OAuth2 scopes (DAC).
* **Rate Limiting:** The DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.

#### 7. Deployment Architecture Document

* **PRM Configuration Definitions:** Include required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`).
