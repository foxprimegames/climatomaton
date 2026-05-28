# Rule Language Design Specification: Climatomaton

## 1. Core Requirements & Logic Constraints

This specification defines the syntax, data types, and execution model for the Climatomaton rule language. The system evaluates an ordered set of **Climate Rules** (which mutate numeric and string data) followed by an ordered set of **Tag Rules** (which mutate lists of descriptive strings).

Rules execute against a strict set of isolated environments. To guarantee deterministic execution, the system employs strong typing and static type checking.

**Strict Failure Policy:** If at any point during parsing or execution a rule attempts to resolve an undefined namespace path, performs an invalid type operation (e.g., adding a string to a number), or encounters any other execution error, **all rule processing is immediately aborted**. The system logs the specific failure, alerts administrators, and discards all pending transactions. No default values are ever assumed for missing external data.

---

## 2. Type System & Operations

The rule language supports four distinct primitives. All literals, operators, and functions are strongly typed.

### 2.1 Number

Represents floating-point or integer numeric values.

* **Literal Representation:** Standard digits, optional negative sign, optional decimal (e.g., `42`, `-15`, `3.14`).
* **Operators:**
  * *Arithmetic:* `+` (add), `-` (subtract), `*` (multiply), `/` (divide), `%` (modulo), `` (exponentiation).
  * *Comparison:* `==`, `!=`, `<`, `<=`, `>`, `>=`.
* **Functions/Methods:**
  * `abs(n)`: Returns the absolute value.
  * `round(n, [precision])`: Rounds to the nearest integer, or optionally to a specific decimal precision.
  * `min(n1, n2, ...)`: Returns the smallest value.
  * `max(n1, n2, ...)`: Returns the largest value.
  * `clamp(n, min_val, max_val)`: Constrains a number within a specific range.

### 2.2 Boolean

Represents true or false logic states, primarily used in conditions or as flags.

* **Literal Representation:** `true`, `false`.
* **Operators:**
  * *Logical:* `and`, `or`, `not`.
  * *Comparison:* `==`, `!=`.
* **Functions/Methods:** No specific methods are required for booleans, as they are managed via logical operators.

### 2.3 String

Represents standard text.

* **Literal Representation:** Text enclosed in double or single quotes (e.g., `"Mild"`, `'Greenhouse'`).
* **Operators:**
  * *Concatenation:* `+` (joins two strings).
  * *Comparison:* `==`, `!=`.
* **Functions/Methods:**
  * `length(s)`: Returns the character count of the string.
  * `contains(s, substring)`: Returns a boolean indicating if the substring exists within the string.
  * `starts_with(s, prefix)`: Returns true if the string begins with the given prefix.
  * `ends_with(s, suffix)`: Returns true if the string ends with the given suffix.

### 2.4 Tag List

Represents an ordered collection of unique string tags used for climate descriptions.

* **Literal Representation:** A comma-separated list of strings enclosed in square brackets (e.g., `["Mild", "Windy"]`, `[]`).
* **Operators:**
  * *Comparison:* `==`, `!=` (evaluates to true only if both lists contain the exact same tags).
  * *Mutation:* `includes` (adds a tag if not present), `excludes` (removes a tag if present).
* **Functions/Methods:**
  * `length(list)`: Returns the number of tags in the list.
  * `has(list, tag)`: Returns true if the specific string tag exists in the list.
  * `has_any(list, [tag1, tag2])`: Returns true if the list contains at least one of the provided tags.
  * `has_all(list, [tag1, tag2])`: Returns true if the list contains all of the provided tags.
  * `is_empty(list)`: Returns true if the list contains zero tags.

---

## 3. Environments and Static Typing

Rules execute against contextual data sets called environments. Paths are accessed via `.`-separated identifiers.

1. **`climate.*` (Read-Only):** The historical baseline state prior to rule execution.
2. **`proposals.*` (Read-Only):** Summary of EOT data (e.g., `proposals.count`, `proposals.passed`).
3. **`{pem_namespace}.*` (Read-Only):** Externally provided data modules.
4. **`new.*` (Mutable):** The transaction environment initialized from `climate.*` and mutable PEM keys.

### 3.1 The Variable Environment (`var.`) & Strong Typing

The `var.` namespace provides ephemeral, mutable storage that exists only for the duration of a single rule execution cycle.

To satisfy the requirement that variables are **not predefined** (auto-initializing on first reference) while also guaranteeing **static type-checking** during the parsing phase, the `var.` namespace utilizes **Type Partitioning via Prefixes**.

Whenever a rule references a variable, the identifier path itself dictates the expected data type. This allows the parser to validate the AST at compile time without requiring an explicit variable declaration block.

The variable namespace is segmented as follows:

* **`var.n.*` (Numbers):** Auto-initializes to `0`.
  * *Example:* `var.n.turn_modifier = 5`
* **`var.b.*` (Booleans):** Auto-initializes to `false`.
  * *Example:* `var.b.is_critical = true`
* **`var.s.*` (Strings):** Auto-initializes to `""` (empty string).
  * *Example:* `var.s.status_message = "Warning"`
* **`var.l.*` (Tag Lists):** Auto-initializes to `[]` (empty list).
  * *Example:* `var.l.temp_tags includes "Frozen"`

If the parser detects an operation mismatch—such as attempting to concatenate a string to `var.n.counter` or checking `has()` on `var.s.status`—it will reject the rule set during the PRM loading phase before it ever affects the active system.

---

## 4. Rule Structure and Evaluation

A rule is defined by its name, a set of conditions, and a set of actions.

### 4.1 Conditions

Conditions are boolean expressions. A rule activates only if all condition statements evaluate to `true`.

* **Range Syntax:** To provide a concise syntax for range checking (avoiding verbose `x >= 10 and x <= 20` statements), the language supports a `between` operator: `climate.value between (10, 20)`.

### 4.2 Actions

Actions mutate data in either the `new.*` or `var.*` namespaces. An action consists of a target path, an assignment/mutation operator, and an expression.

* **Numeric Actions:** Use `=`, `+=`, or `-=`.
  * `new.climate.value += (var.n.passed_proposals * 2)`
* **String Actions:** Use `=`.
  * `var.s.report_prefix = "Extreme "`
* **Tag List Actions:** Use `includes` or `excludes`.
  * `new.climate.tags includes "Windy"`
  * `new.climate.tags excludes "Mild"`

---

---

### Discussion & Notes

* **Variable Typing Strategy (`var.n.*`, etc.):** Because you explicitly require variables to initialize on first use *and* want static type checking, we cannot rely on runtime type inference (which breaks static checking). By enforcing a type prefix right in the namespace path, the parser immediately knows the signature of the variable when it reads the AST. This is a very robust, clean way to handle dynamic instantiation in a strongly typed execution engine.
* **Tag List Operations:** I separated "Strings" and "Tag Lists" completely. Treating a Tag List strictly as a collection rather than a single comma-separated string prevents messy regex or string-splitting logic inside the rules engine. The `includes`/`excludes` operators give rules a clean, declarative way to flip tags on and off.
* **Range Syntax:** I added a `between` operator (`x between (y, z)`) to satisfy the requirement for a concise range syntax in boolean expressions.
* **Compile-Time Validation:** With these strict types, when your Pluggable Rules Module (PRM) attempts to swap the active rules file, the Core Daemon can do a complete static analysis pass. If a rule says `new.climate.value += "High"`, the parser knows `new.climate.value` is a Number and `"High"` is a String, and it will reject the entire rule file swap, keeping the system safe.
