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

The bus strictly manages the following currently defined topics to route data between the Core Daemon and its pluggable subsystems.

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

To standardize communication, the `EventBusWrapper` strictly enforces a generic schema for all messages and implements a strict lifecycle for managing responses.

### 5.1 Event Schema

When a publisher dispatches a payload, the wrapper constructs an `Event` object containing:

* **`event_id`**: A unique UUID string generated at the time of publication.
* **`topic`**: The routing string (e.g., `game.eot_detected`).
* **`sender_id`**: The unique identifier of the component that published the event.
* **`timestamp_utc`**: An ISO-8601 formatted UTC timestamp.
* **`payload`**: The generic, topic-specific data payload (can accommodate arbitrary structures based on the event type).

### 5.2 Response Lifecycle & Schema

When a subscriber receives an `Event`, it processes the payload and determines the response lifecycle by returning a value to the wrapper. The wrapper evaluates the return value as follows:

* **No Response:** The subscriber returns `None`. The wrapper takes no further action, and no response event is generated.
* **Successful Response:** The subscriber returns a generic data payload. The wrapper constructs a `Response` object containing the originating event's ID assigned to `correlation_id`, a `status` of `"success"`, and the returned payload. The wrapper then encapsulates this `Response` within a new `Event` object and publishes it back to the original publisher.
* **Exception State:** The subscriber raises an unhandled exception. The wrapper intercepts the exception and proceeds to the error handling procedure outlined in Section 6.

**Response Schema:**
When generated, the encapsulated `Response` object contains:

* **`correlation_id`**: The UUID matching the `event_id` of the original `Event` that triggered the response.
* **`status`**: A string indicating `"success"` or `"exception"`.
* **`data`**:
  * For `"success"`: The custom payload returned by the subscriber.
  * For `"exception"`: An error payload explicitly containing both the exception instance itself and the traceback object (as tracebacks are not always cleanly attached depending on how the loop caught them).

## 6. Error Handling & Isolation

Because subscriber callbacks execute asynchronously within the native event loop, the `EventBusWrapper` implements a strict isolation and logging policy to maintain system stability.

1. **Execution Wrapping:** The wrapper executes all subscriber callbacks within a safe `try/except` block.
2. **Exception Capture & Routing:** If a subscriber raises an unhandled exception, the wrapper intercepts it to prevent the background broker loop from crashing. It then evaluates the originating event to prevent recursive error loops:
   * If the originating `Event` already contained a `Response` object with a `status` of `"exception"`, the wrapper bypasses the event bus entirely and dumps the new exception directly to standard error (`stderr`).
   * If the originating `Event` did not contain a `Response` object, or the wrapped `Response` object did not have a `status` of `"exception"`, the wrapper constructs a `Response` object containing the originating event's ID assigned to `correlation_id`, a `status` of `"exception"`, and the exception payload (the exception and traceback). This `Response` object is then wrapped in a new `Event` and published back to the original publisher.
3. **Logging & Recursive Guard:** Independently of the response routing above, the wrapper also attempts to generate and publish a standard `sys.log` event detailing the intercepted exception to ensure it reaches the Logging Manager. To prevent infinite recursive error loops (e.g., if the Logging Manager itself crashes while processing a log event), the wrapper inspects the `topic` of the originating `Event`. If the originating `topic` was `sys.log`, the wrapper assumes the observability pipeline is compromised. It skips publishing a new `sys.log` event and instead dumps the critical failure and traceback directly to `stderr`.
