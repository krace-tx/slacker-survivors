"""Blender MCP 项目的共享常量定义。"""

# TCP 传输默认配置（严格限定本地回环地址，杜绝局域网未授权访问）
DEFAULT_HOST: str = "127.0.0.1"
DEFAULT_PORT: int = 9876

# Socket 单次读取缓冲区大小
BUFFER_SIZE: int = 65536

# Addon 侧发送超时（秒）：非阻塞 socket 发送大报文时临时切换为阻塞模式
SEND_TIMEOUT: float = 5.0

# Bridge 命令超时（渲染等重操作耗时较久，需比常规 socket 超时更长）
BRIDGE_TIMEOUT: float = 120.0
CONNECT_TIMEOUT: float = 5.0

# Blender 定时器轮询间隔（秒）
POLL_INTERVAL: float = 0.05

# 每次轮询最多处理的报文数，避免单帧阻塞 Blender UI 过久
MAX_MESSAGES_PER_POLL: int = 16
