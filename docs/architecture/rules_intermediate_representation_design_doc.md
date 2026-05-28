# Rule Language Design Specification: Climatomaton

## 1. Core Requirements & Logic Constraints

This specification defines the syntax, data types, and execution model for the Climatomaton rule language. The system evaluates an ordered set of **Climate Rules** followed by an ordered set of **Tag Rules**.

### 1.1 JSON-IR Compilation & Validation

Rules are authored in an externally defined source format. The Pluggable Rules Module (PRM) is strictly responsible for the pure syntactic parsing of this source format into a structured **JSON Intermediate Representation (JSON-IR)**. This term replaces "AST" to ensure no specific parser architecture or parsing paradigm is enforced upon PRM developers; the JSON-IR is simply the standardized execution data model consumed by the Core Daemon. Because external Pluggable Environment Module (PEM) schemas and internal core schemas (`climate.`, `proposals.`) are not accessible to the PRM, the Core Daemon handles the symbolic/semantic evaluation and static type-checking pass upon receiving the JSON-IR.

### 1.2 Validation & Re-Evaluation Lifecycle

To prevent validation errors from blocking the processing of infrequent end-of-turn (EOT) reports, the Core Daemon proactively validates the JSON-IR. The Core Daemon immediately executes a comprehensive semantic and static type-checking pass against all known internal and PEM schemas under the following conditions:

1. When the system detects that the active rules file has been updated.
2. When the Core Daemon receives new or updated environment schemas from any registered PEM.
3. When an existing environment schema is deleted or deregistered (e.g., a PEM goes offline and its schema is removed).

#### Rejection Before Execution Runtime

If a ruleset fails this proactive validation pass, it is **rejected before execution runtime**. This means:

* The invalid ruleset is completely discarded and never applied to any runtime context.
* The Core Daemon retains its current in-memory, Last-Known-Good (LKG) valid ruleset to ensure continuous, uninterrupted processing of game data.
* The system generates a high-severity log entry containing the exact validation or type-checking error.
* The system emits a `sys.notification` event to alert administrators via the Discord interaction channel that the new ruleset is broken and was ignored.

### 1.3 Execution Conventions

Because the JSON-IR permits general-purpose actions across valid data types, the core execution engine cannot statically enforce that Climate Rules strictly mutate numeric/boolean data or that Tag Rules strictly mutate tag lists. This separation of concerns is a **convention** that must be maintained by rule authors and documented in the language guide.

### 1.4 Strict Failure Policy

If at any point during execution a rule attempts to resolve an undefined namespace path, performs an invalid operation (e.g., a failed type conversion or mismatched type operation), or encounters any other execution error, **all rule processing is immediately aborted**. The system logs the specific failure, alerts administrators, and discards all pending transactions. No default values are ever assumed.

---

## 2. Type System & Operations

The rule language supports four distinct primitives. All operations, parameters, and return types are strongly typed.

### 2.1 Number

Represents floating-point or integer numeric values.

* **Literal Representation:** Standard digits, optional negative sign, optional decimal (e.g., `42`, `-15`, `3.14`).

#### Expression Operators

* **Addition (`+`)**: Adds two numeric values. Returns a Number.
* **Subtraction (`-`)**: Subtracts the right numeric value from the left. Returns a Number.
* **Multiplication (`*`)**: Multiplies two numeric values. Returns a Number.
* **Division (`/`)**: Divides the left numeric value by the right. Returns a Number. Triggers a strict failure if the divisor evaluates to `0`.
* **Modulo (`%`)**: Returns the remainder of division of the left numeric value by the right. Returns a Number.
* **Exponentiation**: Uses the double-asterisk string (`""`). Raises the left numeric value to the power of the right numeric value. Returns a Number.
* **Equality (`==`)**: Evaluates if two numeric values are equal. Returns a Boolean.
* **Inequality (`!=`)**: Evaluates if two numeric values are not equal. Returns a Boolean.
* **Less Than (`<`)**: Evaluates if the left value is strictly less than the right value. Returns a Boolean.
* **Less Than or Equal (`<=`)**: Evaluates if the left value is less than or equal to the right value. Returns a Boolean.
* **Greater Than (`>`)**: Evaluates if the left value is strictly greater than the right value. Returns a Boolean.
* **Greater Than or Equal (`>=`)**: Evaluates if the left value is greater than or equal to the right value. Returns a Boolean.

#### Mutation Operators

* **Assignment (`=`)**: Overwrites the target number variable or transaction field with the evaluated numeric expression result.
* **Addition Assignment (`+=`)**: Adds the evaluated numeric expression to the current value of the target field.
* **Subtraction Assignment (`-=`)**: Subtracts the evaluated numeric expression from the current value of the target field.

#### Functions / Methods

* **`abs(n)`**: Returns the absolute value of the numeric expression `n`.
* **`round(n, [precision])`**: Rounds `n` to the nearest integer, or to a specified integer `precision` decimal places.
* **`min(n1, n2, ...)`**: Accepts an arbitrary number of numeric arguments and returns the lowest value.
* **`max(n1, n2, ...)`**: Accepts an arbitrary number of numeric arguments and returns the highest value.
* **`clamp(n, min_val, max_val)`**: Constrains `n` so it does not fall below `min_val` or exceed `max_val`. Returns a Number.
* **`within(n, lo, hi, [bounds])`**: Evaluates whether `n` falls within the range between `lo` and `hi`. The optional `bounds` parameter accepts a string literal defining inclusivity boundaries:
  * `"[]"` (Default): Inclusive/Inclusive ($lo \le n \le hi$)
  * `"()"`: Exclusive/Exclusive ($lo < n < hi$)
  * `"[)"`: Inclusive/Exclusive ($lo \le n < hi$)
  * `"(]"`: Exclusive/Inclusive ($lo < n \le hi$)
  * Returns a Boolean.
* **`to_string(n)`**: Converts the numeric value `n` to its literal string representation. Returns a String.

### 2.2 Boolean

Represents true or false logic states.

* **Literal Representation:** `true`, `false`.

#### Expression Operators

* **Logical Conjunction (`and`)**: Evaluates to `true` if both left and right expressions are true. Returns a Boolean.
* **Logical Disjunction (`or`)**: Evaluates to `true` if either the left or right expression is true. Returns a Boolean.
* **Logical Negation (`not`)**: Unary operator that inverts the boolean value of the expression. Returns a Boolean.
* **Equality (`==`)**: Evaluates if two boolean states are identical. Returns a Boolean.
* **Inequality (`!=`)**: Evaluates if two boolean states are opposite. Returns a Boolean.

#### Mutation Operators

* **Assignment (`=`)**: Overwrites the target boolean variable or transaction field with the evaluated boolean expression result.

### 2.3 String

Represents a sequence of characters.

* **Literal Representation:** Text enclosed in double (`"`) or single (`'`) quotes (e.g., `"Mild"`, `'Greenhouse'`).
  * To include a quote character of the same type inside the string literal itself, it must be escaped using a backslash character (e.g., `"The engine reported: \"Anomalous Warmth\""` or `'It\'s a critical state'`).
  * To include a literal backslash character inside a string literal, it must be escaped using an additional backslash character (e.g., `"Path: C:\\Rules"` evaluates to the text sequence `Path: C:\Rules`).

#### Expression Operators

* **Concatenation (`+`)**: Joins two string expressions sequentially together. Returns a String.
* **Equality (`==`)**: Evaluates if two strings contain the exact same character sequence. Returns a Boolean.
* **Inequality (`!=`)**: Evaluates if two strings differ in character sequence. Returns a Boolean.

#### Mutation Operators

* **Assignment (`=`)**: Overwrites the target string variable or transaction field with the evaluated string expression result.

#### Functions / Methods

* **`length(s)`**: Returns the total character count of the string `s`. Returns a Number.
* **`contains(s, substring)`**: Evaluates whether the exact text sequence `substring` exists within string `s`. Returns a Boolean.
* **`starts_with(s, prefix)`**: Evaluates whether string `s` begins with the exact text sequence `prefix`. Returns a Boolean.
* **`ends_with(s, suffix)`**: Evaluates whether string `s` ends with the exact text sequence `suffix`. Returns a Boolean.
* **`to_number(s)`**: Parses a string representation of digits into a valid numeric value. Returns a Number. Triggers a strict failure abort if `s` contains characters that cannot form a valid integer or float.

### 2.4 Tag List

Represents a mathematical set of unique string tags, preserving insertion order.

* **Literal Representation:** A comma-separated list of string literals enclosed in square brackets (e.g., `["Mild", "Windy"]`, `[]`).

#### Expression Operators

* **Equality (`==`)**: Evaluates if two lists contain the exact same unique tags, regardless of ordering. Returns a Boolean.
* **Inequality (`!=`)**: Evaluates if there is any mismatch of unique tags between the two lists. Returns a Boolean.

#### Mutation Operators

* **Assignment (`=`)**: Overwrites the target tag list variable or transaction field completely with a new tag list.
* **Set Union (`includes`)**: Appends elements to the target list if they do not already exist. Accepts a single String expression or a Tag List expression.
* **Set Difference (`excludes`)**: Removes elements from the target list if they exist. Accepts a single String expression or a Tag List expression.

#### Functions / Methods

* **`length(list)`**: Returns the total count of unique tags currently in `list`. Returns a Number.
* **`has(list, tag)`**: Evaluates whether the single string expression `tag` is present within `list`. Returns a Boolean.
* **`has_any(list, tag_list)`**: Evaluates whether at least one tag inside the expression `tag_list` is present within `list`. Returns a Boolean.
* **`has_all(list, tag_list)`**: Evaluates whether every tag inside the expression `tag_list` is present within `list`. Returns a Boolean.
* **`is_empty(list)`**: Evaluates whether the list contains zero elements. Returns a Boolean.

---

## 3. Environments and Static Typing

Rules execute against contextual data sets accessed via `.`-separated identifiers. The Core Daemon utilizes these specific namespace prefixes and registered schemas to perform semantic analysis and type checking.

* **`climate.*` (Read-Only):** The historical baseline state prior to rule execution.
* **`proposals.*` (Read-Only):** Summary of EOT data (e.g., `proposals.count`, `proposals.passed`).
* **`{pem_namespace}.*` (Read-Only):** Externally provided data modules.
* **`new.*` (Mutable):** The transaction environment initialized from `climate.*` and mutable PEM keys.
* **`var.*` (Mutable):** A flat set of ephemeral variables that persist only for the duration of a single rule execution cycle.

### 3.1 The Variable Environment (`var.`) & Strong Typing

To satisfy the requirement that variables are **not predefined** while guaranteeing **static type-checking** during the Core Daemon's validation pass, the `var.` namespace utilizes **Type Partitioning via Prefixes**. The identifier path itself explicitly dictates the data type:

* **`var.n.*` (Numbers):** Auto-initializes to `0`.
* **`var.b.*` (Booleans):** Auto-initializes to `false`.
* **`var.s.*` (Strings):** Auto-initializes to `""` (empty string).
* **`var.l.*` (Tag Lists):** Auto-initializes to `[]` (empty list).

---

## 4. Rule Structure and Evaluation

A rule is defined by its name, a set of conditions, and a set of actions.

### 4.1 Conditions

Conditions are boolean expressions. A rule activates only if all condition statements evaluate to `true`.

### 4.2 Actions

Actions mutate data in either the `new.*` or `var.*` namespaces. An action consists of a target path, a mutation operator, and an expression.

---

## 5. JSON Intermediate Representation (JSON-IR)

To decouple the PRM's source-language parser from the Core Daemon's execution engine, rules are communicated via a strict **JSON Intermediate Representation (JSON-IR)**. This format standardizes how conditions and actions are structured for the semantic validator and the execution runtime.

### 5.1 Root Document Structure

The root JSON document represents the complete ruleset, divided into the two required execution phases:

```json
{
  "climate_rules": [ ... ],
  "tag_rules": [ ... ]
}
```

### 5.2 Rule Object

Each rule inside the `climate_rules` or `tag_rules` array is an object containing its name, an array of condition expressions (implicitly joined by a logical AND), and an array of action mutations.

```json
{
  "name": "Extreme Heat Modifier",
  "conditions": [ { /* Expression Node */ } ],
  "actions": [ { /* Mutation Node */ } ]
}
```

### 5.3 Expression Nodes

Expressions (used in conditions or on the right side of mutations) are represented by nested node objects. Every expression node must declare a `"type"`.

* **Literal Node:** Represents a hardcoded value. Requires a `datatype` indicator for type-checking.
```json
{ "type": "literal", "datatype": "number", "value": 15 }
{ "type": "literal", "datatype": "tag_list", "value": ["Mild", "Windy"] }
```

* **Reference Node:** Represents a dynamic lookup in an environment namespace.
```json
{ "type": "reference", "path": "climate.value" }
```

* **Operator Node:** Represents a side-effect-free evaluation. Requires an `"op"` string, a `"left"` expression node, and (except for unary `not`) a `"right"` expression node.
```json
{
  "type": "operator",
  "op": "**",
  "left": { "type": "reference", "path": "var.n.base_multiplier" },
  "right": { "type": "literal", "datatype": "number", "value": 2 }
}
```



* **Function Node:** Represents a method call. Requires a `"name"` string and an `"args"` array of expression nodes.
```json
{
  "type": "function",
  "name": "within",
  "args": [
    { "type": "reference", "path": "climate.value" },
    { "type": "literal", "datatype": "number", "value": 10 },
    { "type": "literal", "datatype": "number", "value": 20 },
    { "type": "literal", "datatype": "string", "value": "[)" }
  ]
}
```

### 5.4 Mutation Nodes (Actions)

Mutations dictate state changes. They define the `"target"` namespace path, the mutation `"op"`, and the `"expression"` node that evaluates to the new value or modifier.

```json
{
  "target": "new.climate.value",
  "op": "+=",
  "expression": {
    "type": "literal",
    "datatype": "number",
    "value": 5
  }
}
```

---

---

### Discussion & Notes

* **Exponentiation Formatting:** I altered the markdown syntax entirely for that line item. Instead of putting backticks inside parentheses, I used explicit phrasing: `Uses the double-asterisk string ("")`. This definitively prevents Markdown formatting from eating the character sequence regardless of the client-side parser rules.
* **AST Terminology Replacement:** The term "JSON Intermediate Representation" (JSON-IR) accurately describes exactly what this system does—it's an intermediate execution model decoupled from how the human-readable text was originally written. I built Section 5 to give concrete, easily adaptable JSON schemas for literals, references, operations, and function calls. This design allows PRMs to be built in Python, Rust, Node, etc., as long as they can stringify their parsed data into this JSON schema.

---

### Consolidated List of Pending Architecture Document Updates

The following items represent design changes established during this language specification sequence that require formal updates to the main **Climatomaton Architecture Specification**:

1. **Core Daemon Immediate Validation Pass (Section 4.1 Update):**
   * *Current State:* Section 4.1 says the Core Daemon loads rules and checks them on a broad loop.
   * *Required Change:* Update to specify that the Core Daemon must actively monitor the rules folder *and* the schemas folder using a file-watcher loop. The core must proactively parse and type-check incoming JSON-IR files immediately upon modification of the rules file, **or** whenever a PEM schema is added, updated, or deleted.
2. **Validation Error Recovery Policy (Section 4.1 & 2.2 Update):**
   * *Required Change:* Detail the "Last-Known-Good" (LKG) fallback strategy. If a newly watched JSON-IR file fails semantic/static verification (or if an environment change suddenly renders the active rules invalid, such as a PEM deletion), the Core Daemon must not crash or drop the previous working state. It must drop the file change (or halt execution readiness if a critical PEM vanished), log the validation trace, issue an admin alert, and keep processing utilizing the prior working version if possible.
3. **PEM Schema Exchange & Registration Cadence (Section 4.2 Update):**
   * *Current State:* Section 4.2 governs the writing of data to shared volumes by PEMs but lacks an explicit data typing or schema declaration contract.
   * *Required Change:* Establish an initialization file contract where every registered PEM must write a static schema description file (e.g., `{pem_namespace}.schema.json`) to the shared IPC volume during its boot phase. The Core Daemon reads these files on startup and during dynamic reloads to successfully construct the type-checking reference map required for validating JSON-IR expressions.
