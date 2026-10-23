# -*- coding: utf-8 -*-
"""Declarative forbidden-pattern rules (R01~R04, R07, R08, R10, R11, R13)."""

from __future__ import annotations

import re
from typing import Tuple

from ..context import WorkspaceContext
from ..models import ForbiddenPatternSpec, RuleFunc, RuleResult, Violation


def make_pattern_checker(spec: ForbiddenPatternSpec) -> RuleFunc:
    def _check(ctx: WorkspaceContext) -> RuleResult:
        res = RuleResult(
            rule_id=spec.rule_id,
            title=spec.title,
            pass_summary=spec.pass_summary,
            fail_header=spec.fail_header,
        )
        for sf in ctx.iter_files(
            prefixes=spec.prefixes,
            exts=spec.exts,
            exclude_paths=spec.exclude_paths,
        ):
            line_stream = (
                sf.code_lines
                if (spec.code_only and sf.ext == ".gd")
                else enumerate(sf.lines, start=1)
            )
            for ln, text in line_stream:
                if spec.ignore_md_tables and sf.ext == ".md" and text.strip().startswith("|"):
                    continue
                if spec.pattern.search(text):
                    v = Violation(location=f"{sf.rel_path}:{ln}", message=text.strip())
                    if spec.as_warning:
                        res.warnings.append(v)
                    else:
                        res.errors.append(v)
        return res

    return _check


DECLARATIVE_PATTERN_SPECS: Tuple[ForbiddenPatternSpec, ...] = (
    ForbiddenPatternSpec(
        rule_id="R01",
        title="Network Facade Convention",
        pass_summary="Network facade convention (App.net)",
        fail_header="Deprecated 'App.network' usage detected (use 'App.net')",
        pattern=re.compile(r"\bApp\.network\b"),
        prefixes=("src/",),
        exts=(".gd",),
    ),
    ForbiddenPatternSpec(
        rule_id="R02",
        title="Singular Domain Path",
        pass_summary="Singular domain path (infra/param/)",
        fail_header="Deprecated plural path 'infra/params/' detected (use 'infra/param/')",
        pattern=re.compile(r"infra/params/"),
        prefixes=("src/", "addons/", "docs/"),
        exts=(".gd", ".md", ".tscn"),
        code_only=False,
    ),
    ForbiddenPatternSpec(
        rule_id="R03",
        title="Plural Asset Container Path",
        pass_summary="Plural asset container path (assets/videos/)",
        fail_header="Deprecated singular path 'assets/video/' detected (use 'assets/videos/')",
        pattern=re.compile(r"assets/video/"),
        prefixes=("src/", "addons/", "docs/"),
        exts=(".gd", ".md", ".tscn"),
        code_only=False,
    ),
    ForbiddenPatternSpec(
        rule_id="R04",
        title="Logger Module Path",
        pass_summary="Logger module path (modules/logger/)",
        fail_header="Deprecated module path 'modules/log/' detected (use 'modules/logger/')",
        pattern=re.compile(r"modules/log/"),
        prefixes=("src/", "addons/", "docs/"),
        exts=(".gd", ".md", ".tscn"),
        code_only=False,
        ignore_md_tables=False,
    ),
    ForbiddenPatternSpec(
        rule_id="R07",
        title="Unidirectional Dependency & Project-Agnostic Framework Boundary",
        pass_summary="Unidirectional & project-agnostic boundary (zero game/test/project-name leaks in framework)",
        fail_header="Reverse dependency or project-specific identifier/path leak inside 'src/framework/' detected",
        pattern=re.compile(r'(?<!`)res://src/(game|test)/|\b(slacker|survivor|SLKE|SLKZ)\b|slacker[_-]survivors|file:///', re.IGNORECASE),
        prefixes=("src/framework/",),
        exts=(".gd", ".md", ".tscn", ".tres"),
        code_only=False,
        ignore_md_tables=False,
    ),
    ForbiddenPatternSpec(
        rule_id="R08",
        title="Explicit Dependency Injection",
        pass_summary="Explicit dependency injection (zero implicit App.xxx in modules/infra/util)",
        fail_header="Implicit 'App.xxx' access inside 'framework/modules|infra|util' (use constructor DI)",
        pattern=re.compile(r"\bApp\."),
        prefixes=("src/framework/modules/", "src/framework/infra/", "src/framework/util/"),
        exts=(".gd",),
    ),
    ForbiddenPatternSpec(
        rule_id="R10",
        title="Facade Boundary Isolation",
        pass_summary="Facade boundary isolation (zero internal impl leaks in src/game/)",
        fail_header="Direct reference to internal 'impl/' class in 'src/game/' (program against 'Base*' facades)",
        pattern=re.compile(
            r"\b(RuntimeManifest|RuntimeServiceHost|RuntimeEnvironment|FrameworkLogger|ClockSystem|"
            r"AssetSystem|AssetCache|ResourceLoaderAdapter|StorageSystem|StorageCache|StorageMigrator|"
            r"MemoryStorageDriver|DiskStorageDriver|RemoteStorageDriver|NetworkClient|RequestQueue|"
            r"AuthSystem|GuestAuthProvider|SteamAuthProvider|AppleAuthProvider|GooglePlayAuthProvider|"
            r"CustomTokenAuthProvider|LocalPassthroughVerifier|RemoteGatewayVerifier|"
            r"SceneRouter|SceneStack|SceneTransition|DisplaySystem|AudioSystem|BgmPlayer|SfxPool|"
            r"LocalizationSystem|TranslationServerAdapter|HapticFeedback|InputSystem|InputDeviceTracker|"
            r"InputRebindCapturer|InputMapAdapter|VideoPlayer|VideoStreamHost|VideoPrewarmer|VideoCacheManager)\b"
        ),
        prefixes=("src/game/",),
        exts=(".gd",),
    ),
    ForbiddenPatternSpec(
        rule_id="R11",
        title="Utility Consolidation",
        pass_summary="Codec, async & spine consolidation (FileCodecUtils / ResourceCodecUtils / TaskScope / SpinePool)",
        fail_header="Deprecated utility usage detected (FileCodecType/ImageFileCodec/Texture2DFileCodec/AsyncUtils/SpineUtils/TimeUtils.wait_safe)",
        pattern=re.compile(
            r"\b(FileCodecType|ImageFileCodec|Texture2DFileCodec|AsyncUtils|SpineUtils)\b|TimeUtils\.wait_safe"
        ),
        prefixes=("src/",),
        exts=(".gd",),
    ),
    ForbiddenPatternSpec(
        rule_id="R13",
        title="Structured Logger Enforcement",
        pass_summary="No raw print() statements found",
        fail_header="Raw print() statements found (prefer App.logger)",
        pattern=re.compile(r"^\s*print\("),
        prefixes=("src/framework/", "src/game/"),
        exts=(".gd",),
        as_warning=True,
    ),
)
