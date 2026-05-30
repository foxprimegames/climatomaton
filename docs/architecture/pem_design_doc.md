# Pluggable Environment Module (PEM) Design Document

## 1. System Overview

A Pluggable Environment Module (PEM) is an independent, stateless process responsible for managing an externally-defined environment data set. Its primary function is to make a specific data namespace available to the Climatomaton core system, allowing climate and tag rules to evaluate and potentially mutate this data during end-of-turn (EOT) processing.

PEMs are entirely decoupled from the core daemon and communicate strictly via file-based Interprocess Communication (IPC) utilizing a shared directory volume. To ensure data integrity, all file writes must be performed atomically. A PEM must write its data to a temporary file (e.g., `.tmp`) and then execute a system rename operation to place the file in its final path. All timestamping must utilize the UTC timezone.

---

## 2. The Schema File

The schema file dictates the structure, data types, and mutability of the environment data the PEM provides.

**IMPORTANT NOTE:** The file layout represented in this section is a custom mapping format specific to Climatomaton's internal engine. It is **NOT** a standard "JSON Schema" (i.e., it does not conform to the IETF JSON Schema specification), though it uses JSON syntax to declare types and mutability.

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

The following are the formal JSON Schema representations for validating the system files defined above.

### 5.1 PEM Custom Schema File (`{pem_namespace}.schema.json`)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "PEM Custom Mapping Schema",
  "type": "object",
  "required": ["namespace", "heartbeat_interval_seconds", "paths"],
  "properties": {
    "namespace": {
      "type": "string",
      "description": "The top-level prefix for this module."
    },
    "heartbeat_interval_seconds": {
      "type": "integer",
      "minimum": 1
    },
    "paths": {
      "type": "object",
      "patternProperties": {
        "^.*$": {
          "type": "object",
          "required": ["type", "mutable"],
          "properties": {
            "type": {
              "type": "string",
              "enum": ["number", "string", "boolean", "tag_list"]
            },
            "mutable": {
              "type": "boolean"
            }
          }
        }
      }
    }
  }
}
```

### 5.2 PEM Environment Data File (`{pem_namespace}.json`)

*Note: Because this file contains the arbitrary data provided by the PEM, a single rigid JSON Schema cannot represent it. A meta-schema would simply define it as a generic JSON object. If a standard JSON Schema is adopted in the future (see discussion below), this file would be validated against the PEM's published JSON Schema.*

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "PEM Environment Data File",
  "type": "object",
  "description": "The dynamic data object containing the PEM's environment variables. Its specific structure is dictated by the associated schema file."
}
```

### 5.3 Transaction Request File (`req_{tx_id}_{namespace}.json`)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
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

### 5.4 Transaction Acknowledgment File (`ack_{tx_id}_{namespace}.json`)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
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

### Discussion Points & Investigation

1. **Investigating standard JSON Schema for the PEM Schema File:** It is entirely feasible to replace the custom `"paths"` mapping object with a fully standard JSON Schema definition.
* **How it would work:** The PEM would publish a file that adheres to standard JSON Schema drafts. Instead of the custom object, it would declare its fields using standard `properties`, `type`, and `items` keywords. To handle the `mutable` requirement, we could introduce a custom vocabulary keyword (e.g., `x-climatomaton-mutable: true`) that the Rules Engine reads when parsing the schema.
* **Benefits:** This would allow the core daemon to leverage highly robust, off-the-shelf JSON Schema validation libraries to guarantee the integrity of the Environment Data File before passing it to the rules engine. It natively handles wildcards via `patternProperties` and `additionalProperties` without requiring custom parser logic.
* **Consideration:** We should discuss whether it is worth shifting the design to fully embrace standard JSON Schema with custom annotations, as it would significantly reduce the maintenance burden of a custom type registry.



### Pending Updates for Other Documents

#### Rules Engine Design Document

1. **Dynamic Type Registry Initialization:** The engine must be designed to construct a master `TypeMap` at runtime by scanning and flattening the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. Parsing and translation logic will depend on the PEM Design Document's specifications for translating path patterns and wildcards into resolving regex patterns within the registry. (Note: If standard JSON Schema is adopted, this requirement shifts to loading and compiling JSON Schemas).
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints (e.g., preventing a `MOD` operation on a string), and guaranteeing no implicit type coercion takes place. If an undefined symbol or type mismatch is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.

#### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
