# -*- coding: utf-8 -*-
"""Structural & architectural boundary rules (R05, R06, R09, R15)."""

from __future__ import annotations

import re

from ..context import WorkspaceContext
from ..models import RuleResult, Violation


def check_display_video_ui_decoupling(ctx: WorkspaceContext) -> RuleResult:
    """R05: Ensure framework display & video modules contain no business UI dialog/toast/overlay scripts."""
    res = RuleResult(
        rule_id="R05",
        title="Display & Video Layer UI Decoupling",
        pass_summary="Display & Video layer decoupling (zero hardcoded UI overlays/dialogs in framework)",
        fail_header="Business UI dialog/toast/overlay scripts found in 'framework/modules/display|video'",
    )
    re_ui_script = re.compile(r"(dialog|modal|toast|overlay)", re.IGNORECASE)
    for sf in ctx.iter_files(
        prefixes=("src/framework/modules/display/", "src/framework/modules/video/"),
        exts=(".gd",),
    ):
        if re_ui_script.search(sf.path.name):
            res.errors.append(Violation(location=sf.rel_path, message="Forbidden UI script in framework module"))
    return res


def check_shared_three_pillar_architecture(ctx: WorkspaceContext) -> RuleResult:
    """R06: Enforce src/game/shared/ 3-pillar layout (model/service/component) and zero upward deps."""
    res = RuleResult(
        rule_id="R06",
        title="Shared 3-Pillar Architecture & DAG",
        pass_summary="Shared 3-pillar architecture (model/service/component & zero upward deps)",
        fail_header="Shared kernel architecture or upward dependency violation",
    )
    re_legacy = re.compile(r"shared/(define|components|models|constants|events|msvp)/")
    for sf in ctx.iter_files(prefixes=("src/", "docs/"), exts=(".gd", ".md", ".tscn")):
        for ln, text in enumerate(sf.lines, start=1):
            if sf.ext == ".md" and text.strip().startswith("|"):
                continue
            if re_legacy.search(text):
                res.errors.append(
                    Violation(
                        location=f"{sf.rel_path}:{ln}",
                        message=f"Legacy shared path (use shared/model|service|component/): {text.strip()}",
                    )
                )

    re_upward = re.compile(r"res://src/game/(features|bootstrap)/")
    for sf in ctx.iter_files(
        prefixes=("src/game/shared/",),
        exts=(".gd",),
        exclude_paths=("src/game/shared/model/config/game_scenes.gd",),
    ):
        for ln, line in sf.code_lines:
            if re_upward.search(line):
                res.errors.append(
                    Violation(
                        location=f"{sf.rel_path}:{ln}",
                        message=f"Upward dependency to features/ or bootstrap/: {line.strip()}",
                    )
                )
    return res


def check_module_dependency_manifests(ctx: WorkspaceContext) -> RuleResult:
    """R09: Verify all 15 core modules declare MODULE_ID, REQUIRED_MODULES, and OPTIONAL_MODULES."""
    module_impls = (
        "env/impl/runtime_environment.gd",
        "logger/impl/framework_logger.gd",
        "clock/impl/clock_system.gd",
        "asset/impl/asset_system.gd",
        "input/impl/input_system.gd",
        "haptic/impl/haptic_feedback.gd",
        "network/impl/network_client.gd",
        "auth/impl/auth_system.gd",
        "storage/impl/storage_system.gd",
        "locale/impl/localization_system.gd",
        "scene/impl/scene_router.gd",
        "display/impl/display_system.gd",
        "cursor/impl/cursor_system.gd",
        "audio/impl/audio_system.gd",
        "video/impl/video_player.gd",
    )
    total = len(module_impls)
    res = RuleResult(
        rule_id="R09",
        title="Core Module Dependency Manifests",
        pass_summary=f"Core module dependency manifests ({total}/{total} modules verified)",
        fail_header="Core module dependency manifest violation",
    )
    required_consts = ("MODULE_ID", "REQUIRED_MODULES", "OPTIONAL_MODULES")
    for rel_mod in module_impls:
        full_path = ctx.root / "src" / "framework" / "modules" / rel_mod
        if not full_path.is_file():
            res.errors.append(Violation(location=rel_mod, message="Missing core module implementation file"))
            continue
        text = full_path.read_text(encoding="utf-8", errors="replace")
        missing = [c for c in required_consts if not re.search(rf"const\s+{c}\b", text)]
        if missing:
            res.errors.append(
                Violation(location=rel_mod, message=f"Missing manifest constant(s): {', '.join(missing)}")
            )
    return res


def check_global_class_references(ctx: WorkspaceContext) -> RuleResult:
    """R15: Forbid redundant preload/load aliases of scripts that already declare class_name."""
    res = RuleResult(
        rule_id="R15",
        title="Global Class Reference",
        pass_summary="Global class reference (zero redundant preload aliases of class_name scripts)",
        fail_header="Redundant script preload/load alias of a global class_name (reference the class directly)",
    )
    re_load = re.compile(r'\b(?:pre)?load\(\s*"(res://src/[^"]+\.gd)"\s*\)')
    for sf in ctx.iter_files(prefixes=("src/",), exts=(".gd",)):
        for ln, line in sf.code_lines:
            for m in re_load.finditer(line):
                target = m.group(1)
                if target in ctx.global_classes:
                    res.errors.append(
                        Violation(
                            location=f"{sf.rel_path}:{ln}",
                            message=f"Use global '{ctx.global_classes[target]}' instead of loading '{target}'",
                        )
                    )
    return res
