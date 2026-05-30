# Pluggable Environment Module (PEM) Design Document

## 1. System Overview

A Pluggable Environment Module (PEM) is an independent, stateless process responsible for managing an externally-defined environment data set. Its primary function is to make a specific data namespace available to the Climatomaton core system, allowing climate and tag rules to evaluate and potentially mutate this data during end-of-turn (EOT) processing.

PEMs are entirely decoupled from the core daemon and communicate strictly via file-based Interprocess Communication (IPC) utilizing a shared directory volume. To ensure data integrity, all file writes must be performed atomically. A PEM must write its data to a temporary file (e.g., `.tmp`) and then execute a system rename operation to place the file in its final path. All timestamping must utilize the UTC timezone.

---

## 2. The Schema File

The schema file dictates the structure, data types, and mutability of the environment data the PEM provides. It is authored as a standard JSON Schema document adhering strictly to Draft 2020-12.

* **File Naming Convention:** `pems/{pem_namespace}.schema.json`.
* **Timing and Cadence:** The file must be written as soon as the PEM starts up. To serve as a heartbeat indicating the PEM is alive, this file must be atomically updated (e.g., touching the file to update its modified timestamp or rewriting it) at a system-wide defined interval of **no greater than 30 seconds**.
* **Heartbeat Monitoring & Cleanup:** The Core Daemon actively monitors this heartbeat using a more lenient validation interval to prevent unnecessary churn during brief disk I/O latency. The Core Daemon checks the timestamp every 60 seconds. A PEM is only considered dead or removed if it fails two consecutive checks (meaning the file has not been touched in over 120 seconds). If this occurs, the Core Daemon automatically purges the stale schema and data files from the volume.
* **Content Description:** The schema uses standard JSON Schema validation keywords (`properties`, `type`, `items`, `patternProperties`) to define the allowed namespace paths and primitive types.
* **Mutability (The `readOnly` Constraint):** For the purposes of the Climatomaton engine, the default state of any property within a PEM schema is assumed to be read-only (`"readOnly": true`). If a PEM intends to allow the Rules Engine to mutate a specific field via tag or climate rules, it must explicitly include `"readOnly": false` on that property definition in the schema.

**Format Layout (`{pem_namespace}.schema.json`)**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://codeberg.org/foxprimegames/climatomaton/src/branch/main/docs/schemas/weather.schema.json",
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

### 5.2 Transaction Request File (`req_{tx_id}_{namespace}.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://codeberg.org/foxprimegames/climatomaton/src/branch/main/docs/schemas/transaction_request.schema.json",
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

### 5.3 Transaction Acknowledgment File (`ack_{tx_id}_{namespace}.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://codeberg.org/foxprimegames/climatomaton/src/branch/main/docs/schemas/transaction_ack.schema.json",
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

---

### Discussion Points, Questions & Comments

1. **Python Library Recommendation:** For the Python 3 core engine, the officially recommended library is `jsonschema` (available via PyPI). Version 4.18.0 and above provide full support for Draft 2020-12 validation.
* *Validation:* You would parse the JSON and use `jsonschema.validate(instance=data, schema=schema)`.
* *Extracting `readOnly`:* Standard JSON Schema validation only checks data structures, not annotations (meaning a standard validator will not automatically fail if you write to a field marked `"readOnly": true`). Therefore, during the Rules Engine startup/initialization phase, you will write a quick recursive dictionary traversal function in Python that walks the loaded `schema.json` dictionary to find and catalog any paths where the `"readOnly": false` key is present. This catalog will be passed to the Type Registry to build the mutable fields list.


2. **Heartbeat & Cleanup Cadence:** Your logic is sound. I have updated Section 2 to implement the "fast publish, lenient subscribe" model. The PEM is required to update its timestamp every 30 seconds, but the Core Engine only checks every 60 seconds and allows for two consecutive misses. This drastically reduces the likelihood of race conditions or minor volume latency causing an accidental teardown, while still isolating dead PEMs well before the weekly EOT report processing.
3. **Python Library for PEM Modules:** I completely agree with your instinct here. I have deliberately kept any mention of a "helper library" out of the design document. The architecture strictly demands decoupled, language-agnostic integration via JSON and shared volumes. Keeping the document language-agnostic ensures that developers using Go, Rust, or Node.js to write a PEM in the future understand the exact baseline requirements without being sidetracked by Python-specific tooling.

---

### Pending Updates for Other Documents

#### Rules Engine Design Document

1. **Dynamic Type Registry Initialization:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. Because the system now utilizes standard JSON Schema (Draft 2020-12), the engine must incorporate a compliant JSON Schema library (e.g., `jsonschema`) to load these files. The initialization phase must recursively traverse the parsed schema dict to extract and register mutable namespace paths strictly where the `"readOnly": false` attribute is present. Wildcards will be resolved via the schema's `patternProperties`.
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints (e.g., preventing a `MOD` operation on a string), and guaranteeing no implicit type coercion takes place. If an undefined symbol, a type mismatch, or a write operation to a `readOnly: true` (default) field is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.

#### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
