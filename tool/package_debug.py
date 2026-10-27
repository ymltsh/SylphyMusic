"""Backward-compatible debug packaging entrypoint; see package_review.py."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).with_name("package_review.py")), run_name="__main__")
