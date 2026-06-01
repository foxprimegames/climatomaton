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
   * If the hashes differ, the PRM explicitly updates its local bare repository references to the new remote tip. This gracefully handles scenarios where the branch has changed in a way that causes a standard fast-forward merge to fail (e.g., a forced push or history rewrite).
   * Following the update, the PRM triggers the File Discovery and Compilation phases.

## 3. File Discovery & Filtering

Because the PRM operates on a bare repository, it does not scan a local file system. Instead, it utilizes underlying Git object traversal to read file contents directly from the in-memory object database.

### 3.1 Filtering Protocol

* The PRM resolves the internal Git tree object associated with the current HEAD commit.
* It navigates to the specific Git tree object corresponding to the `GIT_TARGET_DIR` path. To be clear, this traversal examines the immediate child blob objects of that specific Git tree object only; it does not recursively descend into sub-trees. This ensures a strictly flat evaluation of the designated folder level, avoiding the deep recursive scans typically associated with file system directory tree traversals.
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

If the parsing library throws a syntax error exception during compilation:

1. **Abort Compilation:** The PRM immediately halts compilation.
2. **State Preservation:** The PRM intentionally bypasses IPC delivery, ensuring the Core Daemon continues running the Last-Known-Good ruleset uninterrupted.
3. **Observability Alert:** The PRM dispatches a high-priority alert payload to the `notifications/` directory detailing the exact file, line number, and syntax error.

---

### Comments, New Issues, Discussion Points, and Questions

**1. Parser Logic Extraction**
As requested, the detailed lexing and parsing mechanisms have been stripped from Section 4 of this document. This PRM document now correctly focuses strictly on the *integration* between the Git polling loop, the in-memory blobs, and the external parser library.

**2. Cutesy / Clever Language Name Ideas**
Naming a custom Domain Specific Language is one of the best parts of system design! Since this DSL governs the climate for "Nomicron," we should lean into meteorological, Nomic, or atmospheric puns. Here are a few options to consider:

* **Atmos:** (Short, punchy, implies atmosphere/climate rules).
* **NomiScript:** (Standard naming convention, very clear what it belongs to).
* **Weathervane:** (Implies directing the climate, slightly whimsical).
* **C-Lex:** (Climate Lexicon).
* **Zephyr:** (A light wind, often used in software for lightweight environments/languages).
* **Isobar:** (The lines on a weather map indicating pressure—fitting for rules that apply pressure to the game state).
* *My Recommendation:* **Atmos** or **Isobar**. They are easy to say, short enough to use as file extensions (e.g., `.atmos` instead of `.rules`), and thematic. Let me know what direction you prefer!

**3. Application & Library Organization (Monorepo vs. Polyrepo)**
Because the Climatomaton project consists of several distinct but tightly coupled Python components (the Core Daemon, the Git-Fetch PRM container, standard PEM containers, the CLI Tool, and the core Parser Library), we need a cohesive strategy for versioning and building them.

* **Polyrepo (Multiple Repositories):** You would have one repo for the Core Daemon, one for the PRM, one for the shared parser library, etc.
* *Pros:* Strict boundary enforcement. Forces the parser library to be a completely independent, `pip`-installable package.
* *Cons:* "Dependency hell." If you update a language keyword in the parser library, you must publish a new package version, go to the PRM repo, bump the requirement, go to the Core Daemon repo, bump the requirement, and rebuild everything. This is massive overhead for a single project.


* **Monorepo (Single Repository):** All code lives in one Git repository (e.g., `climatomaton/`). Inside, you use a modular structure like `apps/core`, `apps/git-prm`, and `libs/parser`.
* *Pros:* Atomic commits. A single pull request can update the grammar in the parser library and update the Git-Fetch PRM to utilize the new AST structure simultaneously. You don't have to publish the internal library to PyPI; you can link it locally during Docker builds.
* *Cons:* Requires slightly more complex Dockerfile setups to ensure each container image only bundles what it needs.



*Recommendation:* Use a **Python Monorepo** managed with a modern build system like `Poetry` or `uv`. You can define multiple packages/workspaces in one repository. The architecture for this codebase organization should be documented in a new **Codebase & Repository Architecture Document** (or folded into the Deployment Architecture Document as a "Build Strategy" section). I have added this to the pending updates.

---

### Pending Updates for Other Documents

#### 1. Shared Volume Design Document (New Document)

* **Atomic Write Protocol:** Formally define the system-wide atomic write protocol here. Specify that all files written to the shared volume must first be written to a temporary file, followed by a system rename operation. Grant processes explicit permission to arbitrarily remove any existing temporary files they strictly own before overwriting them.
* **Volume Topology:** Detail the directory structure of the shared volume (e.g., `prm/`, `tx/`, `logs/`, `notifications/`).
* **Decentralized Schemas:** State that this document outlines the mechanical rules of engagement, but the specific JSON schemas for the payloads remain owned by the component design documents generating them.

#### 2. Deployment Architecture Document

* **Shared Volume Requirements:** Specify that the deployed shared volume used to accommodate the IPC mechanisms must support the underlying file system operations required by the atomic write protocol.
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

#### 10. Parser Library & CLI Tooling Design Document (New Document)

* **Library Specifications:** Detail the architecture of the shared Python parsing library that translates plain-English `.rules` files into JSON-IR.
* **I/O Decoupling Requirement:** Explicitly specify that the library must perform **no file operations**. The functions for Lexing, Parsing, and Emitting must be designed to accept either static objects (strings, lists of strings, or populated AST objects) *or* iterators yielding the appropriate content, returning the resulting token stream, AST, or JSON-IR respectively.
* **CLI Tooling:** Define the behavior of the standalone syntax checker CLI, detailing input arguments, exit codes for CI/CD integration, file-loading wrappers (since the library does not do I/O itself), and verbose error formatting for local debugging.

#### 11. Codebase & Repository Architecture Document (New Document)

* **Monorepo Structure:** Define the project layout for managing the multiple Python applications and shared internal libraries (Core Daemon, PRM, CLI tool, Parser Library).
* **Build System:** Specify the tooling (e.g., Poetry, `uv`) used to manage internal package dependencies and orchestrate container builds without requiring the internal libraries to be published to public package registries.
