## List of required Design Documents

### 1. Shared Volume Contract Design Document [_COMPLETE_]

This document defines the core data layout, synchronization protocols, and atomic file update rules that govern decoupled communication across all container modules over the shared Docker volume.

* **Shared Volume Layout & Directory Structure:** Define the folder topology, including the static `rules.commit` pointer path, the `outbox/` IPC notification queue, and versioned rules folders (`rules-YYYYMMDD-HHMMSS/`).
* **Atomic File Update Protocol:** Outline the strict three-step sequence (`Serialize` to `.tmp` $\rightarrow$ `Flush` via `fsync()` $\rightarrow$ `Rename`) required for any container component writing to the shared volume to prevent partial reads by the engine.
* **Rules Promotion and Validation Lifecycle:** Detail the Core Engine's execution phases when a new path is committed, including dynamic dependency extraction, JSON environment schema validation boundaries, the atomic memory pointer swap, and post-swap garbage collection.
* **Asynchronous Outbox Notification Protocol:** Specify the lifecycle and schema of JSON payloads written to the `outbox/` queue, mapping out how the engine polls, sorts, processes, and safely unlinks completed event files.

---

### 2. Custom DSL Parser & AST Interpreter Design Document

This document defines how the Core Engine ingests raw `.rules` files, builds an executable Abstract Syntax Tree (AST), handles sorting priorities, and safely executes calculations against the dynamic memory graph.

* **Lexer / Tokenizer Specification:** Define the regular expressions and token states for literals (strings, floats, integers), relational operators, and logical keywords, explicitly matching space-separated strings `climate rule` and `tag rule`.
* **Parser Architecture & AST Schema:** Outline the recursive descent parser mapping to EBNF grammar, including the structural expansion of chained relational expressions (e.g., `0 < climate.value <= 90`) into implicit logical conjunction nodes.
* **Collation, Sorting, and Rule ID Indexer Engine:** Detail the multi-file merging algorithm sorted ascending primarily by numeric `FileNumber` and secondarily alphabetically by filename, utilizing resetting counters to assign unique continuous `FileNumber-RuleIndex` identifiers.
* **Syntax Discovery & Validation Pipeline:** Detail how the parser acts as an isolated validation phase during rules promotion, throwing compiler exceptions to abort transactions before memory pointers are modified.
* **Runtime AST Interpreter & Transaction Safety:** Document the runtime evaluation engine that resolves `NamespacePath` variables sequentially in strict numeric order, enforcing an immediate abort, transactional rollback, and dual-delivery error log upon any processing failure.

---

### 3. PRM (Git-Fetch) Design Document

This document defines how the Pluggable Rules Module operates as an automated version-control fetcher and directory coordinator to act as the system's operational clock.

* **Git Operations & Authentication Config:** Define the process environment variables required to target the external source repository (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_FOLDER`) and how the system securely loads access credentials.
* **Sync Polling Logic:** Define the interval timers and commit hash comparison rules used to fetch upstream changes without procedurally modifying the rulesets themselves.
* **Staging Directory Rotation Pipeline:** Detail the workflow for establishing uniquely named, versioned folders (`rules-YYYYMMDD-HHMMSS/`) relative to the root of the shared volume to maintain complete write isolation.
* **Atomic Promotion Protocol:** Outline the sequence for flushing written rules files, writing the relative folder path payload to `.rules.commit.tmp`, and performing an atomic host-level `rename()` to the static `rules.commit` file path.

---

### 4. Discord Gateway & Ingestion Engine Design Document

This document serves as the implementation blueprint for the inbound gateway client, message processing loops, command ingestion wrappers, and system state transitions.

* **Gateway Connection & Channel Monitoring Infrastructure:** Specify connection lifecycle management rules, tracking heartbeats, handling session resumes, and declaring the mandatory Privileged Gateway Intents (`GUILD_MESSAGES`, `MESSAGE_CONTENT`) required to capture raw channel events.
* **Discord Command Registration & Ingestion Layer:** Detail global registration routines targeting Discord's REST endpoints for the `/climate` command and its subcommands (`reprocess`, `reset`), alongside gateway hooks for `INTERACTION_CREATE` and administrator `MESSAGE_CREATE` DM events that normalize inputs into uniform text arrays.
* **Inbound Proposal Ingestion:** Detail the text pattern-matching filters that actively monitor the public game channel for incoming proposal reports to parse metrics directly into the `proposals` namespace keys (`count`, `passed`, `failed`).
* **Bootstrap Flow & State Recovery Engine:** Document the chronological lookback loop pattern that processes historical logs backward to locate the most recent live climate report anchor state or trigger a baseline reset, constrained by a startup gate preventing rule evaluation during the initialization scan.
* **Unified Command Parser (Pure Text & Logic Processing Layer):** Detail the positional string-splitting algorithm, the hyphen (`-`) placeholder token processing for omitted optional parameters, and the step-by-step internal execution workflows for `reprocess` and `reset` (including the literal `default` baseline wipe and updated plain-English status broadcasts).
* **Outbox IPC Worker:** Document the background file watcher that polls the shared volume's `outbox/` queue, enforces alphabetical sorting for chronological transmission, manages rate-limiting client queues, and unlinks event files only after verified HTTP delivery.
