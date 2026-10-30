# -*- coding: utf-8 -*-
"""Blender 5.x pure Data-API / BMesh high-precision builders for Cozy Anime Atelier Venue."""

from __future__ import annotations

import math
import bpy
import bmesh
from mathutils import Euler, Matrix, Vector


def clear_scene() -> None:
    """Idempotently reset all scene objects, collections, and datablocks."""
    if bpy.context.active_object and bpy.context.active_object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col)

    for datablock_group in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.lights,
        bpy.data.cameras,
        bpy.data.node_groups,
        bpy.data.armatures,
        bpy.data.actions,
    ):
        for block in list(datablock_group):
            datablock_group.remove(block)


def ensure_collection(
    name: str,
    parent_col: bpy.types.Collection | None = None,
    hide_render: bool = False,
) -> bpy.types.Collection:
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    target_parent = parent_col or bpy.context.scene.collection
    if col.name not in target_parent.children:
        target_parent.children.link(col)
    col.hide_render = hide_render
    return col


def create_asset_collection_tree(asset_name: str) -> dict[str, bpy.types.Collection]:
    root_col = ensure_collection(f"COL_Asset_{asset_name}")
    export_col = ensure_collection("01_Export_Hierarchy", root_col, hide_render=False)
    work_col = ensure_collection("02_Work_Helpers", root_col, hide_render=True)
    studio_col = ensure_collection("03_Studio_LookDev", root_col, hide_render=False)
    return {
        "root": root_col,
        "export": export_col,
        "work": work_col,
        "studio": studio_col,
    }


def create_hierarchy_node(
    name: str,
    parent: bpy.types.Object | None = None,
    collection: bpy.types.Collection | None = None,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    display_type: str = "PLAIN_AXES",
    display_size: float = 0.15,
) -> bpy.types.Object:
    empty_obj = bpy.data.objects.new(name, None)
    empty_obj.empty_display_type = display_type
    empty_obj.empty_display_size = display_size
    empty_obj.location = Vector(location)

    target_col = collection or bpy.context.scene.collection
    target_col.objects.link(empty_obj)

    if parent is not None:
        bpy.context.view_layer.update()
        world_mat = Matrix.Translation(Vector(location))
        empty_obj.parent = parent
        empty_obj.matrix_parent_inverse = parent.matrix_world.inverted()
        empty_obj.matrix_world = world_mat
    return empty_obj


def attach_child_keep_world_transform(
    child_obj: bpy.types.Object,
    parent_obj: bpy.types.Object,
    target_col: bpy.types.Collection | None = None,
) -> None:
    bpy.context.view_layer.update()
    world_mat = child_obj.matrix_world.copy()
    child_obj.parent = parent_obj
    child_obj.matrix_parent_inverse = parent_obj.matrix_world.inverted()
    child_obj.matrix_world = world_mat

    if target_col is not None and child_obj.name not in target_col.objects:
        for col in list(child_obj.users_collection):
            col.objects.unlink(child_obj)
        target_col.objects.link(child_obj)


def hex_to_rgba(hex_str: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    """Convert #RRGGBB sRGB hex color to linear RGBA tuple for Blender Principled BSDF."""
    h = hex_str.lstrip("#")
    sr = int(h[0:2], 16) / 255.0
    sg = int(h[2:4], 16) / 255.0
    sb = int(h[4:6], 16) / 255.0

    def to_lin(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (to_lin(sr), to_lin(sg), to_lin(sb), alpha)


def create_pbr_mat(
    name: str,
    hex_color: str,
    roughness: float = 0.58,
    metallic: float = 0.0,
    emission_hex: str | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name=name)
    if not mat.use_nodes:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    rgba = hex_to_rgba(hex_color, alpha)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.28
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        if emission_hex is not None and emission_strength > 0.0:
            em_rgba = hex_to_rgba(emission_hex, 1.0)
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = em_rgba
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = em_rgba
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 0.999:
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    return mat


def _ensure_box_uvs(bm: bmesh.types.BMesh) -> None:
    """Assign clean world-scale triplanar box UVs so shaders/textures never have zero UVs."""
    uv_layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                loop[uv_layer].uv = (co.x * 0.5 + 0.5, co.y * 0.5 + 0.5)
            elif ax >= ay:
                loop[uv_layer].uv = (co.y * 0.5 + 0.5, co.z * 0.5 + 0.5)
            else:
                loop[uv_layer].uv = (co.x * 0.5 + 0.5, co.z * 0.5 + 0.5)


def _finalize_mesh_object(
    name: str,
    bm: bmesh.types.BMesh,
    loc: tuple[float, float, float],
    rot_deg: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    bevel_width: float = 0.0,
    bevel_segs: int = 3,
    subsurf_levels: int = 0,
    smooth: bool = True,
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _ensure_box_uvs(bm)
    for f in bm.faces:
        f.smooth = smooth

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    obj.location = Vector(loc)
    obj.rotation_euler = Euler(
        (math.radians(rot_deg[0]), math.radians(rot_deg[1]), math.radians(rot_deg[2])),
        "XYZ",
    )
    obj.data.materials.append(mat)
    col.objects.link(obj)
    attach_child_keep_world_transform(obj, parent, col)

    if bevel_width > 0.0:
        m_bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        m_bev.width = bevel_width
        m_bev.segments = bevel_segs
        m_bev.limit_method = "ANGLE"
        m_bev.angle_limit = math.radians(32.0)
        if hasattr(m_bev, "miter_outer"):
            m_bev.miter_outer = "MITER_ARC"

    if subsurf_levels > 0:
        m_sub = obj.modifiers.new(name="Subsurf", type="SUBSURF")
        m_sub.levels = subsurf_levels
        m_sub.render_levels = subsurf_levels

    if bevel_width > 0.0 and subsurf_levels == 0:
        m_wn = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
        m_wn.keep_sharp = True

    return obj


def make_box(
    name: str,
    size: tuple[float, float, float],
    loc: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    bevel: float = 0.010,
    segs: int = 3,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    subsurf: int = 0,
) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return _finalize_mesh_object(
        name, bm, loc, rot_deg, mat, parent, col, bevel_width=bevel, bevel_segs=segs, subsurf_levels=subsurf
    )


def make_cylinder(
    name: str,
    radius: float,
    depth: float,
    loc: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    segs: int = 32,
    bevel: float = 0.006,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    r_top: float | None = None,
    subsurf: int = 0,
) -> bpy.types.Object:
    bm = bmesh.new()
    rt = radius if r_top is None else r_top
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=radius,
        radius2=rt,
        depth=depth,
    )
    return _finalize_mesh_object(
        name, bm, loc, rot_deg, mat, parent, col, bevel_width=bevel, bevel_segs=2, subsurf_levels=subsurf
    )


def make_soft_cushion(
    name: str,
    size: tuple[float, float, float],
    loc: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    puff: float = 0.16,
    subsurf: int = 2,
) -> bpy.types.Object:
    """High-subdivision plump anime pillow/cushion with smooth organic curvature."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=4, use_grid_fill=True)
    sx, sy, sz = size
    for v in bm.verts:
        nx, ny, nz = v.co.x * 2.0, v.co.y * 2.0, v.co.z * 2.0
        bulge = 1.0 + puff * max(0.0, 1.0 - 0.36 * (nx * nx + ny * ny + nz * nz))
        # Subtle pinch seam around horizontal equator for tailored upholstery feel
        seam = 1.0 - 0.035 * max(0.0, 1.0 - abs(nz) * 4.0)
        v.co = Vector((v.co.x * sx * bulge * seam, v.co.y * sy * bulge * seam, v.co.z * sz * bulge))
    return _finalize_mesh_object(name, bm, loc, rot_deg, mat, parent, col, bevel_width=0.0, subsurf_levels=subsurf)


def make_capsule_tube(
    name: str,
    p_start: tuple[float, float, float],
    p_end: tuple[float, float, float],
    r_start: float,
    r_end: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    segments: int = 18,
    steps: int = 8,
) -> bpy.types.Object:
    bm = bmesh.new()
    p0, p1 = Vector(p_start), Vector(p_end)
    mid = (p0 + p1) * 0.5
    p0_l, p1_l = p0 - mid, p1 - mid
    axis = p1_l - p0_l
    tangent = axis.normalized() if axis.length > 1e-5 else Vector((0.0, 0.0, 1.0))
    up = Vector((0.0, 1.0, 0.0)) if abs(tangent.z) > 0.9 else Vector((0.0, 0.0, 1.0))
    side = tangent.cross(up).normalized()
    normal = side.cross(tangent).normalized()

    rings = []
    for i in range(steps + 1):
        t = i / steps
        center = p0_l.lerp(p1_l, t)
        r = r_start * (1.0 - t) + r_end * t
        ring = [
            bm.verts.new(
                center
                + (side * math.cos(2.0 * math.pi * j / segments) + normal * math.sin(2.0 * math.pi * j / segments)) * r
            )
            for j in range(segments)
        ]
        rings.append(ring)

    for i in range(steps):
        for j in range(segments):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segments], rings[i + 1][(j + 1) % segments], rings[i + 1][j]))

    v_top = bm.verts.new(p0_l - tangent * (r_start * 0.45))
    v_bot = bm.verts.new(p1_l + tangent * (r_end * 0.45))
    for j in range(segments):
        bm.faces.new((v_top, rings[0][(j + 1) % segments], rings[0][j]))
        bm.faces.new((v_bot, rings[-1][j], rings[-1][(j + 1) % segments]))

    return _finalize_mesh_object(name, bm, (mid.x, mid.y, mid.z), (0.0, 0.0, 0.0), mat, parent, col)


def make_curved_leaf(
    name: str,
    length: float,
    width: float,
    arch_drop: float,
    loc: tuple[float, float, float],
    rot_deg: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
) -> bpy.types.Object:
    """Sculpted botanical anime leaf (pointed tip, heart base, central midrib fold, natural arch droop + Subsurf)."""
    bm = bmesh.new()
    u_steps = 8   # across width
    v_steps = 12  # base (0) to tip (1)
    thickness = max(0.006, width * 0.045)

    top_grid: list[list[bmesh.types.BMVert]] = []
    bot_grid: list[list[bmesh.types.BMVert]] = []

    for iv in range(v_steps + 1):
        v = iv / v_steps
        # Botanical leaf silhouette: rounded base -> wide belly at v=0.35 -> pointed tip at v=1.0
        half_w = (width * 0.5) * math.sin(math.pi * (v ** 0.72)) * (1.0 - 0.18 * v)
        if iv in (0, v_steps):
            half_w = max(0.003, half_w)
        y = v * length
        z_arch = math.sin(v * math.pi * 0.78) * (length * 0.16) - (v * v) * arch_drop

        row_top = []
        row_bot = []
        for iu in range(u_steps + 1):
            u = (iu / u_steps) * 2.0 - 1.0  # -1..+1
            x = u * half_w
            # Gentle V-cupping along central midrib
            cup_z = abs(u) * (width * 0.08) * (1.0 - 0.5 * v)
            t_local = thickness * (1.0 - 0.65 * v) * (1.0 - 0.5 * abs(u))
            row_top.append(bm.verts.new((x, y, z_arch + cup_z + t_local * 0.5)))
            row_bot.append(bm.verts.new((x, y, z_arch + cup_z - t_local * 0.5)))
        top_grid.append(row_top)
        bot_grid.append(row_bot)

    for iv in range(v_steps):
        for iu in range(u_steps):
            bm.faces.new((top_grid[iv][iu], top_grid[iv][iu + 1], top_grid[iv + 1][iu + 1], top_grid[iv + 1][iu]))
            bm.faces.new((bot_grid[iv][iu + 1], bot_grid[iv][iu], bot_grid[iv + 1][iu], bot_grid[iv + 1][iu + 1]))

    # Stitch perimeter rim
    for iv in range(v_steps):
        bm.faces.new((bot_grid[iv][0], top_grid[iv][0], top_grid[iv + 1][0], bot_grid[iv + 1][0]))
        bm.faces.new((top_grid[iv][-1], bot_grid[iv][-1], bot_grid[iv + 1][-1], top_grid[iv + 1][-1]))
    for iu in range(u_steps):
        bm.faces.new((top_grid[0][iu], bot_grid[0][iu], bot_grid[0][iu + 1], top_grid[0][iu + 1]))
        bm.faces.new((bot_grid[-1][iu], top_grid[-1][iu], top_grid[-1][iu + 1], bot_grid[-1][iu + 1]))

    return _finalize_mesh_object(name, bm, loc, rot_deg, mat, parent, col, subsurf_levels=1)


def make_draped_curtain(
    name: str,
    width: float,
    height: float,
    pleat_depth: float,
    pleat_waves: int,
    loc: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    tie_side: float = 0.0,
) -> bpy.types.Object:
    """Flowing gathered sheer curtain along Y (width) and Z (height) facing +X into room."""
    bm = bmesh.new()
    ny = 22
    nz = 24
    thick = 0.012

    front_g: list[list[bmesh.types.BMVert]] = []
    back_g: list[list[bmesh.types.BMVert]] = []

    for iz in range(nz + 1):
        tz = iz / nz  # 0 = bottom hem, 1 = top rod
        z = (tz - 0.5) * height
        # Soft waist gather around tz = 0.34 if tie_side != 0
        waist = math.exp(-((tz - 0.34) / 0.18) ** 2)
        gather = 1.0 - (0.36 * waist if abs(tie_side) > 0.01 else 0.0)
        sway_y = tie_side * 0.10 * waist + tie_side * 0.04 * (1.0 - tz)
        billow_x = 0.045 * math.sin(math.pi * (1.0 - tz))

        r_front = []
        r_back = []
        for iy in range(ny + 1):
            ty = iy / ny  # 0..1
            y = ((ty - 0.5) * width) * gather + sway_y
            wave = math.sin(ty * pleat_waves * 2.0 * math.pi) * pleat_depth * (0.55 + 0.45 * (1.0 - waist * 0.5))
            x = billow_x + wave
            r_front.append(bm.verts.new((x + thick * 0.5, y, z)))
            r_back.append(bm.verts.new((x - thick * 0.5, y, z)))
        front_g.append(r_front)
        back_g.append(r_back)

    for iz in range(nz):
        for iy in range(ny):
            bm.faces.new((front_g[iz][iy], front_g[iz][iy + 1], front_g[iz + 1][iy + 1], front_g[iz + 1][iy]))
            bm.faces.new((back_g[iz][iy + 1], back_g[iz][iy], back_g[iz + 1][iy], back_g[iz + 1][iy + 1]))

    for iz in range(nz):
        bm.faces.new((back_g[iz][0], front_g[iz][0], front_g[iz + 1][0], back_g[iz + 1][0]))
        bm.faces.new((front_g[iz][-1], back_g[iz][-1], back_g[iz + 1][-1], front_g[iz + 1][-1]))
    for iy in range(ny):
        bm.faces.new((front_g[0][iy], back_g[0][iy], back_g[0][iy + 1], front_g[0][iy + 1]))
        bm.faces.new((back_g[-1][iy], front_g[-1][iy], front_g[-1][iy + 1], back_g[-1][iy + 1]))

    return _finalize_mesh_object(name, bm, loc, (0.0, 0.0, 0.0), mat, parent, col, subsurf_levels=1)


def make_torus_ring(
    name: str,
    major_r: float,
    minor_r: float,
    loc: tuple[float, float, float],
    mat: bpy.types.Material,
    parent: bpy.types.Object,
    col: bpy.types.Collection,
    major_segs: int = 48,
    minor_segs: int = 14,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Clean quad torus ring for braided rug coils, mug handles, lamp rims & curtain rings."""
    bm = bmesh.new()
    rings = []
    for i in range(major_segs):
        phi = 2.0 * math.pi * i / major_segs
        cp, sp = math.cos(phi), math.sin(phi)
        ring = []
        for j in range(minor_segs):
            theta = 2.0 * math.pi * j / minor_segs
            r = major_r + minor_r * math.cos(theta)
            z = minor_r * math.sin(theta)
            ring.append(bm.verts.new((r * cp, r * sp, z)))
        rings.append(ring)

    for i in range(major_segs):
        ni = (i + 1) % major_segs
        for j in range(minor_segs):
            nj = (j + 1) % minor_segs
            bm.faces.new((rings[i][j], rings[ni][j], rings[ni][nj], rings[i][nj]))

    return _finalize_mesh_object(name, bm, loc, rot_deg, mat, parent, col)
