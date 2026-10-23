# -*- coding: utf-8 -*-
"""Unified rule registry assembler (R01 ~ R16)."""

from __future__ import annotations

import time
from typing import Dict, List, Optional, Sequence, Set, Tuple

from ..context import WorkspaceContext
from ..models import RegisteredRule, RuleResult
from .architecture_rules import (
    check_display_video_ui_decoupling,
    check_global_class_references,
    check_module_dependency_manifests,
    check_shared_three_pillar_architecture,
)
from .asset_rules import check_asset_governance
from .pattern_rules import DECLARATIVE_PATTERN_SPECS, make_pattern_checker
from .sandbox_rules import check_sandbox_persistence
from .syntax_rules import check_gdscript_compilation


def build_rule_registry() -> Tuple[RegisteredRule, ...]:
    by_id: Dict[str, RegisteredRule] = {
        spec.rule_id: RegisteredRule(spec.rule_id, spec.title, make_pattern_checker(spec))
        for spec in DECLARATIVE_PATTERN_SPECS
    }
    domain_rules = (
        RegisteredRule("R05", "Display & Video Layer UI Decoupling", check_display_video_ui_decoupling),
        RegisteredRule("R06", "Shared 3-Pillar Architecture & DAG", check_shared_three_pillar_architecture),
        RegisteredRule("R09", "Core Module Dependency Manifests", check_module_dependency_manifests),
        RegisteredRule("R12", "GDScript Syntax & Static Type Compilation", check_gdscript_compilation),
        RegisteredRule("R14", "Asset Topology, Naming & Ownership", check_asset_governance),
        RegisteredRule("R15", "Global Class Reference", check_global_class_references),
        RegisteredRule("R16", "Sandbox Persistence Topology & Tier-2 Ownership", check_sandbox_persistence),
    )
    for r in domain_rules:
        by_id[r.rule_id] = r
    return tuple(by_id[k] for k in sorted(by_id.keys()))


def run_rules(
    ctx: WorkspaceContext,
    rules: Sequence[RegisteredRule],
    only_rules: Optional[Set[str]] = None,
    skip_syntax: bool = False,
) -> List[RuleResult]:
    results: List[RuleResult] = []
    for rule in rules:
        if only_rules and rule.rule_id.upper() not in only_rules:
            continue
        if skip_syntax and rule.rule_id == "R12":
            continue
        t0 = time.perf_counter()
        res = rule.fn(ctx)
        res.elapsed_ms = (time.perf_counter() - t0) * 1000.0
        results.append(res)
    return results
