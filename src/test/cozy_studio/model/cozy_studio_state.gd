class_name CozyStudioState
extends RefCounted

## 2.5D 温馨工作室测试场景运行时状态。

enum CameraMode {
	TELEPHOTO_25 = 0, ## 黄金配方：24.5° 长焦微缩透视 + 34° 俯角
	ORTHO_DIORAMA = 1, ## 正交箱庭：零透视变形等轴测沙盘
	WIDE_70_COMPARE = 2, ## 反例对比：70° 传统广角透视（观察边缘拉伸感）
}

enum LightingMood {
	AFTERNOON_SUN = 0, ## 明媚午后斜射暖阳
	COZY_EVENING = 1, ## 傍晚台灯与咖啡吧吊灯暖调
}

var camera_mode: CameraMode = CameraMode.TELEPHOTO_25
var lighting_mood: LightingMood = LightingMood.AFTERNOON_SUN
var follow_camera: bool = true
var glue_enabled: bool = true
var player_pos: Vector3 = Vector3(-0.42, 0.0, 0.68)
var world_facing_dir: Vector3 = Vector3(sin(deg_to_rad(37.0)), 0.0, cos(deg_to_rad(37.0)))
