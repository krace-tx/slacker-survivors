#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
Godot Scene Visual Preview & Multimodal Verification Runner
==============================================================================
Captures deterministic PNG snapshots of Godot `.tscn` scenes so the AI Agent
can inspect real rendered layouts via `read_file` (multimodal vision loop).

Supported Modes:
  1. `editor-2d` / `editor-3d` / `editor-node`:
     Captures live viewport/node screenshot directly via Godot MCP (`127.0.0.1:9080`).
  2. `runtime` (Default):
     Renders any `.tscn` via Godot `--write-movie` across one or more target
     resolutions (e.g. `1920x1080,1280x720`) and optionally runs `audit_scene.gd`.

Usage:
  python .agents/skills/godot-scene-pipeline/scripts/capture_scene_preview.py \
      --scene res://src/test/inventory/inventory_test.tscn \
      --out-dir scratch/previews \
      --resolutions 1920x1080,1280x720 \
      --audit
==============================================================================
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from mcp_scene_cli import MinimalWebSocketClient, find_godot_binary, is_mcp_online  # noqa: E402


def run_structural_audit(godot_bin: str, repo_root: Path, scene_path: str) -> Dict[str, Any]:
    audit_gd = SCRIPT_DIR / "audit_scene.gd"
    cmd = [
        godot_bin,
        "--headless",
        "--path",
        str(repo_root),
        "-s",
        str(audit_gd),
        "--",
        f"--scene={scene_path}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45)
    raw = proc.stdout.strip()
    start_idx = raw.find("{")
    if start_idx >= 0:
        try:
            return json.loads(raw[start_idx:])
        except json.JSONDecodeError:
            pass
    return {
        "status": "PASS" if proc.returncode == 0 else "FAIL",
        "raw_output": raw,
        "stderr": proc.stderr.strip(),
    }


def capture_runtime_frames(
    godot_bin: str,
    repo_root: Path,
    scene_path: str,
    out_dir: Path,
    resolutions: List[str],
    frames: int,
) -> List[Dict[str, Any]]:
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = Path(scene_path).stem
    captures: List[Dict[str, Any]] = []

    for res_str in resolutions:
        clean_res = res_str.strip().lower()
        if "x" not in clean_res:
            continue
        base_png = out_dir / f"{stem}_{clean_res}.png"
        for old_file in glob.glob(str(out_dir / f"{stem}_{clean_res}*.png")):
            try:
                os.remove(old_file)
            except OSError:
                pass

        cmd = [
            godot_bin,
            "--path",
            str(repo_root),
            "--resolution",
            clean_res,
            "--fixed-fps",
            "60",
            "--quit-after",
            str(max(2, frames)),
            "--write-movie",
            str(base_png),
            scene_path,
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
        generated = sorted(glob.glob(str(out_dir / f"{stem}_{clean_res}*.png")))
        final_frame = ""
        if generated:
            last_png = Path(generated[-1])
            canonical = out_dir / f"{stem}_{clean_res}_preview.png"
            shutil.copyfile(last_png, canonical)
            for g in generated:
                try:
                    os.remove(g)
                except OSError:
                    pass
            final_frame = str(canonical.resolve())

        captures.append({
            "resolution": clean_res,
            "exit_code": proc.returncode,
            "image_path": final_frame,
        })

    return captures


def capture_editor_mcp(
    mode: str,
    scene_path: str,
    node_path: str,
    out_dir: Path,
    host: str,
    port: int,
) -> Dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = Path(scene_path).stem if scene_path else "editor_viewport"
    target_png = (out_dir / f"{stem}_{mode}.png").resolve()

    client = MinimalWebSocketClient(host, port)
    client.connect()
    try:
        if scene_path:
            client.rpc("scene.open", {"path": scene_path})
        if mode == "editor-3d":
            res = client.rpc("viewport.capture_3d", {
                "viewport_index": 0,
                "save_path": str(target_png).replace("\\", "/"),
                "return_base64": False,
            })
        elif mode == "editor-node":
            res = client.rpc("viewport.capture_node", {
                "node_path": node_path or ".",
                "save_path": str(target_png).replace("\\", "/"),
                "return_base64": False,
            })
        else:
            res = client.rpc("viewport.capture_2d", {
                "save_path": str(target_png).replace("\\", "/"),
                "return_base64": False,
            })
        return {
            "mode": mode,
            "image_path": str(target_png),
            "width": res.get("width", 0),
            "height": res.get("height", 0),
        }
    finally:
        client.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture Godot scene previews & run structural audit")
    parser.add_argument("--scene", required=True, help="Scene path (e.g. res://src/test/inventory/inventory_test.tscn)")
    parser.add_argument("--out-dir", required=True, help="Directory to store output PNG screenshots")
    parser.add_argument(
        "--mode",
        choices=["runtime", "editor-2d", "editor-3d", "editor-node"],
        default="runtime",
        help="Capture mode (default: runtime via --write-movie)",
    )
    parser.add_argument("--node-path", default=".", help="Node path when --mode=editor-node")
    parser.add_argument("--resolutions", default="1920x1080", help="Comma-separated resolutions for runtime mode")
    parser.add_argument("--frames", type=int, default=3, help="Frames to render before snapshot in runtime mode")
    parser.add_argument("--audit", action="store_true", help="Also run audit_scene.gd structural gate")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9080)
    args = parser.parse_args()

    repo_root = SCRIPT_DIR.parents[3]
    out_dir = Path(args.out_dir).resolve()
    result_payload: Dict[str, Any] = {"scene": args.scene}

    godot_bin = find_godot_binary()
    if args.audit:
        if not godot_bin:
            print(json.dumps({"error": "Godot binary not found for --audit"}), file=sys.stderr)
            return 1
        audit_res = run_structural_audit(godot_bin, repo_root, args.scene)
        result_payload["audit"] = audit_res

    if args.mode.startswith("editor-"):
        if not is_mcp_online(args.host, args.port):
            print(json.dumps({"error": f"Godot MCP is offline at ws://{args.host}:{args.port}"}), file=sys.stderr)
            return 1
        result_payload["editor_capture"] = capture_editor_mcp(
            args.mode, args.scene, args.node_path, out_dir, args.host, args.port
        )
    else:
        if not godot_bin:
            print(json.dumps({"error": "Godot binary not found for runtime capture"}), file=sys.stderr)
            return 1
        res_list = [r.strip() for r in args.resolutions.split(",") if r.strip()]
        result_payload["runtime_captures"] = capture_runtime_frames(
            godot_bin, repo_root, args.scene, out_dir, res_list, args.frames
        )

    print(json.dumps(result_payload, ensure_ascii=False, indent=2))
    if args.audit and result_payload.get("audit", {}).get("status") == "FAIL":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
