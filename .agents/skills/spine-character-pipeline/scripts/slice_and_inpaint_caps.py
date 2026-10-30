#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Step 3 of `spine-character-pipeline`:
Deterministic Part Extraction, Zero-Jitter Facial Patch Fusion, Open-Cap Joint Outline Inpainting,
Medial-Axis Joint Pivot Solver & Straight-Alpha Shelf Atlas Packer.

Eliminates the 3 core visual bugs of naive AI Spine cutouts:
  1. Unpremultiplied `#FF00FF` chroma unmixing + dark-outline despill (zero pink fringe);
  2. `cv2.inpaint` erases dark internal cut-outlines on `arm_full`, `leg_full`, and `coat_tail`
     insertion caps + elliptical alpha taper (zero U-shaped wooden-doll joint seams);
  3. Inner-oval expression fusion onto `face_open`'s exact outer head shell (0.00px jaw/ear jitter).
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
from PIL import Image


def chroma_key_magenta(img: Image.Image) -> np.ndarray:
    """Unmixes flat #FF00FF / magenta-guide background into clean Straight-Alpha RGBA uint8."""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

    # Magenta dominance: min(R, B) - G (~255 on #FF00FF, >=160 on guide strokes, <=35 on character art)
    mag_excess = np.minimum(r, b) - g
    alpha = 1.0 - np.clip((mag_excess - 38.0) / 88.0, 0.0, 1.0)

    # Remove isolated 1px JPEG compression speckles
    solid_core = mag_excess < 66.0
    kernel = np.ones((3, 3), dtype=np.uint8)
    near_core = cv2.dilate(solid_core.astype(np.uint8), kernel, iterations=1) > 0
    alpha = np.where(near_core, alpha, 0.0)

    safe_a = np.maximum(alpha, 0.05)
    bg_w = 1.0 - alpha
    out_r = np.clip((r - 255.0 * bg_w) / safe_a, 0.0, 255.0)
    out_g = np.clip(g / safe_a, 0.0, 255.0)
    out_b = np.clip((b - 255.0 * bg_w) / safe_a, 0.0, 255.0)

    # Despill residual magenta chroma bleed along dark charcoal/espresso ink lines (#241B1E)
    spill = np.maximum(0.0, np.minimum(out_r, out_b) - out_g - 14.0)
    spill_mask = (spill > 0.0) & (alpha > 0.01)
    blend = np.clip(spill / 68.0, 0.0, 1.0)
    out_r = np.where(spill_mask, out_r * (1.0 - blend) + 38.0 * blend, out_r)
    out_g = np.where(spill_mask, out_g * (1.0 - blend) + 29.0 * blend, out_g)
    out_b = np.where(spill_mask, out_b * (1.0 - blend) + 32.0 * blend, out_b)

    alpha = np.where(alpha < 0.08, 0.0, alpha)
    rgba = np.zeros((rgb.shape[0], rgb.shape[1], 4), dtype=np.uint8)
    rgba[:, :, 0] = np.round(out_r).astype(np.uint8)
    rgba[:, :, 1] = np.round(out_g).astype(np.uint8)
    rgba[:, :, 2] = np.round(out_b).astype(np.uint8)
    rgba[:, :, 3] = np.round(alpha * 255.0).astype(np.uint8)
    rgba[rgba[:, :, 3] == 0] = 0
    return rgba


def trim_alpha(arr: np.ndarray, pad: int = 2) -> np.ndarray:
    ys, xs = np.where(arr[:, :, 3] > 12)
    if len(xs) == 0:
        return arr
    y0 = max(0, int(ys.min()) - pad)
    y1 = min(arr.shape[0], int(ys.max()) + 1 + pad)
    x0 = max(0, int(xs.min()) - pad)
    x1 = min(arr.shape[1], int(xs.max()) + 1 + pad)
    return arr[y0:y1, x0:x1].copy()


def resize_rgba_straight(arr: np.ndarray, new_w: int, new_h: int) -> np.ndarray:
    """Resizes RGBA without premultiplied dark-fringe or transparent-zero color bleed."""
    new_w = max(4, int(round(new_w)))
    new_h = max(4, int(round(new_h)))
    # Inpaint RGB into transparent pixels before Lanczos resize so edge RGB never mixes with (0,0,0)
    alpha = arr[:, :, 3]
    bgr = cv2.cvtColor(arr[:, :, :3], cv2.COLOR_RGB2BGR)
    empty_mask = (alpha < 8).astype(np.uint8) * 255
    if np.any(alpha >= 8) and np.any(empty_mask > 0):
        bgr_filled = cv2.inpaint(bgr, empty_mask, 3.0, cv2.INPAINT_TELEA)
    else:
        bgr_filled = bgr
    rgb_filled = cv2.cvtColor(bgr_filled, cv2.COLOR_BGR2RGB)
    rgb_res = np.asarray(Image.fromarray(rgb_filled).resize((new_w, new_h), Image.Resampling.LANCZOS), dtype=np.uint8)
    a_res = np.asarray(Image.fromarray(alpha).resize((new_w, new_h), Image.Resampling.LANCZOS), dtype=np.uint8)
    out = np.zeros((new_h, new_w, 4), dtype=np.uint8)
    out[:, :, :3] = rgb_res
    out[:, :, 3] = np.where(a_res < 10, 0, a_res)
    out[out[:, :, 3] == 0] = 0
    return out


def extract_zone_part(
    full_rgba: np.ndarray,
    rx0: float,
    ry0: float,
    rx1: float,
    ry1: float,
    slot_name: str,
    allow_multi_island: bool = False,
) -> np.ndarray:
    """
    Extracts the target part inside normalized cell `[rx0, ry0, rx1, ry1]`, discarding any
    edge fragments whose centroid lies outside the cell's core region.
    """
    H, W, _ = full_rgba.shape
    x0 = max(0, int(round(rx0 * W)))
    y0 = max(0, int(round(ry0 * H)))
    x1 = min(W, int(round(rx1 * W)))
    y1 = min(H, int(round(ry1 * H)))

    sub = full_rgba[y0:y1, x0:x1].copy()
    sh, sw, _ = sub.shape
    mask = (sub[:, :, 3] > 24).astype(np.uint8)
    num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)

    valid_ids: List[Tuple[float, int]] = []
    cx_mid, cy_mid = sw * 0.5, sh * 0.5
    for lid in range(1, num_labels):
        area = int(stats[lid, cv2.CC_STAT_AREA])
        if area < 90:
            continue
        bx = int(stats[lid, cv2.CC_STAT_LEFT])
        by = int(stats[lid, cv2.CC_STAT_TOP])
        bw = int(stats[lid, cv2.CC_STAT_WIDTH])
        bh = int(stats[lid, cv2.CC_STAT_HEIGHT])
        ccx, ccy = float(centroids[lid][0]), float(centroids[lid][1])

        # Reject neighbor-cell bleed touching outer 2px border whose centroid is near edge
        touches_border = bx <= 1 or by <= 1 or (bx + bw) >= sw - 1 or (by + bh) >= sh - 1
        near_outer = ccx < sw * 0.10 or ccx > sw * 0.90 or ccy < sh * 0.08 or ccy > sh * 0.92
        if touches_border and near_outer:
            continue

        dist_pen = math.hypot((ccx - cx_mid) / max(1.0, sw), (ccy - cy_mid) / max(1.0, sh))
        score = area / (1.0 + 1.8 * dist_pen)
        valid_ids.append((score, lid))

    if not valid_ids:
        raise RuntimeError(f"Slot '{slot_name}' is empty in zone ({x0},{y0})-({x1},{y1})!")

    valid_ids.sort(reverse=True)
    keep = np.zeros((sh, sw), dtype=np.uint8)
    if allow_multi_island:
        max_area = int(stats[valid_ids[0][1], cv2.CC_STAT_AREA])
        for _sc, lid in valid_ids:
            if int(stats[lid, cv2.CC_STAT_AREA]) >= max(110, int(max_area * 0.06)):
                keep[labels == lid] = 255
    else:
        keep[labels == valid_ids[0][1]] = 255

    # Include 1px anti-aliased soft alpha edge
    keep_dilated = cv2.dilate(keep, np.ones((3, 3), dtype=np.uint8), iterations=1)
    sub[keep_dilated == 0] = 0
    return trim_alpha(sub, pad=3)


def straighten_vertical_part(arr: np.ndarray, max_tilt_deg: float = 28.0) -> np.ndarray:
    """Uses PCA on the alpha mask to rotate slightly slanted limbs/weapons upright to 0 deg vertical."""
    ys, xs = np.where(arr[:, :, 3] > 40)
    if len(xs) < 100:
        return arr
    pts = np.column_stack([xs.astype(np.float32), ys.astype(np.float32)])
    mean = pts.mean(axis=0)
    cov = np.cov((pts - mean).T)
    eigvals, eigvecs = np.linalg.eigh(cov)
    major = eigvecs[:, int(np.argmax(eigvals))]  # (vx, vy)
    if major[1] < 0:
        major = -major
    # Angle from straight down (0, 1)
    tilt_rad = math.atan2(float(major[0]), float(major[1]))
    tilt_deg = math.degrees(tilt_rad)
    if 2.2 < abs(tilt_deg) <= max_tilt_deg:
        # PIL rotate is CCW positive; if tilted +X at bottom (major[0]>0), rotate CW (-tilt_deg)
        pil = Image.fromarray(arr)
        rot = pil.rotate(-tilt_deg, resample=Image.Resampling.BICUBIC, expand=True)
        res = np.array(rot, dtype=np.uint8, copy=True)
        res[res[:, :, 3] < 10] = 0
        return trim_alpha(res, pad=3)
    return arr


def inpaint_open_joint_cap(arr: np.ndarray, cap_ratio: float = 0.16, taper_px: int = 12) -> np.ndarray:
    """
    Erases dark closed ink outlines along the top insertion cap of a limb/skirt using OpenCV
    Telea inpainting from interior cloth/skin colors, then applies a smooth elliptical cap taper.
    """
    out = arr.copy()
    h, w, _ = out.shape
    cap_h = max(8, min(h // 3, int(round(h * cap_ratio))))

    alpha = out[:, :, 3]
    solid = alpha > 40
    # Sample interior fill luminance from rows `[cap_h .. min(h, cap_h * 2 + 12)]` eroded away from side outlines
    eroded = cv2.erode(solid.astype(np.uint8) * 255, np.ones((7, 7), dtype=np.uint8), iterations=1) > 0
    sample_band = eroded[cap_h : min(h, cap_h * 2 + 16), :]
    rgb_f = out[:, :, :3].astype(np.float32)
    lum = 0.299 * rgb_f[:, :, 0] + 0.587 * rgb_f[:, :, 1] + 0.114 * rgb_f[:, :, 2]

    if np.any(sample_band):
        ref_lum = float(np.median(lum[cap_h : min(h, cap_h * 2 + 16), :][sample_band]))
    else:
        ref_lum = float(np.median(lum[solid])) if np.any(solid) else 140.0

    # Dark outline pixels inside the top `cap_h` rows (preserve left/right outer silhouette below cap_h)
    dark_thresh = max(52.0, ref_lum * 0.66)
    stroke_mask = np.zeros((h, w), dtype=np.uint8)
    top_region = solid[:cap_h, :] & (lum[:cap_h, :] < dark_thresh)
    stroke_mask[:cap_h, :][top_region] = 255
    stroke_mask = cv2.dilate(stroke_mask, np.ones((3, 3), dtype=np.uint8), iterations=1)

    if np.any(stroke_mask > 0):
        bgr = cv2.cvtColor(out[:, :, :3], cv2.COLOR_RGB2BGR)
        inpainted = cv2.inpaint(bgr, stroke_mask, 5.0, cv2.INPAINT_TELEA)
        out[:, :, :3] = cv2.cvtColor(inpainted, cv2.COLOR_BGR2RGB)

    # Smooth rounded semi-elliptical joint cap at the very top rim so +/-50 deg rotation never pokes corners
    limit = min(cap_h, max(6, taper_px))
    for ry in range(limit):
        t = 1.0 - (ry / float(limit))
        xs = np.where(out[ry, :, 3] > 20)[0]
        if len(xs) >= 4:
            cx = 0.5 * (xs.min() + xs.max())
            half_w = 0.5 * (xs.max() - xs.min()) * math.sqrt(max(0.0, 1.0 - 0.75 * t * t))
            for x in range(w):
                dist_ratio = abs(x - cx) / max(1.0, half_w)
                if dist_ratio > 1.0:
                    out[ry, x] = 0
                elif dist_ratio > 0.85:
                    fade = (1.0 - dist_ratio) / 0.15
                    out[ry, x, 3] = int(round(out[ry, x, 3] * fade))
                    if out[ry, x, 3] == 0:
                        out[ry, x] = 0

    return trim_alpha(out, pad=2)


def fuse_expression_onto_base_head(base_head: np.ndarray, expr_head_raw: np.ndarray) -> np.ndarray:
    """
    Eliminates 100% of head-swap silhouette jitter: resizes `expr_head_raw` to match `base_head`
    and composites ONLY the inner facial oval (eyes + brows + blush + mouth) with a soft cosine
    feather inside `base_head`'s eroded skin interior. Outer jaw/ears/skull remain pixel-identical!
    """
    bh, bw, _ = base_head.shape
    expr_aligned = resize_rgba_straight(expr_head_raw, bw, bh)

    # Eroded interior of `base_head` so outer dark outline (chin, ear, cheek) is 100% untouched
    base_solid = (base_head[:, :, 3] > 180).astype(np.uint8) * 255
    interior = cv2.erode(base_solid, np.ones((11, 11), dtype=np.uint8), iterations=1) > 0

    # Inner 3/4 facial feature oval (shifted +X so far-right 3/4 eye corner is 100% covered)
    yy, xx = np.mgrid[0:bh, 0:bw]
    cx = bw * 0.58
    cy = bh * 0.58
    rx = bw * 0.43
    ry = bh * 0.32
    norm_d = np.sqrt(((xx - cx) / max(1.0, rx)) ** 2 + ((yy - cy) / max(1.0, ry)) ** 2)
    oval_w = np.clip((1.0 - norm_d) / 0.18, 0.0, 1.0)
    oval_w = oval_w * oval_w * (3.0 - 2.0 * oval_w)  # smoothstep feather

    # Soft distance feather from `interior` boundary (erode 5px so outer jaw/skull ink stays untouched)
    interior = cv2.erode(base_solid, np.ones((7, 7), dtype=np.uint8), iterations=1) > 0
    dist_in = cv2.distanceTransform(interior.astype(np.uint8), cv2.DIST_L2, 5)
    interior_w = np.clip(dist_in / 5.0, 0.0, 1.0)
    blend = (oval_w * interior_w)[:, :, None]

    out = base_head.copy()
    blended_rgb = base_head[:, :, :3].astype(np.float32) * (1.0 - blend) + expr_aligned[:, :, :3].astype(np.float32) * blend
    out[:, :, :3] = np.clip(np.round(blended_rgb), 0, 255).astype(np.uint8)
    out[out[:, :, 3] == 0] = 0
    return out


def punch_face_cutout_from_bangs(bangs_rgba: np.ndarray, face_open_rgba: np.ndarray) -> np.ndarray:
    """
    If the AI filled the empty face window inside `hair_bangs` with flat skin color instead of
    `#FF00FF`, automatically detects it by matching `face_open`'s forehead skin tone and punches
    it out cleanly (including the thin bottom chin arc) while preserving bang & side-lock ink lines.
    """
    out = bangs_rgba.copy()
    bh, bw, _ = out.shape
    fh, fw, _ = face_open_rgba.shape

    f_patch = face_open_rgba[int(fh * 0.16) : int(fh * 0.34), int(fw * 0.38) : int(fw * 0.62)]
    f_valid = f_patch[:, :, 3] > 180
    if not np.any(f_valid):
        return out
    skin_rgb = np.median(f_patch[:, :, :3][f_valid].astype(np.float32), axis=0)

    sx, sy = int(bw * 0.52), int(bh * 0.66)
    if not (0 <= sx < bw and 0 <= sy < bh) or out[sy, sx, 3] < 40:
        return out
    seed_rgb = out[sy, sx, :3].astype(np.float32)
    if float(np.linalg.norm(seed_rgb - skin_rgb)) > 54.0:
        return out

    rgb_f = out[:, :, :3].astype(np.float32)
    lum = 0.299 * rgb_f[:, :, 0] + 0.587 * rgb_f[:, :, 1] + 0.114 * rgb_f[:, :, 2]
    dist_skin = np.linalg.norm(rgb_f - skin_rgb[None, None, :], axis=2)

    walkable = ((out[:, :, 3] > 20) & (dist_skin < 52.0) & (lum > 80.0)).astype(np.uint8)
    num_l, labels = cv2.connectedComponents(walkable, connectivity=4)
    target_lbl = int(labels[sy, sx])
    if target_lbl == 0:
        return out

    pocket = (labels == target_lbl).astype(np.uint8) * 255
    # Also clear the thin bottom chin-outline arc directly enclosing the bottom of the face pocket
    # while preserving left/right cheek side-locks (`x < 0.27*bw` or `x > 0.77*bw`) and upper bangs (`y < 0.72*bh`)
    dilated_bot = cv2.dilate(pocket, np.ones((11, 7), dtype=np.uint8), iterations=1) > 0
    yy, xx = np.mgrid[0:bh, 0:bw]
    chin_arc_zone = (yy >= int(bh * 0.73)) & (xx >= int(bw * 0.27)) & (xx <= int(bw * 0.77))
    clear_mask = (pocket > 0) | (dilated_bot & chin_arc_zone)

    out[clear_mask] = 0
    return trim_alpha(out, pad=2)


def make_far_shaded(arr: np.ndarray, mul_rgb: Tuple[float, float, float]) -> np.ndarray:
    out = arr.copy().astype(np.float32)
    mask = out[:, :, 3] > 8
    out[mask, 0] *= mul_rgb[0]
    out[mask, 1] *= mul_rgb[1]
    out[mask, 2] *= mul_rgb[2]
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def pack_shelf_atlas(parts: Dict[str, np.ndarray], max_width: int = 2048, pad: int = 8) -> Tuple[Image.Image, Dict[str, dict]]:
    sorted_items = sorted(parts.items(), key=lambda kv: (-kv[1].shape[0], kv[0]))
    placed: List[Tuple[str, np.ndarray, int, int]] = []
    cur_x, cur_y, row_h, used_w = pad, pad, 0, 0

    for name, arr in sorted_items:
        ph, pw = arr.shape[0], arr.shape[1]
        if cur_x + pw + pad > max_width and cur_x > pad:
            cur_x = pad
            cur_y += row_h + pad
            row_h = 0
        placed.append((name, arr, cur_x, cur_y))
        cur_x += pw + pad
        row_h = max(row_h, ph)
        used_w = max(used_w, cur_x)

    total_h = cur_y + row_h + pad
    atlas_w = max(256, int(2 ** math.ceil(math.log2(max(256, used_w)))))
    atlas_h = max(256, int(2 ** math.ceil(math.log2(max(256, total_h)))))
    if atlas_w > max_width:
        atlas_w = max(max_width, used_w + pad)

    atlas = np.zeros((atlas_h, atlas_w, 4), dtype=np.uint8)
    manifest: Dict[str, dict] = {}
    for name, arr, px, py in placed:
        ph, pw = arr.shape[0], arr.shape[1]
        atlas[py : py + ph, px : px + pw] = arr
        manifest[name] = {
            "x": int(px),
            "y": int(py),
            "w": int(pw),
            "h": int(ph),
            "u0": round(px / atlas_w, 6),
            "v0": round(py / atlas_h, 6),
            "u1": round((px + pw) / atlas_w, 6),
            "v1": round((py + ph) / atlas_h, 6),
        }

    return Image.fromarray(atlas), manifest


def measure_master_anatomy(master_scaled: np.ndarray) -> Dict[str, float]:
    """
    Measures true anatomical horizontal & vertical landmarks directly from `master_scaled`
    so tall animal ears / hats / horns NEVER inflate skull width (`bobblehead bug`) or crush legs!
    """
    th, tw, _ = master_scaled.shape
    mask = master_scaled[:, :, 3] > 24

    def band_widths(r0: float, r1: float) -> List[int]:
        widths: List[int] = []
        for y in range(max(0, int(round(th * r0))), min(th, int(round(th * r1)))):
            xs = np.where(mask[y])[0]
            if len(xs) >= 4:
                widths.append(int(xs.max() - xs.min() + 1))
        return widths

    # Head/hair widest span in [0.22..0.46] of total height (immune to top ear/hat height!)
    hw_list = band_widths(0.22, 0.46)
    hair_w = float(np.percentile(hw_list, 92)) if hw_list else float(tw * 0.88)

    # Top headgear / animal ears span in [0.02..0.20]
    ew_list = band_widths(0.02, 0.20)
    ear_w = float(np.percentile(ew_list, 90)) if ew_list else hair_w * 0.80

    # Neck/upper-shoulder trunk width in [0.51..0.58] (before A-pose sleeves flare wide)
    sw_list = band_widths(0.51, 0.58)
    trunk_w = float(np.percentile(sw_list, 35)) if sw_list else hair_w * 0.62

    # Skirt / lower coat hem width in [0.73..0.81]
    kw_list = band_widths(0.73, 0.81)
    skirt_w = float(np.percentile(kw_list, 65)) if kw_list else trunk_w * 1.20

    # Lower straight-leg outer span in [0.84..0.94]
    lw_list = band_widths(0.84, 0.94)
    leg_outer_span = float(np.median(lw_list)) if lw_list else 62.0

    return {
        "hair_w": round(hair_w, 1),
        "ear_w": round(ear_w, 1),
        "trunk_w": round(trunk_w, 1),
        "skirt_w": round(skirt_w, 1),
        "leg_outer_span": round(leg_outer_span, 1),
    }


def process_operator_kit(spec_path: Path) -> None:
    char_dir = spec_path.parent
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    char_id = spec["char_id"]

    layout_path = char_dir / "templates" / "slot_grid_layout.json"
    if not layout_path.exists():
        raise FileNotFoundError(f"Missing {layout_path}; run generate_mannequin_guide.py first!")
    layout = json.loads(layout_path.read_text(encoding="utf-8"))

    kit_img_path = char_dir / spec["kit_source"]
    if not kit_img_path.exists():
        raise FileNotFoundError(f"Missing AI kit image: {kit_img_path}")

    full_rgba = chroma_key_magenta(Image.open(kit_img_path))

    # 1. Extract Left Master Assembled Reference & calibrate scale to setup canvas target height
    mz = layout["master_zone"]
    master_raw = extract_zone_part(full_rgba, mz["rx0"], mz["ry0"], mz["rx1"], mz["ry1"], "master_ref", allow_multi_island=True)

    props = spec.get("proportions", {})
    canvas_cfg = spec.get("canvas", {"width": 512, "height": 512, "ground_y": 448, "center_x": 256})
    cw = int(canvas_cfg.get("width", 512))
    ch = int(canvas_cfg.get("height", 512))
    cx = int(canvas_cfg.get("center_x", 256))
    gy = int(canvas_cfg.get("ground_y", 448))
    target_h = int(props.get("target_total_height", 336))

    master_scale = target_h / float(max(1, master_raw.shape[0]))
    master_w = max(32, int(round(master_raw.shape[1] * master_scale)))
    master_scaled = resize_rgba_straight(master_raw, master_w, target_h)

    # Render clean `512x512` Master Reference Canvas grounded at `(cx, gy)` for Gate 1 Audit!
    out_dir = char_dir / "textures"
    out_dir.mkdir(parents=True, exist_ok=True)
    master_canvas = np.zeros((ch, cw, 4), dtype=np.uint8)
    mx0 = max(0, min(cw - master_w, cx - master_w // 2))
    my0 = max(0, min(ch - target_h, gy - target_h))
    master_canvas[my0 : my0 + target_h, mx0 : mx0 + master_w] = master_scaled
    master_ref_path = out_dir / "master_reference_512.png"
    Image.fromarray(master_canvas).save(master_ref_path)

    # 2. Extract all 12 right-hand modular slots
    cell_overrides: Dict[str, List[float]] = spec.get("cell_overrides", {})
    multi_island_slots = {"head_acc", "hair_bangs"}
    raw_slots: Dict[str, np.ndarray] = {}
    for cell in layout["cells"]:
        sname = cell["slot"]
        if sname in cell_overrides:
            rx0, ry0, rx1, ry1 = cell_overrides[sname]
        else:
            rx0, ry0, rx1, ry1 = cell["rx0"], cell["ry0"], cell["rx1"], cell["ry1"]
        raw_slots[sname] = extract_zone_part(
            full_rgba, rx0, ry0, rx1, ry1, sname, allow_multi_island=(sname in multi_island_slots)
        )

    # 3. Master-Calibrated Anatomical Scaling (prevents bobblehead inflation from tall ears/horns!)
    anat = measure_master_anatomy(master_scaled)
    head_scale = float(props.get("head_scale", 1.0))

    # Bald anime V-chin head shell fits INSIDE `anat["hair_w"]` (~69% of full fluffy hair width, aspect clamped <= 1.00)
    f_open_raw = raw_slots["face_open"]
    raw_head_aspect = f_open_raw.shape[1] / float(max(1, f_open_raw.shape[0]))
    clamped_head_aspect = max(0.88, min(1.00, raw_head_aspect))
    head_w = int(round(anat["hair_w"] * 0.69 * head_scale))
    head_target_h = int(round(head_w / clamped_head_aspect))
    face_open = resize_rgba_straight(f_open_raw, head_w, head_target_h)
    face_blink = fuse_expression_onto_base_head(face_open, raw_slots["face_blink"])
    face_skill = fuse_expression_onto_base_head(face_open, raw_slots["face_skill"])

    # Hair bangs & back hair locked directly to Master's measured `hair_w`
    bangs_scale = float(props.get("bangs_scale", 1.0))
    bangs_clean_raw = punch_face_cutout_from_bangs(raw_slots["hair_bangs"], f_open_raw)
    bangs_aspect = bangs_clean_raw.shape[0] / float(max(1, bangs_clean_raw.shape[1]))
    bangs_w = max(48, int(round(anat["hair_w"] * 0.97 * bangs_scale)))
    bangs_h = max(48, int(round(bangs_w * min(1.12, max(0.82, bangs_aspect)))))
    hair_bangs = resize_rgba_straight(bangs_clean_raw, bangs_w, bangs_h)

    hb_raw = raw_slots["hair_back"]
    hb_aspect = hb_raw.shape[0] / float(max(1, hb_raw.shape[1]))
    hb_w = max(56, int(round(anat["hair_w"] * 1.01 * head_scale)))
    hb_h = max(56, int(round(hb_w * min(1.15, max(0.88, hb_aspect)))))
    hair_back = resize_rgba_straight(hb_raw, hb_w, hb_h)

    acc_raw = raw_slots["head_acc"]
    acc_aspect = acc_raw.shape[0] / float(max(1, acc_raw.shape[1]))
    acc_w = max(24, int(round(anat["ear_w"] * float(props.get("acc_scale", 1.0)))))
    acc_h = max(20, int(round(acc_w * min(0.95, max(0.45, acc_aspect)))))
    head_acc = resize_rgba_straight(acc_raw, acc_w, acc_h)

    # Torso (collar + jacket + waist/midriff) calibrated to Master's trunk width & torso height
    torso_scale = float(props.get("torso_scale", 1.0))
    t_raw = raw_slots["torso"]
    torso_w = max(52, int(round(anat["trunk_w"] * 0.96 * torso_scale)))
    torso_target_h = max(60, int(round(target_h * 0.255 * torso_scale)))
    torso = resize_rgba_straight(t_raw, torso_w, torso_target_h)

    ct_raw = trim_alpha(raw_slots["coat_tail"], pad=2)
    coat_h = int(round(target_h * float(props.get("coat_height_ratio", 0.19))))
    natural_coat_w = int(round(coat_h * (ct_raw.shape[1] / float(max(1, ct_raw.shape[0])))))
    coat_w = max(torso_w + 14, min(int(round(anat["trunk_w"] * 1.26)), natural_coat_w))
    coat_tail = resize_rgba_straight(ct_raw, coat_w, coat_h)

    # Continuous 1-Piece Arm & Straight Tapered Leg calibrated to Master's leg outer span!
    arm_clean = inpaint_open_joint_cap(straighten_vertical_part(raw_slots["arm_full"]), cap_ratio=0.16, taper_px=10)
    arm_h = int(props.get("arm_length", round(target_h * 0.29)))
    arm_w = max(22, min(32, int(round(arm_h * (arm_clean.shape[1] / float(max(1, arm_clean.shape[0])))))))
    arm_near = resize_rgba_straight(arm_clean, arm_w, arm_h)

    leg_clean = inpaint_open_joint_cap(straighten_vertical_part(raw_slots["leg_full"]), cap_ratio=0.14, taper_px=10)
    leg_h = int(props.get("leg_length", round(target_h * 0.34)))
    target_leg_w = max(24, min(34, int(round(anat["leg_outer_span"] * 0.46))))
    leg_near = resize_rgba_straight(leg_clean, target_leg_w, leg_h)

    far_tint_list = spec.get("style", {}).get("far_limb_tint", [0.85, 0.82, 0.90])
    far_tint = (float(far_tint_list[0]), float(far_tint_list[1]), float(far_tint_list[2]))
    arm_far = make_far_shaded(arm_near, far_tint)
    leg_far = make_far_shaded(leg_near, far_tint)

    # Weapons (proportioned cleanly to 2.8-head chibi so sword feels sleek, not oversized)
    wpn_h = int(props.get("weapon_length", round(target_h * 0.46)))
    w1_clean = straighten_vertical_part(raw_slots["weapon_primary"], max_tilt_deg=35.0)
    w1_w = max(16, int(round(wpn_h * (w1_clean.shape[1] / float(max(1, w1_clean.shape[0]))))))
    weapon_primary = resize_rgba_straight(w1_clean, w1_w, wpn_h)

    w2_clean = straighten_vertical_part(raw_slots["weapon_secondary"], max_tilt_deg=35.0)
    wpn2_h = int(props.get("weapon_secondary_length", round(wpn_h * 1.08)))
    w2_w = max(16, int(round(wpn2_h * (w2_clean.shape[1] / float(max(1, w2_clean.shape[0]))))))
    weapon_secondary = resize_rgba_straight(w2_clean, w2_w, wpn2_h)

    packed_parts = {
        "hair_back": hair_back,
        "face_open": face_open,
        "face_blink": face_blink,
        "face_skill": face_skill,
        "hair_bangs": hair_bangs,
        "head_acc": head_acc,
        "torso": torso,
        "coat_tail": coat_tail,
        "arm_near": arm_near,
        "arm_far": arm_far,
        "leg_near": leg_near,
        "leg_far": leg_far,
        "weapon_primary": weapon_primary,
        "weapon_secondary": weapon_secondary,
    }

    atlas_img, atlas_crops = pack_shelf_atlas(packed_parts, max_width=2048, pad=8)
    atlas_rel = f"textures/tex_{char_id}_parts.png"
    atlas_path = char_dir / atlas_rel
    atlas_img.save(atlas_path)

    manifest = {
        "char_id": char_id,
        "canvas": {"width": cw, "height": ch, "center_x": cx, "ground_y": gy, "target_height": target_h},
        "master_ref": {
            "file": "textures/master_reference_512.png",
            "bbox": [int(mx0), int(my0), int(master_w), int(target_h)],
            "anatomy": anat,
        },
        "atlas": {
            "file": atlas_rel,
            "width": atlas_img.width,
            "height": atlas_img.height,
            "parts": atlas_crops,
        },
    }
    manifest_path = out_dir / "part_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        f"[SLICE_AND_CAP_OK] char={char_id} atlas={atlas_img.size} parts={len(atlas_crops)} "
        f"master_bbox=({mx0},{my0},{master_w},{target_h})"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract, cap-inpaint & pack 2.5D Arknights Spine parts.")
    parser.add_argument("--spec", required=True, help="Path to operator_spec.json")
    args = parser.parse_args()
    process_operator_kit(Path(args.spec).resolve())


if __name__ == "__main__":
    main()
