# Internal Event Bus Design Document

## 1. Overview

The Internal Event Bus is the central messaging backbone of the Core Daemon. It operates as an entirely in-memory, lightweight Pub/Sub broker, facilitating asynchronous Event-Driven Architecture (EDA) across all components. To strictly adhere to the requirement for a stateless system, the event bus utilizes no external database or persistent message queue services (such as Redis or RabbitMQ). It routes ephemeral data payloads instantly to active subscribers, ensuring that input/output operations remain decoupled from core logic execution.

## 2. Implementation Options for Python 3

To satisfy the strict system constraints—requiring **no external message broker** and **no synchronous solutions**—the architecture must rely entirely on native Python 3 asynchronous primitives. Below is an evaluation of the primary pathways, including the specific architecture proposed by Hash Block.

### Option A: Standard Library `asyncio.Queue` Custom Broker

* **Mechanism:** The event bus maintains a single central incoming `asyncio.Queue`. When a component subscribes to a topic, the bus provisions a dedicated outgoing `asyncio.Queue` for that component. A background Broker Loop continually reads from the central queue and pushes messages into the respective subscribers' queues.
* **Evaluation:** Highly compliant. It enforces a strict asynchronous producer-consumer separation but introduces minor overhead for managing multiple internal queue objects.

### Option B: Hash Block Async Callback Engine (Highly Applicable)

This approach refers to the pure-Python, 80-line in-memory dispatcher design pattern. It utilizes a `defaultdict(list)` to map string-based topics directly to a collection of asynchronous coroutine functions (`Callable[[Any], Coroutine]`).

* **Mechanism:** When an event is published, the engine iterates over the subscribers registered to that topic and directly schedules or executes the handlers asynchronously within the native event loop (e.g., using `asyncio.create_task` or a fanned-out loop).
* **Evaluation:** Fully applicable and optimal for this project. It features zero third-party library dependencies, eliminates external brokers entirely, and operates natively within the `asyncio` loop to prevent any synchronous blocking or micro-blocking of the main daemon.

### Option C: Synchronous Libraries (Dismissed)

Libraries such as PyPubSub or Blinker rely on a synchronous execution model where publishing an event directly invokes callback functions on the current thread.

* **Evaluation:** Violates core constraints. A slow or blocking operation in a subscriber would block the publisher, stalling the entire Core Daemon.

**Selection:** Option B (the Hash Block async callback model) provides the cleanest and most lightweight baseline, as it eliminates the boilerplate of individual sub-queues while guaranteeing full asynchronous, non-blocking execution.

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
