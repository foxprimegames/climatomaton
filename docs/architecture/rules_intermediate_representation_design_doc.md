# Rule Language Design Specification: Climatomaton

## 1. Core Requirements & Logic Constraints

This specification defines the syntax, data types, and execution model for the Climatomaton rule language. The system evaluates an ordered set of **Climate Rules** followed by an ordered set of **Tag Rules**.

### 1.1 JSON-IR Compilation & Validation

Rules are authored in an externally defined source format. The Pluggable Rules Module (PRM) is strictly responsible for the pure syntactic parsing of this source format into a structured **JSON Intermediate Representation (JSON-IR)**. The JSON-IR is the standardized execution data model consumed by the Core Daemon. Because external Pluggable Environment Module (PEM) schemas and internal core schemas are not accessible to the PRM, the Core Daemon handles the symbolic/semantic evaluation and static type-checking pass upon receiving the JSON-IR.

### 1.2 Validation & Re-Evaluation Lifecycle

To prevent validation errors from blocking the processing of infrequent end-of-turn (EOT) reports, the Core Daemon proactively validates the JSON-IR. The Core Daemon immediately executes a comprehensive semantic and static type-checking pass against all known internal and PEM schemas under the following conditions:

1. When the system detects that the active rules file has been updated.
2. When the Core Daemon receives new or updated environment schemas from any registered PEM.
3. When an existing environment schema is deleted or deregistered (e.g., a PEM goes offline and its schema is removed).

#### Rejection Before Execution Runtime & State Fallback

If a ruleset fails this proactive validation pass, it is **rejected before execution runtime**. The exact fallback behavior depends on the trigger of the failure:

* **Ruleset Update Failure:** If the failure is due to a newly pushed, invalid ruleset, the invalid ruleset is completely discarded. The Core Daemon retains its current in-memory, Last-Known-Good (LKG) valid ruleset to ensure continuous, uninterrupted processing of game data. The system logs the exact validation error and emits a `sys.notification` event to alert administrators.
* **Schema Modification/Deletion Failure:** If an environment schema changes or is deleted causing previously-defined environment namespace paths to no longer exist, the existing rules suddenly fail validation. In this case, there is no LKG version. The fallback is to immediately place the system into a **PAUSED** mode. The system halts all EOT report processing and dispatches a high-severity `sys.notification` to administrators detailing the broken dependencies and the paused state.

### 1.3 Execution Conventions

Because the JSON-IR permits general-purpose actions across valid data types, the core execution engine cannot statically enforce that Climate Rules strictly mutate numeric/boolean data or that Tag Rules strictly mutate tag lists. This separation of concerns is a **convention** that must be maintained by rule authors and documented in the language guide.

### 1.4 Strict Failure Policy

If at any point during execution a rule attempts to resolve an undefined namespace path, performs an invalid operation (e.g., a failed type conversion), or encounters any error, **all rule processing is immediately aborted**. The system logs the specific failure, alerts administrators, and discards all pending transactions. No default values are ever assumed.

---

## 2. Type System & Operations

The rule language supports four distinct primitives. All operations, parameters, and return types are strongly typed. To guarantee standardized interpretation across any language or parser, the JSON-IR utilizes standardized short-word keywords for all operators rather than symbols.

**No Implicit Coercion:** To prevent unpredictable behaviors during state evaluation, the language strictly prohibits implicit type coercion. Any attempt to operate across mismatched types without an explicit conversion function will result in a strict failure abort.

Note: For functions, both the function call syntax and the method call syntax are provided below for source-language design flexibility. The JSON-IR format remains identical regardless of the source language syntax chosen.

### 2.1 Number

Represents floating-point or integer numeric values. The specific memory limits and precision of a number are intentionally unspecified by the language and left to the underlying execution engine.

* **Literal Representation:** Standard digits, optional negative sign, optional decimal (e.g., `42`, `-15`, `3.14`).

#### Expression Operators

* **Unary Negation (`NEG`)**: Unary operator that inverts the sign of the numeric expression. Returns a Number.
* **Addition (`ADD`)**: Adds two numeric values. Returns a Number.
* **Subtraction (`SUB`)**: Subtracts the right numeric value from the left. Returns a Number.
* **Multiplication (`MUL`)**: Multiplies two numeric values. Returns a Number.
* **Division (`DIV`)**: Divides the left numeric value by the right. Returns a Number. Triggers a strict failure if the divisor evaluates to `0`.
* **Modulo (`MOD`)**: Returns the remainder of division of the left numeric value by the right. Returns a Number.
* **Exponentiation (`EXP`)**: Raises the left numeric value to the power of the right numeric value. Returns a Number.
* **Equality (`EQ`)**: Evaluates if two numeric values are equal. Returns a Boolean.
* **Inequality (`NEQ`)**: Evaluates if two numeric values are not equal. Returns a Boolean.
* **Less Than (`LT`)**: Evaluates if the left value is strictly less than the right value. Returns a Boolean.
* **Less Than or Equal (`LTE`)**: Evaluates if the left value is less than or equal to the right value. Returns a Boolean.
* **Greater Than (`GT`)**: Evaluates if the left value is strictly greater than the right value. Returns a Boolean.
* **Greater Than or Equal (`GTE`)**: Evaluates if the left value is greater than or equal to the right value. Returns a Boolean.

#### Mutation Operators

* **Assignment (`ASSIGN`)**: Overwrites the target number variable or transaction field with the evaluated numeric expression result.
* **Addition Assignment (`ADD_ASSIGN`)**: Adds the evaluated numeric expression to the current value of the target field.
* **Subtraction Assignment (`SUB_ASSIGN`)**: Subtracts the evaluated numeric expression from the current value of the target field.

#### Functions / Methods

* **`abs(n)`** / **`n.abs()`**: Returns the absolute value of the numeric expression `n`.
* **`round(n, [precision])`** / **`n.round([precision])`**: Rounds `n` to the nearest integer, or to a specified integer `precision` decimal places.
* **`min(n1, n2, ...)`** / **`n1.min(n2, ...)`**: Accepts an arbitrary number of numeric arguments and returns the lowest value.
* **`max(n1, n2, ...)`** / **`n1.max(n2, ...)`**: Accepts an arbitrary number of numeric arguments and returns the highest value.
* **`clamp(n, min_val, max_val)`** / **`n.clamp(min_val, max_val)`**: Constrains `n` so it does not fall below `min_val` or exceed `max_val`. Returns a Number.
* **`within(n, lo, hi, [bounds])`** / **`n.within(lo, hi, [bounds])`**: Evaluates whether `n` falls within the range between `lo` and `hi`. The optional `bounds` parameter accepts a string literal defining inclusivity boundaries:
  * `"[]"` (Default): Inclusive/Inclusive (`lo ≤ n ≤ hi`)
  * `"()"`: Exclusive/Exclusive (`lo < n < hi`)
  * `"[)"`: Inclusive/Exclusive (`lo ≤ n < hi`)
  * `"(]"`: Exclusive/Inclusive (`lo < n ≤ hi`)
  * Returns a Boolean.
* **`to_string(n)`** / **`n.to_string()`**: Converts the numeric value `n` to its literal string representation. Returns a String.

### 2.2 Boolean

Represents true or false logic states.

* **Literal Representation:** `true`, `false`.

#### Expression Operators

* **Logical Conjunction (`AND`)**: Evaluates to `true` if both left and right expressions are true. Guarantees short-circuit evaluation: if the left expression evaluates to `false`, the right expression is not evaluated. Returns a Boolean.
* **Logical Disjunction (`OR`)**: Evaluates to `true` if either the left or right expression is true. Guarantees short-circuit evaluation: if the left expression evaluates to `true`, the right expression is not evaluated. Returns a Boolean.
* **Logical Negation (`NOT`)**: Unary operator that inverts the boolean value of the expression. Returns a Boolean.
* **Equality (`EQ`)**: Evaluates if two boolean states are identical. Returns a Boolean.
* **Inequality (`NEQ`)**: Evaluates if two boolean states are opposite. Returns a Boolean.

#### Mutation Operators

* **Assignment (`ASSIGN`)**: Overwrites the target boolean variable or transaction field with the evaluated boolean expression result.

### 2.3 String

Represents a sequence of characters.

* **Literal Representation:** Text enclosed in double (`"`) or single (`'`) quotes.
  * To include a quote character of the same type inside the string literal itself, it must be escaped using a backslash character (`\`).
  * To include a literal backslash character inside a string literal, it must be escaped using an additional backslash character (`\\`).

#### Expression Operators

* **Concatenation (`CONCAT`)**: Joins two string expressions sequentially together. Returns a String.
* **Equality (`EQ`)**: Evaluates if two strings contain the exact same character sequence. Returns a Boolean.
* **Inequality (`NEQ`)**: Evaluates if two strings differ in character sequence. Returns a Boolean.

#### Mutation Operators

* **Assignment (`ASSIGN`)**: Overwrites the target string variable or transaction field with the evaluated string expression result.

#### Functions / Methods

* **`length(s)`** / **`s.length()`**: Returns the total character count of the string `s`. Returns a Number.
* **`contains(s, substring)`** / **`s.contains(substring)`**: Evaluates whether the exact text sequence `substring` exists within string `s`. Returns a Boolean.
* **`starts_with(s, prefix)`** / **`s.starts_with(prefix)`**: Evaluates whether string `s` begins with the exact text sequence `prefix`. Returns a Boolean.
* **`ends_with(s, suffix)`** / **`s.ends_with(suffix)`**: Evaluates whether string `s` ends with the exact text sequence `suffix`. Returns a Boolean.
* **`to_number(s)`** / **`s.to_number()`**: Parses a string representation of digits into a valid numeric value. Returns a Number. Triggers a strict failure abort if `s` contains characters that cannot form a valid integer or float.

### 2.4 Tag List

Represents a mathematical set of unique string tags, preserving insertion order.

* **Literal Representation:** A comma-separated list of string literals enclosed in square brackets (e.g., `["Mild", "Windy"]`, `[]`).

#### Expression Operators

* **Equality (`EQ`)**: Evaluates if two lists contain the exact same unique tags, regardless of ordering. Returns a Boolean.
* **Inequality (`NEQ`)**: Evaluates if there is any mismatch of unique tags between the two lists. Returns a Boolean.

#### Mutation Operators

* **Assignment (`ASSIGN`)**: Overwrites the target tag list variable or transaction field completely with a new tag list.
* **Set Union (`INCLUDES`)**: Appends elements to the target list if they do not already exist. Accepts a single String expression or a Tag List expression.
* **Set Difference (`EXCLUDES`)**: Removes elements from the target list if they exist. Accepts a single String expression or a Tag List expression.

#### Functions / Methods

* **`length(list)`** / **`list.length()`**: Returns the total count of unique tags currently in `list`. Returns a Number.
* **`has(list, tag)`** / **`list.has(tag)`**: Evaluates whether the single string expression `tag` is present within `list`. Returns a Boolean.
* **`has_any(list, tag_list)`** / **`list.has_any(tag_list)`**: Evaluates whether at least one tag inside the expression `tag_list` is present within `list`. Returns a Boolean.
* **`has_all(list, tag_list)`** / **`list.has_all(tag_list)`**: Evaluates whether every tag inside the expression `tag_list` is present within `list`. Returns a Boolean.
* **`is_empty(list)`** / **`list.is_empty()`**: Evaluates whether the list contains zero elements. Returns a Boolean.

---

## 3. Environments and Static Typing

Rules execute against contextual data sets accessed via a `NamespacePath`. A `NamespacePath` is a generic series of `.`-separated identifiers. The first identifier dictates the environment namespace, and subsequent identifiers traverse the structured data set.

* **`climate.*` (Read-Only):** The historical baseline state prior to rule execution.
* **`proposals.*` (Read-Only):** Summary of EOT data.
* **`{pem_namespace}.*` (Read-Only):** Externally provided data modules.
* **`new.*` (Mutable):** The transaction environment initialized from explicitly registered mutable fields.
* **`var.*` (Mutable):** A flat set of ephemeral variables that persist only for the duration of a single rule execution cycle.

### 3.1 The Variable Environment (`var.`) & Strong Typing

To satisfy the requirement that variables are not predefined while guaranteeing static type-checking during the Core Daemon's validation pass, the `var.` namespace utilizes **Type Partitioning via Prefixes**. The identifier path explicitly dictates the data type, restricting the wildcard (`*`) to exactly one level of identifier:

* **`var.n.*` (Numbers):** Auto-initializes to `0` (e.g., `var.n.counter`, but not `var.n.player.counter`).
* **`var.b.*` (Booleans):** Auto-initializes to `false` (e.g., `var.b.is_active`).
* **`var.s.*` (Strings):** Auto-initializes to `""` (empty string).
* **`var.l.*` (Tag Lists):** Auto-initializes to `[]` (empty list).

### 3.2 PEM Schemas & Environment Typing

The type checking and semantic validation of rules involving PEM namespace paths are executed in strict accordance with the PEM's published schema, as defined by the Pluggable Environment Module (PEM) Design Document.

---

## 4. Rule Structure and Evaluation

A rule is defined by its name, a tracking source string, a set of conditions, and a set of actions.

### 4.1 Conditions

Conditions are boolean expressions. A rule activates only if all condition statements evaluate to `true`.

### 4.2 Actions

Actions mutate data in either the `new.*` or `var.*` namespaces. An action consists of a target path, a mutation operator, and an expression.

---

## 5. JSON Intermediate Representation (JSON-IR)

To decouple the PRM's source-language parser from the Core Daemon's execution engine, rules are communicated via a strict **JSON-IR**. Every structural node within this payload explicitly declares its type identity via a uniform `"kind"` property. The JSON-IR imposes no artificial Abstract Syntax Tree (AST) depth limit; execution engines must handle arbitrarily nested structures.

### 5.1 Root Document Structure

```json
{
  "kind": "ruleset", // Always "ruleset" to identify the root document node
  "id": "ruleset_v1_0_0", // A unique tracking identifier for the specific version of the ruleset
  "climate_rules": [ // Ordered array of rule objects executed first
    {
      /* Rule Object */
    }
  ],
  "tag_rules": [ // Ordered array of rule objects executed second
    {
      /* Rule Object */
    }
  ]
}
```

### 5.2 Rule Object

```json
{
  "kind": "rule", // Always "rule" to identify this structural node
  "name": "Extreme Heat Modifier", // A human-readable name for the rule (does not need to be unique)
  "source": "prm://repository/rules/climate.yml:line_42", // A PRM-generated tracking string to identify rule origin
  "conditions": [ // An array of expression nodes evaluating to a boolean (implicitly ANDed)
    {
      /* Expression Node */
    }
  ],
  "actions": [ // An array of mutation nodes to apply if all conditions are met
    {
      /* Mutation Node */
    }
  ]
}
```

### 5.3 Expression Nodes

Every expression node must declare a `"kind"` to identify its structural type.

* **Literal Node:** Represents a hardcoded primitive value.

```json
{
  "kind": "literal", // Always "literal" to identify this node structure
  "datatype": "number", // The primitive type: "number", "boolean", "string", or "tag_list"
  "value": 15 // The actual primitive value matching the declared datatype
}
```

* **Reference Node:** Represents a dynamic lookup in an environment namespace.

```json
{
  "kind": "reference", // Always "reference" to identify this node structure
  "path": "climate.value" // A string representing the generic NamespacePath
}
```

* **Operator Node:** Represents an evaluation using defined operators.

```json
{
  "kind": "operator", // Always "operator" to identify this node structure
  "op": "EXP", // The string code for the operator
  "left": { // Optional expression node representing the left-hand side (omitted for unary operators like NOT or NEG)
    "kind": "reference",
    "path": "var.n.base_multiplier"
  },
  "right": { // Required expression node representing the right-hand side (or sole operand for unary operators)
    "kind": "literal",
    "datatype": "number",
    "value": 2
  }
}
```

* **Function Node:** Represents a method or function call.

```json
{
  "kind": "function", // Always "function" to identify this node structure
  "name": "within", // An identifier containing the exact source name of the function
  "args": [ // An array of expression nodes representing the ordered arguments
    {
      "kind": "reference",
      "path": "climate.value"
    },
    {
      "kind": "literal",
      "datatype": "number",
      "value": 10
    },
    {
      "kind": "literal",
      "datatype": "number",
      "value": 20
    },
    {
      "kind": "literal",
      "datatype": "string",
      "value": "[)"
    }
  ]
}
```

### 5.4 Mutation Nodes (Actions)

Mutations dictate state changes inside the `actions` array of a Rule Object.

```json
{
  "kind": "mutation", // Always "mutation" to identify this node structure
  "target": "new.climate.value", // A NamespacePath representing the target field to mutate
  "op": "ADD_ASSIGN", // The string code for the mutation operation
  "expression": { // An expression node evaluating to the modifier or new value
    "kind": "literal",
    "datatype": "number",
    "value": 5
  }
}
```

### 5.5 JSON Schema (Draft 2020-12)

This formally defines the validation constraints for the JSON-IR payload sent from the PRM to the Core Daemon.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://climatomaton.nomicron.org/schemas/json-ir.json",
  "title": "Climatomaton JSON-IR",
  "description": "JSON Intermediate Representation for Climatomaton Rules",
  "type": "object",
  "properties": {
    "kind": { "const": "ruleset" },
    "id": { "type": "string" },
    "climate_rules": {
      "type": "array",
      "items": { "$ref": "#/$defs/rule" }
    },
    "tag_rules": {
      "type": "array",
      "items": { "$ref": "#/$defs/rule" }
    }
  },
  "required": ["kind", "id", "climate_rules", "tag_rules"],
  "additionalProperties": false,
  "$defs": {
    "identifier": {
      "type": "string",
      "pattern": "^[a-zA-Z_][a-zA-Z0-9_]*$"
    },
    "namespacePath": {
      "type": "string",
      "pattern": "^[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)*$"
    },
    "rule": {
      "type": "object",
      "properties": {
        "kind": { "const": "rule" },
        "name": { "type": "string" },
        "source": { "type": "string" },
        "conditions": {
          "type": "array",
          "items": { "$ref": "#/$defs/expression" }
        },
        "actions": {
          "type": "array",
          "items": { "$ref": "#/$defs/mutation" }
        }
      },
      "required": ["kind", "name", "source", "conditions", "actions"],
      "additionalProperties": false
    },
    "expression": {
      "type": "object",
      "oneOf": [
        { "$ref": "#/$defs/literal_node" },
        { "$ref": "#/$defs/reference_node" },
        { "$ref": "#/$defs/operator_node" },
        { "$ref": "#/$defs/function_node" }
      ]
    },
    "literal_node": {
      "type": "object",
      "properties": {
        "kind": { "const": "literal" },
        "datatype": { "enum": ["number", "boolean", "string", "tag_list"] },
        "value": {}
      },
      "required": ["kind", "datatype", "value"],
      "additionalProperties": false
    },
    "reference_node": {
      "type": "object",
      "properties": {
        "kind": { "const": "reference" },
        "path": { "$ref": "#/$defs/namespacePath" }
      },
      "required": ["kind", "path"],
      "additionalProperties": false
    },
    "operator_node": {
      "type": "object",
      "properties": {
        "kind": { "const": "operator" },
        "op": {
          "enum": ["ADD", "SUB", "MUL", "DIV", "MOD", "EXP", "EQ", "NEQ", "LT", "LTE", "GT", "GTE", "AND", "OR", "NOT", "NEG", "CONCAT"]
        },
        "left": { "$ref": "#/$defs/expression" },
        "right": { "$ref": "#/$defs/expression" }
      },
      "required": ["kind", "op", "right"],
      "additionalProperties": false
    },
    "function_node": {
      "type": "object",
      "properties": {
        "kind": { "const": "function" },
        "name": { "$ref": "#/$defs/identifier" },
        "args": {
          "type": "array",
          "items": { "$ref": "#/$defs/expression" }
        }
      },
      "required": ["kind", "name", "args"],
      "additionalProperties": false
    },
    "mutation": {
      "type": "object",
      "properties": {
        "kind": { "const": "mutation" },
        "target": { "$ref": "#/$defs/namespacePath" },
        "op": {
          "enum": ["ASSIGN", "ADD_ASSIGN", "SUB_ASSIGN", "INCLUDES", "EXCLUDES"]
        },
        "expression": { "$ref": "#/$defs/expression" }
      },
      "required": ["kind", "target", "op", "expression"],
      "additionalProperties": false
    }
  }
}
```

---

### Discussion Points & Comments

* **Schema Integration**: The root-level string field `id` has been successfully integrated into both the structural example snippet (Section 5.1) and the master JSON Schema validation block (Section 5.5). It is now flagged as a strict requirement alongside `kind`, `climate_rules`, and `tag_rules`.
* **String Constraint Pattern**: Currently, the `id` property in the schema is a generic string. If the parsing library or core daemon relies on a specific identifier pattern (such as UUIDv4, SHA-256 hashes, or strict Semantic Versioning format), we can introduce a `"pattern"` regex constraint to enforce this format cleanly at the JSON schema layer in a subsequent pass.

---

### Remaining Pending Updates for Other Documents

#### 1. Shared Volume Design Document (New Document)

* **Atomic Write Protocol:** Formally define the system-wide atomic write protocol here. Specify that all files written to the shared volume must first be written to a temporary file, followed by a system rename operation. Grant processes explicit permission to arbitrarily remove any existing temporary files they strictly own before overwriting them.
* **Volume Topology:** Detail the directory structure of the shared volume (e.g., `prm/`, `tx/`, `logs/`, `notifications/`).
* **Decentralized Schemas:** State that this document outlines the mechanical rules of engagement, but the specific JSON schemas for the payloads remain owned by the component design documents generating them.

#### 2. Deployment Architecture Document

* **Shared Volume Requirements:** Specify that the deployed shared volume used to accommodate the IPC mechanisms must support the underlying file system operations required by the atomic write protocol.
* **PRM Configuration Definitions:** Include required environment variables for the Git-Fetch PRM container (`GIT_REPO_URL`, `GIT_BRANCH`, `GIT_TARGET_DIR`, `POLL_INTERVAL`, `SYNC_FAILURE_THRESHOLD`).

#### 3. Observability, Health Checking, and Logging Design Document (New Document)

* **Centralization:** Standardize observability. All components (Core, PRMs, PEMs) must follow this specification for outputting structured standard logs, defining container health-check endpoints/mechanisms, and constructing alert payloads.

#### 4. IPC Broker Design Document

* **Notification Payload Format:** Specify the exact JSON schema and required keys for the files dropped into the `notifications/` directory by external modules.
* **Heartbeat Monitoring (PEMs):** Implement a "fast publish, lenient subscribe" model for tracking PEM heartbeats. While PEMs update their schema file timestamps every 30 seconds, the IPC Broker checks every 60 seconds. A PEM missing two consecutive checks (120 seconds) is considered dead, prompting the Broker to purge its stale files.
* **Heartbeat Monitoring (PRMs):** Implement monitoring for the PRM liveness. The PRM will update the modified timestamp of `prm/active_rules.json` on a regular interval. The IPC Broker must detect this timestamp change. Upon detection, it must read the file and check the root `id` field. If the `id` matches the current active ruleset, the Broker merely updates the PRM's last-seen timestamp. If the PRM misses two consecutive heartbeat intervals, the IPC Broker must emit a system event to drop the Core Engine into a PAUSED state.
* **Ruleset Update Event:** Specify that the `ipc.rules_updated` event is only fired if the parsed `id` from the `prm/active_rules.json` file differs from the currently loaded ruleset.

#### 5. Central Architecture Document

* **Cleanup:** Remove the atomic write procedure specifics from this document, delegating them entirely to the new Shared Volume Design Document.

#### 6. Rules Engine Design Document

* **Dynamic Type Registry Initialization & Type Mapping:** The engine must construct a master `TypeMap` at runtime by scanning the IPC volume for loaded PEM schemas. Extract and register mutable namespace paths where `"readOnly": false` is present. Strictly map JSON schema `array` types to internal tag lists, requiring the `items` definition to be `"type": "string"`.
* **Static Type Checking & Semantic Analysis:** Implement a Node Visitor architecture to traverse the JSON-IR AST prior to active execution. Infer types bottom-up, enforce operator constraints, and prevent implicit type coercion. Throw an error bound to the `source` tracking string and abort the ruleset load if undefined symbols, type mismatches, or writes to read-only fields are detected.
* **Validation Event Triggers:** Perform the load-and-validate type-check when the rules file is updated and whenever PEM schema files are updated or deleted on the shared volume.

#### 7. DGL (Discord Gateway Listener) & DAC (Discord API Client) Design Documents

* **Discord Integration Specifics:** Define exact Discord intents/permissions (DGL) and OAuth2 scopes (DAC).
* **Rate Limiting:** The DAC design document must incorporate the specific logic for overall and per-source notification rate limiting.

#### 8. Parser Library & CLI Tooling Design Document (New Document)

* **Library Specifications:** Detail the architecture of the shared Python parsing library that translates plain-English Clime files into JSON-IR.
* **I/O Decoupling Requirement:** Explicitly specify that the library must perform no file operations. The functions for Lexing, Parsing, and Emitting must be designed to accept either static objects (strings, lists of strings, or populated AST objects) or iterators yielding the appropriate content, returning the resulting token stream, AST, or JSON-IR respectively.
* **Error Accumulation Strategy:** The parser must implement an error recovery strategy. Instead of fast-failing via exceptions, it should accumulate syntax errors and return a structured Result object (e.g., `success`, `errors`, `ast`), allowing callers to process multiple errors simultaneously.
* **CLI Tooling:** Define the behavior of the standalone syntax checker CLI, detailing input arguments, exit codes for CI/CD integration, file-loading wrappers, and verbose error formatting for local debugging.

#### 9. Codebase & Repository Architecture Document (New Document)

* **Build System Discussion (`uv` vs `hatch`):** While `hatch` is an officially endorsed PyPA project and fantastic for generic package building, `uv` (built by Astral) is recommended for this specific multi-component project. `uv` acts as an ultra-fast, drop-in replacement for `pip`, `venv`, and `pip-tools` written in Rust. Crucially, `uv` recently introduced Cargo-style "workspace" support. This allows us to define the Parser Library, the PRM, and the Core Engine as separate packages within the same repository, seamlessly linking them together locally without needing to publish the internal library to a PyPI index or wrangle complex local file references in standard `pyproject.toml` configurations.
* **Monorepo Organization:** The document must define a unified workspace layout. A standard approach would separate concerns clearly, for example:
  * `libs/clime-parser`: The shared parsing library.
  * `apps/core-daemon`: The main Climatomaton Discord engine.
  * `apps/git-prm`: The standalone Git-Fetch container process.
  * `tools/clime-cli`: The standalone syntax checker utility.

#### 10. Future Improvements Document (New Document)

* **Signal Handling:** Establish a standardized approach for using Unix signals (e.g., `SIGHUP`) across all Climatomaton container processes to trigger out-of-band operations without requiring container restarts. Examples include forcing an immediate repository poll in the Git-Fetch PRM, triggering an immediate state cache dump in the Core Engine, or forcing an out-of-cycle schema re-broadcast in PEMs.
