# Synchronization Protocol

## 1. Shared Volume Layout and Manifest Specification

The shared volume serves as the primary communication medium. The Core Engine and all modules coordinate via a deterministic versioned directory structure.

```text
/ (Shared Volume Root)
├── rules.commit                    # Atomic pointer file
├── outbox/                         # IPC queue for Discord notifications
└── rules-YYYYMMDD-HHMMSS/          # Active versioned directory
    ├── [FileNumber]-[Descriptor].rules
    └── [namespace].json            # Pluggable environment module data
```

### "Atomic" File Update Protocol

To ensure the Core Engine never reads a partially written file, all modules (PRM and PEMs) must adhere to the following sequence for any file (including rules, environment objects, or outbox events):

1. **Serialize**: Write the new content to a temporary file (e.g., `.filename.tmp`) within the target directory.
2. **Flush**: Call `fsync()` on the temporary file to ensure data is fully flushed from OS buffers to physical storage.
3. **Rename**: Perform an OS-level `rename()` operation to replace the target file with the temporary file (e.g., `.filename.tmp` -> `filename`).
   * *Assumption*: The integrity of this protocol relies on the host OS `rename()` operation being atomic.

---

## 2. PRM Operational Workflow

The PRM acts as the autonomous system clock. It governs the timeline and dictates when the current ruleset must be superseded.

1. **Initiation**: The PRM autonomously evaluates internal game state or temporal markers to determine that a new ruleset is required.
2. **Generation**: Create a new, uniquely named versioned directory (e.g., `rules-YYYYMMDD-HHMMSS/`).
3. **Compilation**: Compile and write the validated `.rules` files into the new directory.
4. **Commitment**: Use the **Atomic File Update Protocol** to update `rules.commit` to point to the new directory. This atomic pointer update forces the Core Engine to acknowledge the new ruleset.

---

## 3. PEM Operational Workflow

PEMs are reactive components that operate independently of the Core Engine's state.

1. **Async Update**: PEMs continuously maintain their own `[namespace].json` files.
2. **Atomic Write**: PEMs use the **Atomic File Update Protocol** to ensure the Core Engine never reads a partial file when it performs its climate management cycle.
3. **Identifier Constraint**: The `[namespace]` identifier must be alphanumeric and begin with a letter to ensure valid reference within the rules language.

---

## 4. Core Engine and Game State Management

The Core Engine acts as the central orchestrator. It separates interaction types and manages data ingestion through two distinct phases.

### Phases of Operation

1. **Phase A: Rules Promotion (Compilation & Verification)**:
   * **Trigger**: Change in `rules.commit`.
   * **Action**: Compile all `.rules` files in the target directory to validate syntax and identify required `[namespace].json` dependencies.
   * **Validation**: Verify these required files exist in the target directory (or wait up to `T_MAX`).

2. **Phase B: Climate Management (Ingestion)**:
   * **Trigger**: Start of a climate update cycle.
   * **Action**: Read and parse all required `[namespace].json` files into memory.
   * **Execution**: Perform the climate management logic using the ingested data.

### Interaction Interfaces

* **Command Interface (Inbound)**: Slash commands and DMs from Discord users.
* **Report Interface (Bidirectional)**:
  * *Inbound*: Proposal reports posted to the game channel.
  * *Outbound*: Climate reports posted by the engine to the game channel.
* **Notification Interface (Outbound)**: Asynchronous alerts and logs via the `outbox/` IPC.

---

## 5. Discord Notification Workflow

This governs all **asynchronous outbound notifications**, ensuring centralized, rate-limited, and ordered communication with Discord.

#### JSON Payload Definition

The event file must contain a valid JSON object:

```json
{
  "event_type": "notification" | "report",
  "log_level": "info" | "warning" | "error" | "critical",
  "payload": "string"
}
```

#### Notification Lifecycle

1. **Event Generation**: Any component (PRM, PEM, or Core Engine) writes the JSON payload to `outbox/` using the **Atomic File Update Protocol**, with the filename formatted as `[YYYYMMDDHHMMSS]-[module].event.json`.
2. **Core Engine Processing (Gateway Logic)**:
   * The Core Engine continuously polls the `outbox/` directory.
   * Files are sorted alphabetically to ensure chronological order.
   * The engine processes files in sequence, executing the Discord API call based on the `event_type`.
   * Files are **deleted** only after the API call succeeds.

---

## 6. Summary of Interactions

| Interface Type | Participants | Direction | Interaction Trigger | Pipeline |
| --- | --- | --- | --- | --- |
| **Command Interface** | Discord User ↔ Core Engine | Inbound | Discord Command / DM | Synchronous API |
| **Report Interface** | Discord Channel ↔ Core Engine | Bidirectional | Proposal/Climate Reports | Synchronous API |
| **Notification Interface** | Module ↔ Core Engine ↔ Discord | Outbound | Event Generation | Asynchronous (`outbox/`) |
| **Rules Promotion** | PRM ↔ Core Engine | Internal | `rules.commit` update | Compile & Verify |
| **Climate Management** | PEM ↔ Core Engine | Internal | Update Cycle | Ingestion (Read/Parse) |
