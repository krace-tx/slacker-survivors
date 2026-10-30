#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AI-Generated Spine Cutout Part Atlas Extractor & Packer for 2.5D Cozy Studio.
Extracts modular anatomical parts from the 4 AI-generated Spine rigging sheets in
`art/spines/cozy_studio/ai_sources/`, applies unpremultiplied #FF00FF chroma keying
and warm-espresso ink despill, generates cel-shaded far-side limb variants for 2.5D
depth separation, and packs clean straight-alpha atlases + `part_manifest.json` for Rev2D.
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
AI_SRC_DIR = HERE / "ai_sources"
OUT_DIR = HERE / "textures"


def chroma_key_magenta(img: Image.Image) -> np.ndarray:
    """
    Keys out flat #FF00FF magenta background with unmixing + warm-brown ink despill.
    Returns straight-alpha RGBA uint8 array (H, W, 4) with zero magenta halo.
    """
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]

    # Magenta dominance metric: min(R, B) - G (255 on #FF00FF, <= ~30 on warm anime colors)
    mag_excess = np.minimum(r, b) - g
    alpha = 1.0 - np.clip((mag_excess - 42.0) / 96.0, 0.0, 1.0)

    # Remove 1px isolated JPEG magenta fringe speckles via alpha erosion check
    solid_core = mag_excess < 68.0
    padded_core = np.pad(solid_core, ((1, 1), (1, 1)), mode="constant", constant_values=False)
    near_core = (
        padded_core[1:-1, 1:-1]
        | padded_core[:-2, 1:-1]
        | padded_core[2:, 1:-1]
        | padded_core[1:-1, :-2]
        | padded_core[1:-1, 2:]
    )
    alpha = np.where(near_core, alpha, 0.0)

    safe_a = np.maximum(alpha, 0.05)
    bg_w = 1.0 - alpha
    out_r = np.clip((r - 255.0 * bg_w) / safe_a, 0.0, 255.0)
    out_g = np.clip(g / safe_a, 0.0, 255.0)
    out_b = np.clip((b - 255.0 * bg_w) / safe_a, 0.0, 255.0)

    # Despill any residual JPEG 4:2:0 chroma bleed along dark espresso ink outlines (#4A2E1B)
    spill = np.maximum(0.0, np.minimum(out_r, out_b) - out_g - 16.0)
    spill_mask = (spill > 0.0) & (alpha > 0.01)
    blend = np.clip(spill / 72.0, 0.0, 1.0)
    out_r = np.where(spill_mask, out_r * (1.0 - blend) + 74.0 * blend, out_r)
    out_g = np.where(spill_mask, out_g * (1.0 - blend) + 46.0 * blend, out_g)
    out_b = np.where(spill_mask, out_b * (1.0 - blend) + 27.0 * blend, out_b)

    alpha = np.where(alpha < 0.08, 0.0, alpha)
    rgba = np.zeros((rgb.shape[0], rgb.shape[1], 4), dtype=np.uint8)
    rgba[:, :, 0] = np.round(out_r).astype(np.uint8)
    rgba[:, :, 1] = np.round(out_g).astype(np.uint8)
    rgba[:, :, 2] = np.round(out_b).astype(np.uint8)
    rgba[:, :, 3] = np.round(alpha * 255.0).astype(np.uint8)
    rgba[rgba[:, :, 3] == 0] = 0
    return rgba


def extract_components(rgba: np.ndarray, min_area: int = 120) -> List[Tuple[dict, np.ndarray]]:
    """Extracts isolated connected components with clean masked RGBA crops."""
    mask = rgba[:, :, 3] > 28
    h, w = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    results: List[Tuple[dict, np.ndarray]] = []

    for y in range(h):
        xs = np.where(mask[y] & (~visited[y]))[0]
        for sx in xs:
            if visited[y, sx]:
                continue
            q = deque([(y, int(sx))])
            visited[y, sx] = True
            pixels: List[Tuple[int, int]] = []
            min_x = max_x = int(sx)
            min_y = max_y = y
            while q:
                cy, cx = q.popleft()
                pixels.append((cy, cx))
                if cx < min_x:
                    min_x = cx
                if cx > max_x:
                    max_x = cx
                if cy < min_y:
                    min_y = cy
                if cy > max_y:
                    max_y = cy
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = True
                        q.append((ny, nx))

            if len(pixels) >= min_area:
                cw = max_x - min_x + 1
                ch = max_y - min_y + 1
                comp_mask = np.zeros((ch, cw), dtype=bool)
                for py, px in pixels:
                    comp_mask[py - min_y, px - min_x] = True
                # Include soft anti-aliased 1px edge around component mask
                padded = np.pad(comp_mask, ((1, 1), (1, 1)), mode="constant", constant_values=False)
                dilated = (
                    padded[1:-1, 1:-1]
                    | padded[:-2, 1:-1]
                    | padded[2:, 1:-1]
                    | padded[1:-1, :-2]
                    | padded[1:-1, 2:]
                )
                crop = rgba[min_y : max_y + 1, min_x : max_x + 1].copy()
                crop[~dilated] = 0
                info = {
                    "x": min_x,
                    "y": min_y,
                    "w": cw,
                    "h": ch,
                    "cx": (min_x + max_x) * 0.5,
                    "cy": (min_y + max_y) * 0.5,
                    "area": len(pixels),
                }
                results.append((info, crop))
    return results


def pick_part(
    comps: List[Tuple[dict, np.ndarray]],
    target_cx: float,
    target_cy: float,
    min_area: int = 100,
) -> np.ndarray:
    """Selects the isolated component closest to `(target_cx, target_cy)`."""
    best_dist = 1e18
    best_crop: np.ndarray | None = None
    for info, crop in comps:
        if info["area"] < min_area:
            continue
        dx = info["cx"] - target_cx
        dy = info["cy"] - target_cy
        d2 = dx * dx + dy * dy
        if d2 < best_dist:
            best_dist = d2
            best_crop = crop
    if best_crop is None:
        raise RuntimeError(f"No component found near ({target_cx}, {target_cy})")
    return best_crop.copy()


def trim_alpha(arr: np.ndarray, pad: int = 2) -> np.ndarray:
    ys, xs = np.where(arr[:, :, 3] > 8)
    if len(xs) == 0:
        return arr
    y0 = max(0, int(ys.min()) - pad)
    y1 = min(arr.shape[0], int(ys.max()) + 1 + pad)
    x0 = max(0, int(xs.min()) - pad)
    x1 = min(arr.shape[1], int(xs.max()) + 1 + pad)
    return arr[y0:y1, x0:x1].copy()


def rotate_part(arr: np.ndarray, angle_ccw_deg: float) -> np.ndarray:
    pil = Image.fromarray(arr)
    rot = pil.rotate(angle_ccw_deg, resample=Image.Resampling.BICUBIC, expand=True)
    return trim_alpha(np.asarray(rot, dtype=np.uint8))


def scale_part(arr: np.ndarray, sx: float, sy: float | None = None) -> np.ndarray:
    if sy is None:
        sy = sx
    pil = Image.fromarray(arr)
    nw = max(4, int(round(pil.width * sx)))
    nh = max(4, int(round(pil.height * sy)))
    return np.asarray(pil.resize((nw, nh), resample=Image.Resampling.LANCZOS), dtype=np.uint8)


def flip_h(arr: np.ndarray) -> np.ndarray:
    return np.ascontiguousarray(arr[:, ::-1, :])


def make_far_shaded(arr: np.ndarray, mul_rgb: Tuple[float, float, float] = (0.87, 0.82, 0.79)) -> np.ndarray:
    """Applies warm cel-shadow tint to far-side limbs for 2.5D side-profile depth separation."""
    out = arr.copy().astype(np.float32)
    mask = out[:, :, 3] > 8
    out[mask, 0] *= mul_rgb[0]
    out[mask, 1] *= mul_rgb[1]
    out[mask, 2] *= mul_rgb[2]
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def seamless_bottom_skin_cap(arr: np.ndarray, cap_rows: int = 24, fade_rows: int = 6) -> np.ndarray:
    """
    Removes the dark ink U-outline along the bottom joint cap of an upper thigh while keeping
    the left/right outer contour outlines crisp, so `thigh` overlaps `shin` with zero doll-joint seam!
    """
    out = arr.copy()
    h, w, _ = out.shape
    # Sample clean interior skin tone from the lower-middle of the thigh
    mid_y = max(0, h - cap_rows - 10)
    mid_xs = np.where(out[mid_y, :, 3] > 200)[0]
    if len(mid_xs) < 8:
        return out
    inner_slice = out[mid_y, mid_xs[len(mid_xs) // 4 : (3 * len(mid_xs)) // 4], :3].astype(np.float32)
    skin_rgb = np.median(inner_slice, axis=0)

    start_y = max(0, h - cap_rows)
    for ry in range(start_y, h):
        xs = np.where(out[ry, :, 3] > 24)[0]
        if len(xs) == 0:
            continue
        x0, x1 = int(xs.min()), int(xs.max())
        span = x1 - x0 + 1
        # Keep 5px side outlines on upper cap rows; in the very bottom 7px tip, replace entire bottom arc
        rows_from_bottom = h - 1 - ry
        margin = 0 if rows_from_bottom < 7 else min(6, max(3, span // 7))
        ix0 = x0 + margin
        ix1 = x1 - margin
        if ix0 <= ix1:
            for x in range(ix0, ix1 + 1):
                if out[ry, x, 3] > 20:
                    px = out[ry, x, :3].astype(np.float32)
                    lum = 0.299 * px[0] + 0.587 * px[1] + 0.114 * px[2]
                    # Dark ink or anti-aliased outline pixel inside the joint cap -> blend to skin tone!
                    if lum < 192.0:
                        ref_y = max(0, start_y - 4)
                        above = out[ref_y, x, :3].astype(np.float32)
                        above_lum = 0.299 * above[0] + 0.587 * above[1] + 0.114 * above[2]
                        fill = above if (out[ref_y, x, 3] > 200 and above_lum >= 192.0) else skin_rgb
                        out[ry, x, 0] = int(round(fill[0]))
                        out[ry, x, 1] = int(round(fill[1]))
                        out[ry, x, 2] = int(round(fill[2]))
        if rows_from_bottom < fade_rows:
            fade = (rows_from_bottom + 0.5) / float(fade_rows)
            # Only fade interior cap pixels so outer side outlines don't break prematurely
            for x in range(max(x0, ix0), min(x1, ix1) + 1):
                out[ry, x, 3] = int(round(out[ry, x, 3] * fade))
            if rows_from_bottom < 3:
                out[ry, x0 : x1 + 1, 3] = (out[ry, x0 : x1 + 1, 3].astype(np.float32) * (fade * 0.75)).astype(np.uint8)
    out[out[:, :, 3] == 0] = 0
    return out


def taper_top_cap(arr: np.ndarray, cap_px: int = 20) -> np.ndarray:
    """Rounds off the top `cap_px` rows of a cut limb into a smooth elliptical joint cap."""
    out = arr.copy()
    h, w, _ = out.shape
    limit = min(h, cap_px)
    for ry in range(limit):
        t = 1.0 - (ry / max(1.0, float(limit)))
        xs = np.where(out[ry, :, 3] > 20)[0]
        if len(xs) >= 4:
            cx = 0.5 * (xs.min() + xs.max())
            half_w = 0.5 * (xs.max() - xs.min()) * float(np.sqrt(max(0.0, 1.0 - t * t)))
            for x in range(w):
                if abs(x - cx) > half_w:
                    out[ry, x] = 0
    return trim_alpha(out)


def split_vertical_limb_with_cap(
    arr: np.ndarray,
    split_y: int,
    overlap_px: int = 18,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Splits a full leg into `(upper_thigh, lower_shin_shoe)` with smooth rounded overlap caps
    around `split_y` so knee rotation up to +-45 degrees never shows a gap.
    """
    h, w, _ = arr.shape
    y_top_end = min(h, split_y + overlap_px)
    y_bot_start = max(0, split_y - overlap_px)

    upper = arr[:y_top_end, :, :].copy()
    lower = arr[y_bot_start:, :, :].copy()

    # Round off the bottom of `upper` and the top of `lower` with elliptical mask taper
    for ry in range(max(0, y_top_end - overlap_px), y_top_end):
        t = (ry - (y_top_end - overlap_px)) / max(1.0, float(overlap_px))
        xs = np.where(upper[ry, :, 3] > 20)[0]
        if len(xs) >= 4:
            cx = 0.5 * (xs.min() + xs.max())
            half_w = 0.5 * (xs.max() - xs.min()) * float(np.sqrt(max(0.0, 1.0 - t * t)))
            for x in range(w):
                if abs(x - cx) > half_w:
                    upper[ry, x] = 0

    for ry in range(0, min(lower.shape[0], overlap_px)):
        t = 1.0 - (ry / max(1.0, float(overlap_px)))
        xs = np.where(lower[ry, :, 3] > 20)[0]
        if len(xs) >= 4:
            cx = 0.5 * (xs.min() + xs.max())
            half_w = 0.5 * (xs.max() - xs.min()) * float(np.sqrt(max(0.0, 1.0 - t * t)))
            for x in range(w):
                if abs(x - cx) > half_w:
                    lower[ry, x] = 0

    return trim_alpha(upper), trim_alpha(lower)


def pack_shelf_atlas(parts: Dict[str, np.ndarray], max_width: int = 2048, pad: int = 8) -> Tuple[Image.Image, Dict[str, dict]]:
    """Packs RGBA part arrays into a tight, padded RGBA atlas PNG + crop dictionary."""
    # Sort tallest first for clean shelf packing
    sorted_items = sorted(parts.items(), key=lambda kv: (-kv[1].shape[0], kv[0]))
    placed: List[Tuple[str, np.ndarray, int, int]] = []
    cur_x = pad
    cur_y = pad
    row_h = 0
    used_w = 0

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
    atlas_w = max(256, int(2 ** np.ceil(np.log2(max(256, used_w)))))
    atlas_h = max(256, int(2 ** np.ceil(np.log2(max(256, total_h)))))
    if atlas_w > max_width:
        atlas_w = max(max_width, used_w + pad)

    atlas = np.zeros((atlas_h, atlas_w, 4), dtype=np.uint8)
    manifest: Dict[str, dict] = {}
    for name, arr, px, py in placed:
        ph, pw = arr.shape[0], arr.shape[1]
        atlas[py : py + ph, px : px + pw] = arr
        manifest[name] = {"x": int(px), "y": int(py), "w": int(pw), "h": int(ph)}

    return Image.fromarray(atlas), manifest


def punch_enclosed_pocket(arr: np.ndarray, seed_x: int, seed_y: int, tol: float = 42.0) -> np.ndarray:
    """Clears an enclosed flat backing pocket (e.g. open cardigan waist gap) while preserving dark ink lines."""
    out = arr.copy()
    h, w, _ = out.shape
    if not (0 <= seed_x < w and 0 <= seed_y < h):
        return out
    ref = out[seed_y, seed_x, :3].astype(np.float32)
    visited = np.zeros((h, w), dtype=bool)
    q = deque([(seed_y, seed_x)])
    visited[seed_y, seed_x] = True
    pocket = np.zeros((h, w), dtype=bool)
    while q:
        cy, cx = q.popleft()
        pocket[cy, cx] = True
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and out[ny, nx, 3] > 20:
                px_rgb = out[ny, nx, :3].astype(np.float32)
                # Stop sharply at dark-brown ink lines (lum < 120) or outside color tolerance
                lum = 0.299 * px_rgb[0] + 0.587 * px_rgb[1] + 0.114 * px_rgb[2]
                dist = float(np.linalg.norm(px_rgb - ref))
                if lum > 115.0 and dist < tol:
                    visited[ny, nx] = True
                    q.append((ny, nx))
    out[pocket] = 0
    return out


def build_slacker_parts() -> Tuple[Image.Image, Dict[str, dict]]:
    front_rgba = chroma_key_magenta(Image.open(AI_SRC_DIR / "raw_spine_slacker_front.jpg"))
    side_rgba = chroma_key_magenta(Image.open(AI_SRC_DIR / "raw_spine_slacker_side.jpg"))
    back_rgba = chroma_key_magenta(Image.open(AI_SRC_DIR / "raw_spine_slacker_back.jpg"))

    f_comps = extract_components(front_rgba)
    s_comps = extract_components(side_rgba)
    b_comps = extract_components(back_rgba)

    parts: Dict[str, np.ndarray] = {}

    # --- FRONT VIEW PARTS ---
    parts["f_hair_back"] = trim_alpha(pick_part(f_comps, 875, 151))
    parts["f_face_open"] = trim_alpha(pick_part(f_comps, 455, 133))
    parts["f_face_happy"] = trim_alpha(pick_part(f_comps, 671, 133))
    parts["f_bangs"] = trim_alpha(pick_part(f_comps, 1056, 121))
    parts["f_hair_side_l"] = trim_alpha(pick_part(f_comps, 1160, 139, min_area=1000))
    parts["f_hair_side_r"] = trim_alpha(pick_part(f_comps, 1223, 142, min_area=1000))
    parts["f_ahoge"] = trim_alpha(pick_part(f_comps, 1303, 83, min_area=400))

    f_torso_raw = trim_alpha(pick_part(f_comps, 475, 386))
    parts["f_torso"] = punch_enclosed_pocket(f_torso_raw, seed_x=96, seed_y=240, tol=44.0)
    parts["f_skirt"] = trim_alpha(pick_part(f_comps, 713, 363))
    parts["f_skirt_sit"] = trim_alpha(pick_part(f_comps, 711, 601))

    # Straight sleeve rotated upright (-9 deg CW so sleeve hangs straight down)
    f_arm_str = rotate_part(pick_part(f_comps, 918, 416), -9.0)
    parts["f_arm_straight_r"] = f_arm_str
    parts["f_arm_straight_l"] = flip_h(f_arm_str)
    parts["f_arm_bent_r"] = trim_alpha(pick_part(f_comps, 1100, 353))
    parts["f_arm_bent_l"] = flip_h(parts["f_arm_bent_r"])
    parts["f_arm_latte"] = trim_alpha(pick_part(f_comps, 1260, 331))

    f_thigh = seamless_bottom_skin_cap(trim_alpha(pick_part(f_comps, 1124, 571)), cap_rows=26, fade_rows=6)
    parts["f_thigh_r"] = f_thigh
    parts["f_thigh_l"] = flip_h(f_thigh)
    f_shin = trim_alpha(pick_part(f_comps, 1276, 604))
    parts["f_shin_shoe_l"] = f_shin  # Toe points slightly screen-left -> character's right / screen-left leg
    parts["f_shin_shoe_r"] = flip_h(f_shin)

    # --- SIDE VIEW PARTS (Facing +X Screen Right) ---
    parts["s_hair_back"] = trim_alpha(pick_part(s_comps, 390, 196))
    s_head_open = trim_alpha(pick_part(s_comps, 589, 160))
    s_head_happy_raw = trim_alpha(pick_part(s_comps, 582, 596))
    # Match s_head_happy dimensions to s_head_open for zero-jitter blink/smile swap
    parts["s_head_open"] = s_head_open
    parts["s_head_happy"] = scale_part(
        s_head_happy_raw,
        s_head_open.shape[1] / float(s_head_happy_raw.shape[1]),
        s_head_open.shape[0] / float(s_head_happy_raw.shape[0]),
    )
    parts["s_ahoge"] = trim_alpha(pick_part(s_comps, 391, 386, min_area=500))
    parts["s_hair_side"] = trim_alpha(pick_part(s_comps, 430, 501, min_area=1000))

    parts["s_torso"] = trim_alpha(pick_part(s_comps, 800, 215))
    parts["s_skirt"] = trim_alpha(pick_part(s_comps, 808, 461))
    parts["s_skirt_sit"] = trim_alpha(pick_part(s_comps, 840, 635))

    s_arm_str = trim_alpha(pick_part(s_comps, 1073, 198))
    parts["s_arm_straight"] = s_arm_str
    parts["s_arm_straight_far"] = make_far_shaded(s_arm_str)
    parts["s_arm_bent"] = trim_alpha(pick_part(s_comps, 1236, 132))
    parts["s_arm_latte"] = trim_alpha(pick_part(s_comps, 1234, 287))

    # Rotate diagonal thigh (#17, hip top-left -> knee bottom-right) by -46 deg CW so hip is top & knee is bottom!
    s_thigh = seamless_bottom_skin_cap(rotate_part(pick_part(s_comps, 1111, 448), -46.0), cap_rows=24, fade_rows=5)
    parts["s_thigh"] = s_thigh
    parts["s_thigh_far"] = make_far_shaded(s_thigh)

    # #18 is lower leg + white sock; take lower shin portion with rounded knee joint cap for crisp 2-bone IK!
    s_leg_raw = trim_alpha(pick_part(s_comps, 1265, 510))
    s_shin = taper_top_cap(s_leg_raw[60:, :, :], cap_px=22)
    parts["s_shin"] = s_shin
    parts["s_shin_far"] = make_far_shaded(s_shin)

    s_shoe = trim_alpha(pick_part(s_comps, 1282, 695))
    parts["s_shoe"] = s_shoe
    parts["s_shoe_far"] = make_far_shaded(s_shoe)

    # --- BACK VIEW PARTS ---
    parts["b_hair_dome"] = trim_alpha(pick_part(b_comps, 552, 154))
    parts["b_hair_curtain"] = trim_alpha(pick_part(b_comps, 548, 361))
    parts["b_hair_lock_l"] = trim_alpha(pick_part(b_comps, 424, 585))
    parts["b_hair_lock_r"] = trim_alpha(pick_part(b_comps, 670, 585))
    parts["b_ahoge"] = trim_alpha(pick_part(b_comps, 552, 587))

    parts["b_torso"] = trim_alpha(pick_part(b_comps, 890, 262))
    parts["b_skirt"] = trim_alpha(pick_part(b_comps, 892, 565))

    b_arm = trim_alpha(pick_part(b_comps, 1278, 229))
    parts["b_arm_r"] = b_arm
    parts["b_arm_l"] = flip_h(b_arm)

    b_leg_full = trim_alpha(pick_part(b_comps, 1285, 564))
    b_thigh_raw, b_shin_shoe = split_vertical_limb_with_cap(b_leg_full, split_y=146, overlap_px=18)
    b_thigh = seamless_bottom_skin_cap(b_thigh_raw, cap_rows=22, fade_rows=6)
    parts["b_thigh_r"] = b_thigh
    parts["b_thigh_l"] = flip_h(b_thigh)
    parts["b_shin_shoe_r"] = b_shin_shoe
    parts["b_shin_shoe_l"] = flip_h(b_shin_shoe)

    return pack_shelf_atlas(parts, max_width=2048, pad=8)


def build_partner_parts() -> Tuple[Image.Image, Dict[str, dict]]:
    partner_rgba = chroma_key_magenta(Image.open(AI_SRC_DIR / "raw_spine_partner_front.jpg"))
    p_comps = extract_components(partner_rgba)

    parts: Dict[str, np.ndarray] = {}
    parts["p_hair_back"] = trim_alpha(pick_part(p_comps, 435, 130))
    p_head_open = trim_alpha(pick_part(p_comps, 658, 125))
    p_head_blink_raw = trim_alpha(pick_part(p_comps, 649, 341))
    parts["p_head_open"] = p_head_open
    parts["p_head_blink"] = scale_part(
        p_head_blink_raw,
        p_head_open.shape[1] / float(p_head_blink_raw.shape[1]),
        p_head_open.shape[0] / float(p_head_blink_raw.shape[0]),
    )
    parts["p_hair_side_l"] = trim_alpha(pick_part(p_comps, 409, 521))
    parts["p_hair_side_r"] = trim_alpha(pick_part(p_comps, 648, 530))
    parts["p_headphones"] = trim_alpha(pick_part(p_comps, 519, 662))

    parts["p_torso"] = trim_alpha(pick_part(p_comps, 912, 186))
    parts["p_tablet"] = trim_alpha(pick_part(p_comps, 917, 456))

    p_arm_up = trim_alpha(pick_part(p_comps, 1203, 91))
    parts["p_arm_upper_l"] = p_arm_up
    parts["p_arm_upper_r"] = flip_h(p_arm_up)
    parts["p_arm_stylus"] = trim_alpha(pick_part(p_comps, 1229, 204))
    # Flip horizontally so right-screen elbow is on the right and fingers cradle the bottom of the tablet inward
    parts["p_arm_cradle"] = flip_h(trim_alpha(pick_part(p_comps, 1205, 328)))

    parts["p_leg_l"] = trim_alpha(pick_part(p_comps, 1135, 572))
    parts["p_leg_r"] = trim_alpha(pick_part(p_comps, 1272, 570))

    return pack_shelf_atlas(parts, max_width=2048, pad=8)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    slacker_img, slacker_manifest = build_slacker_parts()
    partner_img, partner_manifest = build_partner_parts()

    slacker_path = OUT_DIR / "tex_slacker_parts.png"
    partner_path = OUT_DIR / "tex_partner_parts.png"
    slacker_img.save(slacker_path)
    partner_img.save(partner_path)

    manifest = {
        "canvas": {"w": 576, "h": 920, "ground_y": 888},
        "slacker_atlas": {
            "file": "textures/tex_slacker_parts.png",
            "w": slacker_img.width,
            "h": slacker_img.height,
            "parts": slacker_manifest,
        },
        "partner_atlas": {
            "file": "textures/tex_partner_parts.png",
            "w": partner_img.width,
            "h": partner_img.height,
            "parts": partner_manifest,
        },
    }
    (OUT_DIR / "part_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        f"[EXTRACT_AI_PARTS_OK] slacker={slacker_img.size} ({len(slacker_manifest)} parts), "
        f"partner={partner_img.size} ({len(partner_manifest)} parts)"
    )


if __name__ == "__main__":
    main()
