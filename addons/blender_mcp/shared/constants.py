"""Blender MCP 项目的共享常量定义。"""

# TCP 服务器默认配置
DEFAULT_HOST: str = "127.0.0.1"
DEFAULT_PORT: int = 9876

# Socket 配置
SOCKET_TIMEOUT: float = 10.0
BUFFER_SIZE: int = 65536

# Bridge 命令超时（比 Socket 超时更长，因为渲染等重操作耗时更久）
BRIDGE_TIMEOUT: float = 30.0

# 连接健康检测
HEARTBEAT_INTERVAL: float = 5.0
RECONNECT_DELAY: float = 2.0
MAX_RECONNECT_ATTEMPTS: int = 5

# Blender 定时器轮询间隔（秒）
POLL_INTERVAL: float = 0.05

# Blender 插件标识符
ADDON_BL_IDNAME: str = "blender_mcp"
