# Rule Language Design Specification: Climatomaton

## 1. Core Requirements & Logic Constraints

This specification defines the syntax, data types, and execution model for the Climatomaton rule language. The system evaluates an ordered set of **Climate Rules** followed by an ordered set of **Tag Rules**.

### 1.1 AST Compilation & Validation

Rules are authored in an externally defined source format. The Pluggable Rules Module (PRM) is strictly responsible for the pure syntactic parsing of this source format into a structured JSON Abstract Syntax Tree (AST). Because external Pluggable Environment Module (PEM) schemas and internal core schemas (`climate.`, `proposals.`) are not accessible to the PRM, the Core Daemon handles the symbolic/semantic evaluation and static type-checking pass upon receiving the AST.

### 1.2 Immediate Validation Lifecycle

To prevent validation errors from blocking the processing of infrequent end-of-turn (EOT) reports, the Core Daemon proactively loads and validates the rule AST. As soon as the system detects that a rules file has been updated, the Core Daemon immediately performs the semantic and static type-checking pass against all known internal and PEM schemas.

### 1.3 Execution Conventions

Because the AST permits general-purpose actions across valid data types, the core execution engine cannot statically enforce that Climate Rules strictly mutate numeric/boolean data or that Tag Rules strictly mutate tag lists. This separation of concerns is a **convention** that must be maintained by rule authors and documented in the language guide.

### 1.4 Strict Failure Policy

If at any point during execution a rule attempts to resolve an undefined namespace path, performs an invalid operation (e.g., a failed type conversion), or encounters any other execution error, **all rule processing is immediately aborted**. The system logs the specific failure, alerts administrators, and discards all pending transactions. No default values are ever assumed.

---

## 2. Type System & Operations

The rule language supports four distinct primitives.

### 2.1 Number

Represents floating-point or integer numeric values.

* **Literal Representation:** Standard digits, optional negative sign, optional decimal (e.g., `42`, `-15`, `3.14`).
* **Operators:** Arithmetic (`+`, `-`, `*`, `/`, `%`, ``) and Comparison (`==`, `!=`, `<`, `<=`, `>`, `>=`).
* **Functions/Methods:** `abs(n)`, `round(n, [precision])`, `min(n1, n2, ...)`, `max(n1, n2, ...)`, `clamp(n, min_val, max_val)`, `within(n, lo, hi, [bounds])`, and `to_string(n)`. The optional `bounds` parameter in `within` is a string literal specifying inclusivity: `"[]"` (default, `lo <= n <= hi`), `"()"` (`lo < n < hi`), `"[)"` (`lo <= n < hi`), or `"(]"` (`lo < n <= hi`).

### 2.2 Boolean

Represents true or false logic states.

* **Literal Representation:** `true`, `false`.
* **Operators:** Logical (`and`, `or`, `not`), Comparison (`==`, `!=`), and Mutation (`=`).

### 2.3 String

Represents standard text.

* **Literal Representation:** Text enclosed in double or single quotes.
* **Operators:** Concatenation (`+`), Comparison (`==`, `!=`), and Mutation (`=`).
* **Functions/Methods:** `length(s)`, `contains(s, substring)`, `starts_with(s, prefix)`, `ends_with(s, suffix)`, and `to_number(s)`. If `to_number(s)` cannot parse the string into a valid number, the strict failure policy is triggered.

### 2.4 Tag List

Represents an ordered collection of unique string tags.

* **Literal Representation:** A comma-separated list of strings enclosed in square brackets (e.g., `["Mild", "Windy"]`, `[]`).
* **Operators:** Comparison (`==`, `!=`) and Mutation (`=`, `includes`, `excludes`). The `includes` and `excludes` operators accept either a single String literal/variable or another Tag List literal/variable.
* **Functions/Methods:** `length(list)`, `has(list, tag)`, `has_any(list, tag_list)`, `has_all(list, tag_list)`, and `is_empty(list)`.

---

## 3. Environments and Static Typing

Rules execute against contextual data sets accessed via `.`-separated identifiers. The Core Daemon utilizes the namespace prefixes and known schemas to perform static type checking upon loading the AST.

* **`climate.*` (Read-Only):** The historical baseline state.
* **`proposals.*` (Read-Only):** Summary of EOT data (e.g., `proposals.count`, `proposals.passed`).
* **`{pem_namespace}.*` (Read-Only):** Externally provided data modules.
* **`new.*` (Mutable):** The transaction environment initialized from `climate.*` and mutable PEM keys.
* **`var.*` (Mutable):** A flat set of ephemeral variables that persist only for the duration of a single rule execution cycle.

### 3.1 The Variable Environment (`var.`) & Strong Typing

To satisfy the requirement that variables are **not predefined** while guaranteeing **static type-checking**, the `var.` namespace utilizes **Type Partitioning via Prefixes**. The identifier path dictates the data type, allowing the Core Daemon to validate variable operations before execution.

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

* **Numeric Actions:** Use `=`, `+=`, or `-=` (e.g., `new.climate.value += (var.n.modifier * 2)`).
* **Boolean Actions:** Use `=` (e.g., `var.b.flag_triggered = true`).
* **String Actions:** Use `=` (e.g., `var.s.report_prefix = "Extreme "`).
* **Tag List Actions:** Use `=`, `includes`, or `excludes` (e.g., `new.climate.tags includes "Windy"`, `new.climate.tags excludes ["Mild", "Stable"]`).

---

---

### Discussion & Notes

* **Architecture Document Update Required:** Shifting the semantic evaluation and static type-checking to the Core Daemon necessitates an update to the Climatomaton Architecture Specification. Specifically, Section 4.1 (PRM Protocol) currently states that the Core "parses the new rules... validates them, and atomically swaps the active rules pointer." This language needs to be expanded to explicitly include the *immediate semantic validation against all registered schemas* prior to swapping that pointer.
* **Validation Failure Behavior:** If the Core Daemon's static validation pass fails upon loading a newly provided AST from the PRM, the system should discard the new ruleset, retain the previously active (and valid) ruleset, and fire a high-priority `sys.notification` event to the administrators indicating a compilation/type error in the PRM's output.
* **List Formatting in the Spec:** I've flattened the lists in Section 2 to ensure the specification remains highly scannable and avoids nested bullet visual clutter, grouping operators and functions logically within single bullet points.
