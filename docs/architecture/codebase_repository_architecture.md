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
* **`tools/clime-cli`**: The standalone syntax checker utility. This CLI tool utilizes the parser library for local debugging and CI/CD validation.

---

### Comments & Discussion Points

* **First-Party PEMs**: Should we establish an `apps/pems/` or `libs/pems/` directory within this monorepo for officially supported Pluggable Environment Modules, or will they be strictly developed and maintained in entirely separate repositories?
* **Deployment Configuration**: Do we need a dedicated `deploy/` or `docker/` directory at the root of the workspace to house the Dockerfiles, `docker-compose.yml`, and testing environment configurations mentioned in the Deployment Architecture Document?
* **Global Formatting**: Since `uv` supports it natively, should we define project-wide linting and formatting standards (e.g., Ruff) at the workspace root to ensure consistency across all `apps`, `libs`, and `tools`?
