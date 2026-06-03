# Internal Event Bus Design Document

## 1. Overview

The Internal Event Bus is the central messaging backbone of the Core Daemon. It operates as an entirely in-memory, lightweight Pub/Sub broker, facilitating asynchronous Event-Driven Architecture (EDA) across all components. To strictly adhere to the requirement for a stateless system, the event bus utilizes no external database or persistent message queue services (such as Redis or RabbitMQ). It routes ephemeral data payloads instantly to active subscribers, ensuring that input/output operations remain decoupled from core logic execution.

## 2. Implementation Strategy

The Event Bus utilizes a pure-Python, asynchronous callback engine based on the architecture described in ["How I built an in-memory Pub/Sub engine in Python with only 80 lines" by Hash Block](https://medium.com/@connect.hashblock/how-i-built-an-in-memory-pub-sub-engine-in-python-with-only-80-lines-eb42d30f0160).

This specific implementation is a structural design pattern consisting of a single, highly optimized class utilizing `asyncio` and `defaultdict`. It is not available as a standalone PyPI package. By integrating this source code directly into the shared libraries, the project completely avoids external dependencies while strictly satisfying the "no external message broker" and "no synchronous solutions" constraints.

### 2.1 The EventBus Wrapper

To satisfy the strict requirements of the Core Daemon without modifying the original Hash Block implementation, the raw `PubSub` class is encapsulated within a custom `EventBusWrapper`. All system components interact exclusively with this wrapper. The wrapper provides the standard `subscribe()` interface (passing it directly to the underlying engine) but overrides the `publish()` behavior to construct standardized envelopes.

## 3. Sender Identification & Registration

Every message traversing the bus must be explicitly traceable to its origin. To enforce this, the `EventBusWrapper` handles the following workflow:

1. **Attachment:** When a component initializes and attaches to the wrapper, it must pass a unique string identifier (e.g., `core.rules_engine`, `dgl.listener`). The wrapper provisions a bound publisher interface specific to that component.
2. **Encapsulation:** Components do not format the final message envelope. They call the bound publish method, providing only the topic and the payload. The wrapper automatically wraps this payload into a standard `Event` object, injecting the registered component's identifier as the `sender_id` alongside a UTC timestamp, and then passes the complete object to the underlying `PubSub` engine.
3. **Delivery:** Subscribers receive this fully formed `Event` object from the underlying engine, ensuring they can reliably route responses (such as `app.health_response`) or trace the origin of an `app.abort` signal.

## 4. Topic Registry

The bus strictly manages the following predefined topics to route data between the Core Daemon and its pluggable subsystems.

| Topic | Publisher | Subscriber(s) | Payload / Data Communicated |
| --- | --- | --- | --- |
| `network.inbound` | DGL | Command Parser, EOT Parser | `raw_json_payload`, `source` (channel/DM) |
| `game.eot_detected` | EOT Parser | Rules Engine | `EOTSummary` object |
| `game.command` | Command Parser | Core Daemon, Rules Engine | `command_action` (e.g., reset), `parsed_args` |
| `ipc.rules_updated` | IPC Broker | Rules Engine | `file_path` (relative to shared volume) |
| `ipc.pem_ack` | IPC Broker | Rules Engine | `tx_id`, `namespace` |
| `sys.log` | All Components, IPC Broker | Logging Manager | `level`, `source`, `message`, `metadata` |
| `sys.notification` | All Components, IPC Broker | Logging Manager | `level`, `message_text`, `admin_ids` |
| `network.outbound` | Rules Engine, Logging Manager | DAC | `formatted_message`, `target_destination` (channel/user ID) |
| `app.waiting_to_initialize` | All Components | App Wrapper | `component_id` |
| `app.initialize` | App Wrapper | All Components | (Empty/Command) |
| `app.ready` | All Components | App Wrapper | `component_id` |
| `app.start` | App Wrapper | All Components | (Empty/Command) |
| `app.abort` | All Components | App Wrapper | `error_details` |
| `app.terminate_gracefully` | All Components | App Wrapper | (Empty/Command) |
| `app.prepare_for_shutdown` | App Wrapper | All Components | (Empty/Command) |
| `app.ready_for_shutdown` | All Components | App Wrapper | `component_id` |
| `app.pause` | State Rehydrator, Command Parser | Rules Engine, Core Daemon | `reason` |
| `app.unpause` | Command Parser | Rules Engine, Core Daemon | `reason` |
| `app.health_query` | App Wrapper | All Components | `query_payload` (JSON) |
| `app.health_response` | All Components | App Wrapper | `status_payload` (JSON) |

## 5. Event and Response Envelopes

To standardize communication, the `EventBusWrapper` strictly enforces a generic schema for all messages and their corresponding asynchronous replies.

### 5.1 Event Schema

When a publisher dispatches a payload, the wrapper constructs an `Event` object containing:

* **`event_id`**: A unique UUID string generated at the time of publication.
* **`topic`**: The routing string (e.g., `game.eot_detected`).
* **`sender_id`**: The unique identifier of the component that published the event.
* **`timestamp_utc`**: An ISO-8601 formatted UTC timestamp.
* **`payload`**: The generic, topic-specific data payload (can accommodate arbitrary structures based on the event type).

### 5.2 Response Schema

For events that require or trigger a direct return structure, the subscriber returns a `Response` object containing:

* **`event_id`**: The UUID matching the original `Event`.
* **`status`**: A string indicating the outcome (e.g., `success` or `error`).
* **`data`**:
  * If `status` is `success`, this contains the successful custom response payload.
  * If `status` is `error`, this contains the serialized exception information and stack trace.

## 6. Error Handling & Isolation

Because subscriber callbacks execute asynchronously within the native event loop, the `EventBusWrapper` implements a strict isolation and logging policy to maintain system stability.

1. **Execution Wrapping:** The wrapper executes all subscriber callbacks within a safe `try/except` block.
2. **Exception Capture:** If a subscriber raises an unhandled exception, it is caught by the wrapper, preventing the background broker loop from crashing. The wrapper then constructs an `error` status `Response` containing the exception data.
3. **Logging & Recursive Guard:** Upon catching an exception, the wrapper automatically attempts to publish a `sys.log` event to route the error to the Logging Manager. To prevent infinite recursive error loops (e.g., if a failure occurs while processing the `sys.log` event itself), the wrapper utilizes a strict fallback. If an exception occurs *during* the handling or dispatch of an error event, the wrapper bypasses the event bus entirely and dumps the critical failure directly to standard error (`stderr`).
