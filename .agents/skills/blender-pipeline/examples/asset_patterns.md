# Skill Wiki · Blender 3D 资产构建正反范例库 (Asset Patterns)

> 📖 **Wiki 定位**：通过真实踩坑案例的 ❌反模式 (Anti-Pattern) 与 ✅黄金范式 (Golden Pattern) 对比，帮助 Agent 在编码阶段直接避开几何缩水、坐标错位与骨骼扭曲。

---

## 范例 1：细长装饰件建模（领带 / 呆毛 / 肢体）

### ❌ 典型反模式 (Anti-Pattern)
```python
# 错误 1：使用 8 顶点 Cube 加 Subsurf 制作细长领带，细分后上下两端严重向内缩水 25%，导致领带与领结断开并陷进胸口
# 错误 2：对原点在 (0,0,0) 的 BMesh 对象设置 scale=(1.35, 0.45, 1.0) 并 apply，导致 Y 坐标从 -0.206 直接变成 -0.092 缩进体内！
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.21, 0.98))
tie = bpy.context.active_object
tie.scale = (0.046, 0.016, 0.17)
bpy.ops.object.modifier_add(type='SUBSURF') # 缩水变形！
```

### ✅ 黄金范式 (Golden Pattern)
```python
# 正确：使用多段环截面放样 (create_capsule_limb) 直接连接领结底端与领带尖，不绕世界原点缩放 Y 轴
tie = create_capsule_limb(
    name="Worker_Tie_Body",
    p_start=(0.0, -0.205, 1.135),
    p_end=(0.0, -0.210, 0.89),
    r_start=0.022,
    r_end=0.032,
    mat=mats["tie"],
    vg_name="Tie_Bone",
    segments=12,
)
```

---

## 范例 2：角色四肢骨骼与关节连接

### ❌ 典型反模式 (Anti-Pattern)
```python
# 错误 1：静息态骨骼斜向摆放且未归零 roll，导致绕 X 轴旋转时手臂斜向劈叉
# 错误 2：未开启 use_connect=True，动画大幅度摆臂时前臂与上臂在肘部脱节分离
ua = eb.new("UpperArm_R")
ua.head = (0.29, 0.0, 1.15) # X=0.29 超出躯干在 Z=1.15 处的实际表面宽度 0.22，肩膀悬空！
ua.tail = (0.40, 0.0, 0.92)
fa = eb.new("Forearm_R")
fa.head = (0.40, 0.0, 0.92)
fa.tail = (0.46, -0.08, 0.67)
fa.parent = ua # 未设置 use_connect = True
```

### ✅ 黄金范式 (Golden Pattern)
```python
# 正确：肩点内嵌进躯干截面内部 (X=0.235)，手臂垂直向下，开启 use_connect=True 且 roll=0.0
ua = eb.new("UpperArm_R")
ua.head = (0.235, 0.0, 1.11)
ua.tail = (0.255, 0.0, 0.88)
ua.parent = spine
ua.roll = 0.0

fa = eb.new("Forearm_R")
fa.head = (0.255, 0.0, 0.88)
fa.tail = (0.265, 0.0, 0.63)
fa.parent = ua
fa.use_connect = True
fa.roll = 0.0
```

---

## 范例 3：建筑场景导出与预览灯光隔离

### ❌ 典型反模式 (Anti-Pattern)
```python
# 错误：先添加用于渲染预览图的 350W 室内强光和相机，再全场景导出 GLB，导致 Godot 加载 GLB 时把预览强光和额外相机一并导入！
bpy.ops.object.light_add(type='AREA', location=(0, 0, 3.4))
bpy.ops.object.camera_add(location=(-6, 4, 3))
bpy.ops.export_scene.gltf(filepath=EXPORT_GLB_PATH, use_selection=False)
```

### ✅ 黄金范式 (Golden Pattern)
```python
# 正确：先保存纯净建筑工程并导出 GLB，随后再在内存中布置预览灯光与多视角相机进行离线渲染
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
bpy.ops.export_scene.gltf(
    filepath=EXPORT_GLB_PATH,
    export_format='GLB',
    use_selection=False,
    export_apply=True,
    export_materials='EXPORT',
)
# 导出完成后再打光拍照，绝不污染 GLB 产物
setup_studio_lights_and_render_previews()
```

---

## 范例 4：高面数写实有机角色与硬表面护甲构建

### ❌ 典型反模式 (Anti-Pattern)
```python
# 错误 1：让 LLM 在代码里硬写成百上千个顶点坐标去“捏”人脸或肌肉，必然坍塌为抽象派多面体
# 错误 2：全篇滥用依赖 UI 上下文的 bpy.ops.object.modifier_add，在后台或 MCP 执行时直接报 poll() failed
vertices = [(0.12, -0.05, 1.62), (0.15, -0.08, 1.61), ...] # 严禁手写海量有机顶点！
bpy.ops.object.modifier_add(type='SOLIDIFY')
bpy.ops.object.modifier_add(type='BEVEL')
```

### ✅ 黄金范式 (Golden Pattern)
```python
# 正确 1：有机高模主体由 3D 扩散模型 (Hunyuan3D / TRELLIS 2 / Rodin) 导入后用 QuadriFlow 重拓扑
# 正确 2：硬表面装备使用 bpy.data (obj.modifiers.new) 构建非破坏性分层修改器栈 + 顶点组空间锚点
base_obj = import_and_normalize_base_mesh("character_raw_2m.glb", target_height=1.75)
refine_character_mesh(base_obj.name, target_faces=50000, recover_highpoly_details=True)

# 在胸口顶点组锚点上挂载非破坏性硬表面修改器栈
create_spatial_anchor_vgroup(base_obj, "Chest_Armor_Zone", z_range=(1.15, 1.42))
apply_hardsurface_modifier_stack(
    armor_plate,
    use_mirror=True,
    solidify_thickness=0.008,
    bevel_width=0.002,
    bevel_segments=4,
    subsurf_levels=1,
)
```

---

## 范例 5：工程化树状 Hierarchy vs. 扁平对象汤 / 无脑全合并

### ❌ 典型反模式 (Anti-Pattern)
```python
# 错误 1（全扁平对象汤）：把几十个桌面、椅腿、座垫、显示器直接丢在默认 Scene Collection 根下，全部 parent=None
# 错误 2（无脑全合并死网格）：把人体工学椅的五星底座与可旋转座垫全部 join() 成一个死 Mesh，在 Godot 中无法旋转椅身
bpy.ops.mesh.primitive_cylinder_add(location=(0, 0, 0.2)) # 裸命名 Cylinder，无父节点
bpy.ops.mesh.primitive_cube_add(location=(0, 0, 0.45))    # 裸命名 Cube.001，无枢轴
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join() # 动静部件全部焊死，层级彻底丢失！
```

### ✅ 黄金范式 (Golden Pattern)
```python
# 正确：建立三层隔离 Collection 树 + 单根多级父子场景图 (ROOT -> GRP/PIVOT/SOCKET -> MSH)
cols = create_asset_collection_tree("ErgoChair")
export_col = cols["export"]

root = create_hierarchy_node("ROOT_Prop_ErgoChair", collection=export_col, location=(0, 0, 0))
grp_base = create_hierarchy_node("GRP_Chair_StaticBase", parent=root, collection=export_col, location=(0, 0, 0))
pivot_swivel = create_hierarchy_node("PIVOT_Chair_UpperSwivel", parent=root, collection=export_col, location=(0, 0, 0.46), display_type='ARROWS')

# 底座网格挂入静态组，座垫与靠背挂入旋转枢轴下（保持世界坐标不变）
attach_child_keep_world_transform(msh_star_base, grp_base, export_col)
attach_child_keep_world_transform(msh_casters, grp_base, export_col)
attach_child_keep_world_transform(msh_seat_cushion, pivot_swivel, export_col)
attach_child_keep_world_transform(msh_backrest_mesh, pivot_swivel, export_col)
```
