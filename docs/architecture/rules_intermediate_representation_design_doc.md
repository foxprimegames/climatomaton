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

If at any point during execution a rule attempts to resolve an undefined namespace path, performs an invalid operation (e.g., a failed type conversion), or encounters any other execution error, **all rule processing is immediately aborted**. The system logs the specific failure, alerts administrators, and discards all pending transactions. No default values are ever assumed.

---

## 2. Type System & Operations

The rule language supports four distinct primitives. All operations, parameters, and return types are strongly typed. To guarantee standardized interpretation across any language or parser, the JSON-IR utilizes standardized short-word keywords for all operators rather than symbols.

Note: For functions, both the function call syntax and the method call syntax are provided below for source-language design flexibility. The JSON-IR format remains identical regardless of the source language syntax chosen.

### 2.1 Number

Represents floating-point or integer numeric values.

* **Literal Representation:** Standard digits, optional negative sign, optional decimal (e.g., `42`, `-15`, `3.14`).

#### Expression Operators

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
  * `"[]"` (Default): Inclusive/Inclusive ($lo \le n \le hi$)
  * `"()"`: Exclusive/Exclusive ($lo < n < hi$)
  * `"[)"`: Inclusive/Exclusive ($lo \le n < hi$)
  * `"(]"`: Exclusive/Inclusive ($lo < n \le hi$)
  * Returns a Boolean.
* **`to_string(n)`** / **`n.to_string()`**: Converts the numeric value `n` to its literal string representation. Returns a String.

### 2.2 Boolean

Represents true or false logic states.

* **Literal Representation:** `true`, `false`.

#### Expression Operators

* **Logical Conjunction (`AND`)**: Evaluates to `true` if both left and right expressions are true. Returns a Boolean.
* **Logical Disjunction (`OR`)**: Evaluates to `true` if either the left or right expression is true. Returns a Boolean.
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

To satisfy the requirement that variables are not predefined while guaranteeing static type-checking during the Core Daemon's validation pass, the `var.` namespace utilizes **Type Partitioning via Prefixes**. The identifier path explicitly dictates the data type:

* **`var.n.*` (Numbers):** Auto-initializes to `0`.
* **`var.b.*` (Booleans):** Auto-initializes to `false`.
* **`var.s.*` (Strings):** Auto-initializes to `""` (empty string).
* **`var.l.*` (Tag Lists):** Auto-initializes to `[]` (empty list).

### 3.2 PEM Schemas & Environment Typing

Because the Core Engine performs the semantic and type validation of rules, it must understand the data types present in external namespaces. Every PEM must provide a corresponding static schema file (e.g., `{pem_namespace}.schema.json`) mapping its namespace paths to their primitive types.

To prevent schemas from becoming excessively verbose for highly nested data, the schema definitions support wildcard pattern mapping. For example, a PEM schema might declare `weather.regions.*.temp` as a `Number`, which informs the Core Engine that any identifier matching that generic path pattern during rule evaluation is strongly typed as a Number.

---

## 4. Rule Structure and Evaluation

A rule is defined by its name, a set of conditions, and a set of actions.

### 4.1 Conditions

Conditions are boolean expressions. A rule activates only if all condition statements evaluate to `true`.

### 4.2 Actions

Actions mutate data in either the `new.*` or `var.*` namespaces. An action consists of a target path, a mutation operator, and an expression.

---

## 5. JSON Intermediate Representation (JSON-IR)

To decouple the PRM's source-language parser from the Core Daemon's execution engine, rules are communicated via a strict **JSON-IR**.

### 5.1 Root Document Structure

```json
{
  "climate_rules": [ ... ],
  "tag_rules": [ ... ]
}
```

### 5.2 Rule Object

```json
{
  "name": "Extreme Heat Modifier",
  "conditions": [ { /* Expression Node */ } ],
  "actions": [ { /* Mutation Node */ } ]
}
```

### 5.3 Expression Nodes

* **Literal Node:**

```json
{ "type": "literal", "datatype": "number", "value": 15 }
```

* **Reference Node:**

```json
{ "type": "reference", "path": "climate.value" }
```

* **Operator Node:**

```json
{
  "type": "operator",
  "op": "EXP",
  "left": { "type": "reference", "path": "var.n.base_multiplier" },
  "right": { "type": "literal", "datatype": "number", "value": 2 }
}
```

* **Function Node:** Represents a method call. Requires a `"name"` string and an `"args"` array of expression nodes. *(See 5.5 for signature resolution)*.

```json
{
  "type": "function",
  "name": "within:nnns",
  "args": [
    { "type": "reference", "path": "climate.value" },
    { "type": "literal", "datatype": "number", "value": 10 },
    { "type": "literal", "datatype": "number", "value": 20 },
    { "type": "literal", "datatype": "string", "value": "[)" }
  ]
}
```

### 5.4 Mutation Nodes (Actions)

```json
{
  "target": "new.climate.value",
  "op": "ADD_ASSIGN",
  "expression": {
    "type": "literal",
    "datatype": "number",
    "value": 5
  }
}
```

### 5.5 Function Signature Resolution (Name Mangling)

Because the rule language permits functions with the same name but different argument counts or types (function overloading), the JSON-IR requires the PRM parser to programmatically generate a unique name for the function node's `"name"` attribute.

This is accomplished by appending the data types of the provided arguments directly to the function name, separated by a colon (`:`). The data types are abbreviated to single characters mirroring the `var` namespace prefixes:

* `n` = Number
* `b` = Boolean
* `s` = String
* `l` = Tag List

The Core Engine registers and validates these specific, mangled signatures. For example, if a rule calls `within` with three numbers, the PRM parses the name as `within:nnn`. If it includes the optional bounds string, the PRM parses it as `within:nnns`. This guarantees explicit, unambiguous static type-checking within the Core Daemon.

### 5.6 JSON Schema (Draft 2020-12)

This formally defines the validation constraints for the JSON-IR payload sent from the PRM to the Core Daemon.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://climatomaton.nomicron.org/schemas/json-ir.json",
  "title": "Climatomaton JSON-IR",
  "description": "JSON Intermediate Representation for Climatomaton Rules",
  "type": "object",
  "properties": {
    "climate_rules": {
      "type": "array",
      "items": { "$ref": "#/$defs/rule" }
    },
    "tag_rules": {
      "type": "array",
      "items": { "$ref": "#/$defs/rule" }
    }
  },
  "required": ["climate_rules", "tag_rules"],
  "additionalProperties": false,
  "$defs": {
    "rule": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "conditions": {
          "type": "array",
          "items": { "$ref": "#/$defs/expression" }
        },
        "actions": {
          "type": "array",
          "items": { "$ref": "#/$defs/mutation" }
        }
      },
      "required": ["name", "conditions", "actions"],
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
        "type": { "const": "literal" },
        "datatype": { "enum": ["number", "boolean", "string", "tag_list"] },
        "value": {}
      },
      "required": ["type", "datatype", "value"],
      "additionalProperties": false
    },
    "reference_node": {
      "type": "object",
      "properties": {
        "type": { "const": "reference" },
        "path": { "type": "string" }
      },
      "required": ["type", "path"],
      "additionalProperties": false
    },
    "operator_node": {
      "type": "object",
      "properties": {
        "type": { "const": "operator" },
        "op": { 
          "enum": ["ADD", "SUB", "MUL", "DIV", "MOD", "EXP", "EQ", "NEQ", "LT", "LTE", "GT", "GTE", "AND", "OR", "NOT", "CONCAT"] 
        },
        "left": { "$ref": "#/$defs/expression" },
        "right": { "$ref": "#/$defs/expression" }
      },
      "required": ["type", "op", "left"],
      "additionalProperties": false
    },
    "function_node": {
      "type": "object",
      "properties": {
        "type": { "const": "function" },
        "name": { 
          "type": "string",
          "pattern": "^[a-zA-Z_][a-zA-Z0-9_]*:[nbsl]+$" 
        },
        "args": {
          "type": "array",
          "items": { "$ref": "#/$defs/expression" }
        }
      },
      "required": ["type", "name", "args"],
      "additionalProperties": false
    },
    "mutation": {
      "type": "object",
      "properties": {
        "target": { "type": "string" },
        "op": {
          "enum": ["ASSIGN", "ADD_ASSIGN", "SUB_ASSIGN", "INCLUDES", "EXCLUDES"]
        },
        "expression": { "$ref": "#/$defs/expression" }
      },
      "required": ["target", "op", "expression"],
      "additionalProperties": false
    }
  }
}
```

---

---

### Discussion & Notes

* **Markdown Formatting Fix:** The bolding asterisks in the Functions/Methods lists have been isolated completely outside the backticks representing the inline code (e.g., **`abs(n)`**). This ensures that standard Markdown parsers will consistently render the bolding without injecting artifacts into the code spans.
* **Signature Resolution (Mangling):** Using single characters matches the existing environment prefix taxonomy and keeps the JSON-IR compact. Applying the colon (`:`) creates a clean barrier between the human-readable function name and the compiler-generated signature since a colon is not a valid identifier character in standard programming paradigms. I added a regex pattern `^[a-zA-Z_][a-zA-Z0-9_]*:[nbsl]+$` into the formal JSON schema to enforce this exact shape.
* **JSON Schema 2020-12 Implementation:** The schema strictly defines the shape of the AST and utilizes `$defs` for compositional reuse. `additionalProperties: false` ensures that PRMs cannot sneak arbitrary or non-standard fields into the IR, which protects the Core Engine from encountering malformed instructions. Note that the schema strictly requires the `left` side for an operator, but leaves `right` optional to account for unary operators like `NOT`.

### Consolidated List of Pending Architecture Document Updates

The following items represent design changes established during the rule language specification sequence that require formal updates to the main **Climatomaton Architecture Specification**:

1. **Core Daemon Immediate Validation Pass:** Update Section 4.1 to specify that the Core Daemon must actively monitor the rules folder and the schemas folder. It must proactively parse and type-check incoming JSON-IR files immediately upon modification of the rules file, or whenever a PEM schema is added, updated, or deleted.
2. **Validation Error Recovery Policy:** Update the architecture to reflect the exact fallback strategies:
   * **LKG Fallback:** If a newly watched JSON-IR file fails semantic/static verification, the Core Daemon discards it, retains the prior working version, logs the trace, and issues an admin alert.
   * **PAUSED Fallback:** If an environment change (like a PEM deletion) renders the active rules invalid, there is no "last-known-good" ruleset to fall back to. The Core Daemon must immediately drop into a **PAUSED** state, halt EOT reporting, and notify the administrators.
3. **PEM Schema Exchange & Registration Cadence:** Establish an initialization file contract (updating Section 4.2) where every registered PEM must write a static schema description file (e.g., `{pem_namespace}.schema.json`) to the shared IPC volume. The Core Daemon reads these files on startup and during dynamic reloads to successfully construct the type-checking reference map required for validating JSON-IR expressions. This section should also note the implementation of wildcard path matching to streamline heavily nested module schemas.
