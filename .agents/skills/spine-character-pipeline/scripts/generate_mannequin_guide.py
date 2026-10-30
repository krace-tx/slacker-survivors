#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Step 1 of `spine-character-pipeline`:
Generates deterministic 2.8-head Arknights-style 3/4 Quarter-View Mannequin Guides:
  1. `templates/mannequin_front_34.png` (512x512 canonical setup proportion ruler)
  2. `templates/kit_guide_front_34.png` (1536x864 16:9 widescreen guide: Left Master + Right 4x3 Grid)
     drawn strictly in zero-green magenta-family tones (`G = 0`, `#FF00FF` bg + `#D400D4`/`#AE00AE` shapes)
     so `image-generator` locks exact proportions & slot placement while any residual guide pixels
     dissolve cleanly to `alpha = 0` during `#FF00FF` chroma keying!
  3. `templates/slot_grid_layout.json` (normalized [0..1] zone & 12-cell bounding boxes)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple

from PIL import Image, ImageDraw


BG_MAGENTA = (255, 0, 255)
SIL_FILL = (216, 0, 216)      # G=0 -> min(R,B)-G = 216 (keys out cleanly if residual!)
SIL_DARK = (172, 0, 172)      # G=0 -> min(R,B)-G = 172
SIL_ACCENT = (234, 0, 234)    # G=0 -> min(R,B)-G = 234


def _draw_tapered_limb(
    draw: ImageDraw.ImageDraw,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    r_top: float,
    r_bot: float,
    fill: Tuple[int, int, int],
    outline: Tuple[int, int, int],
    width: int = 3,
) -> None:
    import math

    dx = x1 - x0
    dy = y1 - y0
    dist = max(1.0, math.hypot(dx, dy))
    nx = -dy / dist
    ny = dx / dist
    poly = [
        (x0 + nx * r_top, y0 + ny * r_top),
        (x1 + nx * r_bot, y1 + ny * r_bot),
        (x1 - nx * r_bot, y1 - ny * r_bot),
        (x0 - nx * r_top, y0 - ny * r_top),
    ]
    draw.polygon(poly, fill=fill, outline=outline)
    draw.ellipse((x0 - r_top, y0 - r_top, x0 + r_top, y0 + r_top), fill=fill, outline=outline, width=width)
    draw.ellipse((x1 - r_bot, y1 - r_bot, x1 + r_bot, y1 + r_bot), fill=fill, outline=outline, width=width)
    draw.polygon(poly, fill=fill)
    draw.line([poly[0], poly[1]], fill=outline, width=width)
    draw.line([poly[2], poly[3]], fill=outline, width=width)


def _draw_anime_chibi_head(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    fill: Tuple[int, int, int],
    outline: Tuple[int, int, int],
    width: int = 3,
    draw_ear: bool = True,
) -> None:
    """Draws a true 3/4 anime V-chin chibi head shell (round cranium + delicate tapered chin, NEVER a wide potato oval!)."""
    import math

    if draw_ear:
        ear_box = (cx - rx * 1.06, cy + ry * 0.02, cx - rx * 0.78, cy + ry * 0.42)
        draw.ellipse(ear_box, fill=fill, outline=outline, width=width)

    pts: List[Tuple[float, float]] = []
    steps = 48
    for i in range(steps):
        ang = (2.0 * math.pi * i) / steps  # 0 = +X right, pi/2 = +Y down (chin)
        ca, sa = math.cos(ang), math.sin(ang)
        # Taper lower jaw smoothly into a cute 3/4 anime V-chin shifted slightly +X (+0.08 * rx)
        lower = max(0.0, sa)
        width_taper = 1.0 - 0.24 * (lower ** 1.6)
        chin_shift_x = rx * 0.08 * (lower ** 1.4)
        px = cx + ca * rx * width_taper + chin_shift_x
        py = cy + sa * ry * (1.0 + 0.04 * (lower ** 2))
        pts.append((px, py))
    draw.polygon(pts, fill=fill, outline=outline, width=width)


def draw_mannequin_34(
    draw: ImageDraw.ImageDraw,
    cx: float,
    ground_y: float,
    total_h: float,
    fill: Tuple[int, int, int] = SIL_FILL,
    outline: Tuple[int, int, int] = SIL_DARK,
    stroke_w: int = 3,
) -> None:
    """Draws a 2.8-head 35-degree 3/4 front-right Arknights chibi mannequin (body crown = 0.86 * total_h, ears/headgear headroom = 0.14)."""
    body_h = total_h * 0.86
    head_h = body_h * 0.34
    torso_h = body_h * 0.30
    leg_h = body_h * 0.36

    hip_y = ground_y - leg_h
    neck_y = hip_y - torso_h
    head_cy = neck_y - head_h * 0.47
    head_rx = head_h * 0.48
    head_ry = head_h * 0.50

    # Far arm (24 deg clean A-pose to screen right)
    _draw_tapered_limb(
        draw,
        cx + body_h * 0.09,
        neck_y + body_h * 0.05,
        cx + body_h * 0.21,
        neck_y + body_h * 0.33,
        r_top=body_h * 0.046,
        r_bot=body_h * 0.036,
        fill=fill,
        outline=outline,
        width=stroke_w,
    )

    # Far & near straight vertical parallel legs (clean stance separation, flat boots on ground_y!)
    _draw_tapered_limb(
        draw,
        cx + body_h * 0.058,
        hip_y + body_h * 0.02,
        cx + body_h * 0.060,
        ground_y - body_h * 0.035,
        r_top=body_h * 0.050,
        r_bot=body_h * 0.040,
        fill=fill,
        outline=outline,
        width=stroke_w,
    )
    _draw_tapered_limb(
        draw,
        cx - body_h * 0.058,
        hip_y + body_h * 0.02,
        cx - body_h * 0.060,
        ground_y - body_h * 0.035,
        r_top=body_h * 0.052,
        r_bot=body_h * 0.042,
        fill=fill,
        outline=outline,
        width=stroke_w,
    )

    # Flaring coat-tail / pleated skirt around pelvis
    hem_poly = [
        (cx - body_h * 0.115, hip_y - body_h * 0.03),
        (cx + body_h * 0.115, hip_y - body_h * 0.03),
        (cx + body_h * 0.175, hip_y + body_h * 0.13),
        (cx - body_h * 0.180, hip_y + body_h * 0.13),
    ]
    draw.polygon(hem_poly, fill=fill, outline=outline, width=stroke_w)

    # Closed-side torso + tapered waist/midriff down to hip_y
    torso_poly = [
        (cx - body_h * 0.105, neck_y + body_h * 0.02),
        (cx + body_h * 0.105, neck_y + body_h * 0.02),
        (cx + body_h * 0.095, hip_y - body_h * 0.07),
        (cx + body_h * 0.108, hip_y),
        (cx - body_h * 0.108, hip_y),
        (cx - body_h * 0.095, hip_y - body_h * 0.07),
    ]
    draw.polygon(torso_poly, fill=fill, outline=outline, width=stroke_w)

    # Near arm (24 deg clean A-pose to screen left)
    _draw_tapered_limb(
        draw,
        cx - body_h * 0.095,
        neck_y + body_h * 0.05,
        cx - body_h * 0.215,
        neck_y + body_h * 0.33,
        r_top=body_h * 0.048,
        r_bot=body_h * 0.038,
        fill=fill,
        outline=outline,
        width=stroke_w,
    )

    # Anime V-chin 3/4 chibi head dome
    _draw_anime_chibi_head(draw, cx, head_cy, head_rx, head_ry, fill=SIL_ACCENT, outline=outline, width=stroke_w)
    eye_y = head_cy + head_ry * 0.18
    face_cx = cx + head_rx * 0.16
    draw.line([(cx - head_rx * 0.72, eye_y), (cx + head_rx * 0.84, eye_y)], fill=outline, width=max(2, stroke_w - 1))
    draw.line([(face_cx, head_cy - head_ry * 0.85), (face_cx, head_cy + head_ry * 0.92)], fill=outline, width=max(2, stroke_w - 1))


def _draw_slot_guides(draw: ImageDraw.ImageDraw, cells: List[dict]) -> None:
    """Draws unmistakable zero-green magenta-family anime-proportioned silhouettes inside each of the 12 grid cells."""
    by_key: Dict[str, dict] = {c["slot"]: c for c in cells}

    # (0,0) hair_back
    c = by_key["hair_back"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5
    draw.ellipse((cx - 64, cy - 82, cx + 64, cy + 62), fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.polygon([(cx - 66, cy - 8), (cx + 66, cy - 8), (cx + 78, cy + 84), (cx - 78, cy + 84)], fill=SIL_FILL, outline=SIL_DARK, width=3)

    # (0,1..3) 3 Anime V-Chin Bald Heads (aspect ~0.94, large anime eyes, delicate small mouth — NEVER wide potato ovals!)
    for slot_key, mode in [("face_open", "open"), ("face_blink", "blink"), ("face_skill", "skill")]:
        c = by_key[slot_key]
        cx, cy = (c["x0"] + c["x1"]) * 0.5 + 4, (c["y0"] + c["y1"]) * 0.5 + 4
        _draw_anime_chibi_head(draw, cx, cy, rx=58, ry=64, fill=SIL_ACCENT, outline=SIL_DARK, width=3, draw_ear=True)
        ey = cy + 12
        if mode == "open":
            draw.rounded_rectangle((cx - 32, ey - 15, cx - 4, ey + 17), radius=8, fill=SIL_DARK)
            draw.rounded_rectangle((cx + 16, ey - 15, cx + 40, ey + 17), radius=8, fill=SIL_DARK)
            draw.line([(cx + 2, cy + 40), (cx + 14, cy + 40)], fill=SIL_DARK, width=3)
        elif mode == "blink":
            draw.arc((cx - 32, ey - 2, cx - 4, ey + 12), start=15, end=165, fill=SIL_DARK, width=4)
            draw.arc((cx + 16, ey - 2, cx + 40, ey + 12), start=15, end=165, fill=SIL_DARK, width=4)
            draw.line([(cx + 2, cy + 40), (cx + 14, cy + 40)], fill=SIL_DARK, width=3)
        else:
            draw.polygon([(cx - 34, ey - 12), (cx - 4, ey - 3), (cx - 8, ey + 15), (cx - 30, ey + 13)], fill=SIL_DARK)
            draw.polygon([(cx + 16, ey - 3), (cx + 42, ey - 12), (cx + 38, ey + 13), (cx + 18, ey + 15)], fill=SIL_DARK)
            draw.rounded_rectangle((cx + 1, cy + 32, cx + 17, cy + 48), radius=5, fill=SIL_DARK)

    # (1,0) hair_bangs (fluffy bangs + cheek side-locks with OPEN MAGENTA FACE WINDOW in center!)
    c = by_key["hair_bangs"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5
    draw.pieslice((cx - 72, cy - 82, cx + 72, cy + 44), start=180, end=360, fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.polygon([(cx - 72, cy - 20), (cx - 44, cy - 20), (cx - 52, cy + 82), (cx - 76, cy + 64)], fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.polygon([(cx + 44, cy - 20), (cx + 72, cy - 20), (cx + 76, cy + 64), (cx + 52, cy + 82)], fill=SIL_FILL, outline=SIL_DARK, width=3)

    # (1,1) head_acc (animal ears / headgear + ahoge)
    c = by_key["head_acc"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5 + 16
    draw.polygon([(cx - 60, cy + 26), (cx - 42, cy - 58), (cx - 12, cy + 16)], fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.polygon([(cx + 12, cy + 16), (cx + 42, cy - 58), (cx + 60, cy + 26)], fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.arc((cx - 16, cy - 78, cx + 22, cy - 18), start=190, end=350, fill=SIL_DARK, width=5)

    # (1,2) torso (closed-side collar + jacket + lower waist/midriff — NO open side armhole holes!)
    c = by_key["torso"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5 + 4
    draw.polygon(
        [
            (cx - 50, cy - 72),
            (cx + 50, cy - 72),
            (cx + 56, cy + 24),
            (cx + 46, cy + 72),
            (cx - 46, cy + 72),
            (cx - 56, cy + 24),
        ],
        fill=SIL_FILL,
        outline=SIL_DARK,
        width=3,
    )

    # (1,3) coat_tail (flaring lower hem / tactical pleated miniskirt)
    c = by_key["coat_tail"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5 + 4
    draw.polygon(
        [(cx - 54, cy - 50), (cx + 54, cy - 50), (cx + 82, cy + 54), (cx - 82, cy + 54)],
        fill=SIL_FILL,
        outline=SIL_DARK,
        width=3,
    )

    # (2,0) arm_full (single upright 1-piece tapered sleeve + hand)
    c = by_key["arm_full"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5
    _draw_tapered_limb(draw, cx, cy - 74, cx, cy + 64, r_top=28, r_bot=21, fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.ellipse((cx - 18, cy + 58, cx + 18, cy + 92), fill=SIL_ACCENT, outline=SIL_DARK, width=3)

    # (2,1) leg_full (single upright 1-piece tapered leg + boot)
    c = by_key["leg_full"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5
    _draw_tapered_limb(draw, cx, cy - 82, cx, cy + 72, r_top=30, r_bot=22, fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.rounded_rectangle((cx - 24, cy + 60, cx + 34, cy + 96), radius=10, fill=SIL_DARK, outline=SIL_DARK, width=2)

    # (2,2) weapon_primary (upright sword: tip up, hilt at bottom)
    c = by_key["weapon_primary"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5
    draw.polygon([(cx, cy - 112), (cx + 15, cy - 80), (cx + 13, cy + 48), (cx - 13, cy + 48), (cx - 15, cy - 80)], fill=SIL_ACCENT, outline=SIL_DARK, width=3)
    draw.rounded_rectangle((cx - 34, cy + 46, cx + 34, cy + 58), radius=4, fill=SIL_DARK)
    draw.rounded_rectangle((cx - 7, cy + 58, cx + 7, cy + 104), radius=4, fill=SIL_FILL, outline=SIL_DARK, width=3)

    # (2,3) weapon_secondary (upright halberd / heavy polearm: head up, grip at bottom)
    c = by_key["weapon_secondary"]
    cx, cy = (c["x0"] + c["x1"]) * 0.5, (c["y0"] + c["y1"]) * 0.5
    draw.rounded_rectangle((cx - 6, cy - 92, cx + 6, cy + 108), radius=3, fill=SIL_FILL, outline=SIL_DARK, width=3)
    draw.polygon([(cx, cy - 116), (cx + 42, cy - 72), (cx + 28, cy - 18), (cx - 18, cy - 38)], fill=SIL_ACCENT, outline=SIL_DARK, width=3)


def generate_guides(out_dir: Path, master_ref: Path | None = None) -> Dict[str, object]:
    tpl_dir = out_dir / "templates"
    tpl_dir.mkdir(parents=True, exist_ok=True)

    # 1. 512x512 Canonical Setup Mannequin
    man_img = Image.new("RGB", (512, 512), BG_MAGENTA)
    man_draw = ImageDraw.Draw(man_img)
    draw_mannequin_34(man_draw, cx=256.0, ground_y=448.0, total_h=336.0, stroke_w=3)
    man_path = tpl_dir / "mannequin_front_34.png"
    man_img.save(man_path)

    # 2. 1536x864 (16:9) Left-Master + Right-4x3-Grid Kit Guide
    kit_w, kit_h = 1536, 864
    kit_img = Image.new("RGBA", (kit_w, kit_h), (*BG_MAGENTA, 255))
    kit_draw = ImageDraw.Draw(kit_img)

    # Left Master Zone: either lock an existing Master Reference sprite or draw the 2.8-head Mannequin
    if master_ref is not None and master_ref.exists():
        import numpy as np

        m_rgba = np.asarray(Image.open(master_ref).convert("RGBA"), dtype=np.uint8)
        ys, xs = np.where(m_rgba[:, :, 3] > 20)
        if len(xs) > 0:
            crop = m_rgba[int(ys.min()) : int(ys.max()) + 1, int(xs.min()) : int(xs.max()) + 1]
            target_mh = 620
            scale = target_mh / float(max(1, crop.shape[0]))
            target_mw = max(32, int(round(crop.shape[1] * scale)))
            m_pil = Image.fromarray(crop).resize((target_mw, target_mh), Image.Resampling.LANCZOS)
            px = max(8, int(round(240.0 - target_mw * 0.5)))
            py = max(16, int(round(776.0 - target_mh)))
            kit_img.alpha_composite(m_pil, (px, py))
        else:
            draw_mannequin_34(kit_draw, cx=240.0, ground_y=756.0, total_h=564.0, stroke_w=4)
    else:
        draw_mannequin_34(kit_draw, cx=240.0, ground_y=756.0, total_h=564.0, stroke_w=4)

    slot_order = [
        ["hair_back", "face_open", "face_blink", "face_skill"],
        ["hair_bangs", "head_acc", "torso", "coat_tail"],
        ["arm_full", "leg_full", "weapon_primary", "weapon_secondary"],
    ]
    grid_x0 = 496
    cell_w = 256
    cell_h = 288
    cells: List[dict] = []
    for r in range(3):
        for c in range(4):
            x0 = grid_x0 + c * cell_w
            y0 = r * cell_h
            x1 = x0 + cell_w
            y1 = y0 + cell_h
            cells.append(
                {
                    "slot": slot_order[r][c],
                    "row": r,
                    "col": c,
                    "x0": x0,
                    "y0": y0,
                    "x1": x1,
                    "y1": y1,
                    "rx0": round(x0 / kit_w, 6),
                    "ry0": round(y0 / kit_h, 6),
                    "rx1": round(x1 / kit_w, 6),
                    "ry1": round(y1 / kit_h, 6),
                }
            )

    _draw_slot_guides(kit_draw, cells)
    kit_path = tpl_dir / "kit_guide_front_34.png"
    kit_img.convert("RGB").save(kit_path)

    layout = {
        "guide_size": [kit_w, kit_h],
        "setup_canvas": {"width": 512, "height": 512, "center_x": 256, "ground_y": 448, "target_height": 336},
        "master_zone": {
            "x0": 8,
            "y0": 24,
            "x1": 484,
            "y1": 848,
            "rx0": round(8 / kit_w, 6),
            "ry0": round(24 / kit_h, 6),
            "rx1": round(484 / kit_w, 6),
            "ry1": round(848 / kit_h, 6),
        },
        "cells": cells,
    }
    layout_path = tpl_dir / "slot_grid_layout.json"
    layout_path.write_text(json.dumps(layout, indent=2), encoding="utf-8")
    print(f"[MANNEQUIN_GUIDE_OK] mannequin={man_path} kit_guide={kit_path} cells={len(cells)}")
    return layout


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate 2.8-head Arknights 2.5D Spine mannequin & 12-slot kit guides.")
    parser.add_argument("--out-dir", required=True, help="Target character directory, e.g. art/spines/vanguard_lupo")
    parser.add_argument("--master-ref", default="", help="Optional existing transparent Master character PNG to lock on left panel")
    args = parser.parse_args()
    m_ref = Path(args.master_ref).resolve() if args.master_ref else None
    generate_guides(Path(args.out_dir).resolve(), master_ref=m_ref)


if __name__ == "__main__":
    main()
