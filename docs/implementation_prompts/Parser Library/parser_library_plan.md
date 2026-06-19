Got it. Skipping the `ruff` configuration since that is already locked in.

Here is the implementation plan structured directly into GitHub milestones and issues. To keep the issues organized within the monorepo, I've introduced a few new component labels (`comp/parser`, `comp/lexer`, `comp/ast`, `comp/emitter`, `comp/cli`) that strictly mirror your established format.

### Milestone 1: Library Foundation & Interface Contracts

**Description:** Establish the parsing library within the `uv` workspace, define the public API contracts, and set up the base data structures.

* **Task: Initialize `comp/parser` workspace package**
  * **Description:** Create the dedicated, I/O-agnostic parser library package within the `uv` monorepo. Expose the primary `parse_clime`, `tokenize`, `parse`, and `emit` functions as empty stubs.
  * **Labels:** `comp/build system`, `comp/repo`, `type/architecture`
* **Task: Define parsing Result and Token schemas**
  * **Description:** Implement the `BaseResult`, `ASTResult`, and `IRResult` classes to handle error accumulation without fast-failing. Implement the `__str__` and `__repr__` magic methods on all interface types for future CLI debugging.
  * **Labels:** `comp/parser`, `type/architecture`
* **Task: Document parser architecture**
  * **Description:** Update `DEVELOPERS.md` to outline the I/O-decoupled design, the EBNF grammar rules, and the strict zero-file-I/O constraint for the core library.
  * **Labels:** `comp/parser`, `tags/documentation`

### Milestone 2: Lexical Analyzer (Lexer)

**Description:** Build the state machine responsible for processing the raw text of `.rules` files into a discrete stream of tokens.

* **Task: Implement Trie-based character buffer & state machine**
  * **Description:** Build the lexer to accept an `Iterator[str]`. Implement a character buffer and prefix tree to process tokens using the maximal munch principle, safely handling tokens split across yielded string chunks. Ensure the lexer correctly captures dot-separated identifier syntax for `NamespacePath` resolution.
  * **Labels:** `comp/lexer`, `comp/parser`, `type/feature`
* **Task: Implement comment stripping and whitespace handling**
  * **Description:** Add logic to identify and safely discard all `[ ... ]` comments at the lexer level so they are never passed to the parser.
  * **Labels:** `comp/lexer`, `type/feature`
* **Task: Implement lexical error accumulation**
  * **Description:** If the character buffer yields no valid token match, register a structured lexical error with line/column coordinates in the `errors` list, and skip forward to the next whitespace boundary to resume processing.
  * **Labels:** `comp/lexer`, `type/bug` (Handling), `type/feature`

### Milestone 3: Abstract Syntax Tree (AST) & Parser

**Description:** Construct the recursive descent parser to consume the token stream and build the AST in accordance with the Clime EBNF grammar.

* **Task: Define AST Python node classes**
  * **Description:** Create Python classes representing the EBNF grammar (e.g., `Rule`, `Condition`, `Action`, `Expression`, `FunctionCall`).
  * **Labels:** `comp/ast`, `type/architecture`
* **Task: Implement recursive descent expression parsing**
  * **Description:** Build the parser logic to handle standard mathematical and logical expressions, strictly enforcing operator precedence.
  * **Labels:** `comp/parser`, `type/feature`
* **Task: Parse Clime syntactic sugar constructs**
  * **Description:** Implement parsing logic to capture natural language shortcuts (e.g., `x < N < y`, `includes any of`) into specific AST nodes flagged for unrolling later.
  * **Labels:** `comp/ast`, `comp/parser`, `type/feature`
* **Task: Implement rule-boundary error synchronization**
  * **Description:** Implement the error recovery fallback. If syntax errors occur within a rule, record the error in the `ASTResult`, discard the broken branch, and synchronize at the next `climate rule` or `tag rule` keyword to continue parsing subsequent rules.
  * **Labels:** `comp/parser`, `type/feature`

### Milestone 4: JSON-IR Emitter

**Description:** Build the Emitter pipeline to translate the validated AST into the strict JSON-IR dictionary structure required by the Core Daemon.

* **Task: Build AST-to-Dictionary traversal engine**
  * **Description:** Implement the `emit()` function to recursively traverse the AST and generate the native Python dictionary output, injecting the explicit `"kind"` and `"datatype"` structural properties into every node.
  * **Labels:** `comp/emitter`, `type/architecture`, `type/feature`
* **Task: Map operators to strict JSON-IR codes**
  * **Description:** Map standard operators from the AST to their standardized JSON-IR string codes (e.g., `+` to `"ADD"`, `not` to `"NOT"`).
  * **Labels:** `comp/emitter`, `type/feature`
* **Task: Implement syntactic sugar unrolling**
  * **Description:** Expand the AST's flagged sugar nodes during emission. E.g., unroll chained tag actions (`includes X and excludes Y`) into separate, distinct mutation nodes within the rule's `actions` array.
  * **Labels:** `comp/emitter`, `comp/ast`, `type/feature`

### Milestone 5: CLI Tooling Wrapper

**Description:** Construct the standalone CLI to validate `.rules` files locally without hitting the Core Daemon.

* **Task: Implement CLI entry point and file I/O wrappers**
  * **Description:** Create the CLI direct entry point in the workspace. Implement file-loading wrappers that read single or multiple `.rules` files from disk and pass their contents as iterators into the strictly decoupled `parse_clime` library function.
  * **Labels:** `comp/cli`, `comp/build system`, `type/architecture`
* **Task: Implement CLI debug modes and error formatting**
  * **Description:** Parse the `errors` list returned by the library and format them into human-readable terminal output mapping back to exact line/column coordinates. Add optional flags to output raw token streams or raw AST structures for debugging. Return `0` on success and `1` on detected errors.
  * **Labels:** `comp/cli`, `type/feature`

---

Would you like to drill down into the specific Python classes needed for the AST nodes in Milestone 3, or focus first on defining the exact schema for the `BaseResult` error objects in Milestone 1?