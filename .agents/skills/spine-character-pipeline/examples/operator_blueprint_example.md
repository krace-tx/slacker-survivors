# 角色配置蓝图范例（`operator_spec.json`）与正反范式对照

每个 Spine 角色在 `art/spines/<char_id>/operator_spec.json` 中通过一份声明式 JSON 驱动全链路拆件、去内描边补帽、17 环连续网格绑骨、方舟动作合成与五道门禁验证。

---

## 1. 标准 `operator_spec.json` 完整示例

```json
{
  "char_id": "vanguard_lupo",
  "title": "Rhodes Tactical Lupo Vanguard (2.8-Head 2.5D Chibi)",
  "canvas": {
    "width": 512,
    "height": 512,
    "ground_y": 448,
    "center_x": 256
  },
  "kit_source": "ai_sources/raw_kit_front_34.png",
  "export": {
    "out_dir": "../../src/test/spine_stage/assets/spines",
    "spine_name": "spn_spine_stage_vanguard",
    "write_godot_tres": true,
    "default_mix": 0.12
  },
  "style": {
    "far_limb_tint": [0.84, 0.80, 0.88],
    "slash_primary_color": "#38bdf8",
    "slash_core_color": "#e0f2fe",
    "skill_ring_color": "#f43f5e"
  },
  "proportions": {
    "target_total_height": 336,
    "head_scale": 1.0,
    "torso_scale": 1.0,
    "arm_length": 102,
    "leg_length": 118,
    "weapon_length": 176
  },
  "rig_tuning": {
    "neck_offset": [-2, -90],
    "shoulder_near_offset": [-24, -76],
    "shoulder_far_offset": [22, -74],
    "hip_near_offset": [-16, 6],
    "hip_far_offset": [16, 6],
    "coat_offset": [-4, -14],
    "head_acc_offset": [-6, -108],
    "weapon_grip_ratio_y": 0.78
  }
}
```

---

## 2. ❌ 典型翻车反模式 vs ✅ 工业级黄金范式

| 环节 | ❌ 翻车反模式（旧管线痛点） | ✅ 方舟级黄金范式（本管线强制标准） |
| :--- | :--- | :--- |
| **角色比例与拆件** | 画 6~7 头身写实长腿，把大腿、小腿、袜子、皮鞋切成 3~4 块带黑描边的散件 | 锁定 **2.8 头身人台垫图**，`arm_full` 与 `leg_full` 保持**单件一体锥形轮廓**，0 肘部/膝盖/脚踝切割线 |
| **关节搭接区处理** | 直接把带黑色闭合描边的散件叠在一起，一抬腿就露出“U 型木偶球关节黑线” | `slice_and_inpaint_caps.py` 自动识别搭接端深色描边并用 `cv2.inpaint` 以内部底色抹平 + 椭圆羽化帽 |
| **表情眨眼/战吼切换** | 两张带头发或不同尺寸的整头直接切透明度，眨眼时下巴耳朵跟着抽搐缩放 | `face_blink` / `face_skill` 通过轮廓配准后**仅提取内部五官椭圆融合进 `face_open` 外壳**，头部边缘 `0.00px` 零抖动 |
| **肢体与衣摆蒙皮** | 用 `parent` 刚体硬挂或粗糙 4×4 矩形格，弯曲时折出尖锐死角或衣摆根部脱离身体 | 使用 **17 环关节加密 `mesh` + Hermite `smoothstep` 显式权重**；衣摆/后发 `v <= 0.14` 顶点 `100%` 锁死躯干/头骨 |
| **步态与攻击补帧** | 全程手写 `Math.sin(2πt)` 对称正弦波，或对导出视频跑 `RIFE` 光流把黑描边糊成果冻 | 采用 **4 相位踏地挤压碎步 + `3:1:2:4` 瞬斩曲线 + 月牙刀光网格残影 + `60Hz` 弹簧物理滞后烘焙** |
