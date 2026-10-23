# -*- coding: utf-8 -*-
"""Asset 3-axis topology, naming grammar, and cross-domain reference checker (R14)."""

from __future__ import annotations

import re
from typing import Dict, Set, Tuple

from ..context import WorkspaceContext
from ..models import RuleResult, Violation


def check_asset_governance(ctx: WorkspaceContext) -> RuleResult:
    """R14: Verify src/assets/ container topology, naming grammar, and module ownership."""
    res = RuleResult(
        rule_id="R14",
        title="Asset Topology, Naming & Ownership",
        pass_summary="Asset topology, naming & ownership",
        fail_header="Asset topology / naming / ownership violations (see src/assets/_doc_assets.md)",
    )
    containers: Dict[str, Tuple[Set[str], Set[str]]] = {
        "textures": (
            {"png", "svg", "webp", "jpg", "jpeg", "exr", "hdr", "tres"},
            {"tex", "spr", "sht", "atl", "ui", "btn", "ico", "fx"},
        ),
        "spines": ({"skel", "spine-json", "atlas", "png", "tres"}, {"spn"}),
        "models": ({"glb", "gltf", "bin"}, {"mdl", "skm"}),
        "materials": ({"tres"}, {"mat", "ptc"}),
        "shaders": ({"gdshader", "gdshaderinc"}, {"shd"}),
        "themes": ({"tres"}, {"thm", "sbx"}),
        "fonts": ({"ttf", "otf", "woff", "woff2", "tres"}, {"fnt"}),
        "audio/bgm": ({"ogg", "mp3"}, {"bgm"}),
        "audio/sfx": ({"wav", "ogg"}, {"sfx"}),
        "audio/vox": ({"ogg", "mp3"}, {"vox"}),
        "audio/amb": ({"ogg"}, {"amb"}),
        "videos": ({"ogv", "mp4", "webm"}, {"vid"}),
    }
    forbidden_tokens = {"final", "new", "old", "copy", "tmp", "temp", "bak", "backup", "test"}
    re_snake = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
    asset_root = ctx.root / "src" / "assets"
    known_domains: Set[str] = set()
    asset_count = 0

    if asset_root.is_dir():
        for fp in sorted(asset_root.rglob("*")):
            if not fp.is_file():
                continue
            name = fp.name
            if (
                name.endswith((".import", ".uid"))
                or name in {".gitkeep", ".gdignore"}
                or (name.startswith("_doc_") and name.endswith(".md"))
            ):
                continue
            asset_count += 1
            rel = fp.relative_to(asset_root).as_posix()
            parts = rel.split("/")
            container, offset = parts[0], 1
            if container == "audio" and len(parts) >= 2:
                container, offset = f"audio/{parts[1]}", 2
            if container not in containers:
                res.errors.append(Violation(location=rel, message=f"Unknown media container '{container}'"))
                continue
            depth = len(parts) - offset
            if depth < 2 or depth > 3:
                res.errors.append(
                    Violation(location=rel, message="Invalid depth (expect <container>/<domain>/[<group>/]<file>)")
                )
                continue
            domain = parts[offset]
            known_domains.add(domain)
            if "." not in name or name.startswith("."):
                res.errors.append(Violation(location=rel, message="Missing file extension"))
                continue
            stem, ext = name.split(".", 1)
            allowed_exts, allowed_prefixes = containers[container]
            if ext not in allowed_exts:
                res.errors.append(
                    Violation(location=rel, message=f"Extension '.{ext}' not allowed in '{container}/'")
                )
                continue
            if not re_snake.match(stem) or len(stem) > 64:
                res.errors.append(Violation(location=rel, message="Stem must be lowercase snake_case <= 64 chars"))
                continue
            tokens = stem.split("_")
            bad_tok = next(
                (t for t in tokens if t in forbidden_tokens or re.match(r"^v\d+$", t) or re.match(r"^\d$", t)),
                None,
            )
            if bad_tok:
                res.errors.append(
                    Violation(location=rel, message=f"Forbidden/invalid token '{bad_tok}' in asset stem")
                )
                continue
            if tokens[0] not in allowed_prefixes:
                res.errors.append(
                    Violation(location=rel, message=f"Prefix '{tokens[0]}_' not allowed in '{container}/'")
                )
                continue
            expected_head = f"{tokens[0]}_{domain}_"
            if not stem.startswith(expected_head) or len(stem) <= len(expected_head):
                res.errors.append(
                    Violation(location=rel, message=f"Name must start with '{expected_head}<subject>'")
                )

        feature_root = ctx.root / "src" / "game" / "features"
        for dom in sorted(known_domains):
            if dom != "shared" and not (feature_root / dom).is_dir():
                res.warnings.append(
                    Violation(location=f"src/assets/*/{dom}", message=f"No matching src/game/features/{dom}/")
                )

    for sf in ctx.iter_files(prefixes=("src/framework/",), exts=(".gd", ".tscn", ".tres")):
        for ln, line in sf.code_lines:
            if "res://src/assets/" in line:
                res.errors.append(
                    Violation(location=f"{sf.rel_path}:{ln}", message="Framework references business asset")
                )

    re_asset_ref = re.compile(r"res://src/assets/([A-Za-z0-9_\-./]+)")
    for sf in ctx.iter_files(prefixes=("src/game/",), exts=(".gd", ".tscn", ".tres")):
        rel_game = sf.rel_path[len("src/game/") :]
        parts = rel_game.split("/")
        allowed_domains = {"shared"}
        if parts[0] == "features" and len(parts) >= 2:
            allowed_domains.add(parts[1])
        for ln, line in sf.code_lines:
            for m in re_asset_ref.finditer(line):
                asset_parts = [p for p in m.group(1).split("/") if p]
                dom_idx = 2 if (asset_parts and asset_parts[0] == "audio") else 1
                if len(asset_parts) <= dom_idx:
                    continue
                dom = asset_parts[dom_idx]
                if dom not in allowed_domains:
                    res.errors.append(
                        Violation(
                            location=f"{sf.rel_path}:{ln}",
                            message=f"Cross-domain asset '{dom}' not in {sorted(allowed_domains)}",
                        )
                    )

    res.pass_summary = f"Asset topology, naming & ownership ({asset_count} assets verified)"
    return res
