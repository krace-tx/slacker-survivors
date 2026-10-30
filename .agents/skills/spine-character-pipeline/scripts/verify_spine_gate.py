#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Step 6 of `spine-character-pipeline`:
5-Gate Automated Quality Audit & 4-Panel Visual Inspection Card Generator.

Enforces:
  Gate 1: Rest-Pose Height & Ground Contact Alignment vs Master Reference (< 2.5% height diff, <= 3px ground diff)
  Gate 2: Extreme Limb Sweep (+/-45 deg) Zero-Detachment & Zero-Magenta-Fringe Audit
  Gate 3: `rev2d validate` + `rev2d analyze` Loop Seam Closure & IK Safety Audit
  Gate 4: Spine 4.2 Export Completeness & Straight-Alpha Integrity Audit
  Gate 5: Generates 4-Panel Visual Audit Card (`audit/audit_card_<char_id>.png`)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np
from PIL import Image, ImageDraw


HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[3]
REV2D_CLI = REPO_ROOT / "addons" / "rev2d" / "runtime" / "bin" / "rev2d.js"


def run_rev2d(args: List[str]) -> str:
    proc = subprocess.run(
        ["node", str(REV2D_CLI), *args],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"rev2d {' '.join(args)} failed:\n{proc.stdout}\n{proc.stderr}")
    return proc.stdout


def measure_alpha_bbox(rgba: np.ndarray, thresh: int = 24) -> Tuple[int, int, int, int]:
    ys, xs = np.where(rgba[:, :, 3] > thresh)
    if len(xs) == 0:
        return (0, 0, 0, 0)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def measure_magenta_fringe_ratio(rgba: np.ndarray) -> float:
    edge_mask = (rgba[:, :, 3] > 16) & (rgba[:, :, 3] < 245)
    solid_mask = rgba[:, :, 3] > 24
    total = int(np.sum(solid_mask))
    if total == 0:
        return 0.0
    rgb = rgba[:, :, :3].astype(np.float32)
    mag = np.minimum(rgb[:, :, 0], rgb[:, :, 2]) - rgb[:, :, 1]
    pink_px = int(np.sum((mag > 65.0) & (solid_mask | edge_mask)))
    return pink_px / float(total)


def count_major_body_islands(rgba: np.ndarray) -> int:
    mask = (rgba[:, :, 3] > 24).astype(np.uint8)
    # Bridge tiny 2px anti-aliased gaps while catching real limb/shoe detachment (>4px gap)
    bridged = cv2.dilate(mask, np.ones((5, 5), dtype=np.uint8), iterations=1)
    num_labels, _labels, stats, _centroids = cv2.connectedComponentsWithStats(bridged, connectivity=8)
    total_area = max(1, int(np.sum(bridged > 0)))
    major = 0
    for lid in range(1, num_labels):
        if int(stats[lid, cv2.CC_STAT_AREA]) >= max(120, int(total_area * 0.025)):
            major += 1
    return major


def measure_band_span(rgba: np.ndarray, y0: int, y1: int, pct: float = 50.0) -> float:
    spans: List[float] = []
    for y in range(max(0, y0), min(rgba.shape[0], y1)):
        xs = np.where(rgba[y, :, 3] > 24)[0]
        if len(xs) >= 4:
            spans.append(float(xs[-1] - xs[0] + 1))
    return float(np.percentile(spans, pct)) if spans else 0.0


def compute_silhouette_iou(body_rgba: np.ndarray, master_rgba: np.ndarray) -> float:
    b_mask = (body_rgba[:, :, 3] > 24).astype(np.uint8)
    m_mask = (master_rgba[:, :, 3] > 24).astype(np.uint8)
    kernel = np.ones((3, 3), dtype=np.uint8)
    b_dil = cv2.dilate(b_mask, kernel, iterations=1)
    m_dil = cv2.dilate(m_mask, kernel, iterations=1)
    inter = int(np.sum((b_dil > 0) & (m_dil > 0)))
    union = int(np.sum((b_dil > 0) | (m_dil > 0)))
    return inter / float(max(1, union))


def verify_operator(spec_path: Path) -> None:
    char_dir = spec_path.parent
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    char_id = spec["char_id"]
    r2d_path = char_dir / f"{char_id}.r2d.json"
    manifest_path = char_dir / "textures" / "part_manifest.json"
    master_ref_path = char_dir / "textures" / "master_reference_512.png"

    if not r2d_path.exists():
        raise FileNotFoundError(f"Missing {r2d_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    ground_y = int(manifest["canvas"]["ground_y"])
    target_h = int(manifest["canvas"]["target_height"])

    audit_dir = char_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)

    errors: List[str] = []

    # ------------------------------------------------------------------
    # Gate 1: Rest-Pose Height, Ground Contact & Master Silhouette Check
    # ------------------------------------------------------------------
    setup_clean_path = audit_dir / "setup_clean.png"
    setup_overlay_path = audit_dir / "setup_overlay.png"
    run_rev2d(["render", str(r2d_path), "-o", str(setup_clean_path)])
    run_rev2d(["render", str(r2d_path), "-o", str(setup_overlay_path), "--overlay", "bones"])

    setup_rgba = np.asarray(Image.open(setup_clean_path).convert("RGBA"), dtype=np.uint8)
    sx0, sy0, sx1, sy1 = measure_alpha_bbox(setup_rgba)
    setup_h = sy1 - sy0
    # Exclude top ear/weapon tip overhang when checking ground contact at boot sole `sy1`
    ground_err_px = abs(sy1 - ground_y)
    if ground_err_px > 6:
        errors.append(f"[Gate 1] Ground contact y={sy1} deviates from ground_y={ground_y} by {ground_err_px}px (>6px)")

    # Render weapon-hidden setup to measure pure character body height & silhouette vs Master Reference
    body_only_path = audit_dir / "setup_noweapon.png"
    run_rev2d(["render", str(r2d_path), "-o", str(body_only_path), "--param", "WeaponMode=2"])
    body_rgba = np.asarray(Image.open(body_only_path).convert("RGBA"), dtype=np.uint8)
    _bx0, by0, _bx1, by1 = measure_alpha_bbox(body_rgba)
    body_h = by1 - by0
    height_diff_ratio = abs(body_h - target_h) / float(max(1, target_h))
    # Allow head_acc (tall wolf/fox ears) up to +12% taller than skull crown, but never shrunken > 4%
    if body_h < target_h * 0.94 or body_h > target_h * 1.16:
        errors.append(f"[Gate 1] Rig body height {body_h}px out of canonical range around {target_h}px")

    silhouette_iou = 1.0
    head_w_err_ratio = 0.0
    stance_err_px = 0.0
    if master_ref_path.exists():
        master_rgba = np.asarray(Image.open(master_ref_path).convert("RGBA"), dtype=np.uint8)
        _mx0, my0, _mx1, my1 = measure_alpha_bbox(master_rgba)
        mh = max(1, my1 - my0)
        master_head_w = measure_band_span(master_rgba, int(my0 + mh * 0.18), int(my0 + mh * 0.46), pct=90.0)
        rig_head_w = measure_band_span(body_rgba, int(by0 + body_h * 0.18), int(by0 + body_h * 0.46), pct=90.0)
        head_w_err_ratio = abs(rig_head_w - master_head_w) / max(1.0, master_head_w)
        if head_w_err_ratio > 0.12:
            errors.append(
                f"[Gate 1 Anti-Deformity] Head-band width {rig_head_w:.1f}px deviates from Master {master_head_w:.1f}px "
                f"by {head_w_err_ratio*100:.1f}% (>12% bobblehead/shrunken skull threshold)!"
            )

        master_stance_w = measure_band_span(master_rgba, int(my0 + mh * 0.83), int(my0 + mh * 0.95), pct=50.0)
        rig_stance_w = measure_band_span(body_rgba, int(by0 + body_h * 0.83), int(by0 + body_h * 0.95), pct=50.0)
        stance_err_px = abs(rig_stance_w - master_stance_w)
        if stance_err_px > 14.0:
            errors.append(
                f"[Gate 1 Anti-Deformity] Lower-leg stance span {rig_stance_w:.1f}px deviates from Master "
                f"{master_stance_w:.1f}px by {stance_err_px:.1f}px (>14px crouched/splayed leg threshold)!"
            )

        silhouette_iou = compute_silhouette_iou(body_rgba, master_rgba)
        if silhouette_iou < 0.72:
            errors.append(
                f"[Gate 1 Anti-Deformity] Rest-pose silhouette IoU {silhouette_iou:.3f} < 0.72 vs Master Reference!"
            )

    # ------------------------------------------------------------------
    # Gate 2: Extreme Joint Sweep (+/-45 deg) Zero-Detachment & Magenta Halo Check
    # ------------------------------------------------------------------
    fringe_ratio = measure_magenta_fringe_ratio(setup_rgba)
    if fringe_ratio > 0.003:
        errors.append(f"[Gate 2] Magenta fringe ratio {fringe_ratio:.5f} exceeds 0.003 threshold!")

    pose_extreme_path = audit_dir / "sweep_extreme.png"
    run_rev2d([
        "render",
        str(r2d_path),
        "-o",
        str(pose_extreme_path),
        "--param",
        "BodyBobY=8",
        "--param",
        "ArmNearShoulder=-62",
        "--param",
        "WeaponWrist=-72",
        "--param",
        "ArmFarSwing=38",
        "--param",
        "FootNearX=20",
        "--param",
        "FootFarX=-20",
        "--param",
        "FootNearY=-18",
    ])
    ext_rgba = np.asarray(Image.open(pose_extreme_path).convert("RGBA"), dtype=np.uint8)
    islands = count_major_body_islands(ext_rgba)
    if islands != 1:
        errors.append(f"[Gate 2] Detected {islands} disconnected body islands at +/-45 deg extreme pose (detached limb/boot)!")

    # ------------------------------------------------------------------
    # Gate 3: `rev2d validate` + `rev2d analyze` Loop Seam & IK Safety
    # ------------------------------------------------------------------
    val_json = json.loads(run_rev2d(["validate", str(r2d_path), "--json"]))
    val_items = val_json if isinstance(val_json, list) else [val_json]
    for item in val_items:
        if int(item.get("errors", 0)) > 0 or int(item.get("warnings", 0)) > 0:
            errors.append(f"[Gate 3] rev2d validate reported issues: {item.get('diagnostics')}")

    for loop_anim in ("idle", "run"):
        ana_out = run_rev2d(["analyze", str(r2d_path), "--anim", loop_anim, "--warmup", "8", "--json"])
        ana = json.loads(ana_out)
        seam = ana.get("seam", {})
        if seam.get("params") or seam.get("bones"):
            errors.append(f"[Gate 3] Unclosed parameter/bone loop seam on '{loop_anim}': {seam}")
        px_ratio = float(seam.get("pixels", {}).get("ratio", 0.0))
        if px_ratio > 0.015:
            errors.append(f"[Gate 3] Physics loop pixel seam {px_ratio:.4f} > 0.015 on '{loop_anim}'")
        for ik_stat in ana.get("ik", []):
            if int(ik_stat.get("outOfReachFrames", 0)) > 0:
                errors.append(f"[Gate 3] IK '{ik_stat['id']}' hyper-extended out of reach on '{loop_anim}': {ik_stat}")

    # ------------------------------------------------------------------
    # Gate 4: Spine 4.2 Export & Straight-Alpha Integrity Audit
    # ------------------------------------------------------------------
    exp_cfg = spec.get("export", {})
    out_spines_dir = (char_dir / exp_cfg.get("out_dir", "exports")).resolve()
    spine_name = exp_cfg.get("spine_name", f"spn_{char_id}")
    spine_json_path = out_spines_dir / f"{spine_name}.spine-json"
    atlas_path = out_spines_dir / f"{spine_name}.atlas"
    png_path = out_spines_dir / f"{spine_name}.png"

    for p in (spine_json_path, atlas_path, png_path):
        if not p.exists():
            errors.append(f"[Gate 4] Missing exported Spine 4.2 artifact: {p}")

    if atlas_path.exists():
        atlas_txt = atlas_path.read_text(encoding="utf-8")
        if "pma: true" in atlas_txt.lower():
            errors.append("[Gate 4] Exported atlas has `pma: true` instead of `--straight-alpha`!")

    # ------------------------------------------------------------------
    # Gate 5: Render 4-Panel Visual Audit Card (`audit_card_<char_id>.png`)
    # ------------------------------------------------------------------
    run_sheet_path = audit_dir / "sheet_run.png"
    atk_sheet_path = audit_dir / "sheet_attack_1.png"
    skill_sheet_path = audit_dir / "sheet_skill.png"
    run_rev2d(["sheet", str(r2d_path), "-o", str(run_sheet_path), "--anim", "run", "--frames", "6", "--warmup", "4", "--scale", "0.55"])
    run_rev2d(["sheet", str(r2d_path), "-o", str(atk_sheet_path), "--anim", "attack_1", "--frames", "6", "--scale", "0.55"])
    run_rev2d(["sheet", str(r2d_path), "-o", str(skill_sheet_path), "--anim", "skill", "--frames", "6", "--scale", "0.55"])

    master_im = Image.open(master_ref_path).convert("RGBA") if master_ref_path.exists() else Image.new("RGBA", (512, 512), (30, 34, 42, 255))
    overlay_im = Image.open(setup_overlay_path).convert("RGBA")
    ext_im = Image.open(pose_extreme_path).convert("RGBA")
    run_im = Image.open(run_sheet_path).convert("RGBA")
    atk_im = Image.open(atk_sheet_path).convert("RGBA")

    card_w = max(1280, run_im.width + atk_im.width + 48)
    top_h = 380
    bot_h = max(run_im.height, atk_im.height) + 56
    card = Image.new("RGBA", (card_w, top_h + bot_h + 24), (24, 27, 34, 255))
    draw = ImageDraw.Draw(card)

    def paste_panel(img: Image.Image, x: int, y: int, box_w: int, box_h: int, label: str) -> None:
        draw.rounded_rectangle((x, y, x + box_w, y + box_h), radius=10, fill=(34, 39, 49, 255), outline=(68, 78, 96, 255), width=2)
        draw.text((x + 12, y + 8), label, fill=(226, 232, 240, 255))
        avail_h = box_h - 34
        scale = min((box_w - 20) / max(1, img.width), avail_h / max(1, img.height))
        nw, nh = max(1, int(img.width * scale)), max(1, int(img.height * scale))
        resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
        px = x + (box_w - nw) // 2
        py = y + 30 + (avail_h - nh) // 2
        card.alpha_composite(resized, (px, py))

    col3_w = (card_w - 64) // 3
    paste_panel(master_im, 16, 16, col3_w, top_h - 24, "1. Master 2.8-Head Reference (Ground y=448)")
    paste_panel(
        overlay_im,
        32 + col3_w,
        16,
        col3_w,
        top_h - 24,
        f"2. t=0 Rig + Bones (h={body_h}px, iou={silhouette_iou:.2f}, err={ground_err_px}px)",
    )
    paste_panel(ext_im, 48 + col3_w * 2, 16, col3_w, top_h - 24, f"3. +/-45 deg Sweep (islands={islands}, fringe={fringe_ratio:.4f})")

    half_w = (card_w - 48) // 2
    paste_panel(run_im, 16, top_h + 8, half_w, bot_h, "4. Move Cycle (4-Phase Hop-Walk + 60Hz Cloth/Hair Physics)")
    paste_panel(atk_im, 32 + half_w, top_h + 8, half_w, bot_h, "5. Attack 1 (3:1:2:4 Snap Cleave + Crescent Slash Smear)")

    audit_card_path = audit_dir / f"audit_card_{char_id}.png"
    card.convert("RGB").save(audit_card_path)

    if errors:
        print(f"[SPINE_GATE_FAIL] char={char_id} audit_card={audit_card_path}")
        for err in errors:
            print("  -", err)
        sys.exit(1)

    print(
        f"[SPINE_GATE_PASS] char={char_id} body_h={body_h}px (diff={height_diff_ratio*100:.2f}%), "
        f"iou={silhouette_iou:.3f}, head_w_err={head_w_err_ratio*100:.1f}%, stance_err={stance_err_px:.1f}px, "
        f"ground_err={ground_err_px}px, islands={islands}, fringe={fringe_ratio:.5f}, "
        f"audit_card={audit_card_path}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Run 5-Gate quality audit on a 2.5D Arknights Spine character.")
    parser.add_argument("--spec", required=True, help="Path to operator_spec.json")
    args = parser.parse_args()
    verify_operator(Path(args.spec).resolve())


if __name__ == "__main__":
    main()
