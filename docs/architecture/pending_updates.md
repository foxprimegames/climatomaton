### Pending design document updates

*Note: This list is organized in reverse chronological order relative to the sequence of completion (items to be completed last are at the top, while the highest priority item to be completed first is at the bottom). This prevents the need to renumber subsequent entries as completed documents are removed from the list.*

#### 1. Deployment Architecture Document (New Document)

* **Shared Volume Requirements:** Specify that the deployed shared volume used to accommodate the IPC mechanisms must support the underlying file system operations required by the atomic write protocol.
* **PRM Configuration Definitions:** Include required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`).

#### 2. Codebase & Repository Architecture Document (New Document)

* **Build System Discussion (`uv` vs `hatch`):** While `hatch` is an officially endorsed PyPA project and fantastic for generic package building, `uv` (built by Astral) is recommended for this specific multi-component project. `uv` acts as an ultra-fast, drop-in replacement for `pip`, `venv`, and `pip-tools` written in Rust. Crucially, `uv` recently introduced Cargo-style "workspace" support. This allows us to define the Parser Library, the PRM, and the Core Engine as separate packages within the same repository, seamlessly linking them together locally without needing to publish the internal library to a PyPI index or wrangle complex local file references in standard `pyproject.toml` configurations.
* **Monorepo Organization:** The document must define a unified workspace layout. A standard approach would separate concerns clearly into directories such as `libs/clime-parser` for the shared parsing library, `apps/core-daemon` for the main engine, `apps/git-prm` for the container process, and `tools/clime-cli` for the standalone syntax checker utility.

#### 3. Observability, Health Checking, and Logging Design Document (New Document)

* **Centralization:** Standardize observability. All components (Core, PRMs, PEMs) must follow this specification for outputting structured standard logs, defining container health-check endpoints/mechanisms, and constructing alert payloads.

#### 4. DAC (Discord API Client) Design Document (New Document)

* **Discord Integration Specifics:** Define exact OAuth2 scopes (DAC).
* **Rate Limiting:** The DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.

#### 5. DGL (Discord Gateway Listener) Design Document (New Document)

* **Discord Integration Specifics:** Define exact Discord intents/permissions (DGL).

#### 6. Parser Library & CLI Tooling Design Document (New Document)

* **Library Specifications:** Detail the architecture of the shared Python parsing library that translates plain-English Clime files into JSON-IR.
* **I/O Decoupling Requirement:** Explicitly specify that the library must perform no file operations. The functions for Lexing, Parsing, and Emitting must be designed to accept either static objects (strings, lists of strings, or populated AST objects) or iterators yielding the appropriate content, returning the resulting token stream, AST, or JSON-IR respectively.
* **Error Accumulation Strategy:** The parser must implement an error recovery strategy. Instead of fast-failing via exceptions, it should accumulate syntax errors and return a structured Result object (e.g., `success`, `errors`, `ast`), allowing callers to process multiple errors simultaneously.
* **CLI Tooling:** Define the behavior of the standalone syntax checker CLI, detailing input arguments, exit codes for CI/CD integration, file-loading wrappers, and verbose error formatting for local debugging.

#### 7. Rules Engine Design Document (New Document)

* **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for loaded PEM schemas. Extract and register mutable namespace paths where `"readOnly": false` is present. Strictly map JSON schema `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
* **Static Type Checking & Semantic Analysis:** Implement a Node Visitor architecture to traverse the JSON-IR AST prior to active execution. Infer types bottom-up, enforce operator constraints, and prevent implicit type coercion. Throw an error bound to the `source` tracking string and abort the ruleset load if undefined symbols, type mismatches, or writes to read-only fields are detected.
* **Validation Event Triggers:** Perform the load-and-validate type-check when the rules file is updated and whenever PEM schema files are updated or deleted on the shared volume.

#### 8. Internal Event Bus Design Document (New Document)

* **Broker Implementation:** Detail the internal pub/sub message broker mechanics required for asynchronous event passing between core system components.

#### 9. Command Parser Design Document (New Document)

* **Input Processing:** Define the logic and string-matching patterns required to identify, extract, and route commands, configurations, and climate updates from text streams.

#### 10. EOT Parser Design Document (New Document)

* **Report Extraction:** Establish the parsing architecture for pulling relevant state variables and triggering mechanics from standardized end-of-turn text reports.

#### 11. Environment Manager Design Document (New Document)

* **State Tracking:** Outline the memory structures and lifecycles used to track active climate modules, environmental tags, and active modifiers during a running session.

#### 12. State Rehydrator Design Document (New Document)

* **Recovery Sequence:** Define the exact sequence of events for scraping external channel history to organically rebuild the active state upon application startup.

#### 13. IPC Broker Design Document (New Document)

* **Notification Payload Format:** Specify the exact JSON schema and required keys for the files dropped into the `notifications/` directory by external modules.
* **Heartbeat Monitoring (PEMs):** Implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs update their schema file timestamps every 30 seconds, the IPC Broker checks every 60 seconds. A PEM missing two consecutive checks (120 seconds) is considered dead, prompting the Broker to purge its stale files.
* **Heartbeat Monitoring (PRMs):** Implement monitoring for the PRM liveness. The PRM will update the modified timestamp of `prm/active_rules.json` on a regular interval. The IPC Broker must detect this timestamp change. Upon detection, it must read the file and check the root `id` field. If the `id` matches the current active ruleset, the Broker merely updates the PRM's last-seen timestamp. If the PRM misses two consecutive heartbeat intervals, the IPC Broker must emit a system event to drop the Core Engine into a PAUSED state.
* **Ruleset Update Event:** Specify that the `ipc.rules_updated` event is only fired if the parsed `id` from the `prm/active_rules.json` file differs from the currently loaded ruleset.

#### 14. Shared Volume Design Document (New Document)

* **Atomic Write Protocol:** Formally define the system-wide atomic write protocol here. Specify that all files written to the shared volume must first be written to a temporary file, followed by a system rename operation. Grant processes explicit permission to arbitrarily remove any existing temporary files they strictly own before overwriting them.
* **Volume Topology:** Detail the directory structure of the shared volume (e.g., `prm/`, `tx/`, `logs/`, `notifications/`).
* **Decentralized Schemas:** State that this document outlines the mechanical rules of engagement, but the specific JSON schemas for the payloads remain owned by the component design documents generating them.

#### 15. Central Architecture Document

* **Cleanup:** Remove the atomic write procedure specifics from this document, delegating them entirely to the new Shared Volume Design Document.

---

### Discussion & Document Notes

Here are the critical architectural notes and requirements that will need to be detailed in the respective design documents prior to drafting their formal list updates:

* **Central Architecture Document / DGL / DAC:** Must explicitly mandate a strict zero-webhook policy. The system is prohibited from exposing any inbound connectivity endpoints.
* **Deployment Architecture Document:** Must outline a standard Docker containerized environment. Secret injection methods must be exclusively restricted to environment variables.
* **Codebase & Repository Architecture Document:** Needs to formally designate Codeberg as the primary hosting platform for all source code, documentation, and issue tracking.
* **Parser Library & CLI Tooling Design Document:** Must dictate the use of the `.clime` file extension for the DSL. Furthermore, it must specify that unique rule IDs are strictly generated dynamically via file collation and source location, and never embedded directly within the DSL text.
* **Internal Event Bus / Core Engine:** Should outline that the core implementation language across these components will be Python, maximizing compatibility with the shared library components.
* **Command Parser Design Document:** Needs to clearly establish that the parsing logic must recognize climate reports generated by both the primary bot user and any specifically configured administrative users.
* **State Rehydrator Design Document:** Must strictly enforce that historical end-of-turn reports are ignored during the recovery phase. Rehydration must only process state changes where the active rules at the time of execution can be absolutely guaranteed.
