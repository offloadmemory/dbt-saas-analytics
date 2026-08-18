"""`poe build` runs dbt seed followed by dbt run.

This lives as a script so `build.seed` and `build.run` can also be invoked
as standalone tasks (used by CI).
"""
import subprocess
import sys

for cmd in (["dbt", "seed"], ["dbt", "run"]):
    result = subprocess.run(cmd)
    if result.returncode != 0:
        sys.exit(result.returncode)
