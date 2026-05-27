First, you are completely right on both of your initial points. I put words in your mouth regarding the disk exhaustion question—that was my mistake.

Second, you are absolutely correct that I should have asked for the expected throughput and event frequency during the architecture phase. Designing a system without knowing if it needs to handle 10,000 events a second or, as you just clarified, **one event a week**, is a massive oversight. That context completely changes the performance requirements and validates the exact questions you are asking now.

To answer your third point directly: **The described design *is* an Event-Driven Architecture (EDA), but it is a highly specialized, low-infrastructure variant.** Rather than using a traditional, complex EDA setup, this design uses what is known as **Filesystem-Backed Message Passing**. Here is how it differs from a traditional EDA, how they compare, and why this specific flavor is the best practice for your actual game parameters.

---

### How it Differs from a "Traditional" EDA

In a standard enterprise EDA, decoupled components communicate by pushing events to a dedicated **Message Broker** (like RabbitMQ, Apache Kafka, or Redis Pub/Sub).

1. **The Event Bus:** A traditional EDA relies on a network-based middleware broker to route messages. Our design removes the broker entirely and uses the **Shared Docker Volume** (the filesystem) as the event bus.
2. **Push vs. Pull:** A traditional EDA pushes notifications directly into a consumer's memory. Our design relies on independent workers **polling** a directory (like `outbox/` or `rules.commit`) to see if a new event (file) has arrived.
3. **State Management:** Traditional EDAs require complex Acknowledgement/Negative-Acknowledgement (ACK/NACK) protocols to ensure messages aren't lost if a worker crashes. Our design relies on atomic OS-level file renames; the file *is* the state, and it persists on disk naturally until successfully processed and deleted.

### How it is Better or Worse than a Traditional EDA

#### **Where it is Worse (The Cons):**

* **Latency and I/O Overhead:** Filesystem polling is significantly slower than in-memory network routing. Continually asking the hard drive, "Are there new files yet?" consumes CPU cycles and introduces micro-delays.
* **Throughput Ceilings:** If your bot suddenly went viral and had to process 5,000 proposal reports a minute, disk I/O would become a massive bottleneck. A pure EDA with RabbitMQ would handle that easily; our filesystem approach would likely choke.

#### **Where it is Better (The Pros):**

* **Zero Infrastructure Bloat:** You do not need to deploy, configure, secure, or monitor a Redis container or a Kafka cluster. Everything runs inside your single container footprint.
* **Total Network Isolation:** Because components communicate via disk, there are zero internal network ports open. It is completely immune to network-based internal service spoofing.
* **Ultimate Debuggability:** If the outbox queue gets stuck, you don't need a specialized CLI tool to inspect a message broker. You can just `ls` the `outbox/` directory and read the plain-text JSON files.

### Why this Design is a Better Fit for "Best Practices"

Best practices are not universal; they are dictated by constraints. The golden rule of software architecture is **KISS (Keep It Simple, Stupid)** and avoiding premature optimization.

Given your newly revealed constraint—**one proposal report per week**—introducing a traditional EDA message broker would be a massive architectural anti-pattern.

If we built a pure EDA for this, you would be allocating RAM to run a Redis container 24/7, maintaining internal network bridges, and writing connection retry logic, all to route *exactly four messages a month*.

The described design is the best practice for Climatomaton because it captures **100% of the structural benefits of an EDA** (component isolation, independent failure domains, unblocked network listeners) with **0% of the infrastructure overhead**. The polling latency that makes filesystem-queues "worse" for high-frequency trading is completely irrelevant when you have 168 hours to process the next event.

---

Given that we are only expecting one standard execution cycle per week, the in-memory queues I proposed for the Gateway (to handle high-throughput bursts) might also be over-engineered. Would you prefer to strip out the internal memory queues and have the `DiscordGatewayConnector` execute the `CommandIngestionWrapper` synchronously, relying *only* on the outbox filesystem to decouple the Discord network latency?
