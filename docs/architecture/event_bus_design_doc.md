# Internal Event Bus Design Document

## 1. Overview

The Internal Event Bus is the central messaging backbone of the Core Daemon. It operates as an entirely in-memory, lightweight Pub/Sub broker, facilitating asynchronous Event-Driven Architecture (EDA) across all components. To strictly adhere to the requirement for a stateless system, the event bus utilizes no external database or persistent message queue services (such as Redis or RabbitMQ). It routes ephemeral data payloads instantly to active subscribers, ensuring that input/output operations remain decoupled from core logic execution.

## 2. Implementation Options for Python 3

Given the strict constraint against database dependencies and the need for a highly asynchronous, lightweight environment, there are a few primary pathways for implementing the Pub/Sub broker natively in Python 3.

### Option A: Standard Library `asyncio.Queue` (Recommended)

This approach leverages Python's built-in `asyncio` primitives to construct a custom message router.

* **Mechanism:** The event bus maintains a single central incoming `asyncio.Queue`. When a component subscribes to a topic, the bus provisions a dedicated outgoing `asyncio.Queue` for that component. A dedicated background task (the "Broker Loop") continuously awaits the central queue, reads incoming events, and immediately fans them out by placing them into the specific outgoing queues of all registered subscribers for that topic.
* **Advantages:** Zero external dependencies, robust handling of high-concurrency event loops, and native compatibility with the decoupled async operations required by the Core Daemon. It enforces strict non-blocking behavior.
* **Disadvantages:** Requires custom boilerplate to manage subscriber registration, queue provisioning, and graceful teardown during application shutdown.

### Option B: PyPubSub

A popular, lightweight publish-subscribe library for Python.

* **Mechanism:** Components use a unified API to `subscribe()` to string-based topics and `sendMessage()` to broadcast payloads.
* **Advantages:** Exceptionally simple API, built-in topic tree management, and excellent debugging capabilities.
* **Disadvantages:** Primarily designed for synchronous execution. While it can be wrapped in `asyncio.to_thread` or executed within async tasks, it does not natively yield to the Python event loop during dense fan-out operations, potentially causing micro-blocking in a high-throughput async daemon.

### Option C: Blinker

A fast Python in-process signaling library.

* **Mechanism:** Utilizes a signal-based architecture where topics are instantiated as `Signal` objects. Senders emit signals, and connected receivers execute their callback functions.
* **Advantages:** Extremely fast and highly optimized for in-memory object dispatch.
* **Disadvantages:** Like PyPubSub, it is fundamentally synchronous. Dispatching a signal directly invokes the connected receiver functions on the same thread, violating the strict decoupling required to guarantee publishers are never blocked by subscriber execution times.

**Selection:** Option A (`asyncio.Queue` custom broker) is the most viable path. It guarantees the necessary asynchronous, non-blocking boundaries between publishers and subscribers without introducing external state or dependencies.

## 3. Sender Identification & Registration

Every message traversing the bus must be explicitly traceable to its origin. To enforce this:

1. **Attachment:** When a component initializes and attaches to the Internal Event Bus, it must pass a unique string identifier (e.g., `core.rules_engine`, `dgl.listener`).
2. **Encapsulation:** Components do not format the final message envelope. They call an async publish method, providing the topic and the payload. The Event Bus automatically wraps this payload into a standard `Event` object, injecting the registered component's identifier as the `sender_id` alongside a UTC timestamp.
3. **Delivery:** Subscribers receive this fully formed `Event` object, ensuring they can reliably route responses (such as `app.health_response`) or trace the origin of an `app.abort` signal.

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
