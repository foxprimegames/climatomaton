Here is a phased implementation plan for the Clime parsing library. This plan ensures strict separation from file I/O, robust error accumulation, and accurate translation of the EBNF grammar into the required JSON-IR.

### Phase 1: Foundation & Project Structure

The first phase establishes the internal architecture, interface contracts, and development tooling.

* **Initialize the Workspace:** Set up the parsing library as a dedicated package within the `uv` monorepo workspace.
* **Configure Linting:** Configure `ruff` for rigorous linting across the library. Ensure that automated formatting tools are disabled in the configuration to retain manual control over code style and formatting.
* **Documentation Tracking:** Outline these specific implementation milestones in a local `DEVELOPERS.md` to keep project tracking native to the repository.
* **Define Base Result Classes:** Implement the abstract `BaseResult` class containing the `success` boolean and `errors` list. Implement the `ASTResult` and `IRResult` subclasses.
* **Define Output Formatting:** Implement `__str__` and `__repr__` magic methods on all interface types (`Token`, `BaseResult`, `ASTResult`, `IRResult`) to ensure they can be formatted for the CLI debugging outputs.

### Phase 2: Lexical Analyzer (The Lexer)

The Lexer processes the raw text into a token stream without making any assumptions about the underlying source mechanism.

* **Implement I/O Decoupling:** Build the lexer to accept an `Iterator[str]`. Implement an internal character buffer to safely process tokens that might be split across yielded string chunks.
* **Trie-Based State Machine:** Construct a prefix tree (Trie) to evaluate the character buffer using the maximal munch principle. This guarantees the lexer consumes the longest valid token path before yielding.
* **Handle Identifiers & Namespaces:** Configure the state machine to properly lex variables and generic data targets using dot-separated identifier syntax for `NamespacePath` resolution.
* **Comment Stripping:** Add logic to identify and immediately discard text enclosed in square brackets (`[ ... ]`) at the lexer level so they never reach the parser.
* **Lexical Error Accumulation:** If an illegal character sequence breaks the Trie path, record the error with line/column coordinates, skip to the next safe boundary (like whitespace), and resume.

### Phase 3: Parser & AST Construction

The Parser consumes the `Iterator[Token]` to build the Abstract Syntax Tree based on the Clime EBNF grammar.

* **AST Node Definitions:** Create Python classes for each major grammar concept: `Rule`, `Condition`, `Action`, `Expression` (including `Literal`, `Reference`, `Operator`, and `FunctionCall`).
* **Recursive Descent Implementation:** Build a recursive descent parsing mechanism to handle standard nested expressions and enforce operator precedence.
* **Syntactic Sugar Identification:** Parse natural language shortcuts (like `x < N < y` or `<target> includes any of <expr>`) into specific AST representation nodes that flag them for unrolling later.
* **Error Synchronization:** Implement an error recovery fallback. If a rule's syntax is invalid, the parser must record the structural error, discard the broken AST branch, and synchronize at the next `climate rule` or `tag rule` keyword to continue building the remaining tree.

### Phase 4: Emitter & JSON-IR Translation

The Emitter transforms the validated AST into the final execution data model required by the Core Daemon.

* **Strict Dictionary Output:** Build the emitter to generate a native Python dictionary structure, explicitly avoiding serialized JSON strings.
* **Node Translation:** Traverse the AST and inject the required `"kind"` identifiers (e.g., `"rule"`, `"literal"`, `"operator"`) into every dictionary node.
* **Operator Mapping:** Map all parsed operators to their strict JSON-IR string codes (e.g., mapping `+` to `"ADD"`, `not` to `"NOT"`).
* **Sugar Unrolling:** Expand the flagged syntactic sugar nodes. For example, unroll chained tag actions (`includes X and excludes Y`) into separate mutation nodes within the rule's `actions` array.

### Phase 5: API Finalization & CLI Wrapping

The final phase locks the public contract and wraps the library for local validation.

* **Library Entry Points:** Expose `parse_clime(source)`, `tokenize(source)`, `parse(tokens)`, and `emit(ast)` as the sole public API functions.
* **CLI Implementation:** Construct the standalone CLI tool as a workspace entry point. Have it read target `.rules` files from disk, pipe the text iterator into `parse_clime`, and format any accumulated `errors` into a human-readable terminal output.

---

Would you like to start by detailing the Trie-based state machine architecture for the Lexer, or should we map out the specific AST Python node classes for the Parser first?