#!/usr/bin/env python3
"""Generate ass-aliases.sh from nut-aliases.sh (file I/O only)."""
import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "restore", REPO / "scripts" / "restore-ass-migration.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

nut = (REPO / "scripts/lib/nut-aliases.sh").read_text(encoding="utf-8")
out = mod.transform_nut_to_ass(nut)
dest = REPO / "scripts/lib/ass-aliases.sh"
dest.write_text(out, encoding="utf-8")
print(f"Wrote {dest.relative_to(REPO)} ({len(out.splitlines())} lines)")