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
