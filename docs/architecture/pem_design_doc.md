# Pluggable Environment Module (PEM) Design Document

## 1. System Overview

A Pluggable Environment Module (PEM) is an independent, stateless process responsible for managing an externally-defined environment data set. Its primary function is to make a specific data namespace available to the Climatomaton core system, allowing climate and tag rules to evaluate and potentially mutate this data during end-of-turn (EOT) processing.

PEMs are entirely decoupled from the core daemon and communicate strictly via file-based Interprocess Communication (IPC) utilizing a shared directory volume. To ensure data integrity, all file writes must be performed atomically. A PEM must write its data to a temporary file (e.g., `.tmp`) and then execute a system rename operation to place the file in its final path. All timestamping must utilize the UTC timezone.

---

## 2. The Schema File

The schema file dictates the structure, data types, and mutability of the environment data the PEM provides. It is authored as a standard JSON Schema document adhering strictly to Draft 2020-12.

* **File Naming Convention:** `pems/{pem_namespace}.schema.json`.
* **Timing and Cadence:** The file must be written as soon as the PEM starts up. To serve as a heartbeat indicating the PEM is alive, this file must be atomically updated (e.g., touching the file to update its modified timestamp or rewriting it) at a system-wide defined interval of **no greater than 30 seconds**.
* **Content Description:** The schema uses standard JSON Schema validation keywords (`properties`, `type`, `items`, `patternProperties`) to define the allowed namespace paths and primitive types.
* **Mutability (The `readOnly` Constraint):** For the purposes of the Climatomaton engine, the default state of any property within a PEM schema is assumed to be read-only (`"readOnly": true`). If a PEM intends to allow the Rules Engine to mutate a specific field via tag or climate rules, it must explicitly include `"readOnly": false` on that property definition in the schema.

**Format Layout (`{pem_namespace}.schema.json`)**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://climatomaton.local/pems/weather.schema.json",
  "title": "Weather Namespace Schema",
  "type": "object",
  "properties": {
    "temperature": {
      "type": "number"
    },
    "forecast_tags": {
      "type": "array",
      "items": {
        "type": "string"
      },
      "readOnly": false
    },
    "regions": {
      "type": "object",
      "patternProperties": {
        "^.*$": {
          "type": "object",
          "properties": {
            "wind_speed": {
              "type": "number"
            }
          }
        }
      }
    }
  }
}
```

---

## 3. The Environment Data File

The environment data file contains the actual state values utilized by the Rules Engine during evaluation.

* **File Naming Convention:** `pems/{pem_namespace}.json`.
* **Timing and Cadence:** This file must be written as soon as practical after the schema file is established. It must be atomically updated whenever the underlying represented content changes.
* **Content Description:** The file contains the structured JSON environment data. The root of the JSON object maps directly to the identifiers within the namespace, explicitly omitting the PEM's top-level namespace prefix. It must successfully validate against the PEM's published schema file.

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

To standardize data mutation mapping, the transaction file utilizes the **JSON Patch** file format (RFC 6902) to describe the differences applied to the environment state.

* **File Naming Convention:** `tx/req_{tx_id}_{namespace}.json`.
* **Timing:** Written asynchronously by the Rules Engine upon successful completion of a rule evaluation that alters a PEM's state.
* **Content Description:** Contains the unique transaction identifier, the target namespace, and a `patch` array strictly conforming to RFC 6902 detailing the operations (e.g., `add`, `replace`, `remove`) that map the state changes.

**Format Layout (`req_{tx_id}_{namespace}.json`)**

```json
{
  "tx_id": "98765-abcde",
  "namespace": "weather",
  "patch": [
    {
      "op": "replace",
      "path": "/forecast_tags",
      "value": ["Sunny", "Breezy", "Storm_Warning"]
    }
  ]
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

---

## 5. JSON Schema Specifications for IPC Files

The following are the formal JSON Schema representations (Draft 2020-12) for validating the transaction files defined above.

### 5.1 PEM Environment Data File (`{pem_namespace}.json`)

Because this file contains the arbitrary data provided by the PEM, a static engine-wide JSON Schema cannot represent it. This file must be validated dynamically against the specific `{pem_namespace}.schema.json` file published by the PEM itself.

### 5.2 Transaction Request File (`pem_transaction_request.schema.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://codeberg.org/foxprimegames/climatomaton/src/branch/main/docs/schemas/pem_transaction_request.schema.json",
  "title": "Transaction Request File",
  "type": "object",
  "required": ["tx_id", "namespace", "patch"],
  "properties": {
    "tx_id": {
      "type": "string",
      "description": "Unique identifier for the transaction."
    },
    "namespace": {
      "type": "string",
      "description": "The target PEM namespace."
    },
    "patch": {
      "type": "array",
      "description": "An RFC 6902 JSON Patch array.",
      "items": {
        "type": "object",
        "required": ["op", "path"],
        "properties": {
          "op": {
            "type": "string",
            "enum": ["add", "remove", "replace", "move", "copy", "test"]
          },
          "path": {
            "type": "string"
          },
          "value": {}
        }
      }
    }
  }
}
```

### 5.3 Transaction Acknowledgment File (`pem_transaction_ack.schema.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://codeberg.org/foxprimegames/climatomaton/src/branch/main/docs/schemas/pem_transaction_ack.schema.json",
  "title": "Transaction Acknowledgment File",
  "type": "object",
  "required": ["tx_id", "namespace", "status", "timestamp"],
  "properties": {
    "tx_id": {
      "type": "string"
    },
    "namespace": {
      "type": "string"
    },
    "status": {
      "type": "string",
      "enum": ["success", "failure"]
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "UTC timestamp of the acknowledgment."
    }
  }
}
```
