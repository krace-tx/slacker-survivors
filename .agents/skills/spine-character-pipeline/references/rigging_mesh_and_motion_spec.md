# 连续网格蒙皮、运动学与方舟式补帧技术规约

本分册规定 `slice_and_inpaint_caps.py` 与 `build_arknights_rig.mjs` 内部执行的**数学寻轴、17 环加密网格权重、60Hz 弹簧跟随物理与战斗瞬斩补帧标准**。

---

## 1. 确定性关节轴心求解（Zero-Guessing Joint Solver）

严禁人工目测填写骨骼坐标。所有骨骼坐标基于 `512×512`（`ground_y = 448`）标准人台与部件 Alpha 掩码几何特征自动算出：

1. **主干层级链（Master Spine Chain）**：
   - `ground (256, 448)` ➔ `hip (0, -hip_h)` ➔ `torso (0, -torso_pivot_dy)` ➔ `head (neck_dx, -neck_dy)`。
   - 一切跑跳起伏（`BodyBobY`）、受击后仰与踏步挤压（`Squash`）全部作用于 `hip` / `torso`，保证根骨骼 `ground` 恒定锚定在 3D 地面接触圆影中心。
2. **一体式肢体双骨骼轴心与反罗圈腿铁律（Zero-Boomerang Straight Setup）**：
   - 对垂直放置的 `arm_full` `(w_a, h_a)`：肩球心位于 `(0.50 * w_a, 0.14 * h_a)`，肘旋转中心位于 `(0.50 * w_a, 0.50 * h_a)`，手心武器挂点 `weaponGrip` 位于 `0.88` 前臂处；常态采用 `25°` 外展 A-Pose，武器沿 `+128°` 侧后方低垂持握，100% 避让面部与躯干。
   - 对垂直放置的 `leg_full` `(w_l, h_l)`：**Setup 绑定空间必须保持双腿垂直笔直（膝盖仅给 `+1px` 微前偏种子以锁定正向屈膝极性，IK `softness = 0.2`）**。严禁在 Setup 空间将笔直腿图强行弯折 `+16px`，否则站立态会畸变为罗圈香蕉腿！运动中通过压低骨盆（`run` 中 `BodyBobY = +6 ~ +11px`，`idle` 中 `BodyBobY >= 0`）使双腿在全周期内自然屈膝且 `outOfReachFrames == 0`。

---

## 2. 17 环关节加密连续网格与 Hermite 平滑权重

为彻底根除矩形粗网格弯曲时的折角撕裂与“糖果纸拧麻花”塌陷，`arm_near`、`arm_far`、`leg_near`、`leg_far` 统一采用 `Rev2D` 原生 `type: "mesh"` 自定义UV网格与显式顶点权重矩阵：

1. **非均匀纵向加密环线（17 Non-Uniform V-Rings）**：
   - 纵向参数 $v \in [0, 1]$ 在关节弯曲区 $v \in [0.34, 0.66]$ 密集采样：
     `V_RINGS = [0.00, 0.10, 0.20, 0.30, 0.36, 0.41, 0.45, 0.48, 0.50, 0.52, 0.55, 0.59, 0.64, 0.72, 0.82, 0.91, 1.00]`（共 17 道横环 × 7 列 = 119 顶点）。
2. **三次 Hermite 平滑阶跃权重（Smoothstep Partition of Unity）**：
   - 令归一化过渡因子 $t = \mathrm{clamp}\!\left(\frac{v - 0.32}{0.68 - 0.32}, 0, 1\right)$，下段骨骼权重为：
     $$w_{\text{lower}}(v) = t^2 (3 - 2t), \quad w_{\text{upper}}(v) = 1 - w_{\text{lower}}(v)$$
   - 满足 $w_{\text{upper}} + w_{\text{lower}} \equiv 1$ 且在 $v = 0.32$ 与 $v = 0.68$ 处一阶导数为 $0$，肘部/膝部弯曲至 $75^\circ$ 依然保持圆润漫画弧线。
3. **锁根多段物理飘带网格（Root-Locked Cloth & Hair Mesh）**：
   - `coat_tail`、`hair_back`、`head_acc` 采用 `[anchorBone, chain1, chain2]` 三骨骼混合权重：在根部 $v \le 0.14$ 处强制 $w_{\text{anchor}} = 1.0$（**100% 锁死在躯干或头骨上，永不脱节裂开**），$v > 0.14$ 平滑过渡至物理摆锤链。
   - `hair_bangs` 顶冠与前额区（$v < 0.42$ 或中心区 $|u - 0.5| < 0.24$）100% 锁死 `head`，仅左右两侧垂落鬓角平滑绑定至 `sideLockBack` / `sideLockFront` 摆锤骨。

---

## 3. 《明日方舟》运动学节奏与三级补帧策略

### 策略 A：主干高对比度关键姿态补帧（Snappy Key-Pose Curves）
**严禁使用对称匀速正弦波 `Math.sin` 驱动战斗与步态！** 统一采用非对称缓动与动画 12 原则：

| 动画名称 | 标准时长 | 循环 | 关键帧运动学结构与节奏分配 |
| :--- | :--- | :--- | :--- |
| **`idle`** | `2.40s` | ✅ | 胸腔 `Breath` 平滑起伏 + 头部滞后 `0.16s` 相位微倾 + 手持武器呼吸微摆 + `t=1.45s` 步进眨眼 (`0.13s`) |
| **`move`** | `0.48s` | ✅ | **方舟四相位小碎步**：`0%` 跨步触地 ➔ `15%` 踏地受迫下沉挤压 (`BodyBobY=+9px, Squash=+1`) ➔ `50%` 提膝越过 (`FootLift=-26px`) ➔ `75%` 蹬地轻盈腾空 (`BodyBobY=-8px, Squash=-0.8`)；前后腿轨严格相差 `offset = 0.24s` |
| **`attack_1`** | `0.46s` | ❌ | **黄金 `3:1:2:4` 下劈斩**：`0~0.14s` 后仰拧肩蓄力 (`outQuad` 缓入) ➔ **`0.14~0.19s`（仅 `0.05s` 极陡爆发）瞬间挥落 `145°` + 点亮月牙刀光残影网格 `fx_slash_down` + 切战吼脸 `face_skill`** ➔ `0.19~0.28s` 过冲微震卡肉 (`Hit-stop`) ➔ `0.28~0.46s` 弹性收刀 |
| **`attack_2`** | `0.48s` | ❌ | 二段反手上挑连斩：压低重心蓄力 ➔ `0.05s` 极速上撩斩 + 点亮逆弧刀光 `fx_slash_up` + 小幅跃起 |
| **`skill`** | `0.76s` | ❌ | 干员技能爆发：双脚微浮空蓄能（`face_skill` + 脚底源石光环扩散 `fx_skill_ring`）➔ 重击斩落与冲击波扩散 |
| **`hit`** | `0.40s` | ❌ | 瞬切受击表情 + 向后瞬移倾仰 (`outQuad`) + 阻尼震荡回位 |

### 策略 B：60Hz 弹簧摆锤二次动作自动补帧（Secondary Physics Baking）
- 所有头发（`hair_back`、两侧鬓角）、兽耳/呆毛（`head_acc`）、风衣下摆（`coat_tail`）**不手写旋转关键帧**，全部挂载到 `Rev2D` 的 `60Hz` 多段阻尼摆锤物理系统，由 `BodyBobY`、`BodyLean` 与 `HeadNod` 的加速度实时激振。
- 执行 `rev2d export spine` 时，物理引擎先自动预热 `5s` 进入稳态，再以自适应高精度采样烘焙为 Spine 原生平滑贝塞尔旋转与网格变形曲线，确保**循环首尾零跳帧**且主干急停卡肉时衣摆发丝自然惯性追随。

### 策略 C：严禁对二次元立牌全身跑 `RIFE` 光流补帧
- 传统 `RIFE` 光流插帧会将 `3~4px` 深色轮廓线与快速挥舞的武器抹成半透明重影果冻，在 Godot `Sprite3D` 的 `ALPHA_CUT_DISCARD (0.42)` 3D 实时阴影裁切下会产生剧烈的阴影边缘闪烁与黑边碎块。
- 高速挥砍的视觉连贯性**必须通过独立半透明渐变刀光残影网格（`fx_slash_down` / `fx_slash_up`）的顶点扇形拉伸与透明度衰减**实现——既保留帧帧锐利的漫画线稿，又具备顶级打击爽感。
