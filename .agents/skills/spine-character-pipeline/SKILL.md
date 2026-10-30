---
name: spine-character-pipeline
description: >-
  《明日方舟》级 2.5D Spine 角色自动化生产、连续网格蒙皮绑定与动作补帧管线。在生成 2D/2.5D Spine 骨骼角色、制作角色拆件图集、配置 Rev2D (*.r2d.json) 骨骼/IK/摆锤物理、合成待机/移动/战斗刀光动画，或导出 Spine 4.2 (.spine-json/.atlas/.png) 至 Godot 4 (SpineActor3D / CozyStandeeActor3D) 前自动触发。强制执行「人台垫图锚定 ➔ 12槽原位剥离与去内描边补帽 ➔ 17环连续网格自动寻轴蒙皮 ➔ 方舟关键姿态库+物理补帧 ➔ 五道像素与循环门禁」闭环，严禁直接生成散乱爆炸图、手猜骨骼坐标、肘膝硬切黑线或滥用 RIFE 光流糊边。
---

# 工业级 2.5D Spine 角色自动化生产管线 (`spine-character-pipeline`)

> 🎯 **核心宗旨**：对标《明日方舟》2.5D 战斗/基建小人工业标准，将 AI 制作 Spine 从「散件比例失调、肘膝截断黑线、手猜坐标脱臼、正弦波滑步」彻底升级为 **「2.8 头身人台强约束 + 连续一体肢体 17 环平滑蒙皮 + 抽帧瞬斩刀光与 60Hz 弹簧跟随补帧 + 五道确定性门禁」** 的可复现工程管线。

---

## 一、四大技能协同边界

| 技能 | 职责边界 | 协同交接点 |
| :--- | :--- | :--- |
| **`spine-character-pipeline`（本技能）** | 2.5D 角色人台约束生图、去内描边拆件补帽、连续网格骨骼/IK/物理绑定、动作合成与 Spine 4.2 导出验收 | 产出合规 `.spine-json` + `.atlas` + `.png` + `_data.tres` |
| **[`framework-aware`](../framework-aware/SKILL.md)** | `R01~R16` 架构与资产治理（特别是 `R11` `SpinePool` 池化托管与 `R14` `spn_<domain>_<subject>` 命名规范） | 正式资产落入 `src/assets/spines/<domain>/` 或 `src/test/<feature>/assets/spines/` 时同步遵守 |
| **[`godot-scene-pipeline`](../godot-scene-pipeline/SKILL.md)** | 在 `.tscn` 舞台中装配 `SpineActor3D` / `CozyStandeeActor3D`、配置 `SubViewport` 与 3D 灯光阴影 | 骨骼导出验收通过后移交装配舞台并抓拍实机帧 |
| **[`blender-pipeline`](../blender-pipeline/SKILL.md)** | 3D 场景建筑道具建模；或需 8 方向重透视翻滚的纯 3D-to-2D 三渲二序列帧角色 | 2.5D 舞台的 3D 地面/掩体由 Blender 管线供给 |

---

## 二、渐进式披露知识库路由（编码/生图前按需读取）

在执行具体阶段前，**必须使用 `read_file` 点对点查阅**对应参考分册，严禁凭直觉盲写坐标或提示词：

| 任务阶段 | 必读规范分册 | 核心防坑红线 |
| :--- | :--- | :--- |
| **设定角色比例、朝向、拆件槽位与 R14 路径** | [`references/arknights_25d_style_spec.md`](./references/arknights_25d_style_spec.md) | 锁定 **2.8 头身斜 35° 四分之三视角**；手臂/腿部**严禁在肘部、膝盖、脚踝处横切闭合黑线**；外轮廓粗描边，内搭接区零描边。 |
| **调用 `image-generator` 生成角色母图与分件卡** | [`references/ai_kit_generation_prompt_guide.md`](./references/ai_kit_generation_prompt_guide.md) | **严禁无垫图自由发挥**！必须先跑 `generate_mannequin_guide.py` 生成 `1536×864`「左整身母图 + 右 3×4 固定槽位」品红底引导图作为垫图输入。 |
| **构建骨骼、网格权重、物理链与战斗/步态补帧** | [`references/rigging_mesh_and_motion_spec.md`](./references/rigging_mesh_and_motion_spec.md) | 肢体使用 **17 环关节加密网格 + Hermite 平滑双骨骼权重**；飘带根部 `v=0` 100% 锁死父骨防脱节；战斗采用 `3:1:2:4` 瞬斩 + 刀光残影槽，**严禁使用 `Math.sin` 匀速摆或 `RIFE` 光流补帧**。 |
| **编写 `operator_spec.json` 蓝图与排查常见畸变** | [`examples/operator_blueprint_example.md`](./examples/operator_blueprint_example.md) | 查看完整声明式 `operator_spec.json` 参数示例与 ❌典型反模式 vs ✅工业级范式对照。 |

---

## 三、强制执行六步确定性闭环工作流

所有 Spine 角色资产源工程统一存放于 `art/spines/<char_id>/`（受 `art/.gdignore` 保护，不污染 Godot 导入），并严格按以下 6 步顺序执行：

```text
[1. Mannequin Guide] ➔ [2. Guided AI Kit] ➔ [3. Slice & Cap Inpaint] ➔ [4. Auto-Mesh Rig & Motion] ➔ [5. 5-Gate Audit] ➔ [6. Godot Deliver]
                                                       ▲                                                     │
                                                       └───────── 差分超标 / 关节断层 / 循环跳帧 立即返工 ─────┘
```

### Step 1 · 生成标准 2.8 头身人台与 12 槽引导垫图（支持母图锚定 `--master-ref`）
运行 [`scripts/generate_mannequin_guide.py`](./scripts/generate_mannequin_guide.py) 生成二次元尖下巴水滴脸型（`aspect ~0.94`，**严禁画横向扁土豆椭圆头**）与 12 槽引导垫图；若已有参考角色原画，传入 `--master-ref` 锁定左侧母图：
```powershell
python .agents/skills/spine-character-pipeline/scripts/generate_mannequin_guide.py --out-dir art/spines/<char_id> [--master-ref <master_png>]
```

### Step 2 · 垫图强约束生成「左整身母图 + 右 12 槽分件卡」
阅读 [`references/ai_kit_generation_prompt_guide.md`](./references/ai_kit_generation_prompt_guide.md)，调用 `image-generator` 子代理，**传入 Step 1 生成的 `kit_guide_front_34.png` 作为参考底图**，产出 `art/spines/<char_id>/ai_sources/raw_kit_front_34.png`（如需背面战斗朝向，同步产出 `raw_kit_back_34.png`）。
- 收到生图结果后，**必须先用 `read_file` 目视核查原图**：确认三颗表情脸壳为与母图一致的动漫尖下巴 V 脸、`hair_bangs` 中央镂空、`torso` 与 `coat_tail` 花纹配色严格同款（若有露腰结构必须保留）、`arm_full` 与 `leg_full` 均为**笔直未切断的一体锥形件**。

### Step 3 · 母图横向解剖标定、去内描边补帽与 Straight-Alpha 图集打包
编写 `art/spines/<char_id>/operator_spec.json`（参见 [`examples/operator_blueprint_example.md`](./examples/operator_blueprint_example.md)），运行 [`scripts/slice_and_inpaint_caps.py`](./scripts/slice_and_inpaint_caps.py)：
```powershell
python .agents/skills/spine-character-pipeline/scripts/slice_and_inpaint_caps.py --spec art/spines/<char_id>/operator_spec.json
```
脚本自动完成：
1. `#FF00FF` 非预乘色键抠图与深色线稿去溢色（Despill）；
2. **母图横向解剖测量 (`measure_master_anatomy`)**：直接测量左侧母图发团宽 `hair_w`、躯干宽 `trunk_w` 与双腿跨距（**彻底免疫高耸狼耳/高帽/长角对总高的虚增干扰，根除大头娃娃畸变**），强制钳制动漫脸壳宽高比 `<= 1.00`，并将 `face_blink` / `face_skill` 五官椭圆无损融合至 `face_open` 外轮廓壳；
3. 使用 `cv2.inpaint` 自动抹除 `arm_full`、`leg_full` 顶端搭接区的闭合黑描边并保留 `coat_tail` 清晰腰头，自动派生压暗远端后手/后腿；
4. 提取肢体掩码中轴线计算关节锚点，输出 `textures/tex_<char_id>_parts.png` 与 `textures/part_manifest.json`。

### Step 4 & 5 · 自动构建 17 环连续蒙皮网格、方舟侧后持剑架势与 Spine 4.2 导出
运行 [`scripts/build_arknights_rig.mjs`](./scripts/build_arknights_rig.mjs) 调用内置 [`addons/rev2d`](../../../addons/rev2d/README.md) 编译器：
```powershell
node .agents/skills/spine-character-pipeline/scripts/build_arknights_rig.mjs --spec art/spines/<char_id>/operator_spec.json
```
脚本自动生成 `<char_id>.r2d.json`：**Setup 站姿双腿保持垂直笔直（仅 `+1px` 微前偏种子 + `softness=0.2`，严禁在 Setup 空间预折 `+16px` 导致香蕉罗圈腿畸变）**、跑步通过压低骨盆（`BodyBobY > 0`）自然屈膝、武器采用方舟标志性 `+128°` 侧后低垂持握（100% 不遮挡脸与胸腹），烘焙 `60Hz` 多段摆锤物理链与六组方舟节奏动画，导出 `--straight-alpha` 的 Spine 4.2 三件套与 Godot `*_data.tres`。

### Step 6 · 反畸形剪影 IoU + 五道门禁校验与审计卡目视验收
运行 [`scripts/verify_spine_gate.py`](./scripts/verify_spine_gate.py)：
```powershell
python .agents/skills/spine-character-pipeline/scripts/verify_spine_gate.py --spec art/spines/<char_id>/operator_spec.json
```
- 必须确保终端输出 `[SPINE_GATE_PASS]`（含 **母图剪影重合度 `IoU >= 0.72`、头宽偏差 `<= 12%`、站姿腿距偏差 `<= 14px` 三大反畸形硬门禁**，`±45°` 极限摆角孤岛数 `= 1`，零品红残留，`rev2d analyze` 循环闭合且 `outOfReachFrames = 0`）。
- **必须调用 `read_file` 亲自对比 `audit/audit_card_<char_id>.png` 中 Panel 1 母图与 Panel 2/3/4/5 成品**，确认脸型、头身比、露腰/衣摆衔接、笔直站腿与武器姿态零畸变。
- 若导出路径涉及 `src/`，最后必须加跑 `python .agents/skills/framework-aware/scripts/check_compliance.py` 确保 `R01~R16` 全绿。

---

## 四、回复声明格式契约

凡触发本技能完成角色生产或修改，回复开头必须包含以下状态声明：

```markdown
> 🛠️ **已加载 Skill**：`spine-character-pipeline`
> 📖 **已注入规范**：`arknights_25d_style_spec.md`、`rigging_mesh_and_motion_spec.md`
> ✅ **已通过门禁**：`verify_spine_gate.py` (`[SPINE_GATE_PASS]`) + 四联视觉审计卡已核验
```
