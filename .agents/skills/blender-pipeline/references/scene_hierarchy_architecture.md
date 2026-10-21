# Skill Wiki · Blender 工程化层级架构与场景图设计规范 (Scene Hierarchy Architecture)

> 📖 **Wiki 定位**：彻底终结 AI 编写 Blender 脚本时常见的**「全扁平对象汤（Flat Object Soup）」**与**「无脑全合并单网格（Monolithic Joined Mesh）」**两大工程反模式。建立从 **Blender Outliner 集合树 (`bpy.data.collections`)** 到 **Object 父子场景图 (`obj.parent`)** 再到 **Godot 4 `Node3D` 节点树** 的 1:1 工业级映射规范。

---

## 一、 为什么要严禁「扁平化 Hierarchy」？

在 glTF 2.0 规范中，**Blender 里的 Object 父子层级（`obj.parent`）会 1:1 原生导出为 Godot 4 的 `Node3D` 场景树节点**。如果脚本把几十个网格全部平铺在根层级（`parent = None`），或者在末尾把所有部件粗暴 `bpy.ops.object.join()` 成唯一一个死 Mesh，会导致严重的工程后果：

| 扁平化反模式 | 导致的工程灾难 | 工程化树状层级（Hierarchical Design）收益 |
| :--- | :--- | :--- |
| **反模式 A：扁平对象汤**<br>（几十个 `Cube`/`Cylinder` 直接平铺在 `Scene Collection` 根下） | Outliner 无法折叠审阅；导出时极易把布尔切割盒、参考高模、摄影棚灯光误打包进 `.glb`；在 Godot 中展开就是上百个无序同级节点。 | 通过 **3~4 层语义化父子树（`ROOT ➔ GRP/ZONE/PIVOT ➔ MSH`）** 组织，Godot 侧可按功能区开关、按枢轴驱动旋转、按组做 LOD 与视锥裁剪。 |
| **反模式 B：无脑全合并单网格**<br>（把角色身体、头发、眼镜、衣服、手中咖啡杯全部 `join()` 成一个 Mesh） | 无法在游戏运行期换装或显隐配饰；无法对面部单独做 BlendShapes（形态键）；手持道具与眼镜受蒙皮插值影响容易软化变形。 | 角色按**「解剖/换装逻辑域」分层子网格**（共享同一 `Armature` 修改器），刚性挂件通过 **`SOCKET_*` 骨骼插槽** 挂载，支持运行期零成本换装与挂载武器/道具。 |
| **反模式 C：无枢轴（Pivot）死道具**<br>（转椅、显示器、带门柜子全是世界原点下的静态块） | 游戏内无法让椅子上半身独立旋转、无法让屏幕俯仰、无法让柜门绕合页开合。 | 引入 **`PIVOT_*` 空物体转轴层**，将可动部件挂载于局部原点位于物理转轴的 `PIVOT_*` 节点下，引擎一行代码即可驱动局部旋转。 |

---

## 二、 双维工程化层级架构（Collections × Scene Graph）

一个规范的 Blender 工程必须同时具备 **「横向隔离的集合树（Collection Tree）」** 与 **「纵向嵌套的父子变换树（Parent-Child Scene Graph）」**。

### 维度 1：Outliner 集合树规范（工程管理与导出隔离）

严禁将对象直接留在默认的 `Scene Collection` 根下。所有脚本必须使用 `bpy.data.collections` 构建如下三层隔离集合：

```text
Scene Collection
└── COL_Asset_<AssetName>                  # [工程总包集合]
    ├── 01_Export_Hierarchy                # [导出层] ✅ 唯一参与导出 .glb 的集合
    │   ├── COL_Rig_And_Sockets            # 骨架 (ARM_*) 与骨骼挂点插槽 (SOCKET_*)
    │   └── COL_Render_Meshes              # 最终游戏运行态网格树 (ROOT_* -> GRP_* -> MSH_*)
    ├── 02_Work_Helpers                    # [工作辅助层] 🚫 hide_render=True，严禁导出
    │   ├── COL_HighPoly_Sources           # AI 3D 扩散原始百万面高模（供 Shrinkwrap / Normal Bake 读取）
    │   ├── COL_Boolean_Cutters            # 硬表面布尔切割器 (CUT_*, display_type='WIRE')
    │   └── COL_GeoNodes_Prototypes        # Geometry Nodes 实例化源件 (PROTO_*, 如单枚鳞片、单簇叶片)
    └── 03_Studio_LookDev                  # [摄影棚照明层] 🚫 仅用于离线质检渲染，严禁导出
        ├── COL_Studio_Lights              # Key / Fill / Rim 面光与环境光
        └── COL_Studio_Cameras             # Front / Side / Iso34 检视相机与无影背景板
```

---

### 维度 2：Object 父子场景图规范（按资产类型的 3~4 层树状拓扑）

所有需要导出到 Godot 4 的对象，必须挂载在唯一的顶层根节点 `ROOT_<AssetName>`（`EMPTY` 对象，`empty_display_type = 'PLAIN_AXES'`，世界坐标 `(0, 0, 0)`）之下，形成**单根多级树（Single-Root Multi-Tier Tree）**：

#### 1. 角色资产场景图（Character Hierarchy —— 4 层结构）
```text
ROOT_Char_<Name>                           # [L0 资产总根] Empty (0, 0, 0), Facing -Y
└── ARM_Char_<Name>                        # [L1 骨架根] Armature
    ├── GRP_Char_Anatomy                   # [L2 解剖主体组] Empty
    │   ├── MSH_<Name>_Head                # [L3 网格] 头部与五官基底（独立材质与表情形态键）
    │   ├── MSH_<Name>_Body                # [L3 网格] 躯干与四肢有机网格
    │   └── MSH_<Name>_Hair                # [L3 网格] 主发团、刘海与呆毛网格
    ├── GRP_Char_Outfit                    # [L2 模块化服饰组] Empty（支持按节点显隐换装）
    │   ├── MSH_<Name>_Top_Shirt           # [L3 网格] 上装衬衫/外套
    │   ├── MSH_<Name>_Bottom_Pants        # [L3 网格] 下装西裤/裙装
    │   ├── MSH_<Name>_Neck_Tie            # [L3 网格] 领带与领结
    │   └── MSH_<Name>_Shoes_LR            # [L3 网格] 鞋履
    ├── GRP_Char_Hardsurface_Gear          # [L2 硬表面装备组] Empty
    │   └── MSH_<Name>_Armor_Shoulders     # [L3 网格] 挂载非破坏性修改器栈/几何节点的护甲
    └── [L2 骨骼刚性插槽 Sockets —— parent_type='BONE']
        ├── SOCKET_Head_Glasses            # [L2 插槽] 绑定至 Head 骨骼
        │   └── MSH_<Name>_Glasses         # [L3 刚性附件] 眼镜框与镜片（无需蒙皮权重，零畸变）
        ├── SOCKET_Chest_Badge             # [L2 插槽] 绑定至 Spine/Tie_Bone 骨骼
        │   └── MSH_<Name>_IDBadge         # [L3 刚性附件] 胸前工牌
        └── SOCKET_Hand_R                  # [L2 插槽] 绑定至 Forearm_R / Hand_R 骨骼
            └── MSH_Prop_CoffeeCup         # [L3 手持道具] 咖啡杯/武器（Godot 内可动态替换子节点）
```

#### 2. 单体道具资产场景图（Prop Hierarchy —— 3 层动静分离结构）
```text
ROOT_Prop_<PropName>                       # [L0 道具总根] Empty, 底部中心 (0, 0, 0), Facing -Y
├── GRP_<Prop>_StaticBase                  # [L1 静态基座组] Empty
│   ├── MSH_<Prop>_Base_Primary            # [L2 网格] 70% 大轮廓底座（如人体工学椅五星脚架+气压杆）
│   └── MSH_<Prop>_Base_Casters            # [L2 网格] 20% 次级结构（如 5 组万向轮）
├── PIVOT_<Prop>_UpperSwivel               # [L1 活动枢轴] Empty, 原点位于旋转/升降中心 (0, 0, 0.45)
│   ├── MSH_<Prop>_Seat_Cushion            # [L2 网格] 随枢轴旋转的座垫
│   ├── MSH_<Prop>_Backrest_Mesh           # [L2 网格] 网布靠背与腰托
│   ├── PIVOT_<Prop>_Armrest_L             # [L2 二级枢轴] 左扶手调节轴
│   │   └── MSH_<Prop>_Armrest_Pad_L       # [L3 网格] 左扶手垫
│   └── PIVOT_<Prop>_Armrest_R             # [L2 二级枢轴] 右扶手调节轴
│       └── MSH_<Prop>_Armrest_Pad_R       # [L3 网格] 右扶手垫
└── SOCKET_<Prop>_TopPlacement             # [L1 表面放置锚点] Empty（如办公桌面中心 Z=0.75，供放置显示器/咖啡杯）
```

#### 3. 场地与建筑资产场景图（Venue Hierarchy —— 4 层空间分区与实例簇结构）
```text
ROOT_Venue_<VenueName>                     # [L0 场地总根] Empty (0, 0, 0)
├── GRP_01_Building_Shell                  # [L1 建筑壳体层] Empty
│   ├── GRP_Floors_And_Zones               # [L2 分区地面] 水磨石大堂 / 木地板办公区 / 休息区地毯
│   ├── GRP_Columns_And_Core               # [L2 结构柱网] 核心筒、剪力墙、承重立柱
│   ├── GRP_Facade_CurtainWall             # [L2 幕墙系统] 竖向立柱 Mullions + 横梁 + 半透明玻璃面板
│   └── GRP_Ceiling_LightingGrid           # [L2 顶棚系统] 开放式悬浮条形灯带阵列
├── GRP_02_Interior_FunctionalZones        # [L1 室内功能分区层] Empty
│   ├── ZONE_Lobby_Reception               # [L2 前台与闸机区]
│   │   ├── CLUSTER_Reception_Main         # [L3 资产簇] 前台桌 + 背景形象墙 + 绿植
│   │   └── CLUSTER_Turnstiles             # [L3 资产簇] 安检闸机阵列
│   ├── ZONE_OpenOffice_Floor              # [L2 开放工位区]
│   │   ├── CLUSTER_Workstation_01         # [L3 工位簇] 独立父节点，下挂 Desk + Chair + DualMonitor + Keyboard + Mug
│   │   ├── CLUSTER_Workstation_02         # [L3 工位簇]
│   │   └── ...
│   ├── ZONE_Executive_Rooms               # [L2 玻璃隔断主管房/会议室]
│   └── ZONE_Pantry_And_Lounge             # [L2 茶水间与休闲区] 贩卖机 + 咖啡机 + 沙发组
├── GRP_03_Exterior_Plaza                  # [L1 室外景观广场层] 铺装、树池、街道设施、背景高层建筑
└── GRP_04_Gameplay_Anchors                # [L1 游戏逻辑锚点层] 出生点 MARKER_Spawn_*、交互点 MARKER_Interact_*
```

---

## 三、 强制命名词法契约 (Prefix Naming Taxonomy)

所有通过 `bpy` 创建的集合与对象必须携带语义化前缀，严禁出现裸 `Cube`、`Cylinder.001`、`Sphere.002`：

| 前缀 | 对象类型 (`obj.type`) | 工程语义 | 是否导出至 GLB |
| :--- | :--- | :--- | :--- |
| `COL_` | `Collection` | Outliner 集合容器 | 容器本身不生成节点，按集合筛选导出 |
| `ROOT_` | `EMPTY` (`PLAIN_AXES`) | 资产唯一顶层根节点（坐标 `0,0,0`） | ✅ 是（成为 Godot 场景树根下第一层） |
| `GRP_` | `EMPTY` (`PLAIN_AXES`) | 逻辑部件分组节点 | ✅ 是（导出为 Godot `Node3D` 分组节点） |
| `ZONE_` | `EMPTY` (`PLAIN_AXES`) | 场地空间功能分区节点 | ✅ 是 |
| `CLUSTER_` | `EMPTY` (`PLAIN_AXES`) | 组合道具簇节点（如一整套工位） | ✅ 是 |
| `PIVOT_` | `EMPTY` (`ARROWS`) | 局部旋转/平移枢轴节点（原点位于物理转轴） | ✅ 是（供 Godot 脚本控制旋转/位移） |
| `SOCKET_` | `EMPTY` (`CUBE` / `PLAIN_AXES`) | 骨骼挂点或表面吸附插槽 | ✅ 是（供 Godot 动态 `add_child` 挂载道具） |
| `ARM_` | `ARMATURE` | 角色或机械骨骼系统 | ✅ 是（导出为 Godot `Skeleton3D`） |
| `MSH_` | `MESH` | 最终可见渲染网格 | ✅ 是（导出为 Godot `MeshInstance3D`） |
| `CUT_` | `MESH` (`WIRE`) | 布尔修改器切割刀模 | 🚫 **否**（置于 `COL_Boolean_Cutters`） |
| `PROTO_` | `MESH` | Geometry Nodes 实例化原型网格 | 🚫 **否**（置于 `COL_GeoNodes_Prototypes`） |
| `HIGH_` | `MESH` | 原始百万面雕刻高模参考源 | 🚫 **否**（置于 `COL_HighPoly_Sources`） |

---

## 四、 `bpy.data` 层级构建标准工具库 (Hierarchy Builder API)

> [!WARNING]
> **父子挂载坐标跳变陷阱 (`matrix_parent_inverse`)**：
> 在 Blender Data API 中，当父节点 `parent_obj` 的世界坐标不在 `(0, 0, 0)`（例如 `PIVOT_UpperSwivel` 在 `(0, 0, 0.45)`，或 `CLUSTER_Workstation_02` 在 `(3.2, -1.5, 0)`）时，若对已在世界坐标建好模的子物体直接赋值 `child.parent = parent_obj`，子物体会瞬间被叠加父节点的位移而飞出原位！
> **正确做法**：挂载已处于目标世界坐标的子物体时，必须同步设置 `child.matrix_parent_inverse = parent_obj.matrix_world.inverted()`。

在所有建模脚本中，统一复用以下零上下文依赖（Pure `bpy.data`）的层级构建工具函数：

```python
import bpy
from mathutils import Matrix, Vector


def ensure_collection(name: str, parent_col: bpy.types.Collection | None = None, hide_render: bool = False) -> bpy.types.Collection:
    """获取或创建子集合，并挂载到指定父集合下（默认挂到当前 Scene Master Collection）。"""
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    target_parent = parent_col or bpy.context.scene.collection
    if col.name not in target_parent.children:
        target_parent.children.link(col)
    col.hide_render = hide_render
    return col


def create_asset_collection_tree(asset_name: str) -> dict[str, bpy.types.Collection]:
    """初始化标准三层隔离集合树：01_Export / 02_Work_Helpers / 03_Studio_LookDev。"""
    root_col = ensure_collection(f"COL_Asset_{asset_name}")
    export_col = ensure_collection("01_Export_Hierarchy", root_col, hide_render=False)
    work_col = ensure_collection("02_Work_Helpers", root_col, hide_render=True)
    studio_col = ensure_collection("03_Studio_LookDev", root_col, hide_render=False)
    return {
        "root": root_col,
        "export": export_col,
        "work": work_col,
        "cutters": ensure_collection("COL_Boolean_Cutters", work_col, hide_render=True),
        "prototypes": ensure_collection("COL_GeoNodes_Prototypes", work_col, hide_render=True),
        "highpoly": ensure_collection("COL_HighPoly_Sources", work_col, hide_render=True),
        "studio": studio_col,
    }


def create_hierarchy_node(
    name: str,
    parent: bpy.types.Object | None = None,
    collection: bpy.types.Collection | None = None,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    display_type: str = 'PLAIN_AXES',
    display_size: float = 0.15,
) -> bpy.types.Object:
    """创建用于场景图组织的 Empty 节点（ROOT_ / GRP_ / ZONE_ / CLUSTER_ / PIVOT_ / SOCKET_）。"""
    empty_obj = bpy.data.objects.new(name, None)
    empty_obj.empty_display_type = display_type
    empty_obj.empty_display_size = display_size
    empty_obj.location = Vector(location)

    target_col = collection or bpy.context.scene.collection
    target_col.objects.link(empty_obj)

    if parent is not None:
        empty_obj.parent = parent
        # 若 location 为世界坐标，保持世界位置不变：
        empty_obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return empty_obj


def attach_child_keep_world_transform(
    child_obj: bpy.types.Object,
    parent_obj: bpy.types.Object,
    target_col: bpy.types.Collection | None = None,
) -> None:
    """将已在世界坐标系建模完成的网格挂载到父节点下，严格保持其世界空间位置与朝向不发生偏移。"""
    bpy.context.view_layer.update()
    world_mat = child_obj.matrix_world.copy()
    child_obj.parent = parent_obj
    child_obj.matrix_parent_inverse = parent_obj.matrix_world.inverted()
    child_obj.matrix_world = world_mat

    if target_col is not None and child_obj.name not in target_col.objects:
        for col in list(child_obj.users_collection):
            col.objects.unlink(child_obj)
        target_col.objects.link(child_obj)


def create_bone_socket(
    socket_name: str,
    arm_obj: bpy.types.Object,
    bone_name: str,
    world_loc: tuple[float, float, float],
    collection: bpy.types.Collection | None = None,
) -> bpy.types.Object:
    """在指定骨骼上创建刚性挂点插槽 (SOCKET_*)，用于零畸变挂载眼镜、工牌、手持咖啡杯或武器。"""
    sock = bpy.data.objects.new(socket_name, None)
    sock.empty_display_type = 'CUBE'
    sock.empty_display_size = 0.04
    target_col = collection or arm_obj.users_collection[0]
    target_col.objects.link(sock)

    bpy.context.view_layer.update()
    sock.parent = arm_obj
    sock.parent_type = 'BONE'
    sock.parent_bone = bone_name
    # 计算相对于骨骼末尾 (Tail) 的局部逆矩阵，使 Socket 精确落在 world_loc
    pose_bone = arm_obj.pose.bones[bone_name]
    bone_tail_mat = arm_obj.matrix_world @ Matrix.Translation(pose_bone.tail - pose_bone.head) @ pose_bone.matrix
    sock.matrix_parent_inverse = bone_tail_mat.inverted()
    sock.matrix_world = Matrix.Translation(Vector(world_loc))
    return sock
```

---

## 五、 层级化导出契约（仅导出 `01_Export_Hierarchy` 整棵树）

当场景采用上述集合与父子树架构后，导出 `.glb` 时只需递归选中 `01_Export_Hierarchy` 集合中的所有对象（包含 `ROOT_*`、`GRP_*`、`PIVOT_*`、`SOCKET_*`、`ARM_*`、`MSH_*`），即可将完整的层级树一键无损导出至 Godot 4，且自动排除所有布尔切割器、高模参考源和摄影棚灯光：

```python
def select_export_hierarchy(export_col: bpy.types.Collection) -> list[bpy.types.Object]:
    """递归选中导出集合下的整棵场景图节点树（含 Empty 分组/枢轴/插槽、骨架与网格）。"""
    bpy.ops.object.select_all(action='DESELECT')
    selected = []
    for obj in export_col.all_objects:
        obj.hide_set(False)
        obj.select_set(True)
        selected.append(obj)
    if selected:
        bpy.context.view_layer.objects.active = selected[0]
    return selected
```
