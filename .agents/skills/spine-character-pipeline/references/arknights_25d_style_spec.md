# 《明日方舟》级 2.5D Spine 角色美术与分层工程规约

本规范定义 2.5D 倾斜 3D 舞台（如 [`SpineActor3D`](../../../../src/test/spine_stage/view/component/actor/spine_actor_3d.gd) 与 [`CozyStandeeActor3D`](../../../../src/test/cozy_studio/view/component/standee_actor/cozy_standee_actor_3d.gd)）中 Spine 角色的**视角、头身比例、描边法则、12 槽拆件拓扑与 R14 资产归属契约**。

---

## 1. 视角规约：斜 35° 四分之三双视图（Quarter-View Rule）

在俯视 `-18° ~ -32°` 的 3D 场景中，**严禁制作纯 0° 正视图或纯 90° 正侧视图**：

1. **主力默认视图（`front_34`，必选）**：
   - 角色身体与脸部朝向屏幕右下方（`+X / +Z`，偏转约 `35°`）。
   - 同时保留 **75% 正脸双目辨识度** 与 **身体前后立体纵深**。
   - 在引擎中配合 `scale.x` 水平翻转（含 `0.08s` 纸片挤压翻面 Tween），单套 `front_34` 即可通吃横版战斗、基建漫游及左下/右下/正左/正右全向移动。
2. **背向扩展视图（`back_34`，按需开启）**：
   - 角色朝向屏幕右上方（`+X / -Z`，背对镜头斜 `35°`）。
   - 仅当玩法需要长期背对相机朝北移动或驻守时生成，与 `front_34` 共享同一画布尺寸（`512×512`）、同一脚底原点 `(256, 448)` 与同名动画状态机。

---

## 2. 黄金 2.8 头身比例标尺（`512×512` Setup Canvas）

所有角色在 `Rev2D` / Spine Setup 空间统一锚定在 **`512×512` 画布**，脚底接地点严格钉死在 **`(256, 448)`**（头顶留白供高耸兽耳/呆毛/上劈巨剑挥动，脚底留 `64px` 供下劈刀光与踏步特效）：

| 解剖区域 | 高度占比 | 标准像素区间 (`y`) | 像素高度 | 结构与藏缝硬性要求 |
| :--- | :--- | :--- | :--- | :--- |
| **头部总成 (`Head`)** | `38%` | `112 ~ 240` | `128 px` | 大圆脸高辨识度五官；颈部枢轴固定于 `(252, 240)` |
| **躯干上装 (`Torso`)** | `28%` | `238 ~ 332` | `94 px` | 紧凑梯形战术夹克/背心/斗篷领，下缘遮盖髋关节旋转中心 `(252, 332)` |
| **锥形一体腿靴 (`Leg`)** | `34%` | `332 ~ 448` | `116 px` | **严禁画写实凸出膝盖骨或截断脚踝**！采用上宽下窄的圆润锥柱体长筒袜/战术靴直达 `y = 448` |
| **锥形一体袖手 (`Arm`)** | — | `248 ~ 352` | `104 px` | 整条衣袖连同小圆拳/握持手一体成型；握持锚点位于距肩顶 `86%` 处 |

---

## 3. 描边与 Alpha 通道铁律：「外粗内无 + Straight Alpha」

1. **外粗内无（Outer-Thick, Inner-Open）**：
   - 角色各部件的**外侧轮廓**使用 `3.0 ~ 4.0 px` 统一深暖棕（`#2B1D19`）或深炭蓝（`#181D29`）实心钢笔线，确保在复杂 3D 地面上剪影锐利。
   - **关节插入端零描边**：`arm_full` 肩顶、`leg_full` 大腿顶、`coat_tail` 腰顶在送入骨骼前，必须由 `slice_and_inpaint_caps.py` 抹除顶端闭合描边并以内部布料/肤色平滑填充，彻底杜绝关节旋转时露出黑色横线。
2. **非预乘直通透明（`--straight-alpha`）**：
   - 配合 Godot 4 `Sprite3D` 的 `ALPHA_CUT_DISCARD (0.42)` 双面实时阴影投射与 `shd_cozy_studio_standee_2d.gdshader`，图集与 Spine 导出**必须全程保持 Straight Alpha**，严禁预乘黑边或品红溢色残留。

---

## 4. 标准 `3×4` 十二槽分件拓扑（Canonical 12-Cell Kit）

垫图右侧固定划分为 `4 列 × 3 行` 共 12 个无重叠独立部件格，脚本按格自动拾取并生成完整角色部件：

| 行列索引 `(row, col)` | 部件槽位键名 | 骨骼/变形绑定方式 | 衍生层与特殊处理 |
| :--- | :--- | :--- | :--- |
| `(0, 0)` | `hair_back` | `head` 锁根 + `2` 节物理链网格 | 置于最底层 `z = 1.0` |
| `(0, 1)` | `face_open` | 刚体挂接 `head` (`z = 10.0`) | 无刘海光头底壳 + 常态睁眼微笑（作为头部外轮廓唯一基准壳） |
| `(0, 2)` | `face_blink` | 刚体挂接 `head` (`z = 10.1`) | 仅提取内部闭眼五官椭圆无缝贴入 `face_open` 底壳，外轮廓 `0.00px` 零抖动 |
| `(0, 3)` | `face_skill` | 刚体挂接 `head` (`z = 10.2`) | 仅提取内部战吼/欢呼五官椭圆贴入 `face_open` 底壳，攻击/技能/受击瞬切 |
| `(1, 0)` | `hair_bangs` | 顶锁 `head` + 两侧发梢双物理链网格 | 一体式前刘海与鬓角（中央必须挖空 `#FF00FF` 脸窗），顶冠锁死不裂头皮 |
| `(1, 1)` | `head_acc` | `head` 锁根 + 摆锤物理链 (`z = 11.5`) | 兽耳、呆毛、战术耳机天线；置于 `face_open (10.0)` 与 `hair_bangs (12.0)` 之间，耳根自然藏入发冠后零白缝 |
| `(1, 2)` | `torso` | 挂接 `torsoWarp` 呼吸晶格 (`z = 6.8`) | 无袖封闭侧缝躯干主衣体（含领口/露腰腹部），下缘自然塞入裙腰/大衣腰头 |
| `(1, 3)` | `coat_tail` | `hip` 锁根 + `2` 节下摆物理链 (`z = 7.6`) | 战术风衣下摆/百褶裙摆（保留清晰顶腰头包裹髋部），随跑跳挥砍惯性翻飞 |
| `(2, 0)` | `arm_full` | **17 环连续双骨骼蒙皮** (`upper`+`fore`) | **单件一体式手臂**（25° A-pose 展开不遮挡腰腹）；自动派生压暗 `arm_far (z = 2.2)` 与原色 `arm_near (z = 15.0)` |
| `(2, 1)` | `leg_full` | **17 环连续双骨骼 IK 蒙皮** (`thigh`+`shin`) | **单件垂直笔直锥形腿靴**（Setup 严禁预折香蕉腿）；自动派生 `leg_far (z = 4.0)` 与 `leg_near (z = 5.2)` |
| `(2, 2)` | `weapon_primary` | 刚体挂接 `weaponGrip` (`weapon/primary` 皮肤) | 垂直朝上对称绘制；常态默认 `+128°` 方舟侧后低垂持握，**严禁斜横挡脸与胸口** |
| `(2, 3)` | `weapon_secondary` | 刚体挂接 `weaponGrip` (`weapon/secondary` 皮肤) | 第二把可热切武器（长柄镰/重锤/法杖），支持运行期毫秒级不断帧换装 |

---

## 5. R14 美术资产落盘与命名契约

遵循 [`src/assets/_doc_assets.md`](../../../../src/assets/_doc_assets.md)：
- **源工程（隔离区）**：`art/spines/<char_id>/`（存放 `operator_spec.json`、`templates/`、`ai_sources/`、`textures/`、`<char_id>.r2d.json`、`audit/`）。
- **引擎运行期导出落点**：
  - 正式业务模块：`src/assets/spines/<feature>/<subject>/spn_<feature>_<subject>.{spine-json,atlas,png}` 及 `spn_<feature>_<subject>_data.tres`。
  - 测试沙盒模块：`src/test/<test_domain>/assets/spines/spn_<test_domain>_<subject>.{spine-json,atlas,png}` 及 `spn_<test_domain>_<subject>_data.tres`。
  - 文件名严格遵守全小写 `snake_case`，以 `spn_` 开头且第 2 段与所属架构域目录完全一致。
