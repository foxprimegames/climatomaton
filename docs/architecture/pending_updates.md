### Pending design document updates

*Note: This list is organized in reverse chronological order relative to the sequence of completion (items to be completed last are at the top, while the highest priority item to be completed first is at the bottom). This prevents the need to renumber subsequent entries as completed documents are removed from the list.*

#### 1. Testing Protocol Document (New Document)

* **Testing Requirements:** Establish the necessary protocols for functional testing of the integrated system.

#### 2. Deployment Architecture Document (New Document)

* **Shared Volume Requirements:** Specify that the deployed shared volume used to accommodate the IPC mechanisms must support the underlying file system operations required by the Atomic Write Protocol.
* **PRM Configuration Definitions:** Include required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`).
* **Containerized Environment:** Outline a standard Docker containerized environment. Secret injection methods must be exclusively restricted to environment variables.
* **Shared Volume Mounting:** The orchestration layer must support mounting a common, high-speed, POSIX-compliant shared volume across multiple containers (the Core Daemon, PRM, and PEMs) to facilitate the file-based IPC routing.
* **Secrets Management:** Sensitive configurations (e.g., Discord Bot Tokens, Admin User IDs, Target Channel IDs) must be injected safely into the containers strictly via environment variables. The running containers cannot rely on the existence of, or integration with, a secret management system at runtime.
* **Configuration Management:** The method of passing non-secret configuration information (e.g., standardizing internal operations and logging to the UTC timezone, logging verbosity, maximum IPC file size limits, expected PEM modules) to the app and pluggable modules must be defined.
* **Container Lifecycle & Health Checks:** The environment should be capable of automatically restarting failed subprocesses (PEMs/PRMs). The Core Daemon relies on external orchestration to keep the pluggable modules running if they crash.
* **Log Aggregation:** Because the Logging Manager writes all local observability data to `stdout`/`stderr` using a native logger, the deployment environment must feature an agent or mechanism to capture, rotate, and aggregate standard output logs.
* **Graceful Shutdown Signals:** The environment must issue standard termination signals (`SIGTERM`) and provide a brief grace period to allow the Event Bus and Rules Engine to finalize any in-flight file writes and network requests before exiting.
* **Testing Environment:** Functional testing of the integrated system will be performed against a dedicated staging or private testing-only Discord server to ensure live Nomicron gameplay is completely isolated from development.

#### 3. App Wrapper Design Document (New Document)

* **App Workflow Definition:**
  * Start the event bus.
  * Subscribe to the `app.waiting_to_initialize` and `app.ready` events.
  * Start all other components, passing an identifier to each component.
  * Wait for an `app.waiting_to_initialize` event from each component.
  * If it does not receive all such events within a given time limit, cause the entire app to exit with a failure log written directly to stderr and a non-0 exit code.
  * Publish an `app.initialize` event which all components should subscribe to.
  * Wait for an `app.ready` event from each component.
  * If it does not receive a `app.ready` event from all components within a given time limit (more generous since component initialization can take significant time), cause the entire app to exit with a failure log and an exit code.
  * Publish an `app.start` event to indicate all components should begin normal operation.
  * Wait forever for either an `app.terminate_gracefully` event or `app.abort` event.
  * Upon receiving an `app.abort` event, log the error contained within the event directly to stderr and exit with a non-0 exit code.
  * Upon receiving an `app.terminate_gracefully` event, it should send an `app.prepare_for_shutdown` event to all components.
  * After receiving the `app.ready_for_shutdown` event from all components, *or* after a given timeout, exit the app gracefully.
* **Event-Based Health Monitoring:** Detail the explicit requirements for the App Wrapper to routinely dispatch health queries across the internal event bus, enforce response timeouts per component, and maintain a serialized health status file containing sets of healthy/unhealthy subsystems alongside a rolling UTC liveness timestamp.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 4. Health Checking and Observability Procedures Document (New Document)

* **Procedures:** Standardize general health checking and observability procedures to be followed by all components (Core, PRMs, PEMs) for outputting structured standard logs, defining container health-check endpoints/mechanisms, and constructing alert payloads.

#### 5. Logging & Observability Manager Design Document (New Document)

* **Component Specifications:** Detail the internal architecture, event handling, routing logic, and data structures of the Logging & Observability Manager component.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 6. DAC (Discord API Client) Design Document (New Document)

* **Discord Integration Specifics:** Define exact OAuth2 scopes (DAC).
* **Rate Limiting:** The DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 7. DGL (Discord Gateway Listener) Design Document (New Document)

* **Discord Integration Specifics:** Define exact Discord intents/permissions (DGL).
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 8. Rules Engine Design Document (New Document)

* **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for loaded PEM schemas. Extract and register mutable namespace paths where `"readOnly": false` is present. Strictly map JSON schema `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
* **Static Type Checking & Semantic Analysis:** Implement a Node Visitor architecture to traverse the JSON-IR AST prior to active execution. Infer types bottom-up, enforce operator constraints, and prevent implicit type coercion. Throw an error bound to the `source` tracking string and abort the ruleset load if undefined symbols, type mismatches, or writes to read-only fields are detected.
* **Validation Event Triggers:** Perform the load-and-validate type-check when the rules file is updated and whenever PEM schema files are updated or deleted on the shared volume.
* **Pause Event Processing:** Process `app.pause` and `app.unpause` events, even if the component is in initialization, to ensure it does not start up in the wrong state.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 9. Command Parser Design Document (New Document)

* **Input Processing:** Define the logic and string-matching patterns required to identify, extract, and route bot commands and direct messages from text streams.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 10. EOT Parser Design Document (New Document)

* **Report Extraction:** Establish the parsing architecture for pulling relevant state variables and triggering mechanics from standardized end-of-turn text reports.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 11. Environment Manager Design Document (New Document)

* **State Tracking:** Outline the memory structures and lifecycles used to track active climate modules, environmental tags, and active modifiers during a running session.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 12. State Rehydrator Design Document (New Document)

* **Initialization Workflow:** The state rehydration workflow serves as the initialization workflow for the state rehydrator component. Upon receiving the `app.initialize` event, it requests channel history from the DAC, parses messages to populate the `climate` environment, and implements the pause-and-notify mechanism to transition the core daemon to a paused state if any end-of-turn reports are found chronologically later than the most recent climate report. When finished initializing, it publishes an `app.ready` event. Other than this initialization workflow, the state rehydrator does nothing except immediately respond to app wrapper events as appropriate.
* **Climate Report Parsing:** Clearly designate this component's responsibility to parse climate reports, ensuring the parsing logic successfully recognizes reports generated by both the bot itself and any configured administrative users.
* **End-of-Turn Rule Enforcement:** Explicitly enforce the rule that historical end-of-turn reports are never processed during recovery.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 13. IPC Broker Design Document (New Document)

* **Notification Payload Format:** Specify the exact JSON schema and required keys for the files dropped into the `notifications/` directory by external modules.
* **Heartbeat Monitoring (PEMs):** Implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs update their schema file timestamps every 30 seconds, the IPC Broker checks every 60 seconds. A PEM missing two consecutive checks (120 seconds) is considered dead, prompting the Broker to purge its stale files.
* **Heartbeat Monitoring (PRMs):** Implement monitoring for the PRM liveness. The PRM will update the modified timestamp of `prm/active_rules.json` on a regular interval. The IPC Broker must detect this timestamp change. Upon detection, it must read the file and check the root `id` field. If the `id` matches the current active ruleset, the Broker merely updates the PRM's last-seen timestamp. If the PRM misses two consecutive heartbeat intervals, the IPC Broker must emit a system event to drop the Core Engine into a PAUSED state.
* **Ruleset Update Event:** Specify that the `ipc.rules_updated` event is only fired if the parsed `id` from the `prm/active_rules.json` file differs from the currently loaded ruleset.
* Each component, upon receiving the `app.initialize` event, is required to clean up any in-flight or temporary files it may have created and ensure the component is ready to function. When it is finished initializing, it publishes an `app.ready` event.
* Each component, upon receiving the `app.start` event, begins normal processing.
* Each component, upon receiving the `app.prepare_for_shutdown` event, must gracefully stop all in-flight transactions and do as much cleanup as it can, then send the `app.ready_for_shutdown` event.
* **Workflow Diagrams:** Include relevant system event flow and lifecycle diagrams specific to this component.

#### 14. Parser Library & CLI Tooling Design Document (New Document)

* **Library Specifications:** Detail the architecture of the shared Python parsing library that translates plain-English Clime files into JSON-IR.
* **I/O Decoupling Requirement:** Explicitly specify that the library must perform no file operations. The functions for Lexing, Parsing, and Emitting must be designed to accept either static objects (strings, lists of strings, or populated AST objects) or iterators yielding the appropriate content, returning the resulting token stream, AST, or JSON-IR respectively.
* **Error Accumulation Strategy:** The parser must implement an error recovery strategy. Instead of fast-failing via exceptions, it should accumulate syntax errors and return a structured Result object (e.g., `success`, `errors`, `ast`), allowing callers to process multiple errors simultaneously.
* **CLI Tooling:** Define the behavior of the standalone syntax checker CLI, detailing input arguments, exit codes for CI/CD integration, file-loading wrappers, and verbose error formatting for local debugging.
