"""`poe build` runs dbt seed followed by dbt run against Databricks.

Connection values are loaded from `.env` (gitignored; see `.env.example`)
by `dbt_runner.py`, which acts as the single entrypoint for every dbt CLI
call in this repo. This keeps secrets out of the shell and out of chat.

This script only orchestrates `seed` then `run`. Tests and docs are
separate poe tasks (`poe test`, `poe docs`).
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNNER = ROOT / "dbt_runner.py"

for subcommand in ("seed", "run"):
    result = subprocess.run(["python", str(RUNNER), subcommand])
    if result.returncode != 0:
        sys.exit(result.returncode)
