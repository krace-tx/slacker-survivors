class_name SoulsArenaStage3D
extends Node3D

## 3D 大型哥特圆形祭坛竞技场组件（位于 src/test/souls_arena/view/component/stage/，遵循 MSVP 的 `Component` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 作为独立的 `.tscn` 场地预制体脚本，构建半径 `18.5m` 的大型哥特神殿圆形竞技场（提供充足的 3D 环绕走位与翻滚拉扯空间）；[br]
## 2. 铺设三层同心发光符文环与八芒星镶金罗盘石梁，外围环绕 24 座雕花界碑、12 座带凹槽哥特巨柱、高空飞扶壁连廊横梁、古战场残剑石碑与动态摇曳篝火火盆。


#region 私有变量

var _fire_lights: Array[OmniLight3D] = []
var _flame_spheres: Array[MeshInstance3D] = []
var _stage_clock: float = 0.0

#endregion


#region 公开构建与帧更新接口

func _ready() -> void:
	build_stage()


func _process(delta: float) -> void:
	if _fire_lights.is_empty():
		return
	_stage_clock += delta
	for i: int in range(_fire_lights.size()):
		var light: OmniLight3D = _fire_lights[i]
		if light != null:
			var wave: float = sin(_stage_clock * 5.2 + float(i) * 1.3) * 0.14 + cos(_stage_clock * 11.4 + float(i)) * 0.06
			light.light_energy = 1.40 + wave
	for j: int in range(_flame_spheres.size()):
		var f_mesh: MeshInstance3D = _flame_spheres[j]
		if f_mesh != null:
			var s_wave: float = 1.0 + sin(_stage_clock * 7.5 + float(j) * 0.9) * 0.08
			f_mesh.scale = Vector3(s_wave, s_wave * 1.18, s_wave)


func build_stage() -> void:
	var pillars_container: Node3D = get_node_or_null("PillarsContainer") as Node3D
	if pillars_container == null or pillars_container.get_child_count() > 0:
		return

	_fire_lights.clear()
	_flame_spheres.clear()

	var stone_dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	stone_dark_mat.albedo_color = Color(0.11, 0.14, 0.20)
	stone_dark_mat.metallic = 0.24
	stone_dark_mat.roughness = 0.68

	var stone_trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	stone_trim_mat.albedo_color = Color(0.16, 0.20, 0.28)
	stone_trim_mat.metallic = 0.30
	stone_trim_mat.roughness = 0.58

	var rune_gold_mat: StandardMaterial3D = StandardMaterial3D.new()
	rune_gold_mat.albedo_color = Color(0.88, 0.70, 0.30)
	rune_gold_mat.metallic = 0.75
	rune_gold_mat.roughness = 0.28
	rune_gold_mat.emission_enabled = true
	rune_gold_mat.emission = Color(0.82, 0.58, 0.20)
	rune_gold_mat.emission_energy_multiplier = 1.25

	var rune_cyan_mat: StandardMaterial3D = StandardMaterial3D.new()
	rune_cyan_mat.albedo_color = Color(0.28, 0.76, 0.96)
	rune_cyan_mat.emission_enabled = true
	rune_cyan_mat.emission = Color(0.22, 0.68, 0.92)
	rune_cyan_mat.emission_energy_multiplier = 1.15

	var flame_mat: StandardMaterial3D = StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.58, 0.18)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.48, 0.14)
	flame_mat.emission_energy_multiplier = 3.4

	# 1. 内圈与中圈双层雕花石台及三道同心发光符文环 (4.2m / 8.8m / 13.6m)
	var inner_platform: MeshInstance3D = MeshInstance3D.new()
	var inner_cyl: CylinderMesh = CylinderMesh.new()
	inner_cyl.top_radius = 13.8
	inner_cyl.bottom_radius = 14.1
	inner_cyl.height = 0.06
	inner_platform.mesh = inner_cyl
	inner_platform.position = Vector3(0.0, 0.02, 0.0)
	inner_platform.material_override = stone_trim_mat
	pillars_container.add_child(inner_platform)

	var center_medallion: MeshInstance3D = MeshInstance3D.new()
	var med_cyl: CylinderMesh = CylinderMesh.new()
	med_cyl.top_radius = 2.2
	med_cyl.bottom_radius = 2.3
	med_cyl.height = 0.075
	center_medallion.mesh = med_cyl
	center_medallion.position = Vector3(0.0, 0.03, 0.0)
	center_medallion.material_override = stone_dark_mat
	pillars_container.add_child(center_medallion)

	var ring_radii: Array[float] = [4.2, 8.8, 13.6]
	for r_idx: int in range(ring_radii.size()):
		var ring_r: float = ring_radii[r_idx]
		var rune_ring: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = ring_r - 0.09
		torus.outer_radius = ring_r + 0.09
		rune_ring.mesh = torus
		rune_ring.position = Vector3(0.0, 0.055, 0.0)
		rune_ring.material_override = rune_cyan_mat if r_idx == 1 else rune_gold_mat
		pillars_container.add_child(rune_ring)

	# 2. 八芒星放射状镶金罗盘石梁（提供 3D 走位与翻滚的清晰空间方位参照）
	for spoke_i: int in range(8):
		var spoke_ang: float = TAU * float(spoke_i) / 8.0
		var spoke_mesh: MeshInstance3D = MeshInstance3D.new()
		var spoke_box: BoxMesh = BoxMesh.new()
		spoke_box.size = Vector3(0.14, 0.025, 13.4)
		spoke_mesh.mesh = spoke_box
		spoke_mesh.position = Vector3(sin(spoke_ang) * 6.8, 0.052, cos(spoke_ang) * 6.8)
		spoke_mesh.rotation.y = spoke_ang
		spoke_mesh.material_override = rune_gold_mat
		pillars_container.add_child(spoke_mesh)

	# 3. 竞技场有效战斗边界雕花矮墙界碑与古战场残剑纪念碑 (半径 15.6m)
	var curb_ring: MeshInstance3D = MeshInstance3D.new()
	var curb_torus: TorusMesh = TorusMesh.new()
	curb_torus.inner_radius = 15.35
	curb_torus.outer_radius = 15.85
	curb_ring.mesh = curb_torus
	curb_ring.position = Vector3(0.0, 0.14, 0.0)
	curb_ring.material_override = stone_trim_mat
	pillars_container.add_child(curb_ring)

	for bollard_i: int in range(24):
		var b_ang: float = TAU * float(bollard_i) / 24.0
		var bx: float = sin(b_ang) * 15.6
		var bz: float = cos(b_ang) * 15.6
		var post: MeshInstance3D = MeshInstance3D.new()
		var post_box: BoxMesh = BoxMesh.new()
		post_box.size = Vector3(0.36, 0.68, 0.36)
		post.mesh = post_box
		post.position = Vector3(bx, 0.34, bz)
		post.rotation.y = b_ang
		post.material_override = stone_dark_mat
		pillars_container.add_child(post)

		if bollard_i % 3 == 1:
			# 插在界碑旁的古战场巨剑残骸
			var relic_sword: MeshInstance3D = MeshInstance3D.new()
			var sword_box: BoxMesh = BoxMesh.new()
			sword_box.size = Vector3(0.06, 1.65, 0.18)
			relic_sword.mesh = sword_box
			relic_sword.position = Vector3(sin(b_ang) * 16.3, 0.72, cos(b_ang) * 16.3)
			relic_sword.rotation = Vector3(deg_to_rad(14.0), b_ang, deg_to_rad(-10.0))
			relic_sword.material_override = stone_trim_mat
			pillars_container.add_child(relic_sword)

	# 4. 外圈 360° 环绕 12 座哥特石柱、高空飞扶壁横梁与动态火盆
	var pillar_count: int = 12
	var col_radius: float = 17.6
	for i: int in range(pillar_count):
		var angle: float = TAU * float(i) / float(pillar_count)
		var next_angle: float = TAU * float((i + 1) % pillar_count) / float(pillar_count)
		var px: float = sin(angle) * col_radius
		var pz: float = cos(angle) * col_radius
		var nx: float = sin(next_angle) * col_radius
		var nz: float = cos(next_angle) * col_radius
		var with_light: bool = (i % 2 == 0)
		_build_gothic_pillar(
			pillars_container,
			Vector3(px, 0.0, pz),
			angle,
			stone_dark_mat,
			stone_trim_mat,
			rune_gold_mat,
			flame_mat,
			with_light
		)
		_build_colonnade_arch_beam(
			pillars_container,
			Vector3(px, 6.15, pz),
			Vector3(nx, 6.15, nz),
			stone_dark_mat,
			stone_trim_mat,
			rune_gold_mat
		)


func _build_gothic_pillar(
	parent: Node3D,
	base_pos: Vector3,
	yaw_angle: float,
	shaft_mat: Material,
	trim_mat: Material,
	gold_mat: Material,
	flame_mat: Material,
	spawn_light: bool
) -> void:
	var root: Node3D = Node3D.new()
	root.position = base_pos
	root.rotation.y = yaw_angle
	parent.add_child(root)

	# 双层八角/方形柱础 (Double Plinth)
	var plinth_mesh: MeshInstance3D = MeshInstance3D.new()
	var plinth_box: BoxMesh = BoxMesh.new()
	plinth_box.size = Vector3(1.42, 0.58, 1.42)
	plinth_mesh.mesh = plinth_box
	plinth_mesh.position = Vector3(0.0, 0.29, 0.0)
	plinth_mesh.material_override = trim_mat
	root.add_child(plinth_mesh)

	var plinth_upper: MeshInstance3D = MeshInstance3D.new()
	var upper_box: BoxMesh = BoxMesh.new()
	upper_box.size = Vector3(1.18, 0.32, 1.18)
	plinth_upper.mesh = upper_box
	plinth_upper.position = Vector3(0.0, 0.72, 0.0)
	plinth_upper.material_override = shaft_mat
	root.add_child(plinth_upper)

	# 主石柱柱身 (Shaft) + 4 道哥特竖向附柱棱条
	var shaft_mesh: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.54
	cyl.height = 5.2
	shaft_mesh.mesh = cyl
	shaft_mesh.position = Vector3(0.0, 3.30, 0.0)
	shaft_mesh.material_override = shaft_mat
	root.add_child(shaft_mesh)

	for rib_i: int in range(4):
		var rib_ang: float = TAU * float(rib_i) / 4.0
		var rib: MeshInstance3D = MeshInstance3D.new()
		var rib_box: BoxMesh = BoxMesh.new()
		rib_box.size = Vector3(0.14, 5.0, 0.14)
		rib.mesh = rib_box
		rib.position = Vector3(sin(rib_ang) * 0.46, 3.30, cos(rib_ang) * 0.46)
		rib.material_override = trim_mat
		root.add_child(rib)

	# 柱腰金环装饰
	var mid_band: MeshInstance3D = MeshInstance3D.new()
	var band_cyl: CylinderMesh = CylinderMesh.new()
	band_cyl.top_radius = 0.56
	band_cyl.bottom_radius = 0.56
	band_cyl.height = 0.14
	mid_band.mesh = band_cyl
	mid_band.position = Vector3(0.0, 3.40, 0.0)
	mid_band.material_override = gold_mat
	root.add_child(mid_band)

	# 柱头冠座与哥特尖顶塔冠 (Capital & Finial Spire)
	var cap_mesh: MeshInstance3D = MeshInstance3D.new()
	var cap_box: BoxMesh = BoxMesh.new()
	cap_box.size = Vector3(1.36, 0.44, 1.36)
	cap_mesh.mesh = cap_box
	cap_mesh.position = Vector3(0.0, 6.02, 0.0)
	cap_mesh.material_override = trim_mat
	root.add_child(cap_mesh)

	var spire_mesh: MeshInstance3D = MeshInstance3D.new()
	var spire_prism: PrismMesh = PrismMesh.new()
	spire_prism.size = Vector3(0.82, 1.25, 0.82)
	spire_mesh.mesh = spire_prism
	spire_mesh.position = Vector3(0.0, 6.86, 0.0)
	spire_mesh.material_override = trim_mat
	root.add_child(spire_mesh)

	# 内侧铁艺火盆托架、火盆碗与烈焰球
	var bracket_mesh: MeshInstance3D = MeshInstance3D.new()
	var bracket_box: BoxMesh = BoxMesh.new()
	bracket_box.size = Vector3(0.12, 0.14, 0.82)
	bracket_mesh.mesh = bracket_box
	bracket_mesh.position = Vector3(0.0, 3.16, -0.52)
	bracket_mesh.material_override = gold_mat
	root.add_child(bracket_mesh)

	var bowl_mesh: MeshInstance3D = MeshInstance3D.new()
	var bowl_cyl: CylinderMesh = CylinderMesh.new()
	bowl_cyl.top_radius = 0.36
	bowl_cyl.bottom_radius = 0.18
	bowl_cyl.height = 0.22
	bowl_mesh.mesh = bowl_cyl
	bowl_mesh.position = Vector3(0.0, 3.28, -0.82)
	bowl_mesh.material_override = trim_mat
	root.add_child(bowl_mesh)

	var brazier_mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.58
	brazier_mesh.mesh = sphere
	brazier_mesh.position = Vector3(0.0, 3.52, -0.82)
	brazier_mesh.material_override = flame_mat
	root.add_child(brazier_mesh)
	_flame_spheres.append(brazier_mesh)

	if spawn_light:
		var fire_light: OmniLight3D = OmniLight3D.new()
		fire_light.light_color = Color(1.0, 0.62, 0.24)
		fire_light.light_energy = 1.40
		fire_light.omni_range = 12.0
		fire_light.position = Vector3(0.0, 3.85, -1.15)
		root.add_child(fire_light)
		_fire_lights.append(fire_light)


func _build_colonnade_arch_beam(
	parent: Node3D,
	start_pos: Vector3,
	end_pos: Vector3,
	shaft_mat: Material,
	trim_mat: Material,
	gold_mat: Material
) -> void:
	var mid_pos: Vector3 = (start_pos + end_pos) * 0.5
	var span_vec: Vector3 = end_pos - start_pos
	var span_len: float = span_vec.length()
	var beam_yaw: float = atan2(span_vec.x, span_vec.z)

	var arch_root: Node3D = Node3D.new()
	arch_root.position = mid_pos
	arch_root.rotation.y = beam_yaw
	parent.add_child(arch_root)

	var lintel_mesh: MeshInstance3D = MeshInstance3D.new()
	var lintel_box: BoxMesh = BoxMesh.new()
	lintel_box.size = Vector3(0.68, 0.52, span_len)
	lintel_mesh.mesh = lintel_box
	lintel_mesh.material_override = trim_mat
	arch_root.add_child(lintel_mesh)

	var cornice_mesh: MeshInstance3D = MeshInstance3D.new()
	var cornice_box: BoxMesh = BoxMesh.new()
	cornice_box.size = Vector3(0.76, 0.10, span_len)
	cornice_mesh.mesh = cornice_box
	cornice_mesh.position = Vector3(0.0, 0.30, 0.0)
	cornice_mesh.material_override = gold_mat
	arch_root.add_child(cornice_mesh)

	var arch_crest: MeshInstance3D = MeshInstance3D.new()
	var crest_prism: PrismMesh = PrismMesh.new()
	crest_prism.size = Vector3(0.54, 0.65, span_len * 0.55)
	arch_crest.mesh = crest_prism
	arch_crest.position = Vector3(0.0, 0.62, 0.0)
	arch_crest.rotation.y = deg_to_rad(90.0)
	arch_crest.material_override = shaft_mat
	arch_root.add_child(arch_crest)

#endregion
