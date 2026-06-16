# Developer Guide

This document describes how to set up a local development environment for the Climatomaton monorepo, how to run linting and basic checks, and the recommended workflows for using `uv` and other development tooling.

Prerequisites
-------------
- Git
- Python 3.11 or later (3.11+ recommended)
- Docker (optional, required only for validating deployment templates)
- PowerShell (Windows) or a POSIX shell (Linux/macOS)

Recommended local environment (reproducible)
-------------------------------------------
We recommend creating a project-local virtual environment and installing pinned dev dependencies via `dev-requirements.txt`.

Example (PowerShell):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r dev-requirements.txt
```

`dev-requirements.txt` contains the development CLI tools used by contributors (uv, ruff, etc.). See the repository root for the file.

Installing `uv`
----------------
Two common approaches exist:

- Project-local (recommended for reproducibility): install `uv` into the `.venv` used above via `pip install uv` and pin the version in `dev-requirements.txt`.
- Global CLI via `pipx` (useful if you prefer single-user CLI installs):

```powershell
python -m pip install --user pipx
python -m pipx ensurepath
pipx install uv
```

Recommendation: use the project virtual environment and `dev-requirements.txt` so that all developers share the same tool versions and so CI can reproduce the environment.

Recommended uv minimum version
-------------------------------
Use the latest stable release in the 0.9.x range (or the latest stable version at time of setup). The pinned version is listed in `dev-requirements.txt`.

High-level `uv` usage (placeholder)
-----------------------------------
This is a new repository. Once `uv` is installed in your environment, initialize the workspace from the repository root:

```powershell
# from repo root
uv workspace init

# inspect the files created by uv and record them in this guide
uv workspace info  # if available
```

`uv sync` is (in many uv implementations) used to link components and keep workspace state up-to-date. Because `uv` implementations can vary, record the exact outputs of `uv workspace init` here once you run it and we will update this guide.

Linting and code quality
------------------------
We use `ruff` as the repository linter. Important policy: DO NOT run any ruff formatting commands that modify source files (for example `ruff format` or `ruff --fix`). The repository enforces check-only linting.

Run lint checks locally with the provided script:

PowerShell:

```powershell
.\scripts\lint.ps1
```

This script will activate `.venv` (if present) and run `ruff check .`. It returns a non-zero exit code on failure and does not modify files.

Pre-commit and CI
-----------------
CI must run `ruff check .` and fail on any diagnostics. Do not run `ruff format` or `ruff --fix` in CI.

Optional: Install a local Git hook that runs `ruff check .` prior to commit. If you add such a hook, ensure it only runs `ruff check` and that it fails the commit when diagnostics are present. Consider also validating that no tracked files changed after checks complete (to detect accidental formatting).

Linting enforcement notes
------------------------
Ruff does not provide a configuration setting that disables its formatting subcommands; therefore the repository relies on policy and CI enforcement. Recommended controls:

- Provide scripts for common operations (scripts/lint.ps1) and document their use.
- Use CI to run `ruff check .` and fail builds on issues.
- Optionally provide a Git pre-commit hook or a `.pre-commit-config.yaml` that runs ruff in check-only mode.

Build and deploy validation
---------------------------
Deployment manifests live in `deploy/`. The repository enforces a no-inbound-ports policy; all services should avoid `ports:` entries and communicate via the shared IPC volume.

You can validate the base compose file if Docker is available:

```powershell
docker compose -f deploy/docker-compose.yml config
```

Commit checklist
----------------
Before committing, run:

1. Activate .venv and install dev requirements (if needed)
2. .\scripts\lint.ps1  # ruff check
3. Run tests (when present)
4. Ensure git status is clean

If CI is configured, ensure your branch passes the CI pipeline before opening a merge/pull request.

Notes and future updates
------------------------
This guide will be updated after the first successful `uv workspace init` run so the exact workspace metadata filenames are recorded. If your `uv` installation behaves differently, please add notes here.
