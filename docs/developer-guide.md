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
Only one supported installation method is documented here: install `uv` into the project-local virtual environment using pip and pin the version in `dev-requirements.txt`.

Project-local (required for this repository):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r dev-requirements.txt
```

Recommendation: use the project virtual environment and `dev-requirements.txt` so that all developers and CI share the same tool versions.

High-level `uv` usage
----------------------
Each component that should be managed by uv must contain its own project metadata (pyproject.toml), created either by running `uv init` inside that component directory or by adding a pyproject.toml that complies with uv's expectations.

Do not run `uv init` once at the repository root expecting uv to split the repo into multiple projects. Instead create a per-component project for each top-level component you want uv to manage.

Starting a new per-component project

The repository already contains the top-level folders (apps/, libs/, tools/, deploy/). To create a new uv-managed component, run uv init for that component and point it at the desired path. The command will create the component directory if it does not already exist.

PowerShell (single component):

```powershell
# from repository root - create a new app component at apps\<component-dir>
.\.venv\Scripts\uv.exe init --name <component-name> --app apps\<component-dir>
```

Bash / POSIX (single component):

```bash
# from repository root - create a new app component at apps/<component-dir>
.venv/bin/uv init --name <component-name> --app apps/<component-dir>
```

Recommended flag: --no-workspace

To avoid uv attempting workspace discovery or auto-registering the new project immediately, add the --no-workspace flag when running init. This makes the init action safer and reviewable; later, after you have reviewed and committed the generated pyproject.toml, you can run uv sync from the repository root to have uv discover and link workspace members:

```powershell
# init without registering to a workspace immediately
.\.venv\Scripts\uv.exe init --name <component-name> --app --no-workspace apps\<component-dir>

# later, from repo root, discover and link projects
.\.venv\Scripts\uv.exe workspace list
.\.venv\Scripts\uv.exe sync
```

Notes
- Replace --app with --lib for library components.
- Always perform init on a feature branch and review generated files (pyproject.toml, lockfiles) before committing them.
- uv sync will discover any per-component pyproject.toml files and treat them as workspace members even if they were created with --no-workspace.

After each component has a pyproject.toml, inspect the workspace and link or sync components from the repository root:

```powershell
.\.venv\Scripts\uv.exe workspace list
.\.venv\Scripts\uv.exe sync
.\.venv\Scripts\uv.exe workspace metadata
```

Notes
- Creating per-component pyproject files is a one-time, reviewable change — perform these actions on a feature branch, review the generated metadata, and commit if acceptable.
- The `uv sync` command reconciles local workspace members (links packages for local development and updates lockfiles). Record the exact `uv sync` invocation you use here so other contributors can reproduce the environment.

Linting and code quality
------------------------
We use `ruff` as the repository linter. Important policy: DO NOT run any ruff formatting commands that modify source files (for example `ruff format` or `ruff --fix`). The repository enforces check-only linting.

Run lint checks locally with the provided scripts. Use the PowerShell script on Windows and the bash script from a POSIX shell, git-bash, or inside containers.

PowerShell:

```powershell
.\scripts\lint.ps1
```

Bash / POSIX (git-bash, Linux, macOS, or inside containers):

```bash
./scripts/lint.sh
```

Both scripts will activate `.venv` (if present) and run `ruff check .`. They return a non-zero exit code on failure and do not modify files.

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
2. .\scripts\lint.ps1  # ruff check (or ./scripts/lint.sh from a POSIX shell)
3. Run tests (when present)
4. Ensure git status is clean

If CI is configured, ensure your branch passes the CI pipeline before opening a merge/pull request.

Notes and future updates
------------------------
This guide will be updated after the first successful `uv workspace init` run so the exact workspace metadata filenames are recorded. If your `uv` installation behaves differently, please add notes here.
