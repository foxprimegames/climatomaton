# Custom DSL Parser & AST Interpreter Design Document

This document defines how the Core Engine ingests raw `.rules` files, builds an executable Abstract Syntax Tree (AST), handles sorting priorities, and safely executes calculations against the dynamic memory graph.

## 1. Formal DSL Grammar (Updated EBNF)

*Note: The EBNF grammar establishes the definitive structural rules for the DSL, supporting recursive conditional expressions and native function calls.*

```ebnf
File            ::= ( ClimateRule | TagRule )*
ClimateRule     ::= "climate" "rule" String "when" ConditionalExpr "then" ClimateActions "end"
TagRule         ::= "tag" "rule" String "when" ConditionalExpr "then" TagActions "end"

ConditionalExpr ::= LogicalOr
LogicalOr       ::= LogicalAnd ( "or" LogicalAnd )*
LogicalAnd      ::= Inversion ( "and" Inversion )*
Inversion       ::= [ "not" ] Relational
Relational      ::= ArithExpr RelOp ArithExpr [ RelOp ArithExpr ]               
                  | FunctionCall
                  | "(" ConditionalExpr ")"

ArithExpr       ::= Term ( ( "+" | "-" ) Term )*
Term            ::= Factor ( ( "*" | "/" ) Factor )*
Factor          ::= Number | NamespacePath | FunctionCall | "(" ArithExpr ")"

FunctionCall    ::= NamespacePath "(" [ ArgumentList ] ")"
ArgumentList    ::= Argument ( "," Argument )*
Argument        ::= ConditionalExpr | ArithExpr | String

NamespacePath   ::= Identifier ( "." Identifier )*
RelOp           ::= "==" | "!=" | ">" | "<" | ">=" | "<="

ClimateActions  ::= ( NamespacePath ( "+=" | "-=" | "=" ) ArithExpr ";" )+
TagActions      ::= ( ( "include" | "exclude" ) TagList ";" )+
TagList         ::= String ( "," String )*
```

---

## 2. Lexer / Tokenizer Specification

The lexer is responsible for breaking down the raw text of the `.rules` files into a stream of actionable tokens for the parser.

| Token Name | Literal Match / Description |
| --- | --- |
| `TOKEN_CLIMATE` | `"climate"` |
| `TOKEN_TAG` | `"tag"` |
| `TOKEN_RULE` | `"rule"` |
| `TOKEN_WHEN` | `"when"` |
| `TOKEN_THEN` | `"then"` |
| `TOKEN_END` | `"end"` |
| `TOKEN_AND` | `"and"` |
| `TOKEN_OR` | `"or"` |
| `TOKEN_NOT` | `"not"` |
| `TOKEN_INCLUDE` | `"include"` |
| `TOKEN_EXCLUDE` | `"exclude"` |
| `TOKEN_IDENTIFIER` | Alphanumeric string starting with a letter (used in namespace paths) |
| `TOKEN_STRING` | Text enclosed in double quotes. Supports standard escape sequences (e.g., `\"`, `\\`, `\n`, `\t`, `\r`) and Unicode hex escapes (e.g., `\uXXXX`). |
| `TOKEN_NUMBER` | Integer or floating-point numerical values |
| `TOKEN_PLUS` | `+` |
| `TOKEN_MINUS` | `-` |
| `TOKEN_STAR` | `*` |
| `TOKEN_SLASH` | `/` |
| `TOKEN_ASSIGN` | `=` |
| `TOKEN_PLUS_ASSIGN` | `+=` |
| `TOKEN_MINUS_ASSIGN` | `-=` |
| `TOKEN_EQ` | `==` |
| `TOKEN_NEQ` | `!=` |
| `TOKEN_GT` | `>` |
| `TOKEN_LT` | `<` |
| `TOKEN_GTE` | `>=` |
| `TOKEN_LTE` | `<=` |
| `TOKEN_LPAREN` | `(` |
| `TOKEN_RPAREN` | `)` |
| `TOKEN_COMMA` | `,` |
| `TOKEN_SEMICOLON` | `;` |
| `TOKEN_DOT` | `.` |

* **Token Positional Metadata:** In addition to the token type and literal string value, the lexer must attach spatial metadata to every generated token, specifically `LineNumber` and `ColumnNumber`. This spatial data acts in tandem with the active `CompilationContext` to guarantee precise, file-specific error tracebacks during compilation or runtime failures.

---

## 3. Parser Architecture & AST Schema

The system utilizes a recursive descent parser that maps the token stream into an Abstract Syntax Tree (AST). The AST is an in-memory, hierarchical data structure representing the fully parsed ruleset, allowing for safe, isolated evaluation against the runtime state.

* **Root Nodes (`RuleNode`):** The top level of the AST consists of distinct objects for each parsed rule (e.g., `ClimateRuleNode`, `TagRuleNode`). Each root node stores its assigned `Rule ID` and string identifier.
* **Evaluation Trees (`ConditionalNode`):** The `when` clause of a rule is stored as a binary expression tree. Internal nodes represent logical operations (`AndNode`, `OrNode`, `NotNode`) and relational comparisons (`RelationalNode`).
* **Arithmetic Trees (`ArithExprNode`):** Mathematical operations (`+`, `-`, `*`, `/`) are represented by internal arithmetic nodes.
* **Function Nodes (`FunctionCallNode`):** Represent invocations of native or global functions. These nodes capture a target `NamespacePathNode` to identify the function and recursively evaluate their `ArgumentList` prior to executing the underlying engine function.
* **Execution Blocks (`ActionNode`):** The `then` clause of a rule is stored as an ordered list of executable statement nodes (e.g., `AssignmentNode`, `SetMutationNode`), ensuring actions are strictly deferred until the `ConditionalNode` resolves to true.
* **Leaf Nodes:** The terminal ends of the evaluation and action trees consist of literal primitives (`StringNode`, `NumberNode`) and dynamic state pointers (`NamespacePathNode`).

---

## 4. Built-In & Environment Functions

Because the grammar supports `FunctionCall` syntax inside arithmetic factors and relational checks, the Core Engine maps specific `NamespacePath` invocations to native interpreter functions.

### Native Environment Functions

These functions are directly attached to the baseline memory graphs and provide context-aware data extraction:

* **`climate.hasTag(String)`**: Returns a boolean (`ConditionalExpr` compatible) evaluating to true if the specified string exists within the active `climate.tags` array.

### Global Standard Functions

These built-in math and logic utilities are evaluated in the global namespace (no prefix required):

* **`max(...ArithExpr)`**: Variadic function. Returns the largest value from a comma-separated list of arguments.
* **`min(...ArithExpr)`**: Variadic function. Returns the smallest value from a comma-separated list of arguments.
* **`round(ArithExpr)`**: Returns the float rounded to the nearest whole integer. Rounds "half away from zero" (e.g., `2.5` becomes `3`, and `-2.5` becomes `-3`).
* **`abs(ArithExpr)`**: Returns the absolute value of the provided float or integer.

---

## 5. Collation, Sorting, and Rule ID Indexer Engine

Because rules can be distributed across multiple physical `.rules` files, the parser engine enforces a strict multi-file merging and deterministic sorting algorithm.

* **Primary Grouping:** The engine groups and sorts all active `.rules` files in ascending order based on their parsed integer `FileNumber` prefix.
* **Secondary Tie-Breaking:** If multiple rule files share the exact same numeric prefix, the engine sorts those files lexicographically by their full physical filename.
* **The Stateful Compilation Context:** The parsing engine injects a stateful `CompilationContext` object into the parser. This context securely tracks both the parsed `FileNumber` (used for rule ID generation) and the full physical `FileName` (used to trace syntax exceptions and runtime crashes).
* **Stateful AST ID Allocation:** As the recursive descent parser resolves a `ClimateRule` or `TagRule` block, it requests a new ID from the `CompilationContext`. The Context increments the appropriate scope's dedicated counter and returns the permanent identifier formatted as `FileNumber-RuleIndex`. The context strictly resets both counters to `1` only when it detects a transition to a new numeric `FileNumber` prefix.

---

## 6. Syntax Discovery & Validation Pipeline

The parser operates as a strict, isolated validation phase during the dynamic rule and environment synchronization lifecycle.

* **Atomic Presence Verification:** Before allowing a directory swap, the engine parses all `.rules` files to ensure they pass syntax checks.
* **Dynamic Dependency Scanning:** The AST is scanned for references to any `NamespacePath` (including `FunctionCall` namespaces) to dynamically compile the Required Modules List.
* **Compiler Exceptions:** If any invalid syntax or broken grammar rules are encountered, the parser throws a compiler exception to abort the transaction immediately, explicitly before active memory pointers are modified.

---

## 7. Runtime AST Interpreter & Transaction Safety

The active execution environment is fundamentally **read-only by default**. All parsed `.json` environment objects (e.g., `economy`, `factions`), standard namespaces (e.g., `proposals`), and the `climate` baseline snapshot act as a frozen data graph. To support sequential rule execution, the Core Engine initializes an explicitly mutable namespace prefix (`new`) to track the running transaction state.

* **The Mutable `new` Namespace:** At the start of the evaluation phase, the Core Engine deep-copies the `climate` state into the mutable `new` namespace (yielding `new.climate.value` and `new.climate.tags`). This allows `then` blocks to mutate running totals while simultaneously reading from the immutable `climate` snapshot.
* **Dual-State Evaluation Context:**
  * **Within `when` blocks (`ConditionalNode`):** Logic relies strictly on the frozen environment, ensuring the initial conditions of the transaction cycle dictate rule firing.
  * **Within `then` blocks (`ActionNode`):** Logic calculations may read from both the frozen environment (e.g., `climate.value`) and the mutable buffer (e.g., `new.climate.value`), computing deltas dynamically.
* **Immediate Abort & Rollback:** If any rule execution fails (e.g., an unresolvable `NamespacePath`), the active cycle halts immediately. The `new` namespace buffer is discarded, ensuring no partial mutations persist.
* **Dual-Delivery Error Logging:** A global failure triggers the engine's dual-delivery log pipeline, detailing the exact `FileName`, `Rule ID`, unresolvable path or error, and the raw proposal report that triggered the failure.

---

## 8. Namespace Access Control & Immutability Protocol

To guarantee that the frozen environment cannot be manipulated by malicious or poorly written rules, the parser enforces strict compiler-level immutability checks during AST generation.

Because the architecture dictates that *only* the `new` namespace is mutable, the parser completely avoids tracking runtime locks or reading metadata configurations. It relies exclusively on a hardcoded prefix validation check.

### Compile-Time Immutability Validation

1. **Target Inspection**: Whenever the parser resolves an assignment or mutation action within a `then` block (matching operators `=`, `+=`, `-=`, `include`, or `exclude`), it isolates the target `NamespacePath` (the left-hand side of the expression).
2. **Prefix Matching**: The parser serializes the target `NamespacePath` into a continuous dot-notation string and verifies its prefix.
3. **Rejection Rule**: If the target string does **not** begin exactly with `new.`, the action is illegal.
   * *Allowed*: `new.climate.value += 1;` (Targets the mutable buffer)
   * *Allowed*: `new.economy.budget -= 50;` (Future-proofed for potential external buffers)
   * *Rejected*: `climate.value += 1;` (Fails compilation: Missing `new.` prefix)
   * *Rejected*: `economy.inflation = 0;` (Fails compilation: Attempted mutation of frozen PEM environment object)
4. **Compiler Exception**: If a violation is detected, the parser immediately halts AST generation and throws a `CompilerException`. The exception must log:
   * The precise `LineNumber` and `ColumnNumber` of the illegal mutation.
   * The `FileName` where the violation occurred.
   * A clear error trace: `[Compile Error] Attempted illegal mutation on read-only namespace path: <NamespacePath>. All mutations must target the 'new.' namespace.`
