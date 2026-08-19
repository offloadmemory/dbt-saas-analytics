"""Single-entry wrapper around the dbt CLI.

Why this exists: `profiles.yml` reads the four DBT_DATABRICKS_* values from
env vars, and we want those to live in `.env` (gitignored) rather than the
caller's shell. This wrapper:

  1. Loads `.env` from the project root into `os.environ`.
  2. Re-execs the dbt CLI with whatever args were passed through.

Re-exec (rather than subprocess) means dbt sees exactly the env it would see
if the user had `export`-ed the variables themselves — no surprises with
PYTHONPATH / cwd / signal handling.

Usage:
    python dbt_runner.py seed
    python dbt_runner.py run --select +fct_won_deals
    python dbt_runner.py test
    python dbt_runner.py docs generate

The script refuses to run if `.env` is missing AND any of the four required
vars are unset, so silent-fail misconfigurations surface immediately.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

REQUIRED_VARS = (
    "DBT_DATABRICKS_HOST",
    "DBT_DATABRICKS_HTTP_PATH",
    "DBT_DATABRICKS_TOKEN",
    "DBT_DATABRICKS_CATALOG",
)


def main() -> int:
    project_root = Path(__file__).resolve().parent
    env_file = project_root / ".env"

    if env_file.exists():
        # `override=False` so a real shell-set value still wins if present.
        load_dotenv(env_file, override=False)
    else:
        # No .env file: that's fine if the caller already exported the vars
        # in their shell. We just check below that the required ones are set.
        pass

    missing = [v for v in REQUIRED_VARS if not os.environ.get(v)]
    if missing:
        print(
            f"dbt_runner: missing required env vars: {', '.join(missing)}",
            file=sys.stderr,
        )
        print(
            "  Set them in `.env` (see `.env.example`) or export them in your shell.",
            file=sys.stderr,
        )
        return 78  # EX_CONFIG — dbt hasn't been called yet, surface as a config error.

    if len(sys.argv) < 2:
        print("usage: dbt_runner.py <dbt subcommand> [args...]", file=sys.stderr)
        return 2

    os.execvp("dbt", ["dbt", *sys.argv[1:]])
    # execvp never returns on success.
    return 1  # pragma: no cover


if __name__ == "__main__":
    sys.exit(main())
