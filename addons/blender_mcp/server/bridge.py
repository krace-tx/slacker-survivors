"""Blender Addon TCP 桥接客户端。

提供异步 TCP 客户端 :class:`BlenderBridge`，通过 JSON-RPC 2.0
协议与 Blender Addon 的 Socket 服务器通信。使用换行符分隔的
JSON 作为消息帧。
"""
from __future__ import annotations

import asyncio
import json
import uuid
from typing import Any

from blender_mcp.shared.constants import BRIDGE_TIMEOUT, DEFAULT_HOST, DEFAULT_PORT


class BlenderBridge:
    """异步 TCP 客户端，连接 Blender Addon 的 Socket 服务器。

    通过 TCP 连接发送 JSON-RPC 2.0 命令并接收响应。
    使用换行符分隔的 JSON 作为消息帧。
    """

    def __init__(
        self,
        host: str = DEFAULT_HOST,
        port: int = DEFAULT_PORT,
        timeout: float = BRIDGE_TIMEOUT,
    ) -> None:
        self._host = host
        self._port = port
        self._timeout = timeout
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None

    @property
    def is_connected(self) -> bool:
        """检查 TCP 连接是否处于打开状态。"""
        return self._writer is not None and not self._writer.is_closing()

    async def connect(self) -> bool:
        """建立到 Blender Addon 的 TCP 连接。

        Returns:
            连接成功返回 True，否则返回 False。
        """
        try:
            self._reader, self._writer = await asyncio.wait_for(
                asyncio.open_connection(self._host, self._port),
                timeout=self._timeout,
            )
            return True
        except (ConnectionRefusedError, asyncio.TimeoutError, OSError):
            self._reader = None
            self._writer = None
            return False

    async def disconnect(self) -> None:
        """关闭 TCP 连接。"""
        if self._writer:
            try:
                self._writer.close()
                await self._writer.wait_closed()
            except Exception:
                pass
            finally:
                self._writer = None
                self._reader = None

    async def ensure_connected(self) -> bool:
        """确保连接处于活跃状态，必要时重新连接。

        Returns:
            连接已活跃（或重连成功）返回 True，无法建立连接返回 False。
        """
        if self.is_connected:
            return True
        return await self.connect()

    async def send_command(
        self, method: str, params: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """向 Blender 发送命令并等待响应。

        Args:
            method: 命令方法名（例如 ``'mesh.add_primitive'``）。
            params: 命令参数。

        Returns:
            Blender 返回的结果字典。

        Raises:
            ConnectionError: 无法建立连接或连接断开。
            TimeoutError: Blender 在配置的超时时间内未响应。
            RuntimeError: Blender 返回了 JSON-RPC 错误响应。
        """
        if not await self.ensure_connected():
            raise ConnectionError(
                "Cannot connect to Blender. Make sure Blender is running "
                "and the MCP addon server is started (N panel > MCP > Start Server)."
            )

        request_id = str(uuid.uuid4())
        request = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params or {},
        }

        try:
            # 发送换行符分隔的 JSON
            message = json.dumps(request) + "\n"
            self._writer.write(message.encode("utf-8"))  # type: ignore[union-attr]
            await self._writer.drain()  # type: ignore[union-attr]

            # 接收换行符分隔的 JSON 响应
            response_line = await asyncio.wait_for(
                self._reader.readline(),  # type: ignore[union-attr]
                timeout=self._timeout,
            )

            if not response_line:
                await self.disconnect()
                raise ConnectionError("Blender disconnected unexpectedly")

            response: dict[str, Any] = json.loads(response_line.decode("utf-8"))

            # 检查 JSON-RPC 错误
            if "error" in response:
                error = response["error"]
                raise RuntimeError(
                    f"Blender error [{error.get('code', 'unknown')}]: "
                    f"{error.get('message', 'Unknown error')}"
                )

            return response.get("result", {})

        except asyncio.TimeoutError:
            await self.disconnect()
            raise TimeoutError(
                f"Blender did not respond within {self._timeout}s"
            )
        except (ConnectionResetError, BrokenPipeError):
            await self.disconnect()
            raise ConnectionError("Lost connection to Blender")

    async def ping(self) -> bool:
        """检查 Blender 是否正在响应。

        Returns:
            如果 Blender 返回 ``"pong"`` 状态则为 True，否则为 False。
        """
        try:
            result = await self.send_command("system.ping")
            return result.get("status") == "pong"
        except Exception:
            return False
