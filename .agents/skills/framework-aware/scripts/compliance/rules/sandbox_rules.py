# -*- coding: utf-8 -*-
"""Sandbox persistence (user://) topology and Tier-2 STORAGE_DOMAIN ownership checker (R16)."""

from __future__ import annotations

import re

from ..context import WorkspaceContext
from ..models import RuleResult, Violation


def check_sandbox_persistence(ctx: WorkspaceContext) -> RuleResult:
    """R16: Enforce zero raw user:// literals in game layer & 1:1 STORAGE_DOMAIN ownership."""
    res = RuleResult(
        rule_id="R16",
        title="Sandbox Persistence Topology & Tier-2 Ownership",
        pass_summary="Sandbox persistence topology & Tier-2 domain ownership (user:// & StorageItem)",
        fail_header="Sandbox persistence topology & Tier-2 domain violations",
    )
    for sf in ctx.iter_files(prefixes=("src/game/",), exts=(".gd", ".tscn", ".tres")):
        for ln, line in sf.code_lines:
            if '"user://' in line or "'user://" in line:
                res.errors.append(
                    Violation(
                        location=f"{sf.rel_path}:{ln}",
                        message="Raw 'user://' literal in game layer (use StorageItem.for_config / for_save)",
                    )
                )

    re_construct = re.compile(r"\bStorageItem\.(new|for_config|for_save)\s*\(")
    re_domain = re.compile(r'const\s+STORAGE_DOMAIN(?:\s*:\s*StringName)?\s*=\s*&"([^"]+)"')
    re_model_path = re.compile(r"(^|/)model/(.+/)?[a-z0-9_]+_model\.gd$")

    for sf in ctx.iter_files(prefixes=("src/game/",), exts=(".gd",)):
        rel_game = sf.rel_path[len("src/game/") :]
        parts = rel_game.split("/")
        is_model = bool(re_model_path.search(rel_game))
        for ln, line in sf.code_lines:
            if not is_model and re_construct.search(line):
                res.errors.append(
                    Violation(location=f"{sf.rel_path}:{ln}", message="StorageItem constructed outside *_model.gd")
                )
            m_dom = re_domain.search(line)
            if m_dom:
                declared = m_dom.group(1)
                expected = (
                    "shared"
                    if parts[0] == "shared"
                    else (parts[1] if parts[0] == "features" and len(parts) >= 2 else "")
                )
                if expected and declared != expected:
                    res.errors.append(
                        Violation(
                            location=f"{sf.rel_path}:{ln}",
                            message=f"Tier-2 STORAGE_DOMAIN mismatch (expected '&\"{expected}\"', got '&\"{declared}\"')",
                        )
                    )
    return res
