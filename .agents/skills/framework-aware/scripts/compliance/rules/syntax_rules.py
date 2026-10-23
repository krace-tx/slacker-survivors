# -*- coding: utf-8 -*-
"""Godot Headless full GDScript syntax and static type compilation gate (R12)."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Optional

from ..context import WorkspaceContext
from ..models import RuleResult, Violation


def _find_godot_binary() -> Optional[str]:
    env_bin = os.environ.get("GODOT_BIN", "").strip()
    if env_bin and Path(env_bin).is_file():
        return env_bin
    which_bin = shutil.which("godot")
    if which_bin:
        return which_bin
    for cand in (
        "D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe",
        "D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe",
        "/Applications/Godot.app/Contents/MacOS/Godot",
    ):
        if Path(cand).is_file():
            return cand
    return None


def check_gdscript_compilation(ctx: WorkspaceContext) -> RuleResult:
    """R12: Sync global class cache and invoke Godot headless syntax/type compiler."""
    res = RuleResult(
        rule_id="R12",
        title="GDScript Syntax & Static Type Compilation",
        pass_summary="GDScript syntax & static type compilation",
        fail_header="GDScript syntax or static type compilation failed",
    )
    ctx.sync_godot_class_cache()
    godot_bin = _find_godot_binary()
    if not godot_bin:
        res.warnings.append(
            Violation(location="GODOT_BIN", message="Godot binary not found (set GODOT_BIN to enable syntax check)")
        )
        return res

    syntax_script = ctx.script_dir / "check_syntax.gd"
    try:
        proc = subprocess.run(
            [godot_bin, "--headless", "--quit", "--path", str(ctx.root), "-s", str(syntax_script)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=15,
        )
        output_lines = (proc.stdout + "\n" + proc.stderr).splitlines()
        pass_line = next((l for l in output_lines if l.startswith("[SYNTAX_PASS]")), None)
        re_err = re.compile(r"SCRIPT ERROR:|Parse Error:|Compile Error:|\[SYNTAX_FAIL\]")
        err_lines = [l for l in output_lines if re_err.search(l)]
        if proc.returncode == 0 and pass_line and not err_lines:
            count = pass_line.replace("[SYNTAX_PASS]", "").strip()
            res.pass_summary = f"GDScript syntax & static type compilation ({count} scripts verified)"
        else:
            re_detail = re.compile(r"SCRIPT ERROR:|Parse Error:|Compile Error:|\[SYNTAX_FAIL\]|\sat:\s")
            details = [l.strip() for l in output_lines if re_detail.search(l)] or [
                "Compiler exited with non-zero status"
            ]
            for d in details:
                res.errors.append(Violation(location="godot-headless", message=d))
    except subprocess.TimeoutExpired:
        res.errors.append(Violation(location="godot-headless", message="Syntax check timed out after 15s"))
    return res
