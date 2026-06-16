#!/usr/bin/env bash
# lint.sh - run ruff in check-only mode
set -euo pipefail

if [ -d ".venv" ]; then
  echo "Using .venv python to run ruff"
  .venv/bin/python -m ruff check .
  exit $?
else
  echo "No .venv found; falling back to ruff on PATH"
  ruff check .
  exit $?
fi
