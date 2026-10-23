#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
Framework Compliance CLI Entrypoint (Slacker Survivors)
==============================================================================
Thin CLI entrypoint delegating to the modular `compliance/` package.

Usage:
  python .agents/skills/framework-aware/scripts/check_compliance.py
  python .agents/skills/framework-aware/scripts/check_compliance.py --skip-syntax
  python .agents/skills/framework-aware/scripts/check_compliance.py --rule R14 --rule R16
  python .agents/skills/framework-aware/scripts/check_compliance.py --list-rules
  python .agents/skills/framework-aware/scripts/check_compliance.py --json
==============================================================================
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

from compliance import (
    WorkspaceContext,
    build_rule_registry,
    render_console_report,
    render_json_report,
    run_rules,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Slacker Survivors Architecture Compliance Engine")
    parser.add_argument("--rule", action="append", help="Run only specific rule ID(s), e.g., --rule R14 --rule R16")
    parser.add_argument("--skip-syntax", action="store_true", help="Skip Godot headless GDScript syntax compilation")
    parser.add_argument("--list-rules", action="store_true", help="List all registered compliance rules and exit")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON diagnostic report")
    args = parser.parse_args()

    rules = build_rule_registry()
    if args.list_rules:
        for r in rules:
            print(f"{r.rule_id}  {r.title}")
        return 0

    script_dir = Path(__file__).resolve().parent
    root = script_dir.parents[3]
    ctx = WorkspaceContext(root=root, script_dir=script_dir)

    only_set = {rid.strip().upper() for rid in args.rule} if args.rule else None
    results = run_rules(ctx, rules, only_rules=only_set, skip_syntax=args.skip_syntax)

    if args.json:
        return render_json_report(root, results)
    return render_console_report(root, results)


if __name__ == "__main__":
    sys.exit(main())
