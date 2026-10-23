# -*- coding: utf-8 -*-
"""Modular architecture compliance engine package for Slacker Survivors."""

from .context import WorkspaceContext
from .models import ForbiddenPatternSpec, RegisteredRule, RuleResult, SourceFile, Violation
from .reporter import render_console_report, render_json_report
from .rules import build_rule_registry, run_rules

__all__ = [
    "ForbiddenPatternSpec",
    "RegisteredRule",
    "RuleResult",
    "SourceFile",
    "Violation",
    "WorkspaceContext",
    "build_rule_registry",
    "render_console_report",
    "render_json_report",
    "run_rules",
]
