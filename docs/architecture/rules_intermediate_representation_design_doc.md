# Rule Language Design Specification: Climatomaton

## 1. Core Requirements & Logic Constraints

This specification defines the syntax, data types, and execution model for the Climatomaton rule language. The system evaluates an ordered set of **Climate Rules** followed by an ordered set of **Tag Rules**.

### 1.1 AST Compilation & Execution

Rules are authored in an externally defined source format. The Pluggable Rules Module (PRM) is responsible for compiling this source format into a structured JSON Abstract Syntax Tree (AST).

* **Static Type Checking:** All static type checking and validation must be performed by the PRM during the compilation phase.
* **Core Execution:** The Core Daemon expects a fully validated, type-safe JSON AST and does not perform additional static type validation prior to execution.

### 1.2 Execution Conventions

Because the AST permits general-purpose actions across valid data types, the core execution engine cannot statically enforce that Climate Rules strictly mutate numeric/boolean data or that Tag Rules strictly mutate tag lists. This separation of concerns is a **convention** that must be maintained by rule authors and documented in the language guide.

### 1.3 Strict Failure Policy

If at any point during execution a rule attempts to resolve an undefined namespace path, performs an invalid operation (e.g., a failed type conversion), or encounters any other execution error, **all rule processing is immediately aborted**. The system logs the specific failure, alerts administrators, and discards all pending transactions. No default values are ever assumed.

---

## 2. Type System & Operations

The rule language supports four distinct primitives.

### 2.1 Number

Represents floating-point or integer numeric values.

* **Literal Representation:** Standard digits, optional negative sign, optional decimal (e.g., `42`, `-15`, `3.14`).
* **Operators:**
  * *Arithmetic:* `+`, `-`, `*`, `/`, `%`, ``
  * *Comparison:* `==`, `!=`, `<`, `<=`, `>`, `>=`
* **Functions/Methods:**
  * `abs(n)`: Returns the absolute value.
  * `round(n, [precision])`: Rounds to the nearest integer, or optionally to a specific decimal precision.
  * `min(n1, n2, ...)`: Returns the smallest value.
  * `max(n1, n2, ...)`: Returns the largest value.
  * `clamp(n, min_val, max_val)`: Constrains a number within a specific range.
  * `within(n, lo, hi, [bounds])`: Checks if `n` falls within the range of `lo` and `hi`. The optional `bounds` parameter is a string literal specifying inclusivity: `"[]"` (default, `lo <= n <= hi`), `"()"` (`lo < n < hi`), `"[)"` (`lo <= n < hi`), or `"(]"` (`lo < n <= hi`).
  * `to_string(n)`: Converts the number to its string representation.

### 2.2 Boolean

Represents true or false logic states.

* **Literal Representation:** `true`, `false`.
* **Operators:**
  * *Logical:* `and`, `or`, `not`
  * *Comparison:* `==`, `!=`
  * *Mutation:* `=` (Used for assigning states in the transaction or variable environments).

### 2.3 String

Represents standard text.

* **Literal Representation:** Text enclosed in double or single quotes.
* **Operators:**
  * *Concatenation:* `+`
  * *Comparison:* `==`, `!=`
  * *Mutation:* `=`
* **Functions/Methods:**
  * `length(s)`: Returns character count.
  * `contains(s, substring)`: Returns a boolean indicating if the substring exists.
  * `starts_with(s, prefix)`: Returns true if the string begins with the prefix.
  * `ends_with(s, suffix)`: Returns true if the string ends with the suffix.
  * `to_number(s)`: Attempts to convert the string to a numeric value. *Note: If the string cannot be parsed into a valid number, the strict failure policy is triggered, aborting the entire execution cycle.*

### 2.4 Tag List

Represents an ordered collection of unique string tags.

* **Literal Representation:** A comma-separated list of strings enclosed in square brackets (e.g., `["Mild", "Windy"]`, `[]`).
* **Operators:**
  * *Comparison:* `==`, `!=` (Evaluates to true only if both lists contain the exact same tags).
  * *Mutation:* `=`, `includes`, `excludes`. (Note: The `includes` and `excludes` operators accept either a single String literal/variable or another Tag List literal/variable).
* **Functions/Methods:**
  * `length(list)`: Returns the number of tags.
  * `has(list, tag)`: Returns true if the specific string tag exists in the list.
  * `has_any(list, tag_list)`: Returns true if the list contains at least one of the tags from the provided `tag_list`.
  * `has_all(list, tag_list)`: Returns true if the list contains all of the tags from the provided `tag_list`.
  * `is_empty(list)`: Returns true if the list contains zero tags.

---

## 3. Environments and Static Typing

Rules execute against contextual data sets accessed via `.`-separated identifiers. The PRM utilizes the namespace prefixes to perform static type checking during AST compilation.

1.  **`climate.*` (Read-Only):** The historical baseline state.
2.  **`proposals.*` (Read-Only):** Summary of EOT data (e.g., `proposals.count`, `proposals.passed`).
3.  **`{pem_namespace}.*` (Read-Only):** Externally provided data modules.
4.  **`new.*` (Mutable):** The transaction environment initialized from `climate.*` and mutable PEM keys.
5.  **`var.*` (Mutable):** A flat set of ephemeral variables that persist only for the duration of a single rule execution cycle.

### 3.1 The Variable Environment (`var.`) & Strong Typing

To satisfy the requirement that variables are **not predefined** while guaranteeing **static type-checking** during compilation, the `var.` namespace utilizes **Type Partitioning via Prefixes**. The identifier path dictates the data type, allowing the PRM to validate the AST at compile time.

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

Actions mutate data in either the `new.*` or `var.*` namespaces. An action consists of a target path, an assignment/mutation operator, and an expression.

* **Numeric Actions:** Use `=`, `+=`, or `-=`.
  * *Example:* `new.climate.value += (var.n.modifier * 2)`
* **Boolean Actions:** Use `=`.
  * *Example:* `var.b.flag_triggered = true`
* **String Actions:** Use `=`.
  * *Example:* `var.s.report_prefix = "Extreme "`
* **Tag List Actions:** Use `=`, `includes`, or `excludes`.
  * *Example:* `new.climate.tags includes "Windy"`
  * *Example:* `new.climate.tags excludes ["Mild", "Stable"]`
  * *Example:* `var.l.override_tags = ["Chaotic"]`



---

---

### Discussion & Notes

* **Range Checking (`within`):** I replaced the boolean `between` operator concept with a `within(n, lo, hi, [bounds])` function appended directly to the Number type. By defaulting to `"[]"` but allowing strings like `"(]"` or `"()"`, we neatly capture all four permutations of inclusive/exclusive bounds while keeping the syntax very statically analyzable.
* **Type Checking Delegation:** As requested, I've clarified that the PRM acts as the compiler. This shifts the heavy lifting of static analysis entirely onto the PRM, meaning the Core Daemon just runs a JSON schema validation on the AST and trusts that operations like "String + Number" won't be in the payload.
* **Type Conversion Risks (`to_number`):** Adding `to_number(s)` introduces a runtime failure vector (e.g., trying to parse "apple"). Given the strict failure policy dictated by the architecture constraints, I documented that a failed conversion will trigger a complete abort.
* **Tag List Expansions:** `includes` and `excludes` have been explicitly defined to accept both singular Strings and Tag Lists, enabling bulk updates. Pure assignment (`=`) is also permitted for overwriting list states completely.
* **Conventions vs. Protections:** Adding Section 1.2 correctly frames the separation of Climate and Tag rule mutations as a "convention" for rule authors, accurately reflecting the flexibility of a generalized AST framework.
