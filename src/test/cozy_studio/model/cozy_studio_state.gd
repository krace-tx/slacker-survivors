class_name CozyStudioState
extends RefCounted

## 2.5D 温馨工作室测试场景运行时状态（含相机、光影、角色世界朝向与 3D 家具交互姿态）。

enum CameraMode {
	TELEPHOTO_25 = 0, ## 黄金配方：24.5° 长焦微缩透视 + 28.5° 俯角
	ORTHO_DIORAMA = 1, ## 正交箱庭：零透视变形等轴测沙盘
	WIDE_70_COMPARE = 2, ## 反例对比：68° 传统广角透视（观察边缘拉伸感）
}

enum LightingMood {
	AFTERNOON_SUN = 0, ## 明媚午后斜射暖阳
	COZY_EVENING = 1, ## 傍晚台灯与咖啡吧吊灯暖调
}

enum InteractSpotId {
	NONE = 0,
	COFFEE_BAR = 1,        ## 右后意式咖啡吧台：冲泡拿铁 + 机器微震蒸汽
	WORKSTATION_CHAIR = 2, ## 左后双屏手绘屏工位：弧线小跳入座转椅摸鱼
	LOUNGE_SOFA = 3,       ## 右前奶油绿贵妃沙发：弧线小跳窝进沙发休息
	SLEEPING_CAT = 4,      ## 窗边针织蒲团橘猫：Q 弹呼噜回弹 + SVG 爱心气泡
}

enum PostureMode {
	STANDING = 0,
	TRANSITION_HOP = 1,
	SEATED = 2,
}

var camera_mode: CameraMode = CameraMode.TELEPHOTO_25
var lighting_mood: LightingMood = LightingMood.AFTERNOON_SUN
var follow_camera: bool = true
var glue_enabled: bool = true
var player_pos: Vector3 = Vector3(-0.42, 0.0, 0.68)
var world_facing_dir: Vector3 = Vector3(sin(deg_to_rad(37.0)), 0.0, cos(deg_to_rad(37.0)))

var hovered_spot: InteractSpotId = InteractSpotId.NONE
var posture_mode: PostureMode = PostureMode.STANDING
var seated_spot: InteractSpotId = InteractSpotId.NONE
var return_floor_pos: Vector3 = Vector3(-0.42, 0.0, 0.68)
