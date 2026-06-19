You make good points. Streamlining the labels to just the repo-level components will keep the issue tracker much cleaner, and dropping the CLI tasks keeps this plan strictly focused on the library itself.

To answer your question: **A Trie (pronounced "try") is a standard computer science data structure**, also known as a prefix tree. It is not a third-party library. It is widely used in lexical analysis because it is incredibly efficient at character-by-character evaluation. You feed it characters one at a time from your buffer, and it traverses the tree branches. When a branch dead-ends, you know you've found the longest possible valid token (the maximal munch principle). It's much safer and more performant for stream iterators than trying to run complex regular expressions against partial string chunks.

Regarding the testing framework: `behave` (and Gherkin syntax in general) is fantastic for high-level business logic and defining how the Core Daemon evaluates a completed state. However, for a low-level parsing library, **`pytest` is generally the industry standard and highly recommended.** Lexers and parsers require hundreds of tiny, granular tests (e.g., feeding a string like `1 + 2 * 3` and asserting the exact tree shape). `pytest` shines here because its `@pytest.mark.parametrize` decorator allows you to write one test function and feed it hundreds of input/output tuples, keeping your test files incredibly clean. I've added the test setup to Milestone 1, but the final choice of framework is yours.

Here is the revised implementation plan, strictly scoped to the parser library, with updated labels, corrected file references, and comprehensive testing tasks.

---

### Milestone 1: Library Foundation & Interface Contracts

**Description:** Establish the parsing library within the `uv` workspace, define the public API contracts, setup the test framework, and lay down the base data structures.

* **Task: Initialize `comp/parser_library` workspace package**
  * **Description:** Create the dedicated, I/O-agnostic parser library package within the `uv` monorepo. Expose the primary `parse_clime`, `tokenize`, `parse`, and `emit` functions as empty stubs.
  * **Labels:** `comp/build system`, `comp/repo`, `comp/parser_library`, `type/architecture`
* **Task: Define parsing Result and Token schemas**
  * **Description:** Implement the `BaseResult`, `ASTResult`, and `IRResult` classes to handle error accumulation without fast-failing. Implement the `__str__` and `__repr__` magic methods on all interface types.
  * **Labels:** `comp/parser_library`, `type/architecture`
* **Task: Initialize Testing Framework & CI hooks**
  * **Description:** Install and configure the chosen testing framework within the `uv` workspace. Create the base directory structure for unit tests and define the initial test runner script to ensure CI integration is ready.
  * **Labels:** `comp/build system`, `comp/parser_library`, `type/architecture`

### Milestone 2: Lexical Analyzer (Lexer)

**Description:** Build the state machine responsible for processing the raw text of `.rules` files into a discrete stream of tokens.

* **Task: Implement Trie-based character buffer & state machine**
  * **Description:** Build the lexer to accept an `Iterator[str]`. Implement a custom prefix tree (Trie) to process tokens using the maximal munch principle, safely handling tokens split across yielded string chunks. Ensure the lexer correctly captures dot-separated identifier syntax for generic `NamespacePath` resolution.
  * **Labels:** `comp/parser_library`, `type/feature`
* **Task: Implement comment stripping and whitespace handling**
  * **Description:** Add logic to identify and safely discard all `[ ... ]` comments at the lexer level so they are never passed to the parser.
  * **Labels:** `comp/parser_library`, `type/feature`
* **Task: Implement lexical error accumulation**
  * **Description:** If the character buffer yields no valid token match, register a structured lexical error with line/column coordinates in the `errors` list, and skip forward to the next whitespace boundary to resume processing.
  * **Labels:** `comp/parser_library`, `type/bug` (Handling), `type/feature`
* **Task: Lexer Test Suite Implementation**
  * **Description:** Write full-coverage parameterized unit tests validating token generation against the definitions in `rules_language_reference.md`. Ensure specific coverage for fragmented string chunk ingestion and lexical error recovery.
  * **Labels:** `comp/parser_library`, `type/feature`

### Milestone 3: Abstract Syntax Tree (AST) & Parser

**Description:** Construct the recursive descent parser to consume the token stream and build the AST in accordance with the Clime EBNF grammar.

* **Task: Define AST Python node classes**
  * **Description:** Create Python classes representing the exact EBNF grammar nodes defined in `rules_language_reference.md`.
  * **Labels:** `comp/parser_library`, `type/architecture`
* **Task: Implement recursive descent expression parsing**
  * **Description:** Build the parser logic to handle standard mathematical and logical expressions, strictly enforcing operator precedence as outlined in `rules_language_reference.md`.
  * **Labels:** `comp/parser_library`, `type/feature`
* **Task: Parse Clime syntactic sugar constructs**
  * **Description:** Implement parsing logic to capture natural language shortcuts (e.g., `x < N < y`, `includes any of`) into specific AST nodes flagged for unrolling later.
  * **Labels:** `comp/parser_library`, `type/feature`
* **Task: Implement rule-boundary error synchronization**
  * **Description:** Implement the error recovery fallback. If syntax errors occur within a rule, record the error in the `ASTResult`, discard the broken branch, and synchronize at the next `climate rule` or `tag rule` keyword to continue parsing subsequent rules.
  * **Labels:** `comp/parser_library`, `type/feature`
* **Task: Parser Test Suite Implementation**
  * **Description:** Write full-coverage parameterized unit tests feeding mocked token streams into the parser. Assert correct AST structural construction, correct operator precedence, and successful error synchronization upon encountering malformed rules.
  * **Labels:** `comp/parser_library`, `type/feature`

### Milestone 4: JSON-IR Emitter

**Description:** Build the Emitter pipeline to translate the validated AST into the strict JSON-IR dictionary structure required by the Core Daemon.

* **Task: Build AST-to-Dictionary traversal engine**
  * **Description:** Implement the `emit()` function to recursively traverse the AST and generate the native Python dictionary output, injecting the explicit `"kind"` and `"datatype"` structural properties into every node.
  * **Labels:** `comp/parser_library`, `type/architecture`, `type/feature`
* **Task: Map operators to strict JSON-IR codes**
  * **Description:** Map standard operators from the AST to their standardized JSON-IR string codes (e.g., `+` to `"ADD"`, `not` to `"NOT"`).
  * **Labels:** `comp/parser_library`, `type/feature`
* **Task: Implement syntactic sugar unrolling**
  * **Description:** Expand the AST's flagged sugar nodes during emission. E.g., unroll chained tag actions (`includes X and excludes Y`) into separate, distinct mutation nodes within the rule's `actions` array.
  * **Labels:** `comp/parser_library`, `type/feature`
* **Task: Emitter Test Suite Implementation**
  * **Description:** Write full-coverage unit tests feeding manually constructed AST nodes into the emitter. Assert the output dictionaries strictly conform to the Draft 2020-12 schema defined in `rules_intermediate_representation_design_doc.md`.
  * **Labels:** `comp/parser_library`, `type/feature`

---

Which testing framework would you like to lock in for the Milestone 1 setup task?