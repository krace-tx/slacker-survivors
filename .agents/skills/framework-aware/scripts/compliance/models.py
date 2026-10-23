# -*- coding: utf-8 -*-
"""Domain models for the Slacker Survivors architecture compliance engine."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Callable, List, Pattern, Tuple

if TYPE_CHECKING:
    from .context import WorkspaceContext


@dataclass(frozen=True)
class Violation:
    location: str
    message: str


@dataclass
class RuleResult:
    rule_id: str
    title: str
    pass_summary: str
    fail_header: str = ""
    errors: List[Violation] = field(default_factory=list)
    warnings: List[Violation] = field(default_factory=list)
    elapsed_ms: float = 0.0

    @property
    def passed(self) -> bool:
        return len(self.errors) == 0


@dataclass(frozen=True)
class SourceFile:
    path: Path
    rel_path: str
    ext: str
    raw_text: str
    lines: Tuple[str, ...]
    code_lines: Tuple[Tuple[int, str], ...]  # (1-based line_no, code without trailing # comment)


RuleFunc = Callable[["WorkspaceContext"], RuleResult]


@dataclass(frozen=True)
class RegisteredRule:
    rule_id: str
    title: str
    fn: RuleFunc


@dataclass(frozen=True)
class ForbiddenPatternSpec:
    rule_id: str
    title: str
    pass_summary: str
    fail_header: str
    pattern: Pattern[str]
    prefixes: Tuple[str, ...] = ("src/",)
    exts: Tuple[str, ...] = (".gd",)
    exclude_paths: Tuple[str, ...] = ()
    code_only: bool = True
    ignore_md_tables: bool = True
    as_warning: bool = False
