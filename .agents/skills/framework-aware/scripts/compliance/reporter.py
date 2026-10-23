# -*- coding: utf-8 -*-
"""Decoupled ANSI console and JSON diagnostic report formatters."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Sequence

from .models import RuleResult


def render_console_report(root: Path, results: Sequence[RuleResult]) -> int:
    c_cyan, c_green, c_red, c_yellow, c_reset = (
        "\033[0;36m",
        "\033[0;32m",
        "\033[0;31m",
        "\033[1;33m",
        "\033[0m",
    )
    print(f"{c_cyan}[Framework-Aware] Scanning architecture compliance: {root}{c_reset}")
    print(f"{c_cyan}--------------------------------------------------------{c_reset}")

    total_errors = 0
    total_warnings = 0

    for r in results:
        if r.errors:
            print(f"{c_red}[FAIL] [{r.rule_id}] {r.fail_header or r.title}:{c_reset}")
            for err in r.errors:
                print(f"{c_red}       - {err.location} -> {err.message}{c_reset}")
            total_errors += len(r.errors)
        elif not r.warnings:
            print(f"{c_green}[PASS] [{r.rule_id}] {r.pass_summary}{c_reset}")

        if r.warnings:
            for w in r.warnings:
                print(f"{c_yellow}[WARN] [{r.rule_id}] {w.location} -> {w.message}{c_reset}")
            total_warnings += len(r.warnings)

    total_ms = sum(r.elapsed_ms for r in results)
    print(f"{c_cyan}--------------------------------------------------------{c_reset}")
    if total_errors == 0:
        print(
            f"{c_green}[OK] All {len(results)} compliance checks passed "
            f"({total_errors} errors, {total_warnings} warnings, {total_ms:.0f} ms){c_reset}"
        )
        return 0
    print(
        f"{c_red}[ERROR] Compliance check failed "
        f"({total_errors} errors, {total_warnings} warnings, {total_ms:.0f} ms){c_reset}"
    )
    return 1


def render_json_report(root: Path, results: Sequence[RuleResult]) -> int:
    total_errors = sum(len(r.errors) for r in results)
    total_warnings = sum(len(r.warnings) for r in results)
    payload = {
        "workspace": str(root),
        "passed": total_errors == 0,
        "error_count": total_errors,
        "warning_count": total_warnings,
        "total_elapsed_ms": round(sum(r.elapsed_ms for r in results), 2),
        "rules": [
            {
                "rule_id": r.rule_id,
                "title": r.title,
                "passed": r.passed,
                "elapsed_ms": round(r.elapsed_ms, 2),
                "errors": [{"location": e.location, "message": e.message} for e in r.errors],
                "warnings": [{"location": w.location, "message": w.message} for w in r.warnings],
            }
            for r in results
        ],
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if total_errors == 0 else 1
