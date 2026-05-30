# Pluggable Environment Module (PEM) Design Document

## 1. System Overview

A Pluggable Environment Module (PEM) is an independent, stateless process responsible for managing an externally-defined environment data set. Its primary function is to make a specific data namespace available to the Climatomaton core system, allowing climate and tag rules to evaluate and potentially mutate this data during end-of-turn (EOT) processing.

PEMs are entirely decoupled from the core daemon and communicate strictly via file-based Interprocess Communication (IPC) utilizing a shared directory volume. To ensure data integrity, all file writes must be performed atomically. A PEM must write its data to a temporary file (e.g., `.tmp`) and then execute a system rename operation to place the file in its final path. All timestamping must utilize the UTC timezone.

---

## 2. The Schema File

The schema file dictates the structure, data types, and mutability of the environment data the PEM provides.

* **File Naming Convention:** `pems/{pem_namespace}.schema.json`.
* **Timing and Cadence:** The file must be written as soon as the PEM starts up. It must also be periodically updated (at an interval no greater than a predefined maximum, such as 60 seconds) to serve as a heartbeat indicating the PEM is alive.
* **Content Description:** The schema explicitly maps namespace paths to primitive types (e.g., numbers, strings, boolean values, or lists of strings/tags). It rigorously defines which namespace paths are mutable. Any namespace path not explicitly marked as mutable in this file is strictly treated as read-only by the Rules Engine. It also establishes how wildcard characters (e.g., `*`) are handled for dynamic keys.

**Format Layout (`{pem_namespace}.schema.json`)**

```json
{
  "namespace": "weather",
  "heartbeat_interval_seconds": 60,
  "paths": {
    "temperature": {
      "type": "number",
      "mutable": false
    },
    "forecast_tags": {
      "type": "tag_list",
      "mutable": true
    },
    "regions.*.wind_speed": {
      "type": "number",
      "mutable": false
    }
  }
}
```

---

## 3. The Environment Data File

The environment data file contains the actual state values utilized by the Rules Engine during evaluation.

* **File Naming Convention:** `pems/{pem_namespace}.json`.
* **Timing and Cadence:** This file must be written as soon as practical after the schema file is established. It must be atomically updated whenever the underlying represented content changes.
* **Content Description:** The file contains the structured JSON environment data. The root of the JSON object maps directly to the identifiers within the namespace, explicitly omitting the PEM's top-level namespace prefix.

**Format Layout (`{pem_namespace}.json`)**

```json
{
  "temperature": 72,
  "forecast_tags": ["Sunny", "Breezy"],
  "regions": {
    "north": {
      "wind_speed": 15
    },
    "south": {
      "wind_speed": 5
    }
  }
}
```

---

## 4. Transaction & Acknowledgment Files

When the active ruleset successfully mutates a mutable field within a PEM's namespace, the Rules Engine duplicates that mutation into the `new.` transaction environment and writes a diff payload to the shared volume. The PEM is responsible for ingesting this mutation and confirming receipt.

### 4.1 Transaction Request File

* **File Naming Convention:** `tx/req_{tx_id}_{namespace}.json`.
* **Timing:** Written asynchronously by the Rules Engine upon successful completion of a rule evaluation that alters a PEM's state.
* **Content Description:** Contains the unique transaction identifier, the target namespace, and a flat map of the specific namespace paths and their newly mutated values.

**Format Layout (`req_{tx_id}_{namespace}.json`)**

```json
{
  "tx_id": "98765-abcde",
  "namespace": "weather",
  "mutations": {
    "forecast_tags": ["Sunny", "Breezy", "Storm_Warning"]
  }
}
```

### 4.2 Transaction Acknowledgment File

* **File Naming Convention:** `tx/ack_{tx_id}_{namespace}.json`.
* **Timing:** Written atomically by the PEM immediately after it detects, processes, and applies the corresponding transaction request file.
* **Content Description:** Confirms the success or failure of the requested state mutation. Upon detection of this file, the IPC Broker flags the transaction as complete, allowing the core daemon to finalize the Discord report and eventually delete both the request and acknowledgment files.

**Format Layout (`ack_{tx_id}_{namespace}.json`)**

```json
{
  "tx_id": "98765-abcde",
  "namespace": "weather",
  "status": "success",
  "timestamp": "2026-05-30T20:41:43Z"
}
```
