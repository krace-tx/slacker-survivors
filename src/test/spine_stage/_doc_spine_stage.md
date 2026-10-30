# 2.5D「方案 B」原型模块（`src/test/spine_stage`）

## 1. 模块定位与管线架构

本模块是 **Godot 4.7「3D 场景实时光影投射阴影 + Rev2D/Spine 2D 骨骼角色跑跳攻击 + 实时多槽位换装（方案 B）」** 的完整可运行 MSVP 垂直切片验证沙盒。

### 端到端资产与渲染链路
1. **Rev2D 骨骼绑定与物理导出（`art/spines/spine_stage/`）**：
   - 使用 `Rev2D` 构建包含双腿双骨骼 IK（`leg_l_ik` / `leg_r_ik`）、三段摆锤披风与头冠羽饰物理链（`cape_1..3` / `plume_1..2`）的骑士主角 `hero_knight.r2d.json`（含 `idle / run / jump / attack_1 / attack_2` 5 组动作）与稻草魔像靶机 `straw_golem.r2d.json`（含 `idle / hit`）；
   - 通过 `art/spines/spine_stage/build_spine_exports.mjs` 调用 `rev2d validate` 与 `rev2d export spine --straight-alpha`，自动拆分 7 套 Mix-and-Match 皮肤（`default`、`weapon/sword`、`weapon/scythe`、`weapon/hammer`、`outfit/ranger`、`outfit/royal`、`outfit/abyss`）并导出至 `src/test/spine_stage/assets/spines/*.spine-json` + `.atlas` + `.png`。
2. **离屏透明骨骼合成与对象池托管（`SpinePool` + `SubViewport`）**：
   - 场景宿主 `SpineStageScene` 通过框架 `SpinePool` 池化借出 `SpineController`，挂载进每个 `SpineActor3D` 内部的透明 `SubViewport`；
   - 按键换装时通过 `SpineSprite.new_skin("active_loadout")` + `SpineSkin.add_skin(...)` 实时叠加基底躯干、武器与披风头饰皮肤，毫秒级热切且**不断帧、不重置当前跑跳挥砍相位**。
3. **3D PBR 受光与动态剪影投射阴影（`Sprite3D`）**：
   - `CharacterSprite3D` 绑定 `ViewportTexture`，开启 `shaded = true`、`alpha_cut = ALPHA_CUT_DISCARD`（阈值 `0.42`）与 `SHADOW_CASTING_SETTING_DOUBLE_SIDED`；
   - 角色与手中切换的巨镰/符文战锤在主平行光（黄昏斜阳 / 幽蓝月光）以及左右两座摇曳火盆 `OmniLight3D` 照射下，实时在 3D 石板地面与北侧双层石阶高台上投射出随跑跳挥砍同步变形的真实剪影长影。

---

## 2. 目录结构（MSVP 垂直切片）

```text
src/test/spine_stage/
├── _doc_spine_stage.md
├── spine_stage_test.tscn                          # 顶层可运行原型场景入口（F6 直接运行）
├── assets/
│   └── spines/                                    # Spine 4.2 骨骼 JSON / Atlas / PNG / Data Resource
├── model/
│   ├── spine_stage_config.gd                      # 武器/护甲配置表、物理常量与光影枚举
│   └── spine_stage_state.gd                       # 运行时换装槽位、动作文案与连击统计快照
├── service/
│   └── spine_stage_service.gd                     # 换装状态流转、零开方扇形受击裁决与 PCM 音效合成
├── presenter/
│   └── spine_stage_presenter.gd                   # 键鼠输入采样、角色物理步进与 HUD 单向刷新协调器
└── view/
    ├── component/
    │   ├── actor/
    │   │   ├── spine_actor_3d.gd                  # 方案 B 核心：CharacterBody3D + SubViewport + Sprite3D
    │   │   └── spine_actor_3d.tscn
    │   ├── stage/
    │   │   ├── spine_courtyard_stage_3d.gd        # 3D 古堡石阶庭院、双摇曳火盆点光与日夜天光预设
    │   │   └── spine_courtyard_stage_3d.tscn
    │   ├── camera/
    │   │   ├── spine_camera_rig_3d.gd             # -31° 微俯视阻尼跟随与命中微震屏相机组件
    │   │   └── spine_camera_rig_3d.tscn
    │   ├── pill/
    │   │   ├── spine_loadout_slot_button.gd       # Slate Dark 装备槽位胶囊按钮预制体
    │   │   └── spine_loadout_slot_button.tscn
    │   └── hud/
    │       ├── spine_stage_hud_panel.gd           # 顶栏状态徽章 + 底栏武器/护甲双组热切面板
    │       └── spine_stage_hud_panel.tscn
    └── scene/
        └── courtyard/
            ├── spine_stage_scene.gd               # BaseScene 派生根控制器（托管 SpinePool 生命周期）
            └── spine_stage_view.gd                # BaseView 派生安全区自适应 UI 根视图
```

---

## 3. 操控键位一览

| 按键 / 操作 | 功能说明 |
| :--- | :--- |
| `W / A / S / D` 或方向键 | 3D 庭院全向移动（可跃上北侧双层石阶高台） |
| `Space` | 3D 腾空跳跃（观察地面接触圆影缩放与斜阳/火盆投射长影分离） |
| `J` / `K` / 鼠标左键 | 二段近战挥砍连击（命中左右稻草魔像触发击退、受击动作与震屏） |
| `1` / `2` / `3`（或点击底栏左组） | 实时热切武器：`圣银骑士剑` / `猩红死神镰` / `雷霆符文锤`（3D 投射阴影同步变为对应武器剪影） |
| `Q` / `E` 或 `4` / `5` / `6`（或点击底栏右组） | 实时热切服饰披风与头饰：`翡翠游侠装` / `暗金铁卫铠` / `深渊狂猎甲` |
| `L`（或点击右上角光影按钮） | 一键切换 `黄昏斜阳 + 火盆补光` 与 `幽蓝月夜 + 火把长影` 3D 光照预设 |
