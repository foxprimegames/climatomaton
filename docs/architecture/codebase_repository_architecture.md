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

When organizing Docker-related build files and deployment configurations, the following approaches and their respective trade-offs must be considered:

* **Dedicated `deploy/` or `docker/` directory:**
* *Pros:* Keeps the repository root clean. Centralizes orchestration files (e.g., `docker-compose.yml`), container definitions, and deployment scripts into a single, easily discoverable location.
* *Cons:* Can complicate Docker build contexts. If a Dockerfile resides in a subdirectory but requires access to the entire monorepo workspace (e.g., `uv` workspace files), the build command must be explicitly run from the repository root, passing the specific Dockerfile path.


* **Application-level or Root-level Dockerfiles:**
* *Pros:* Simplifies the Docker build context. The Dockerfile sits directly adjacent to the application or workspace it defines.
* *Cons:* Scatters deployment configuration across the repository. Orchestration files and environment scripts can clutter the root directory or obscure application logic within subdirectories.



## 5. Linting and Code Standards

The project enforces a strict separation between code linting and code formatting:

* **Global Linting:** A workspace-wide linting standard will be defined at the repository root to ensure code quality, catch syntax errors, and maintain standard Python conventions across all components.
* **No Automated Formatting:** The use of automated code formatters is strictly prohibited. Developers retain full manual control over the visual structure and formatting of their Python source code.

---

### Comments & Discussion Points

* **Deployment Directory Decision:** Now that the pros and cons of the Docker build file organization are documented, do you want to officially adopt one of these approaches for the monorepo layout, or leave it as an open decision for a later phase?
* **Linting Tooling:** Do you have a preferred linter in mind (e.g., Ruff's linter without the formatter, Flake8) that we should explicitly name in the document, or should it remain generic for now?
