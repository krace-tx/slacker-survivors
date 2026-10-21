"""命令处理器包。

导入此包会自动注册所有命令处理器。每个子模块通过 ``@command`` 装饰器向 dispatcher 注册处理函数。
导入本包即可完成全部命令的注册，无需手动调用任何 ``register()``。
"""

from . import scene_handler    # noqa: F401
from . import mesh_handler     # noqa: F401
from . import modifier_handler # noqa: F401
from . import material_handler # noqa: F401
from . import camera_handler   # noqa: F401
from . import render_handler   # noqa: F401
