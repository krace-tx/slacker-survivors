# -*- coding: utf-8 -*-
"""Workspace single-pass file loader, GDScript comment lexer, and Godot class cache synchronizer."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Set, Tuple

from .models import SourceFile


class WorkspaceContext:
    """Single-pass in-memory workspace snapshot and index."""

    SCAN_DIRS: Tuple[str, ...] = ("src", "addons", "docs")
    TEXT_EXTS: Set[str] = {".gd", ".md", ".tscn", ".tres"}

    def __init__(self, root: Path, script_dir: Path) -> None:
        self.root = root
        self.script_dir = script_dir
        self.files: Tuple[SourceFile, ...] = self._load_files()
        self.global_classes: Dict[str, str] = self._extract_global_classes()

    @staticmethod
    def strip_gd_comment(line: str) -> str:
        """Strip '#' comments outside single/double-quoted string literals."""
        in_single = False
        in_double = False
        escaped = False
        for idx, ch in enumerate(line):
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == "'" and not in_double:
                in_single = not in_single
            elif ch == '"' and not in_single:
                in_double = not in_double
            elif ch == "#" and not in_single and not in_double:
                return line[:idx]
        return line

    def _load_files(self) -> Tuple[SourceFile, ...]:
        loaded: List[SourceFile] = []
        for folder in self.SCAN_DIRS:
            base = self.root / folder
            if not base.is_dir():
                continue
            for fp in sorted(base.rglob("*")):
                if not fp.is_file() or fp.suffix not in self.TEXT_EXTS:
                    continue
                try:
                    raw = fp.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                lines = tuple(raw.splitlines())
                is_code_asset = fp.suffix in {".gd", ".tscn", ".tres"}
                code_lines: List[Tuple[int, str]] = []
                for ln, text in enumerate(lines, start=1):
                    s = text.strip()
                    if not s or (is_code_asset and s.startswith("#")):
                        continue
                    cleaned = self.strip_gd_comment(text) if fp.suffix == ".gd" else text
                    if cleaned.strip():
                        code_lines.append((ln, cleaned))
                loaded.append(
                    SourceFile(
                        path=fp,
                        rel_path=fp.relative_to(self.root).as_posix(),
                        ext=fp.suffix,
                        raw_text=raw,
                        lines=lines,
                        code_lines=tuple(code_lines),
                    )
                )
        return tuple(loaded)

    def iter_files(
        self,
        prefixes: Sequence[str] = ("src/",),
        exts: Sequence[str] = (".gd",),
        exclude_paths: Sequence[str] = (),
    ) -> Iterable[SourceFile]:
        ext_set = set(exts)
        excl_set = set(exclude_paths)
        for sf in self.files:
            if sf.ext not in ext_set or sf.rel_path in excl_set:
                continue
            if any(sf.rel_path.startswith(p) for p in prefixes):
                yield sf

    def _extract_global_classes(self) -> Dict[str, str]:
        re_class = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)")
        mapping: Dict[str, str] = {}
        for sf in self.iter_files(prefixes=("src/",), exts=(".gd",)):
            for _, line in sf.code_lines[:40]:
                m = re_class.match(line.strip())
                if m:
                    mapping[f"res://{sf.rel_path}"] = m.group(1)
                    break
        return mapping

    def sync_godot_class_cache(self) -> None:
        """Deterministically synchronize .godot/global_script_class_cache.cfg."""
        cache_file = self.root / ".godot" / "global_script_class_cache.cfg"
        if not cache_file.parent.is_dir():
            return

        re_tool = re.compile(r"^@tool\b")
        re_abstract = re.compile(r"^@abstract\b")
        re_class = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)")
        re_extends = re.compile(r"^extends\s+([A-Za-z_][A-Za-z0-9_]*)")

        entries: List[Tuple[str, str, str, str, str]] = []
        for sf in self.iter_files(prefixes=("src/", "addons/"), exts=(".gd",)):
            cls_name = ""
            base_name = "RefCounted"
            is_tool = False
            is_abstract = False
            for _, line in sf.code_lines[:40]:
                s = line.strip()
                if re_tool.match(s):
                    is_tool = True
                elif re_abstract.match(s):
                    is_abstract = True
                else:
                    m_c = re_class.match(s)
                    if m_c:
                        cls_name = m_c.group(1)
                    m_e = re_extends.match(s)
                    if m_e:
                        base_name = m_e.group(1)
            if cls_name:
                entries.append(
                    (
                        cls_name,
                        base_name,
                        "true" if is_abstract else "false",
                        "true" if is_tool else "false",
                        f"res://{sf.rel_path}",
                    )
                )

        entries.sort(key=lambda item: item[0])
        blocks = [
            "{\n"
            f'"base": &"{base}",\n'
            f'"class": &"{cls}",\n'
            '"icon": "",\n'
            f'"is_abstract": {abstract},\n'
            f'"is_tool": {tool},\n'
            '"language": &"GDScript",\n'
            f'"path": "{res_path}"\n'
            "}"
            for cls, base, abstract, tool, res_path in entries
        ]
        new_content = "list=[" + ", ".join(blocks) + "]\n"
        old_content = cache_file.read_text(encoding="utf-8", errors="replace") if cache_file.is_file() else ""
        if old_content != new_content:
            cache_file.write_text(new_content, encoding="utf-8", newline="\n")
