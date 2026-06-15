# Codebase & Repository Architecture Document: Climatomaton

## 1. Repository Hosting and Language Stack

The Climatomaton project is structured as a centralized monorepo hosted on Codeberg. All core applications, background processes, and shared libraries within this repository are developed using Python 3.

## 2. Build System and Package Management

To manage the monorepo architecture and dependencies efficiently, the project utilizes `uv` as its primary build and environment management tool.

* **`uv` vs `hatch**`: While `hatch` is an officially endorsed PyPA project and fantastic for generic package building, `uv` (built by Astral) is recommended for this specific multi-component project.
* **Performance and Workspace Support**: `uv` acts as an ultra-fast, drop-in replacement for `pip`, `venv`, and `pip-tools` written in Rust. Crucially, `uv` recently introduced Cargo-style "workspace" support.
* **Local Linking**: This workspace support allows us to define the Parser Library, the PRM, and the Core Engine as separate packages within the same repository. It seamlessly links them together locally without needing to publish the internal library to a PyPI index or wrangle complex local file references in standard `pyproject.toml` configurations.

## 3. Monorepo Organization

The monorepo defines a unified workspace layout that clearly separates concerns between the parsing logic, the core systems, and developer tooling. The standard structure is as follows:

* **`libs/clime-parser`**: The shared Python parsing library. It translates plain-English Clime (`.rules`) source files into compiled JSON-IR.
* **`apps/core-daemon`**: The main Climatomaton Discord engine. This houses the central application wrapper, event bus, and rules engine.
* **`apps/git-prm`**: The standalone Git-Fetch container process. This serves as the primary Pluggable Rules Module, fetching rules from an external source and placing them onto the shared IPC volume.
* **`apps/pems`**: An initially empty directory serving as a dedicated drop-in location for first-party Pluggable Environment Modules (PEMs).
* **`tools/clime-cli`**: The standalone syntax checker utility. This CLI tool utilizes the parser library for local debugging and CI/CD validation.

## 4. Deployment Configuration Organization

Given the monorepo structure, which houses multiple distinct applications alongside shared libraries, the project will utilize a dedicated `deploy/` directory at the repository root.

* **Justification:** A dedicated directory keeps the repository root clean of infrastructure boilerplate. More importantly, because our deployment relies on an orchestration layer to mount a shared volume across multiple containers (the Core Daemon, PRM, and PEMs), placing the orchestration files (e.g., `docker-compose.yml`) and environment templates in a centralized location provides a single, unified source of truth for the entire integrated system, rather than scattering these multi-container configurations across individual app directories.

## 5. Linting and Code Standards

The project enforces a strict separation between code linting and code formatting:

* **Global Linting:** The project will utilize **Ruff** for code linting. Because Ruff is developed by Astral—the same organization behind our chosen build tool, `uv`—it integrates seamlessly into the workflow. Ruff provides exceptionally fast, comprehensive Python linting out-of-the-box and can be easily configured via the workspace root to strictly verify conventions across all components.
* **No Automated Formatting:** The use of automated code formatters is strictly prohibited. Developers retain full manual control over the visual structure and formatting of their Python source code. Ruff's formatting capabilities will remain explicitly disabled in the configuration.

---

### Comments & Discussion Points

* **Build Workflow:** You asked if this is the right place to talk about the build workflow. Yes, high-level build execution steps (e.g., how the `uv` workspace commands are chained, how local environments are bootstrapped, or how the Docker images are built from the monorepo) fit perfectly into this document. However, if you are referring specifically to automated CI/CD pipelines (like Codeberg CI actions for running tests and linters on push), we might want to either add a dedicated "CI/CD & Automation Workflow" section here or branch it into its own smaller document. Let me know how deep you want to detail the build workflow!
* **Pending Updates List:** You asked why I added the Codebase & Repository Architecture document back into the pending updates. That was an oversight on my part! I carried the entire pending list over verbatim from the previous state without removing the item we were actively working on. Good catch. I have successfully removed it from the list below.
