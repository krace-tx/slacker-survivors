# Skill Wiki · 2D / 3D 游戏世界舞台组装规范 (World Stage Assembly)

> 📖 **Wiki 定位**：规范俯视角/横版 2D 关卡及 3D 世界舞台（Jolt Physics + Forward+）的节点分组、相机灯光、碰撞层与 `.glb` 资产装配标准。

---

## 1. 标准世界舞台场景树拓扑

无论是 2D（根节点继承 `BaseScene` 或挂载 `Node2D` 世界容器）还是 3D 关卡，顶层舞台 `.tscn` 必须按职责清晰分桶，严禁将地形、怪物、灯光与 HUD 平铺混杂在同一层级：

```text
<Feature>StageScene (BaseScene)
├── World3D (Node3D) 或 World2D (Node2D)      # 空间世界根容器
│   ├── EnvironmentRig (Node3D)               # WorldEnvironment + DirectionalLight3D / 补光灯
│   ├── CameraRig (Node3D / Camera2D)         # Camera3D (SpringArm3D / Phantom) 或 Camera2D
│   ├── StaticGeometry (Node3D / Node2D)      # 地板、墙壁、建筑、静态掩体预制体实例 + 静态碰撞体
│   ├── NavigationRegion (NavigationRegion3D/2D) # 寻路网格容器（按需）
│   ├── Actors (Node3D / Node2D, %Actors)     # 角色、NPC、敌人动态刷怪挂载锚点
│   └──VfxPoolRoot (Node3D / Node2D, %VfxRoot)# 投射物与粒子特效挂载层
└── HudLayer (CanvasLayer, layer = 10)        # 屏幕空间 UI 覆盖层（仅实例化声明式 HUD 组件 .tscn）
```

---

## 2. 3D 舞台装配与 `.glb` 接地契约（联动 `blender-pipeline`）

本项目物理引擎启用 **Jolt Physics**，渲染管线为 **Forward+ (D3D12)**。组装 3D 舞台时必须遵守：

1. **禁止将 Blender 预览灯/相机带入舞台**：从 `blender-pipeline` 导出的 `.glb` 只含纯净网格/骨骼，舞台光照统一由 `EnvironmentRig` 内的 `WorldEnvironment`（开启柔和环境光/SSAO/Glow）与主辅 `DirectionalLight3D` / `OmniLight3D` 提供：
   - 主光（Key Light）：俯仰角 `-45° ~ -60°`，偏暖白 `#FFF7ED`，开启阴影 `shadow_enabled = true`；
   - 环境补光：`Environment.ambient_light_source` 设为背景/天空混合，避免背光面死黑。
2. **接地零浮空校验（`y = 0` 地平面对齐）**：
   - Blender 资产遵循 `min_z = 0`（导入 Godot 后对应局部原点位于底部 `y = 0`）；
   - 通过 Godot MCP `node.instantiate_scene` 挂载 `.glb` 或角色组件 `.tscn` 后，地板顶面对齐 `y = 0.0`，立柱/桌椅/角色实例默认 `position.y = 0.0`，严禁出现半截入地或悬空阴影脱节。
3. **碰撞体与可视网格分离或预制体化**：
   - 可复用静态道具（如办公桌、障碍箱）应先封装为独立 `component/<prop>/<prop>.tscn`（根为 `StaticBody3D`，内含 `.glb` 实例与精确匹配包围盒的 `CollisionShape3D`），再在关卡舞台中批量 `instantiate_scene` 摆放。

---

## 3. 2D 关卡舞台装配契约

1. **Y-Sort 深度排序**：俯视角（Top-Down / 2.5D）幸存者玩法下，`World2D` 或 `%Actors` 与动态道具容器必须开启 `y_sort_enabled = true`，且所有角色/掩体预制体的视觉精灵底部中心（脚底接触点）必须对齐局部原点 `(0, 0)`。
2. **相机平滑与边界**：`Camera2D` 显式配置合理的 `zoom` 与 `position_smoothing_enabled`，确保在 `1920x1080` 下角色与周边威胁视野比例协调。
3. **世界坐标与 UI 坐标绝对隔离**：血条飘字若置于屏幕 HUD 层需经视口变换；世界空间交互提示统一挂载于对应节点局部锚点，利用 `HudLayer (CanvasLayer)` 承载全局顶栏与技能槽组件。

---

## 4. 舞台视觉验收重点（Step 5 Render）

3D / 2D 舞台在执行 `capture_scene_preview.py` 时，必须确保默认主相机（`Camera3D.current = true` / `Camera2D.enabled = true`）已在 `.tscn` 中激活，以便 `--write-movie` 直接从玩家真实视角出图，重点核查：
- 曝光是否过曝或死黑；
- 角色与场景道具比例尺（Scale）是否符合人类工程学常识（如门高约 `2.1m`、桌面高 `0.75m`、角色高 `1.7m`）；
- 前景 HUD 是否遮挡核心战斗视野。
