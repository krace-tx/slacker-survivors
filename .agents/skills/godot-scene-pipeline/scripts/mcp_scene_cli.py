#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
Godot MCP Scene Pipeline CLI (Zero-Dependency WebSocket JSON-RPC + Blueprint)
==============================================================================
Connects directly to the project's `addons/godot_mcp` EditorPlugin WebSocket
server (`ws://127.0.0.1:9080`) using pure Python stdlib (RFC 6455), ensuring
100% deterministic `.tscn` creation/editing via Godot's native C++ serializer.

If Godot Editor is not running, `apply` automatically falls back to Headless
Godot (`headless_blueprint_builder.gd` -> `PackedScene.pack()`), NEVER writing
fragile `.tscn` text by hand.

Usage:
  python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py status
  python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py discover
  python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py reload-plugin
  python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py call scene.get_current
  python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py call node.get_tree --params '{"max_depth": 6}'
  python .agents/skills/godot-scene-pipeline/scripts/mcp_scene_cli.py apply blueprint.json
==============================================================================
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9080


def find_godot_binary() -> Optional[str]:
    """Locate Godot 4 console/editor executable from env, PATH, or common Windows paths."""
    env_bin = os.environ.get("GODOT_BIN", "").strip()
    if env_bin and Path(env_bin).exists():
        return env_bin

    for candidate in ("godot4", "godot", "Godot_v4.7.1-stable_win64_console.exe"):
        found = shutil.which(candidate)
        if found:
            return found

    common_paths = [
        Path("D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"),
        Path("D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe"),
        Path("C:/Godot/Godot_v4.7.1-stable_win64_console.exe"),
    ]
    for p in common_paths:
        if p.exists():
            return str(p)
    return None


class MinimalWebSocketClient:
    """RFC 6455 compliant client using pure Python standard library."""

    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    def __init__(self, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT, timeout: float = 10.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self._sock: Optional[socket.socket] = None
        self._req_id = 0

    def connect(self) -> None:
        sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        sock.settimeout(self.timeout)
        raw_key = os.urandom(16)
        ws_key = base64.b64encode(raw_key).decode("ascii")
        handshake = (
            f"GET / HTTP/1.1\r\n"
            f"Host: {self.host}:{self.port}\r\n"
            f"Upgrade: websocket\r\n"
            f"Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {ws_key}\r\n"
            f"Sec-WebSocket-Protocol: json\r\n"
            f"Sec-WebSocket-Version: 13\r\n\r\n"
        )
        sock.sendall(handshake.encode("ascii"))

        header_buf = b""
        while b"\r\n\r\n" not in header_buf:
            chunk = sock.recv(1024)
            if not chunk:
                sock.close()
                raise ConnectionError("EOF during WebSocket HTTP Upgrade handshake")
            header_buf += chunk

        header_text = header_buf.split(b"\r\n\r\n", 1)[0].decode("latin1")
        status_line = header_text.splitlines()[0]
        if "101" not in status_line:
            sock.close()
            raise ConnectionError(f"WebSocket Upgrade rejected: {status_line}")

        expected_accept = base64.b64encode(
            hashlib.sha1((ws_key + self.GUID).encode("ascii")).digest()
        ).decode("ascii")
        if expected_accept not in header_text:
            sock.close()
            raise ConnectionError("Invalid Sec-WebSocket-Accept header")

        self._sock = sock

    def close(self) -> None:
        if self._sock is not None:
            try:
                self._send_frame(0x8, b"")
            except OSError:
                pass
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    def send_text(self, text: str) -> None:
        self._send_frame(0x1, text.encode("utf-8"))

    def recv_text(self) -> str:
        fragments: List[bytes] = []
        while True:
            fin, opcode, payload = self._recv_frame()
            if opcode == 0x8:
                raise ConnectionError("WebSocket closed by Godot MCP server")
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode in (0x0, 0x1, 0x2):
                fragments.append(payload)
                if fin:
                    return b"".join(fragments).decode("utf-8")

    def rpc(self, method: str, params: Optional[Dict[str, Any]] = None) -> Any:
        self._req_id += 1
        req_id = self._req_id
        payload = {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": method,
            "params": params or {},
        }
        self.send_text(json.dumps(payload, ensure_ascii=False))
        raw_resp = self.recv_text()
        resp = json.loads(raw_resp)
        if "error" in resp and resp["error"] is not None:
            err = resp["error"]
            raise RuntimeError(f"MCP RPC Error [{err.get('code')}]: {err.get('message')}")
        return resp.get("result")

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        if self._sock is None:
            raise ConnectionError("WebSocket is not connected")
        mask_key = os.urandom(4)
        length = len(payload)
        header = bytearray([0x80 | (opcode & 0x0F)])
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        header.extend(mask_key)
        masked = bytearray(length)
        for i in range(length):
            masked[i] = payload[i] ^ mask_key[i & 3]
        self._sock.sendall(bytes(header) + bytes(masked))

    def _recv_exact(self, n: int) -> bytes:
        if self._sock is None:
            raise ConnectionError("WebSocket is not connected")
        buf = bytearray()
        while len(buf) < n:
            chunk = self._sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("Unexpected EOF reading WebSocket frame")
            buf.extend(chunk)
        return bytes(buf)

    def _recv_frame(self) -> tuple[bool, int, bytes]:
        b1, b2 = self._recv_exact(2)
        fin = bool(b1 & 0x80)
        opcode = b1 & 0x0F
        masked = bool(b2 & 0x80)
        length = b2 & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(8))[0]
        mask_key = self._recv_exact(4) if masked else b""
        payload = bytearray(self._recv_exact(length))
        if masked:
            for i in range(length):
                payload[i] ^= mask_key[i & 3]
        return fin, opcode, bytes(payload)


def is_mcp_online(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1.0):
            return True
    except OSError:
        return False


def apply_node_spec_via_mcp(client: MinimalWebSocketClient, parent_path: str, spec: Dict[str, Any], is_root: bool = False) -> str:
    """Recursively apply a declarative node specification over Godot MCP RPC."""
    if is_root:
        node_path = "."
    else:
        node_name = str(spec.get("name", "Node")).strip()
        instance_path = str(spec.get("instance", "")).strip()
        if instance_path:
            res = client.rpc("node.instantiate_scene", {
                "parent_path": parent_path,
                "scene_path": instance_path,
                "node_name": node_name,
            })
            node_path = res["node_path"]
        else:
            node_type = str(spec.get("type", "Node")).strip()
            res = client.rpc("node.create", {
                "parent_path": parent_path,
                "node_type": node_type,
                "node_name": node_name,
            })
            node_path = res["node_path"]

    if not is_root and spec.get("script"):
        client.rpc("script.attach", {
            "node_path": node_path,
            "script_path": str(spec["script"]),
        })

    if not is_root and spec.get("unique_name"):
        client.rpc("node.set_unique_name", {
            "node_path": node_path,
            "enabled": bool(spec["unique_name"]),
        })

    if spec.get("anchor_preset"):
        preset_cfg = spec["anchor_preset"]
        if isinstance(preset_cfg, str):
            client.rpc("ui.set_anchor_preset", {
                "node_path": node_path,
                "preset": preset_cfg,
                "keep_offsets": False,
            })
        elif isinstance(preset_cfg, dict):
            client.rpc("ui.set_anchor_preset", {
                "node_path": node_path,
                "preset": str(preset_cfg.get("preset", "full_rect")),
                "keep_offsets": bool(preset_cfg.get("keep_offsets", False)),
            })

    if spec.get("size_flags") and isinstance(spec["size_flags"], dict):
        sf = spec["size_flags"]
        client.rpc("ui.set_size_flags", {
            "node_path": node_path,
            "horizontal": str(sf.get("horizontal", "")),
            "vertical": str(sf.get("vertical", "")),
        })

    if spec.get("theme_overrides") and isinstance(spec["theme_overrides"], dict):
        for category, items in spec["theme_overrides"].items():
            if isinstance(items, dict):
                for item_name, val in items.items():
                    client.rpc("ui.set_theme_override", {
                        "node_path": node_path,
                        "override_type": str(category),
                        "name": str(item_name),
                        "value": val,
                    })

    if spec.get("properties") and isinstance(spec["properties"], dict):
        for prop_name, prop_val in spec["properties"].items():
            client.rpc("node.update_property", {
                "node_path": node_path,
                "property": str(prop_name),
                "value": prop_val,
            })

    for child_spec in spec.get("children", []):
        if isinstance(child_spec, dict):
            apply_node_spec_via_mcp(client, node_path, child_spec, is_root=False)

    return node_path


def apply_blueprint_via_mcp(host: str, port: int, blueprint: Dict[str, Any]) -> Dict[str, Any]:
    client = MinimalWebSocketClient(host, port)
    client.connect()
    try:
        scene_path = str(blueprint["scene_path"]).strip()
        base_scene_path = str(blueprint.get("base_scene_path", "")).strip()
        root_spec: Dict[str, Any] = blueprint.get("root", {})

        client.rpc("scene.create", {
            "path": scene_path,
            "root_node_type": str(root_spec.get("type", "Node")),
            "root_node_name": str(root_spec.get("name", "")),
            "base_scene_path": base_scene_path,
            "root_script": str(root_spec.get("script", "")),
        })

        apply_node_spec_via_mcp(client, ".", root_spec, is_root=True)

        for sig in blueprint.get("signals", []):
            if isinstance(sig, dict):
                client.rpc("signal.connect", {
                    "source_node": str(sig["source"]),
                    "signal_name": str(sig["signal"]),
                    "target_node": str(sig.get("target", ".")),
                    "method_name": str(sig["method"]),
                    "persist": bool(sig.get("persist", True)),
                })

        save_res = client.rpc("scene.save", {"path": scene_path})
        return {
            "channel": "godot_mcp_live",
            "scene_path": save_res.get("scene_path", scene_path),
            "status": "ok",
        }
    finally:
        client.close()


def apply_blueprint_headless(repo_root: Path, blueprint_path: Path) -> Dict[str, Any]:
    godot_bin = find_godot_binary()
    if not godot_bin:
        raise RuntimeError("Godot binary not found (set GODOT_BIN or open Godot Editor with MCP)")

    builder_gd = Path(__file__).resolve().parent / "headless_blueprint_builder.gd"
    cmd = [
        godot_bin,
        "--headless",
        "--path",
        str(repo_root),
        "-s",
        str(builder_gd),
        "--",
        f"--blueprint={blueprint_path.resolve()}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45)
    if proc.returncode != 0:
        raise RuntimeError(f"Headless blueprint build failed (exit {proc.returncode}):\n{proc.stdout}\n{proc.stderr}")

    return {
        "channel": "headless_packed_scene_fallback",
        "output": proc.stdout.strip(),
        "status": "ok",
    }


def reload_mcp_plugin(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> Dict[str, Any]:
    """Safely schedule a deferred reload of `addons/godot_mcp` inside the running Editor."""
    client = MinimalWebSocketClient(host, port)
    client.connect()
    reload_code = """
var base := EditorInterface.get_base_control()
var timer := base.get_tree().create_timer(0.15)
timer.timeout.connect(func() -> void:
	EditorInterface.set_plugin_enabled("godot_mcp", false)
	EditorInterface.set_plugin_enabled("godot_mcp", true)
)
result = "scheduled"
"""
    try:
        client.rpc("editor.eval", {"code": reload_code})
    finally:
        client.close()

    time.sleep(0.8)
    for _ in range(10):
        if is_mcp_online(host, port):
            verify = MinimalWebSocketClient(host, port)
            verify.connect()
            try:
                cmds = verify.rpc("rpc.discover")
                return {
                    "reloaded": True,
                    "command_count": len(cmds) if isinstance(cmds, list) else 0,
                }
            finally:
                verify.close()
        time.sleep(0.3)
    raise RuntimeError("Godot MCP server did not come back online on port 9080 after reload")


def main() -> int:
    parser = argparse.ArgumentParser(description="Godot MCP Scene Pipeline CLI")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)

    sub = parser.add_subparsers(dest="subcommand", required=True)

    sub.add_parser("status", help="Check Godot MCP connection & current editor state")
    sub.add_parser("discover", help="List all registered Godot MCP RPC commands")
    sub.add_parser("reload-plugin", help="Hot-reload addons/godot_mcp inside the running Godot Editor")

    call_p = sub.add_parser("call", help="Invoke a single Godot MCP JSON-RPC method")
    call_p.add_argument("method", help="RPC method name (e.g. scene.open, node.get_tree, save_scene)")
    call_p.add_argument("--params", default="{}", help="JSON object string of parameters")
    call_p.add_argument("--params-file", default="", help="Path to JSON file containing parameters")

    apply_p = sub.add_parser("apply", help="Build and save a .tscn from a declarative JSON blueprint")
    apply_p.add_argument("blueprint", help="Path to blueprint JSON file")
    apply_p.add_argument("--force-headless", action="store_true", help="Force Headless PackedScene fallback")

    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[4]

    try:
        if args.subcommand == "status":
            online = is_mcp_online(args.host, args.port)
            if not online:
                print(json.dumps({"online": False, "endpoint": f"ws://{args.host}:{args.port}"}, indent=2))
                return 0
            client = MinimalWebSocketClient(args.host, args.port)
            client.connect()
            try:
                proj = client.rpc("project.info")
                state = client.rpc("editor.state")
                print(json.dumps({
                    "online": True,
                    "endpoint": f"ws://{args.host}:{args.port}",
                    "project": proj,
                    "editor": state,
                }, ensure_ascii=False, indent=2))
            finally:
                client.close()
            return 0

        if args.subcommand == "discover":
            client = MinimalWebSocketClient(args.host, args.port)
            client.connect()
            try:
                cmds = client.rpc("rpc.discover")
                print(json.dumps(cmds, ensure_ascii=False, indent=2))
            finally:
                client.close()
            return 0

        if args.subcommand == "reload-plugin":
            res = reload_mcp_plugin(args.host, args.port)
            print(json.dumps(res, ensure_ascii=False, indent=2))
            return 0

        if args.subcommand == "call":
            if args.params_file:
                params = json.loads(Path(args.params_file).read_text(encoding="utf-8"))
            else:
                params = json.loads(args.params)
            client = MinimalWebSocketClient(args.host, args.port)
            client.connect()
            try:
                res = client.rpc(args.method, params)
                print(json.dumps(res, ensure_ascii=False, indent=2))
            finally:
                client.close()
            return 0

        if args.subcommand == "apply":
            bp_path = Path(args.blueprint).resolve()
            bp_data = json.loads(bp_path.read_text(encoding="utf-8"))
            if not args.force_headless and is_mcp_online(args.host, args.port):
                res = apply_blueprint_via_mcp(args.host, args.port, bp_data)
            else:
                res = apply_blueprint_headless(repo_root, bp_path)
            print(json.dumps(res, ensure_ascii=False, indent=2))
            return 0

    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
