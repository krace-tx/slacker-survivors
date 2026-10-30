# 垫图约束生图规范：零漂移「左整身母图 + 右 12 槽分件卡」提示词指南

为彻底杜绝 AI 自由生成散件导致的比例失调、膝盖黑线与丢件，`spine-character-pipeline` 强制执行 **「程序化人台引导图垫图输入 + 单画布同源生成」** 协议。

---

## 1. 为什么采用「左整身母图 + 右 3×4 分件格」同画布协议？

1. **100% 色彩与笔触一致性**：组装母图与全部 12 个部件在同一次扩散采样中生成，线稿粗细、赛璐璐阴影色温、服装花纹完全一致。
2. **母图即比例标尺**：左侧 `x ∈ [0, 480]` 的完整组装角色严格贴合 `2.8` 头身斜 `35°` 人台，`slice_and_inpaint_caps.py` 直接测量左侧母图的头高与总高来校准右侧所有部件。
3. **无文字、无灰框污染**：`generate_mannequin_guide.py` 生成的 `kit_guide_front_34.png` 使用纯品红底（`#FF00FF`）与暗品红辅助剪影（`#CC00CC`，绿通道 `G = 0`），即使生图残留少量辅助底色，也会被色键方程 $\min(R, B) - G$ 100% 彻底抠净。

---

## 2. 调用 `image-generator` 的标准 Prompt 模板

在调用 `invoke_subagent(TypeName="image-generator", ...)` 时，**必须传入 `templates/kit_guide_front_34.png` 的绝对路径作为参考图**，并使用如下结构化英文 Brief（替换 `<CHARACTER_DESIGN>` 与 `<WEAPON_1>` / `<WEAPON_2>`）：

```text
Edit/transform the reference layout template image (<ABS_PATH_TO_kit_guide_front_34.png>) into a clean, production-ready 2D game Spine 2.5D chibi character kit sheet on a 100% flat solid #FF00FF magenta background (1536x864, 16:9).

ART STYLE & PROPORTIONS (Arknights Battle Chibi Standard):
- Crisp anime cel-shaded game sprite art, 2.8-head chibi proportions, 35-degree 3/4 front-right view.
- Bold clean dark espresso-charcoal outer ink outlines (#241B1E), clean two-tone cel shading, ZERO background gradients, ZERO drop shadows, ZERO text, ZERO numbers, ZERO grid lines or borders!
- Character theme: <CHARACTER_DESIGN>

STRICT LAYOUT MATCHING THE REFERENCE GUIDE (Left Master + Right 4x3 Grid):
- LEFT ZONE (x = 0..480, full height): Complete assembled 2.8-head 3/4 front-right chibi character standing in a clean 30-degree A-pose (arms angled slightly away from torso, legs slightly apart in smooth tapered boots, NO weapon held in front of body).
- RIGHT ZONE (x = 496..1536, 4 columns x 3 rows = 12 isolated parts on flat #FF00FF background, well separated with generous magenta margin around every piece):
  * Row 1, Col 1 (top-left of grid): Back hair silhouette (`hair_back`, complete rear hair mass, no face).
  * Row 1, Col 2: Bald anime chibi head base with pointed cute V-chin (`aspect <= 0.96`, NEVER a wide horizontal potato oval!), normal open anime eyes, eyebrows, and subtle stoic mouth (`face_open`, NO hair bangs).
  * Row 1, Col 3: Identical bald anime V-chin chibi head base with peaceful closed blinking eyes (`face_blink`, NO hair bangs).
  * Row 1, Col 4: Identical bald anime V-chin chibi head base with fierce battle shout expression, sharp glowing eyes and open mouth (`face_skill`, NO hair bangs).
  * Row 2, Col 1: Front hair bangs + cheek side-locks framing a clean empty `#FF00FF` magenta face window (`hair_bangs`, NO eyes/skin drawn inside).
  * Row 2, Col 2: Top head accessory / fluffy animal ears + ahoge hair tuft (`head_acc`, matching the left character's exact ear shape).
  * Row 2, Col 3: Sleeveless closed-side upper torso matching the left character 1:1 (`torso`, including collar + cropped jacket + exposed midriff/belly if present on the left character, NO arms attached).
  * Row 2, Col 4: Matching lower pleated skirt / tactical coat hem (`coat_tail`, exact same fabric color, trim and waistband as the left character).
  * Row 3, Col 1: ONE single continuous upright arm (`arm_full`: rounded shoulder sleeve tapering smoothly down to cuff and cute clenched fist, hanging straight vertically, DO NOT split at elbow!).
  * Row 3, Col 2: ONE single continuous upright tapered chibi leg + boot (`leg_full`: smooth thigh/stocking tapering continuously into tactical boot standing straight vertically, DO NOT split at knee or ankle!).
  * Row 3, Col 3: Upright primary weapon (`weapon_primary`: <WEAPON_1>, blade/tip pointing straight UP, hilt/grip at the bottom).
  * Row 3, Col 4: Upright secondary weapon (`weapon_secondary`: <WEAPON_2>, head/tip pointing straight UP, handle/grip at the bottom).
```

---

## 3. 生图后必检 4 项清单（Visual Pre-Flight Check）

拿到 `raw_kit_front_34.png` 后，在运行 Python 拆件前用 `read_file` 快速扫视：
1. 背景是否为纯净统一的品红色（无渐变地板阴影、无多余框线文字）；
2. 右下角第 3 行第 1、2 格的**手臂与腿靴是否为完整不断开的一体件**（无肘部/膝盖分离）；
3. 第 1 行第 2、3、4 格的三颗无发小圆头（睁眼/闭眼/战吼）朝向与大小是否一致；
4. 各散件之间是否留有至少 `12px` 品红间隔（互不粘连）。若某两件轻微粘连，可让 `image-generator` 局部修整或在 `operator_spec.json` 的 `cell_overrides` 微调裁剪框。
