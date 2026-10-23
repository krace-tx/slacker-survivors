class_name SoulsKnightRig3D
extends Node3D

## 3D 魂系骑士与深渊薪王多关节装配式角色模型组件（位于 src/test/souls_arena/view/component/fighter/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 采用 `Root -> Pelvis -> Torso / LeftLeg / RightLeg / Head / RightArm(Weapon) / LeftArm(Shield) / Cape` 多层级关节枢轴树构建精细的哥特骑士与深渊薪王 3D 装甲模型（包含 24 个分层硬表面护甲、头盔羽饰/恶魔双角、披风、十字护手大剑与纹章盾牌子网格）；[br]
## 2. 支持全 3D 空间 360° 转向（`facing_yaw`）与多段连招差异化挥砍姿态（第 1 段右横扫、第 2 段反手快斩、第 3 段过顶跳劈重砸）。


#region 私有变量 — 关节枢轴树

var _is_boss: bool = false
var _primary_color: Color = Color(0.20, 0.72, 0.98)
var _scale_factor: float = 1.0
var _anim_clock: float = 0.0

var _root_pivot: Node3D = null
var _pelvis_pivot: Node3D = null
var _torso_pivot: Node3D = null
var _head_pivot: Node3D = null
var _cape_pivot: Node3D = null
var _left_leg_pivot: Node3D = null
var _right_leg_pivot: Node3D = null
var _right_arm_pivot: Node3D = null
var _left_arm_pivot: Node3D = null
var _weapon_pivot: Node3D = null
var _shield_pivot: Node3D = null

var _aura_sphere: MeshInstance3D = null
var _danger_ring: MeshInstance3D = null
var _slash_arc_ring: MeshInstance3D = null

#endregion


#region 私有变量 — PBR 材质库

var _plate_mat: StandardMaterial3D = null
var _dark_steel_mat: StandardMaterial3D = null
var _gold_trim_mat: StandardMaterial3D = null
var _cloth_mat: StandardMaterial3D = null
var _blade_mat: StandardMaterial3D = null
var _visor_mat: StandardMaterial3D = null
var _aura_mat: StandardMaterial3D = null
var _danger_mat: StandardMaterial3D = null
var _slash_arc_mat: StandardMaterial3D = null

#endregion


#region 构建多关节装配式 3D 骑士/薪王模型

func setup_rig(is_boss: bool, primary_color: Color) -> void:
	_is_boss = is_boss
	_primary_color = primary_color
	_scale_factor = 1.28 if is_boss else 1.0

	_init_pbr_materials()
	_build_hierarchy_and_meshes()


func _init_pbr_materials() -> void:
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = _primary_color
	_plate_mat.metallic = 0.68
	_plate_mat.roughness = 0.28

	_dark_steel_mat = StandardMaterial3D.new()
	_dark_steel_mat.albedo_color = Color(0.14, 0.16, 0.21)
	_dark_steel_mat.metallic = 0.78
	_dark_steel_mat.roughness = 0.36

	_gold_trim_mat = StandardMaterial3D.new()
	_gold_trim_mat.albedo_color = Color(0.92, 0.74, 0.32) if _is_boss else Color(0.78, 0.88, 0.98)
	_gold_trim_mat.metallic = 0.85
	_gold_trim_mat.roughness = 0.22

	_cloth_mat = StandardMaterial3D.new()
	_cloth_mat.albedo_color = (
		Color(0.36, 0.07, 0.10)
		if _is_boss
		else Color(0.09, 0.24, 0.42)
	)
	_cloth_mat.metallic = 0.05
	_cloth_mat.roughness = 0.82

	_blade_mat = StandardMaterial3D.new()
	_blade_mat.albedo_color = Color(0.94, 0.88, 0.82) if _is_boss else Color(0.88, 0.95, 1.0)
	_blade_mat.metallic = 0.92
	_blade_mat.roughness = 0.16

	_visor_mat = StandardMaterial3D.new()
	_visor_mat.albedo_color = Color(1.0, 0.26, 0.18) if _is_boss else Color(0.25, 0.95, 1.0)
	_visor_mat.emission_enabled = true
	_visor_mat.emission = _visor_mat.albedo_color
	_visor_mat.emission_energy_multiplier = 2.8

	_aura_mat = StandardMaterial3D.new()
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.albedo_color = Color(0.3, 0.9, 1.0, 0.0)
	_aura_mat.emission_enabled = true
	_aura_mat.emission = Color(0.3, 0.9, 1.0)
	_aura_mat.emission_energy_multiplier = 2.2

	_danger_mat = StandardMaterial3D.new()
	_danger_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_danger_mat.albedo_color = Color(1.0, 0.18, 0.2, 0.48)
	_danger_mat.emission_enabled = true
	_danger_mat.emission = Color(1.0, 0.15, 0.15)
	_danger_mat.emission_energy_multiplier = 2.8

	_slash_arc_mat = StandardMaterial3D.new()
	_slash_arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slash_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_slash_arc_mat.albedo_color = Color(1.0, 0.48, 0.22, 0.52) if _is_boss else Color(0.38, 0.90, 1.0, 0.52)
	_slash_arc_mat.emission_enabled = true
	_slash_arc_mat.emission = Color(1.0, 0.42, 0.16) if _is_boss else Color(0.32, 0.88, 1.0)
	_slash_arc_mat.emission_energy_multiplier = 3.2


func _build_hierarchy_and_meshes() -> void:
	_root_pivot = Node3D.new()
	_root_pivot.scale = Vector3.ONE * _scale_factor
	add_child(_root_pivot)

	_pelvis_pivot = Node3D.new()
	_pelvis_pivot.position = Vector3(0.0, 0.82, 0.0)
	_root_pivot.add_child(_pelvis_pivot)

	_build_pelvis_and_tassets()
	_build_articulated_legs()
	_build_torso_and_cape()
	_build_greathelm_and_crest()
	_build_right_arm_and_greatsword()
	_build_left_arm_and_greatshield()
	_build_vfx_auras()


func _build_pelvis_and_tassets() -> void:
	var pelvis_cyl: CylinderMesh = CylinderMesh.new()
	pelvis_cyl.top_radius = 0.26
	pelvis_cyl.bottom_radius = 0.23
	pelvis_cyl.height = 0.24
	_add_mesh(_pelvis_pivot, pelvis_cyl, _dark_steel_mat, Vector3.ZERO)

	var belt_cyl: CylinderMesh = CylinderMesh.new()
	belt_cyl.top_radius = 0.275
	belt_cyl.bottom_radius = 0.275
	belt_cyl.height = 0.07
	_add_mesh(_pelvis_pivot, belt_cyl, _gold_trim_mat, Vector3(0.0, 0.08, 0.0))

	var tabard_box: BoxMesh = BoxMesh.new()
	tabard_box.size = Vector3(0.36, 0.42, 0.16)
	_add_mesh(_pelvis_pivot, tabard_box, _cloth_mat, Vector3(0.10, -0.18, 0.0))

	var tasset_box: BoxMesh = BoxMesh.new()
	tasset_box.size = Vector3(0.28, 0.28, 0.07)
	_add_mesh(
		_pelvis_pivot,
		tasset_box,
		_plate_mat,
		Vector3(0.02, -0.10, 0.24),
		Vector3(deg_to_rad(10.0), 0.0, 0.0)
	)
	_add_mesh(
		_pelvis_pivot,
		tasset_box,
		_plate_mat,
		Vector3(0.02, -0.10, -0.24),
		Vector3(deg_to_rad(-10.0), 0.0, 0.0)
	)


func _build_articulated_legs() -> void:
	_left_leg_pivot = Node3D.new()
	_left_leg_pivot.position = Vector3(0.0, -0.06, -0.14)
	_pelvis_pivot.add_child(_left_leg_pivot)
	_populate_single_leg(_left_leg_pivot)

	_right_leg_pivot = Node3D.new()
	_right_leg_pivot.position = Vector3(0.0, -0.06, 0.14)
	_pelvis_pivot.add_child(_right_leg_pivot)
	_populate_single_leg(_right_leg_pivot)


func _populate_single_leg(leg_root: Node3D) -> void:
	var thigh_cyl: CylinderMesh = CylinderMesh.new()
	thigh_cyl.top_radius = 0.12
	thigh_cyl.bottom_radius = 0.095
	thigh_cyl.height = 0.36
	_add_mesh(leg_root, thigh_cyl, _dark_steel_mat, Vector3(0.0, -0.18, 0.0))

	# 大腿前侧叠层护腿甲 (Cuisse Plate)
	var cuisse_box: BoxMesh = BoxMesh.new()
	cuisse_box.size = Vector3(0.08, 0.26, 0.16)
	_add_mesh(leg_root, cuisse_box, _plate_mat, Vector3(0.08, -0.18, 0.0))

	var knee_sphere: SphereMesh = SphereMesh.new()
	knee_sphere.radius = 0.115
	knee_sphere.height = 0.23
	_add_mesh(leg_root, knee_sphere, _gold_trim_mat, Vector3(0.03, -0.37, 0.0))

	# 哥特式尖刺护膝翼片 (Poleyn Wing)
	var knee_fin: PrismMesh = PrismMesh.new()
	knee_fin.size = Vector3(0.14, 0.18, 0.06)
	_add_mesh(
		leg_root,
		knee_fin,
		_gold_trim_mat,
		Vector3(0.11, -0.36, 0.0),
		Vector3(0.0, 0.0, deg_to_rad(-90.0))
	)

	var shin_cyl: CylinderMesh = CylinderMesh.new()
	shin_cyl.top_radius = 0.105
	shin_cyl.bottom_radius = 0.082
	shin_cyl.height = 0.36
	_add_mesh(leg_root, shin_cyl, _plate_mat, Vector3(0.0, -0.54, 0.0))

	var boot_box: BoxMesh = BoxMesh.new()
	boot_box.size = Vector3(0.28, 0.11, 0.15)
	_add_mesh(leg_root, boot_box, _dark_steel_mat, Vector3(0.05, -0.71, 0.0))

	# 哥特尖头铁靴前尖 (Sabaton Toe Tip)
	var boot_tip: PrismMesh = PrismMesh.new()
	boot_tip.size = Vector3(0.11, 0.12, 0.14)
	_add_mesh(
		leg_root,
		boot_tip,
		_plate_mat,
		Vector3(0.22, -0.71, 0.0),
		Vector3(0.0, 0.0, deg_to_rad(-90.0))
	)


func _build_torso_and_cape() -> void:
	_torso_pivot = Node3D.new()
	_torso_pivot.position = Vector3(0.0, 0.12, 0.0)
	_pelvis_pivot.add_child(_torso_pivot)

	var abdomen_cyl: CylinderMesh = CylinderMesh.new()
	abdomen_cyl.top_radius = 0.31
	abdomen_cyl.bottom_radius = 0.24
	abdomen_cyl.height = 0.56
	_add_mesh(_torso_pivot, abdomen_cyl, _dark_steel_mat, Vector3(0.0, 0.28, 0.0))

	# 腹部三段叠层龙虾甲片 (Plackart Lames)
	for lame_idx: int in range(2):
		var lame_cyl: CylinderMesh = CylinderMesh.new()
		lame_cyl.top_radius = 0.28 + float(lame_idx) * 0.02
		lame_cyl.bottom_radius = 0.26 + float(lame_idx) * 0.02
		lame_cyl.height = 0.07
		_add_mesh(_torso_pivot, lame_cyl, _plate_mat, Vector3(0.01, 0.10 + float(lame_idx) * 0.08, 0.0))

	var chest_box: BoxMesh = BoxMesh.new()
	chest_box.size = Vector3(0.46, 0.44, 0.56)
	_add_mesh(_torso_pivot, chest_box, _plate_mat, Vector3(0.03, 0.36, 0.0))

	# 哥特式斜切 V 字胸甲棱线与金边护胸板
	var breast_ridge_l: BoxMesh = BoxMesh.new()
	breast_ridge_l.size = Vector3(0.12, 0.36, 0.24)
	_add_mesh(
		_torso_pivot,
		breast_ridge_l,
		_plate_mat,
		Vector3(0.22, 0.37, 0.13),
		Vector3(deg_to_rad(14.0), deg_to_rad(-16.0), 0.0)
	)
	_add_mesh(
		_torso_pivot,
		breast_ridge_l,
		_plate_mat,
		Vector3(0.22, 0.37, -0.13),
		Vector3(deg_to_rad(-14.0), deg_to_rad(16.0), 0.0)
	)

	var core_box: BoxMesh = BoxMesh.new()
	core_box.size = Vector3(0.50, 0.15, 0.15)
	_add_mesh(
		_torso_pivot,
		core_box,
		_visor_mat,
		Vector3(0.06, 0.38, 0.0),
		Vector3(deg_to_rad(45.0), 0.0, 0.0)
	)

	# 胸口金边护心镜外框
	var core_frame: BoxMesh = BoxMesh.new()
	core_frame.size = Vector3(0.48, 0.21, 0.21)
	_add_mesh(
		_torso_pivot,
		core_frame,
		_gold_trim_mat,
		Vector3(0.04, 0.38, 0.0),
		Vector3(deg_to_rad(45.0), 0.0, 0.0)
	)

	# 背部脊椎立体装甲脊柱
	for spine_i: int in range(3):
		var spine_node: PrismMesh = PrismMesh.new()
		spine_node.size = Vector3(0.10, 0.12, 0.12)
		_add_mesh(
			_torso_pivot,
			spine_node,
			_gold_trim_mat,
			Vector3(-0.22, 0.20 + float(spine_i) * 0.14, 0.0),
			Vector3(0.0, 0.0, deg_to_rad(90.0))
		)

	var collar_cyl: CylinderMesh = CylinderMesh.new()
	collar_cyl.top_radius = 0.23
	collar_cyl.bottom_radius = 0.28
	collar_cyl.height = 0.13
	_add_mesh(_torso_pivot, collar_cyl, _gold_trim_mat, Vector3(0.0, 0.60, 0.0))

	# 披风双肩金质圆扣 (Cloak Clasps)
	var clasp_sphere: SphereMesh = SphereMesh.new()
	clasp_sphere.radius = 0.065
	clasp_sphere.height = 0.13
	_add_mesh(_torso_pivot, clasp_sphere, _gold_trim_mat, Vector3(-0.14, 0.56, 0.22))
	_add_mesh(_torso_pivot, clasp_sphere, _gold_trim_mat, Vector3(-0.14, 0.56, -0.22))

	_cape_pivot = Node3D.new()
	_cape_pivot.position = Vector3(-0.20, 0.56, 0.0)
	_torso_pivot.add_child(_cape_pivot)

	var cape_upper: BoxMesh = BoxMesh.new()
	cape_upper.size = Vector3(0.05, 1.04, 0.54)
	_add_mesh(
		_cape_pivot,
		cape_upper,
		_cloth_mat,
		Vector3(-0.10, -0.48, 0.0),
		Vector3(0.0, 0.0, deg_to_rad(12.0))
	)
	# 左右两侧飘逸披风翼片与金边下摆
	var cape_wing: BoxMesh = BoxMesh.new()
	cape_wing.size = Vector3(0.04, 0.96, 0.22)
	_add_mesh(
		_cape_pivot,
		cape_wing,
		_cloth_mat,
		Vector3(-0.08, -0.46, 0.30),
		Vector3(deg_to_rad(8.0), deg_to_rad(-12.0), deg_to_rad(11.0))
	)
	_add_mesh(
		_cape_pivot,
		cape_wing,
		_cloth_mat,
		Vector3(-0.08, -0.46, -0.30),
		Vector3(deg_to_rad(-8.0), deg_to_rad(12.0), deg_to_rad(11.0))
	)
	var cape_hem: BoxMesh = BoxMesh.new()
	cape_hem.size = Vector3(0.06, 0.06, 0.56)
	_add_mesh(
		_cape_pivot,
		cape_hem,
		_gold_trim_mat,
		Vector3(-0.21, -0.98, 0.0),
		Vector3(0.0, 0.0, deg_to_rad(12.0))
	)


func _build_greathelm_and_crest() -> void:
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0.0, 0.66, 0.0)
	_torso_pivot.add_child(_head_pivot)

	var helm_cyl: CylinderMesh = CylinderMesh.new()
	helm_cyl.top_radius = 0.175
	helm_cyl.bottom_radius = 0.195
	helm_cyl.height = 0.36
	_add_mesh(_head_pivot, helm_cyl, _plate_mat, Vector3(0.0, 0.18, 0.0))

	var dome_sphere: SphereMesh = SphereMesh.new()
	dome_sphere.radius = 0.175
	dome_sphere.height = 0.22
	_add_mesh(_head_pivot, dome_sphere, _gold_trim_mat, Vector3(0.0, 0.34, 0.0))

	# 楔形破风骑士面甲 (Beveled Visor Faceplate)
	var faceplate: PrismMesh = PrismMesh.new()
	faceplate.size = Vector3(0.26, 0.16, 0.28)
	_add_mesh(
		_head_pivot,
		faceplate,
		_dark_steel_mat,
		Vector3(0.14, 0.17, 0.0),
		Vector3(0.0, 0.0, deg_to_rad(-90.0))
	)

	# 十字金边面甲鼻梁条
	var nasal_bar: BoxMesh = BoxMesh.new()
	nasal_bar.size = Vector3(0.05, 0.26, 0.04)
	_add_mesh(_head_pivot, nasal_bar, _gold_trim_mat, Vector3(0.20, 0.18, 0.0))

	var visor_slit: BoxMesh = BoxMesh.new()
	visor_slit.size = Vector3(0.14, 0.055, 0.25)
	_add_mesh(_head_pivot, visor_slit, _visor_mat, Vector3(0.15, 0.22, 0.0))

	if _is_boss:
		# 深渊薪王专属：五芒烈焰王冠 + 双曲深渊巨角
		var crown_ring: TorusMesh = TorusMesh.new()
		crown_ring.inner_radius = 0.15
		crown_ring.outer_radius = 0.19
		_add_mesh(_head_pivot, crown_ring, _gold_trim_mat, Vector3(0.0, 0.36, 0.0))

		for c_idx: int in range(5):
			var c_ang: float = TAU * float(c_idx) / 5.0
			var spike: PrismMesh = PrismMesh.new()
			spike.size = Vector3(0.06, 0.16, 0.04)
			_add_mesh(
				_head_pivot,
				spike,
				_gold_trim_mat,
				Vector3(cos(c_ang) * 0.16, 0.44, sin(c_ang) * 0.16),
				Vector3(0.0, -c_ang, 0.0)
			)

		var horn_cyl: CylinderMesh = CylinderMesh.new()
		horn_cyl.top_radius = 0.015
		horn_cyl.bottom_radius = 0.058
		horn_cyl.height = 0.48
		_add_mesh(
			_head_pivot,
			horn_cyl,
			_gold_trim_mat,
			Vector3(0.04, 0.46, 0.19),
			Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(-18.0))
		)
		_add_mesh(
			_head_pivot,
			horn_cyl,
			_gold_trim_mat,
			Vector3(0.04, 0.46, -0.19),
			Vector3(deg_to_rad(30.0), 0.0, deg_to_rad(-18.0))
		)
	else:
		# 灰烬骑士专属：金属冠脊 + 双层流光羽冠
		var crest_holder: BoxMesh = BoxMesh.new()
		crest_holder.size = Vector3(0.26, 0.08, 0.05)
		_add_mesh(_head_pivot, crest_holder, _gold_trim_mat, Vector3(-0.02, 0.40, 0.0))

		var plume_box: BoxMesh = BoxMesh.new()
		plume_box.size = Vector3(0.46, 0.15, 0.07)
		_add_mesh(
			_head_pivot,
			plume_box,
			_visor_mat,
			Vector3(-0.10, 0.46, 0.0),
			Vector3(0.0, 0.0, deg_to_rad(18.0))
		)
		var plume_tail: BoxMesh = BoxMesh.new()
		plume_tail.size = Vector3(0.34, 0.10, 0.05)
		_add_mesh(
			_head_pivot,
			plume_tail,
			_cloth_mat,
			Vector3(-0.26, 0.36, 0.0),
			Vector3(0.0, 0.0, deg_to_rad(36.0))
		)


func _build_right_arm_and_greatsword() -> void:
	_right_arm_pivot = Node3D.new()
	_right_arm_pivot.position = Vector3(0.04, 0.50, 0.36)
	_torso_pivot.add_child(_right_arm_pivot)

	var pauldron_sphere: SphereMesh = SphereMesh.new()
	pauldron_sphere.radius = 0.185
	pauldron_sphere.height = 0.31
	_add_mesh(_right_arm_pivot, pauldron_sphere, _plate_mat, Vector3(0.0, 0.04, 0.06))

	var pauldron_trim: BoxMesh = BoxMesh.new()
	pauldron_trim.size = Vector3(0.29, 0.06, 0.29)
	_add_mesh(_right_arm_pivot, pauldron_trim, _gold_trim_mat, Vector3(0.0, -0.04, 0.06))

	if _is_boss:
		var p_spike: PrismMesh = PrismMesh.new()
		p_spike.size = Vector3(0.08, 0.22, 0.08)
		_add_mesh(
			_right_arm_pivot,
			p_spike,
			_gold_trim_mat,
			Vector3(0.0, 0.22, 0.12),
			Vector3(deg_to_rad(-22.0), 0.0, 0.0)
		)

	var arm_cyl: CylinderMesh = CylinderMesh.new()
	arm_cyl.top_radius = 0.085
	arm_cyl.bottom_radius = 0.075
	arm_cyl.height = 0.38
	_add_mesh(
		_right_arm_pivot,
		arm_cyl,
		_dark_steel_mat,
		Vector3(0.12, -0.16, 0.04),
		Vector3(0.0, 0.0, deg_to_rad(35.0))
	)

	# 护肘与前臂铁手甲 (Couter & Gauntlet)
	var couter_sphere: SphereMesh = SphereMesh.new()
	couter_sphere.radius = 0.088
	couter_sphere.height = 0.17
	_add_mesh(_right_arm_pivot, couter_sphere, _gold_trim_mat, Vector3(0.16, -0.20, 0.05))

	var gauntlet_box: BoxMesh = BoxMesh.new()
	gauntlet_box.size = Vector3(0.15, 0.12, 0.13)
	_add_mesh(_right_arm_pivot, gauntlet_box, _plate_mat, Vector3(0.23, -0.26, 0.04))

	_weapon_pivot = Node3D.new()
	_weapon_pivot.position = Vector3(0.24, -0.26, 0.04)
	_right_arm_pivot.add_child(_weapon_pivot)

	var pommel: SphereMesh = SphereMesh.new()
	pommel.radius = 0.072
	pommel.height = 0.14
	_add_mesh(_weapon_pivot, pommel, _gold_trim_mat, Vector3(-0.24, 0.0, 0.0))

	var grip: CylinderMesh = CylinderMesh.new()
	grip.top_radius = 0.036
	grip.bottom_radius = 0.036
	grip.height = 0.28
	_add_mesh(
		_weapon_pivot,
		grip,
		_dark_steel_mat,
		Vector3(-0.08, 0.0, 0.0),
		Vector3(0.0, 0.0, deg_to_rad(90.0))
	)

	# 翼状十字护手与侧护环 (Winged Crossguard & Side Ring)
	var guard: BoxMesh = BoxMesh.new()
	guard.size = Vector3(0.10, 0.48 if _is_boss else 0.38, 0.15)
	_add_mesh(_weapon_pivot, guard, _gold_trim_mat, Vector3(0.06, 0.0, 0.0))

	var guard_ring: TorusMesh = TorusMesh.new()
	guard_ring.inner_radius = 0.07
	guard_ring.outer_radius = 0.10
	_add_mesh(_weapon_pivot, guard_ring, _gold_trim_mat, Vector3(0.09, 0.0, 0.0))

	var blade_len: float = 1.66 if _is_boss else 1.24
	var blade_w: float = 0.20 if _is_boss else 0.125
	var blade: BoxMesh = BoxMesh.new()
	blade.size = Vector3(blade_len, blade_w, 0.045)
	_add_mesh(_weapon_pivot, blade, _blade_mat, Vector3(0.08 + blade_len * 0.5, 0.0, 0.0))

	# 菱形破甲剑尖 (Diamond Sword Tip)
	var blade_tip: PrismMesh = PrismMesh.new()
	blade_tip.size = Vector3(blade_w, 0.28 if _is_boss else 0.22, 0.045)
	_add_mesh(
		_weapon_pivot,
		blade_tip,
		_blade_mat,
		Vector3(0.08 + blade_len + (0.14 if _is_boss else 0.11), 0.0, 0.0),
		Vector3(0.0, 0.0, deg_to_rad(-90.0))
	)

	var fuller: BoxMesh = BoxMesh.new()
	fuller.size = Vector3(blade_len * 0.78, blade_w * 0.38, 0.056)
	_add_mesh(_weapon_pivot, fuller, _visor_mat, Vector3(0.08 + blade_len * 0.42, 0.0, 0.0))


func _build_left_arm_and_greatshield() -> void:
	_left_arm_pivot = Node3D.new()
	_left_arm_pivot.position = Vector3(0.04, 0.50, -0.36)
	_torso_pivot.add_child(_left_arm_pivot)

	var pauldron_sphere: SphereMesh = SphereMesh.new()
	pauldron_sphere.radius = 0.185
	pauldron_sphere.height = 0.31
	_add_mesh(_left_arm_pivot, pauldron_sphere, _plate_mat, Vector3(0.0, 0.04, -0.06))

	var pauldron_trim: BoxMesh = BoxMesh.new()
	pauldron_trim.size = Vector3(0.29, 0.06, 0.29)
	_add_mesh(_left_arm_pivot, pauldron_trim, _gold_trim_mat, Vector3(0.0, -0.04, -0.06))

	if _is_boss:
		var p_spike: PrismMesh = PrismMesh.new()
		p_spike.size = Vector3(0.08, 0.22, 0.08)
		_add_mesh(
			_left_arm_pivot,
			p_spike,
			_gold_trim_mat,
			Vector3(0.0, 0.22, -0.12),
			Vector3(deg_to_rad(22.0), 0.0, 0.0)
		)

	_shield_pivot = Node3D.new()
	_shield_pivot.position = Vector3(0.24, -0.14, -0.10)
	_left_arm_pivot.add_child(_shield_pivot)

	var shield_body: BoxMesh = BoxMesh.new()
	shield_body.size = Vector3(0.08, 0.86, 0.54)
	_add_mesh(_shield_pivot, shield_body, _plate_mat, Vector3.ZERO)

	# 盾牌底部尖锥收口 (Heater Shield Bottom Wedge)
	var shield_bottom: PrismMesh = PrismMesh.new()
	shield_bottom.size = Vector3(0.54, 0.22, 0.08)
	_add_mesh(
		_shield_pivot,
		shield_bottom,
		_plate_mat,
		Vector3(0.0, -0.54, 0.0),
		Vector3(0.0, deg_to_rad(90.0), deg_to_rad(180.0))
	)

	var shield_trim_v: BoxMesh = BoxMesh.new()
	shield_trim_v.size = Vector3(0.10, 0.96, 0.08)
	_add_mesh(_shield_pivot, shield_trim_v, _gold_trim_mat, Vector3(0.01, -0.04, 0.0))

	var shield_trim_h: BoxMesh = BoxMesh.new()
	shield_trim_h.size = Vector3(0.10, 0.08, 0.58)
	_add_mesh(_shield_pivot, shield_trim_h, _gold_trim_mat, Vector3(0.01, 0.10, 0.0))

	var shield_boss: SphereMesh = SphereMesh.new()
	shield_boss.radius = 0.12
	shield_boss.height = 0.15
	_add_mesh(_shield_pivot, shield_boss, _visor_mat, Vector3(0.04, 0.10, 0.0))


func _build_vfx_auras() -> void:
	_aura_sphere = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.08
	sphere.height = 2.16
	_aura_sphere.mesh = sphere
	_aura_sphere.position = Vector3(0.0, 1.05, 0.0)
	_aura_sphere.material_override = _aura_mat
	_aura_sphere.visible = false
	_root_pivot.add_child(_aura_sphere)

	# 3D 挥剑刀光残影环 (Slash Arc Trail)
	_slash_arc_ring = MeshInstance3D.new()
	var arc_torus: TorusMesh = TorusMesh.new()
	arc_torus.inner_radius = 1.35
	arc_torus.outer_radius = 1.88
	_slash_arc_ring.mesh = arc_torus
	_slash_arc_ring.position = Vector3(0.32, 1.12, 0.0)
	_slash_arc_ring.material_override = _slash_arc_mat
	_slash_arc_ring.visible = false
	_root_pivot.add_child(_slash_arc_ring)

	_danger_ring = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.85
	cyl.bottom_radius = 1.85
	cyl.height = 0.04
	_danger_ring.mesh = cyl
	_danger_ring.position = Vector3(0.0, 0.03, 0.0)
	_danger_ring.material_override = _danger_mat
	_danger_ring.visible = false
	add_child(_danger_ring)


func _add_mesh(
	parent: Node3D,
	mesh_res: Mesh,
	mat: Material,
	pos: Vector3,
	rot_rad: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var inst: MeshInstance3D = MeshInstance3D.new()
	inst.mesh = mesh_res
	inst.material_override = mat
	inst.position = pos
	inst.rotation = rot_rad
	parent.add_child(inst)
	return inst

#endregion


#region 每帧程序化 3D 骨骼姿态与多段连招挥砍动画驱动

func update_pose(
	delta: float,
	state_name: StringName,
	state_elapsed: float,
	facing_yaw: float,
	is_invincible_iframe: bool,
	is_unblockable_attack: bool,
	windup_duration: float,
	flash_timer: float,
	combo_step: int = 1,
	is_hyper_armor_active: bool = false
) -> void:
	if _root_pivot == null:
		return

	_anim_clock += delta
	_root_pivot.scale = Vector3.ONE * _scale_factor
	_root_pivot.rotation = Vector3(0.0, facing_yaw, 0.0)

	# 复位关节基准姿态
	_pelvis_pivot.position = Vector3(0.0, 0.82, 0.0)
	_pelvis_pivot.rotation = Vector3.ZERO
	_torso_pivot.rotation = Vector3.ZERO
	_head_pivot.rotation = Vector3.ZERO
	_left_leg_pivot.rotation = Vector3.ZERO
	_right_leg_pivot.rotation = Vector3.ZERO
	_right_arm_pivot.rotation = Vector3.ZERO
	_left_arm_pivot.rotation = Vector3.ZERO
	_weapon_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(18.0))
	_shield_pivot.position = Vector3(0.24, -0.14, -0.10)
	_shield_pivot.rotation = Vector3.ZERO
	_cape_pivot.rotation = Vector3.ZERO

	_aura_sphere.visible = false
	_danger_ring.visible = false
	if _slash_arc_ring != null:
		_slash_arc_ring.visible = false

	if flash_timer > 0.0:
		_plate_mat.albedo_color = Color(1.0, 1.0, 1.0)
	else:
		_plate_mat.albedo_color = _primary_color

	match state_name:
		SoulsCombatConfig.STATE_IDLE:
			var breath: float = sin(_anim_clock * 3.2)
			_pelvis_pivot.position.y = 0.82 + breath * 0.025
			_right_arm_pivot.rotation.z = deg_to_rad(-8.0 + breath * 3.0)
			_cape_pivot.rotation.z = deg_to_rad(4.0 + sin(_anim_clock * 2.4) * 3.5)

		SoulsCombatConfig.STATE_MOVE:
			var stride: float = sin(_anim_clock * 11.5)
			_pelvis_pivot.position.y = 0.82 + absf(stride) * 0.05
			_torso_pivot.rotation.z = deg_to_rad(-7.0)
			_left_leg_pivot.rotation.z = deg_to_rad(stride * 34.0)
			_right_leg_pivot.rotation.z = deg_to_rad(-stride * 34.0)
			_right_arm_pivot.rotation.z = deg_to_rad(-16.0 - stride * 14.0)
			_left_arm_pivot.rotation.z = deg_to_rad(stride * 14.0)
			_cape_pivot.rotation.z = deg_to_rad(22.0 + absf(stride) * 10.0)

		SoulsCombatConfig.STATE_DODGE:
			var roll_ratio: float = clampf(state_elapsed / SoulsCombatConfig.DODGE_DURATION, 0.0, 1.0)
			_pelvis_pivot.rotation.z = -TAU * roll_ratio
			_pelvis_pivot.position.y = 0.72 + sin(roll_ratio * PI) * 0.42
			_left_leg_pivot.rotation.z = deg_to_rad(45.0)
			_right_leg_pivot.rotation.z = deg_to_rad(-25.0)
			if is_invincible_iframe:
				_aura_sphere.visible = true
				_aura_mat.albedo_color = Color(0.20, 0.95, 1.0, 0.34)
				_aura_mat.emission = Color(0.20, 0.95, 1.0)

		SoulsCombatConfig.STATE_PARRY:
			_torso_pivot.rotation.y = deg_to_rad(22.0)
			_left_arm_pivot.rotation.z = deg_to_rad(32.0)
			_shield_pivot.position = Vector3(0.46, 0.04, 0.16)
			_right_arm_pivot.rotation.z = deg_to_rad(48.0)
			_aura_sphere.visible = true
			_aura_mat.albedo_color = Color(1.0, 0.88, 0.22, 0.42)
			_aura_mat.emission = Color(1.0, 0.85, 0.20)

		SoulsCombatConfig.STATE_BLOCK:
			_pelvis_pivot.position.y = 0.76
			_left_leg_pivot.rotation.z = deg_to_rad(18.0)
			_right_leg_pivot.rotation.z = deg_to_rad(-18.0)
			_shield_pivot.position = Vector3(0.42, 0.02, 0.18)
			_aura_sphere.visible = true
			_aura_mat.albedo_color = Color(0.32, 0.72, 1.0, 0.22)
			_aura_mat.emission = Color(0.32, 0.72, 1.0)

		SoulsCombatConfig.STATE_ATTACK_WINDUP:
			var ratio: float = clampf(state_elapsed / maxf(0.05, windup_duration), 0.0, 1.0)
			# 若为慢刀假动作长前摇 (windup_duration >= 0.80s)，前 75% 时间巨剑高举悬停震颤，最后 25% 猛然加速！
			var pose_ratio: float = ratio
			var tremor_deg: float = 0.0
			if windup_duration >= 0.80:
				pose_ratio = clampf(ratio * 1.45, 0.0, 1.0)
				if ratio > 0.35 and ratio < 0.88:
					tremor_deg = sin(_anim_clock * 38.0) * 5.0

			if combo_step == 2:
				_torso_pivot.rotation.y = deg_to_rad(lerpf(0.0, 38.0, pose_ratio))
				_right_arm_pivot.rotation.y = deg_to_rad(lerpf(0.0, 48.0, pose_ratio))
				_right_arm_pivot.rotation.z = deg_to_rad(lerpf(10.0, 72.0, pose_ratio) + tremor_deg)
			elif combo_step >= 3 or windup_duration >= 0.80:
				_pelvis_pivot.position.y = 0.82 + sin(pose_ratio * PI * 0.65) * 0.36
				_torso_pivot.rotation.z = deg_to_rad(lerpf(0.0, 24.0, pose_ratio))
				_right_arm_pivot.rotation.z = deg_to_rad(lerpf(15.0, 134.0, pose_ratio) + tremor_deg)
			else:
				_torso_pivot.rotation.y = deg_to_rad(lerpf(0.0, -32.0, pose_ratio))
				_torso_pivot.rotation.z = deg_to_rad(lerpf(0.0, 14.0, pose_ratio))
				_right_arm_pivot.rotation.z = deg_to_rad(lerpf(10.0, 105.0, pose_ratio))

			_weapon_pivot.rotation.z = deg_to_rad(lerpf(18.0, 46.0, pose_ratio) + tremor_deg)
			_left_leg_pivot.rotation.z = deg_to_rad(-22.0 * pose_ratio)
			_right_leg_pivot.rotation.z = deg_to_rad(22.0 * pose_ratio)

			if is_hyper_armor_active:
				_aura_sphere.visible = true
				_aura_mat.albedo_color = Color(1.0, 0.56, 0.12, 0.26)
				_aura_mat.emission = Color(1.0, 0.58, 0.14)

			if is_unblockable_attack:
				_danger_ring.visible = true
				var ring_s: float = lerpf(0.65, 1.32, ratio)
				_danger_ring.scale = Vector3(ring_s, 1.0, ring_s)
				_danger_mat.albedo_color = Color(1.0, 0.18, 0.20, 0.48)
				_blade_mat.emission_enabled = true
				_blade_mat.emission = Color(1.0, 0.18, 0.18)
				_blade_mat.emission_energy_multiplier = 3.2
			else:
				_blade_mat.emission_enabled = true
				_blade_mat.emission = Color(1.0, 0.75, 0.25)
				_blade_mat.emission_energy_multiplier = 1.6

		SoulsCombatConfig.STATE_ATTACK_SLASH, SoulsCombatConfig.STATE_RIPOSTE:
			if is_hyper_armor_active:
				_aura_sphere.visible = true
				_aura_mat.albedo_color = Color(1.0, 0.56, 0.12, 0.28)
				_aura_mat.emission = Color(1.0, 0.58, 0.14)
			if _slash_arc_ring != null:
				_slash_arc_ring.visible = true
				var arc_col: Color = (
					Color(1.0, 0.72, 0.18, 0.65)
					if is_hyper_armor_active or state_name == SoulsCombatConfig.STATE_RIPOSTE
					else (Color(1.0, 0.35, 0.20, 0.55) if _is_boss else Color(0.32, 0.90, 1.0, 0.55))
				)
				_slash_arc_mat.albedo_color = arc_col
				_slash_arc_mat.emission = Color(arc_col.r, arc_col.g, arc_col.b)
				if combo_step == 2:
					_slash_arc_ring.rotation = Vector3(deg_to_rad(18.0), 0.0, deg_to_rad(-16.0))
				elif combo_step >= 3:
					_slash_arc_ring.rotation = Vector3(deg_to_rad(72.0), 0.0, deg_to_rad(12.0))
				else:
					_slash_arc_ring.rotation = Vector3(deg_to_rad(-22.0), 0.0, deg_to_rad(14.0))
			_pelvis_pivot.position.x = 0.26
			_pelvis_pivot.position.y = 0.74
			if combo_step == 2:
				_torso_pivot.rotation.y = deg_to_rad(-34.0)
				_right_arm_pivot.rotation.y = deg_to_rad(-42.0)
				_right_arm_pivot.rotation.z = deg_to_rad(-38.0)
			else:
				_torso_pivot.rotation.y = deg_to_rad(30.0)
				_torso_pivot.rotation.z = deg_to_rad(-18.0)
				_right_arm_pivot.rotation.z = deg_to_rad(-58.0)
			_weapon_pivot.rotation.z = deg_to_rad(-34.0)
			_left_leg_pivot.rotation.z = deg_to_rad(32.0)
			_right_leg_pivot.rotation.z = deg_to_rad(-28.0)
			_cape_pivot.rotation.z = deg_to_rad(36.0)

		SoulsCombatConfig.STATE_ATTACK_RECOVERY:
			# 收刀后摇破绽期：巨剑砸地后身体前倾低俯，缓慢拔剑收势（明显视觉破绽）
			var rec_Wave: float = clampf(state_elapsed * 1.4, 0.0, 1.0)
			_pelvis_pivot.position.x = lerpf(0.22, 0.0, rec_Wave)
			_pelvis_pivot.position.y = lerpf(0.68, 0.80, rec_Wave)
			_torso_pivot.rotation.z = deg_to_rad(lerpf(-22.0, -6.0, rec_Wave))
			_head_pivot.rotation.z = deg_to_rad(lerpf(-14.0, 0.0, rec_Wave))
			_right_arm_pivot.rotation.z = deg_to_rad(lerpf(-62.0, -14.0, rec_Wave))
			_weapon_pivot.rotation.z = deg_to_rad(lerpf(-42.0, 12.0, rec_Wave))
			_left_leg_pivot.rotation.z = deg_to_rad(lerpf(28.0, 6.0, rec_Wave))
			_right_leg_pivot.rotation.z = deg_to_rad(lerpf(-24.0, -6.0, rec_Wave))

		SoulsCombatConfig.STATE_HIT_STUN:
			_torso_pivot.rotation.z = deg_to_rad(22.0)
			_head_pivot.rotation.z = deg_to_rad(16.0)
			_right_arm_pivot.rotation.z = deg_to_rad(28.0)

		SoulsCombatConfig.STATE_STAGGERED:
			_pelvis_pivot.position.y = 0.48
			_torso_pivot.rotation.z = deg_to_rad(-24.0)
			_head_pivot.rotation.z = deg_to_rad(-20.0)
			_left_leg_pivot.rotation.z = deg_to_rad(52.0)
			_right_leg_pivot.rotation.z = deg_to_rad(-65.0)
			_right_arm_pivot.rotation.z = deg_to_rad(-68.0)
			_danger_ring.visible = true
			_danger_mat.albedo_color = Color(1.0, 0.78, 0.20, 0.48)

		SoulsCombatConfig.STATE_DEAD:
			# 战败倒地终态：单膝跪倒后向前扑倒于石板地面
			var fall_ratio: float = clampf(state_elapsed / 0.65, 0.0, 1.0)
			_pelvis_pivot.position.y = lerpf(0.82, 0.24, fall_ratio)
			_torso_pivot.rotation.z = deg_to_rad(lerpf(0.0, -76.0, fall_ratio))
			_head_pivot.rotation.z = deg_to_rad(lerpf(0.0, -25.0, fall_ratio))
			_left_leg_pivot.rotation.z = deg_to_rad(lerpf(0.0, 68.0, fall_ratio))
			_right_leg_pivot.rotation.z = deg_to_rad(lerpf(0.0, 52.0, fall_ratio))
			_right_arm_pivot.rotation.z = deg_to_rad(lerpf(0.0, -82.0, fall_ratio))
			_left_arm_pivot.rotation.z = deg_to_rad(lerpf(0.0, -64.0, fall_ratio))

	if state_name not in [SoulsCombatConfig.STATE_ATTACK_WINDUP, SoulsCombatConfig.STATE_ATTACK_SLASH]:
		_blade_mat.emission_enabled = false

#endregion
