### Pending Updates for Other Documents

#### IPC Broker Design Document

1. **Heartbeat Monitoring & Cleanup:** The IPC Broker must implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs are required to update their schema file timestamps every 30 seconds, the IPC Broker should check these timestamps every 60 seconds. A PEM is only considered offline if it misses two consecutive checks (i.e., the file has not been touched in over 120 seconds). Upon detecting a dead PEM, the IPC Broker must automatically purge the stale schema and data files from the shared volume.

#### Rules Engine Design Document

1. **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for all loaded PEM schemas (`*.schema.json`) alongside internal schemas. Because the system utilizes standard JSON Schema (Draft 2020-12), the engine must incorporate a compliant JSON Schema library (e.g., `jsonschema`) to load these files. During initialization, the engine must traverse the parsed schema dictionaries to accomplish two tasks:
  * **Mutability Registration:** Dynamically extract and register mutable namespace paths strictly where the `"readOnly": false` attribute is present. This extraction logic must be robust enough to recurse through and resolve complex JSON schema definitions, including `patternProperties`, `anyOf`, `allOf`, `oneOf`, and any other nested or variable sub-schemas.
  * **Data Type Mapping:** Map the properties and standard data types (e.g., `number`, `string`, `boolean`) found in the JSON schema to the specific internal data types defined in the rules language. Crucially, the engine's internal language lacks a generic array type and only supports a "tag list" (an array of strings). Therefore, when mapping an `array` type from a JSON schema, the engine must strictly verify that its `items` definition explicitly specifies `"type": "string"`. Any other array configuration (e.g., arrays of numbers, objects, or unbounded arrays) must be rejected as invalid schema definitions.
2. **Static Type Checking & Semantic Analysis:** The engine must implement a proactive compiler frontend pattern (a Node Visitor architecture) that traverses the JSON-IR AST prior to active execution. This visitor is responsible for inferring types bottom-up, enforcing operator and function constraints (e.g., preventing a `MOD` operation on a string), and guaranteeing no implicit type coercion takes place. If an undefined symbol, a type mismatch (based on the type mapping described above), or a write operation to a `readOnly: true` (default) field is found, it must throw an error bound to the `source` tracking string and abort the ruleset load.

#### DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

1. **Discord Integration specifics:** Must define exact Discord intents and permissions (for the DGL) and specific OAuth2 scopes (for the DAC). Additionally, the DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.
