# Parser Library & CLI Tooling Design Document

## 1. Overview

This document outlines the architecture and specifications for the shared Python 3 parsing library and its accompanying Command Line Interface (CLI) tool. The primary function of this suite is to process Nomicron climate rules written in the plain-English Clime language (`.rules` files) and translate them into the standardized JSON Intermediate Representation (JSON-IR) expected by the Climatomaton Core Engine.

## 2. Shared Parsing Library Specifications

The core of this system is a dedicated, decoupled Python parsing library responsible for lexing, parsing, and emitting the JSON-IR.

### 2.1 I/O Decoupling Requirement

To ensure maximum portability and reusability across different components, the core library must perform absolutely zero file system I/O operations.

* **Lexing, Parsing, and Emitting:** All internal functions must be designed to accept either static memory objects (such as raw strings, lists of strings, or populated Abstract Syntax Tree objects) or memory-safe iterators yielding the appropriate textual content.
* **Outputs:** The library must return the resulting sequence of tokens, the constructed AST, or the final serialized JSON-IR string respectively, without attempting to write data to disk.

### 2.2 Error Accumulation Strategy

To provide a superior developer experience, the parser must not fast-fail or halt on the first encountered syntax error via standard exceptions.

* **Structured Results:** The parsing pipeline must implement an error recovery strategy, accumulating syntax and lexical errors as it traverses the provided input.
* **Return Object:** The primary parsing functions must return a structured `Result` object containing three primary fields:
  * `success` (boolean): Indicating if the parsing completed without fatal structural errors.
  * `errors` (list): A collection of structured error objects (containing line numbers, column numbers, and specific error messages).
  * `ast` / `json_ir` (object/string): The resulting output, which may be partial or null if parsing failed entirely.

## 3. CLI Tooling Specifications

The standalone CLI tool wraps the shared parsing library to provide local and automated validation capabilities.

### 3.1 Scope and Usage Constraint

**CRITICAL:** The CLI tooling is strictly isolated from the runtime operational architecture. It is **NOT** part of the Pluggable Rules Module (PRM) container, nor is it part of the Core Daemon process. Its use is exclusively reserved for local developer validation of `.rules` files and automated syntax checking within CI/CD workflows.

### 3.2 CLI Architecture

Because the underlying parsing library is strictly I/O agnostic, the CLI tool must implement the necessary file-loading wrappers to read `.rules` source files from disk and pass their contents (or iterators) into the library.

### 3.3 Interface and Exit Codes

To properly integrate with CI/CD pipelines and local terminal workflows, the CLI must adhere to standard execution behaviors:

* **Input Arguments:** Must accept a path to a specific `.rules` file or a directory containing multiple `.rules` files for batch validation.
* **Exit Codes:** Must return a `0` exit code on a fully successful validation pass, and a non-zero exit code (e.g., `1`) if any syntax errors are detected in the provided files.
* **Error Formatting:** Must parse the `errors` list returned by the library's `Result` object and format them into verbose, human-readable terminal output. This output should strictly map errors back to the exact line and column in the source `.rules` file to assist in rapid debugging.

---

### Comments & Discussion Points

* **Dependency Management:** Since this is a dedicated Python 3 utility, we should configure the CLI tool as a direct entry point within the monorepo's `uv` workspace to streamline local testing environments.
* **Lexical Analysis:** Given the Clime language grammar heavily prioritizes plain-English keywords separated by spaces, utilizing Regular Expressions (Regex) for the tokenizer/lexer phase will offer more flexibility and power compared to strict string matching or globbing patterns.
