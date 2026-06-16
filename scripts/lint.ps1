param(
	[switch]$Ci
)

# Prefer running ruff via the project venv python to avoid relying on script activation (execution policy may prevent .ps1 activation).
if (Test-Path ".venv\Scripts\python.exe") {
	Write-Host "Using .venv python to run ruff"
	.\.venv\Scripts\python.exe -m ruff check .
	exit $LASTEXITCODE
} else {
	Write-Host "No .venv python found; falling back to ruff on PATH. Ensure ruff is installed."
	ruff check .
	exit $LASTEXITCODE
}
