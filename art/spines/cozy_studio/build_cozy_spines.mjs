#!/usr/bin/env node
/**
 * ============================================================================
 * Cozy Studio 2.5D — AI-Generated Modular Cutout Rev2D Rig & Spine 4.2 Builder
 * ============================================================================
 * Builds high-definition (`576x920`, ground `y = 888`) multi-part 2D anime
 * skeletal rigs from freshly AI-generated Spine cutout part sheets:
 *   1. `cozy_slacker.r2d.json`:
 *      - 6 Spine View Skins (`view/front`, `view/side`, `view/back`,
 *        `view/front_sit`, `view/side_sit`, `view/back_sit`)
 *      - Articulated neck/head, periodic eye blinks & happy cheer smiles,
 *        counter-swinging 2-bone skinned arms + iced-latte cup arm,
 *        2-bone leg IK + ankle roll, seated lap skirt + dangling shins,
 *        breathing torso warps, and ahoge/hair pendulum physics.
 *      - 12 animations: `front/side/back` x `idle/walk/cheer/sit`
 *   2. `cozy_partner.r2d.json`:
 *      - Sleepy lavender-haired indie artist rig with round-glasses slow blinks,
 *        stylus-sketching micro-motion on drawing tablet, hoodie breathing,
 *        and lavender bob hair pendulum physics (`idle`).
 * ============================================================================
 */

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../../..');
const REV2D_CLI = path.join(REPO_ROOT, 'addons/rev2d/runtime/bin/rev2d.js');
const EXTRACT_PY = path.join(__dirname, 'extract_parts.py');
const MANIFEST_PATH = path.join(__dirname, 'textures/part_manifest.json');
const OUT_SPINES_DIR = path.join(REPO_ROOT, 'src/test/cozy_studio/assets/spines');

fs.mkdirSync(OUT_SPINES_DIR, { recursive: true });

function runRev2d(args) {
  return execFileSync(process.execPath, [REV2D_CLI, ...args], {
    cwd: REPO_ROOT,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
}

// 1. Ensure AI cutout part atlases stay synchronized with `extract_parts.py`
const needExtract =
  !fs.existsSync(MANIFEST_PATH) ||
  fs.statSync(EXTRACT_PY).mtimeMs > fs.statSync(MANIFEST_PATH).mtimeMs;
if (needExtract) {
  execFileSync('python', [EXTRACT_PY], { cwd: __dirname, stdio: 'inherit' });
}

const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
const CW = manifest.canvas.w;          // 576
const CH = manifest.canvas.h;          // 920
const GY = manifest.canvas.ground_y;   // 888
const CX = CW * 0.5;                   // 288
const sAtlas = manifest.slacker_atlas.parts;
const pAtlas = manifest.partner_atlas.parts;

function imgPart({
  id,
  atlasMap,
  cropKey,
  x,
  y,
  w,
  h,
  z,
  parent,
  skin,
  cols = 6,
  rows = 8,
  texture = 'partsAtlas',
}) {
  const c = atlasMap[cropKey];
  if (!c) {
    throw new Error(`Missing cropKey "${cropKey}" in part_manifest.json`);
  }
  const entry = {
    id,
    shape: {
      type: 'image',
      texture,
      crop: [c.x, c.y, c.w, c.h],
      x: Math.round(x),
      y: Math.round(y),
      w: Math.round(w ?? c.w),
      h: Math.round(h ?? c.h),
      cols,
      rows,
    },
    opacity: 1,
    z,
  };
  if (skin) {
    entry.skin = skin;
  } else if (parent) {
    entry.parent = parent;
  }
  return entry;
}

function makeWarpMap(cols, rows, fn) {
  const map = {};
  for (let r = 0; r <= rows; r++) {
    const v = r / rows;
    for (let c = 0; c <= cols; c++) {
      const u = c / cols;
      const [dx, dy] = fn(c, r, u, v);
      if (Math.abs(dx) > 0.01 || Math.abs(dy) > 0.01) {
        map[String(r * (cols + 1) + c)] = [Number(dx.toFixed(2)), Number(dy.toFixed(2))];
      }
    }
  }
  return map;
}

function periodicKeys(duration, steps, fn, ease = 'smooth') {
  const keys = [];
  for (let i = 0; i <= steps; i++) {
    const phase = i / steps;
    const t = Number((phase * duration).toFixed(4));
    const v = Number(fn(phase === 1 ? 0 : phase).toFixed(3));
    keys.push({ t, v, ease });
  }
  return keys;
}

/**
 * Binds `part:<id>.opacity` across `ViewId` (`0..5`), optionally gated by `EyeSmile` (`0` or `1`)
 * so face expression swaps (`open` vs `happy`) compose cleanly in one multilinear grid!
 */
function viewOpacityBinding(partId, activeViewId, eyeMode = null) {
  if (eyeMode === null) {
    return {
      target: `part:${partId}.opacity`,
      params: ['ViewId'],
      interpolation: 'step',
      keys: [0, 1, 2, 3, 4, 5].map((vid) => ({
        at: [vid],
        value: vid === activeViewId ? 1 : 0,
      })),
    };
  }
  const keys = [];
  for (const vid of [0, 1, 2, 3, 4, 5]) {
    for (const em of [0, 1]) {
      keys.push({
        at: [vid, em],
        value: vid === activeViewId && em === eyeMode ? 1 : 0,
      });
    }
  }
  return {
    target: `part:${partId}.opacity`,
    params: ['ViewId', 'EyeSmile'],
    interpolation: 'step',
    keys,
  };
}

/** Build natural double/single blink keys inside a looping idle/sit animation. */
function blinkTrackKeys(duration, blinkAtSec = 1.45) {
  const b0 = Number(blinkAtSec.toFixed(3));
  const b1 = Number((blinkAtSec + 0.13).toFixed(3));
  return [
    { t: 0, v: 0, ease: 'step' },
    { t: b0, v: 1, ease: 'step' },
    { t: b1, v: 0, ease: 'step' },
    { t: duration, v: 0, ease: 'step' },
  ];
}

// ============================================================================
// 2. Build `cozy_slacker.r2d.json` (6-Skin 3-View Stand & Sit AI Cutout Rig)
// ============================================================================
const slackerParts = [
  // -------------------- VIEW 0: FRONT STAND (`f_*`) --------------------
  imgPart({ id: 'f_hair_back', atlasMap: sAtlas, cropKey: 'f_hair_back', x: CX - 102, y: 218, w: 204, h: 248, z: 2, parent: 'f_hairBack' }),
  imgPart({ id: 'f_shin_r', atlasMap: sAtlas, cropKey: 'f_shin_shoe_l', x: CX - 80, y: 668, w: 80, h: 220, z: 4.5, parent: 'f_shinR' }),
  imgPart({ id: 'f_shin_l', atlasMap: sAtlas, cropKey: 'f_shin_shoe_r', x: CX + 0, y: 668, w: 80, h: 220, z: 4.6, parent: 'f_shinL' }),
  imgPart({ id: 'f_thigh_r', atlasMap: sAtlas, cropKey: 'f_thigh_r', x: CX - 76, y: 576, w: 72, h: 162, z: 5.5, parent: 'f_thighR' }),
  imgPart({ id: 'f_thigh_l', atlasMap: sAtlas, cropKey: 'f_thigh_l', x: CX + 4, y: 576, w: 72, h: 162, z: 5.6, parent: 'f_thighL' }),
  imgPart({ id: 'f_skirt', atlasMap: sAtlas, cropKey: 'f_skirt', x: CX - 98, y: 492, w: 196, h: 164, z: 8.0, parent: 'f_skirtBone' }),
  imgPart({
    id: 'f_arm_free',
    atlasMap: sAtlas,
    cropKey: 'f_arm_straight_r',
    x: CX - 116,
    y: 382,
    w: 78,
    h: 272,
    z: 9.5,
    cols: 6,
    rows: 12,
    skin: { bones: ['f_upperArmR', 'f_foreArmR'], weights: 'auto', falloff: 2.2 },
  }),
  imgPart({ id: 'f_torso', atlasMap: sAtlas, cropKey: 'f_torso', x: CX - 96, y: 336, w: 192, h: 290, z: 11.0, parent: 'f_torsoWarp', cols: 6, rows: 8 }),
  imgPart({ id: 'f_arm_cup', atlasMap: sAtlas, cropKey: 'f_arm_latte', x: CX - 4, y: 368, w: 166, h: 144, z: 14.0, parent: 'f_armCup' }),
  imgPart({ id: 'f_face_open', atlasMap: sAtlas, cropKey: 'f_face_open', x: CX - 88, y: 216, w: 176, h: 178, z: 18.0, parent: 'f_head' }),
  imgPart({ id: 'f_face_happy', atlasMap: sAtlas, cropKey: 'f_face_happy', x: CX - 88, y: 216, w: 176, h: 178, z: 18.1, parent: 'f_head' }),
  imgPart({ id: 'f_hair_side_r', atlasMap: sAtlas, cropKey: 'f_hair_side_l', x: CX - 98, y: 256, w: 50, h: 152, z: 19.0, parent: 'f_sideLockR' }),
  imgPart({ id: 'f_hair_side_l', atlasMap: sAtlas, cropKey: 'f_hair_side_r', x: CX + 44, y: 256, w: 62, h: 152, z: 19.1, parent: 'f_sideLockL' }),
  imgPart({ id: 'f_bangs', atlasMap: sAtlas, cropKey: 'f_bangs', x: CX - 92, y: 196, w: 184, h: 148, z: 20.0, parent: 'f_head' }),
  imgPart({ id: 'f_ahoge', atlasMap: sAtlas, cropKey: 'f_ahoge', x: CX - 10, y: 148, w: 48, h: 58, z: 21.0, parent: 'f_ahoge' }),

  // -------------------- VIEW 1: SIDE STAND (`s_*`, Facing +X) --------------------
  imgPart({
    id: 's_arm_far',
    atlasMap: sAtlas,
    cropKey: 's_arm_straight_far',
    x: CX - 26,
    y: 382,
    w: 76,
    h: 244,
    z: 1.5,
    cols: 6,
    rows: 12,
    skin: { bones: ['s_upperArmFar', 's_foreArmFar'], weights: 'auto', falloff: 2.2 },
  }),
  imgPart({ id: 's_hair_back', atlasMap: sAtlas, cropKey: 's_hair_back', x: CX - 102, y: 204, w: 188, h: 260, z: 2.5, parent: 's_hairBackWarp', cols: 6, rows: 8 }),
  imgPart({ id: 's_shin_far', atlasMap: sAtlas, cropKey: 's_shin_far', x: CX - 14, y: 708, w: 64, h: 168, z: 4.1, parent: 's_shinFar' }),
  imgPart({ id: 's_thigh_far', atlasMap: sAtlas, cropKey: 's_thigh_far', x: CX - 20, y: 584, w: 74, h: 158, z: 4.3, parent: 's_thighFar' }),
  imgPart({ id: 's_shoe_far', atlasMap: sAtlas, cropKey: 's_shoe_far', x: CX - 28, y: 834, w: 106, h: 54, z: 4.4, parent: 's_footFar' }),
  imgPart({ id: 's_shin_near', atlasMap: sAtlas, cropKey: 's_shin', x: CX - 20, y: 708, w: 64, h: 168, z: 6.1, parent: 's_shinNear' }),
  imgPart({ id: 's_thigh_near', atlasMap: sAtlas, cropKey: 's_thigh', x: CX - 26, y: 584, w: 74, h: 158, z: 6.3, parent: 's_thighNear' }),
  imgPart({ id: 's_shoe_near', atlasMap: sAtlas, cropKey: 's_shoe', x: CX - 36, y: 834, w: 106, h: 54, z: 6.4, parent: 's_footNear' }),
  imgPart({ id: 's_skirt', atlasMap: sAtlas, cropKey: 's_skirt', x: CX - 80, y: 494, w: 168, h: 152, z: 8.0, parent: 's_skirtBone' }),
  imgPart({ id: 's_torso', atlasMap: sAtlas, cropKey: 's_torso', x: CX - 68, y: 340, w: 142, h: 282, z: 11.0, parent: 's_torsoWarp', cols: 6, rows: 8 }),
  imgPart({ id: 's_hair_side', atlasMap: sAtlas, cropKey: 's_hair_side', x: CX - 24, y: 290, w: 52, h: 142, z: 15.0, parent: 's_sideLock' }),
  imgPart({ id: 's_head_open', atlasMap: sAtlas, cropKey: 's_head_open', x: CX - 76, y: 204, w: 170, h: 190, z: 16.0, parent: 's_head' }),
  imgPart({ id: 's_head_happy', atlasMap: sAtlas, cropKey: 's_head_happy', x: CX - 76, y: 204, w: 170, h: 190, z: 16.1, parent: 's_head' }),
  imgPart({ id: 's_ahoge', atlasMap: sAtlas, cropKey: 's_ahoge', x: CX - 30, y: 158, w: 58, h: 55, z: 18.0, parent: 's_ahoge' }),
  imgPart({ id: 's_arm_cup', atlasMap: sAtlas, cropKey: 's_arm_latte', x: CX - 48, y: 372, w: 182, h: 140, z: 20.0, parent: 's_armCup' }),

  // -------------------- VIEW 2: BACK STAND (`b_*`) --------------------
  imgPart({ id: 'b_shin_l', atlasMap: sAtlas, cropKey: 'b_shin_shoe_l', x: CX - 92, y: 704, w: 90, h: 184, z: 4.5, parent: 'b_shinL' }),
  imgPart({ id: 'b_shin_r', atlasMap: sAtlas, cropKey: 'b_shin_shoe_r', x: CX + 2, y: 704, w: 90, h: 184, z: 4.6, parent: 'b_shinR' }),
  imgPart({ id: 'b_thigh_l', atlasMap: sAtlas, cropKey: 'b_thigh_l', x: CX - 82, y: 582, w: 74, h: 160, z: 5.5, parent: 'b_thighL' }),
  imgPart({ id: 'b_thigh_r', atlasMap: sAtlas, cropKey: 'b_thigh_r', x: CX + 8, y: 582, w: 74, h: 160, z: 5.6, parent: 'b_thighR' }),
  imgPart({ id: 'b_skirt', atlasMap: sAtlas, cropKey: 'b_skirt', x: CX - 108, y: 486, w: 216, h: 168, z: 8.0, parent: 'b_skirtBone' }),
  imgPart({
    id: 'b_arm_l',
    atlasMap: sAtlas,
    cropKey: 'b_arm_l',
    x: CX - 116,
    y: 380,
    w: 82,
    h: 262,
    z: 9.5,
    cols: 6,
    rows: 12,
    skin: { bones: ['b_upperArmL', 'b_foreArmL'], weights: 'auto', falloff: 2.2 },
  }),
  imgPart({
    id: 'b_arm_r',
    atlasMap: sAtlas,
    cropKey: 'b_arm_r',
    x: CX + 34,
    y: 380,
    w: 82,
    h: 262,
    z: 9.6,
    cols: 6,
    rows: 12,
    skin: { bones: ['b_upperArmR', 'b_foreArmR'], weights: 'auto', falloff: 2.2 },
  }),
  imgPart({ id: 'b_torso', atlasMap: sAtlas, cropKey: 'b_torso', x: CX - 98, y: 338, w: 196, h: 282, z: 11.0, parent: 'b_torsoWarp', cols: 6, rows: 8 }),
  imgPart({ id: 'b_hair_lock_l', atlasMap: sAtlas, cropKey: 'b_hair_lock_l', x: CX - 110, y: 280, w: 74, h: 184, z: 17.0, parent: 'b_hairLockL' }),
  imgPart({ id: 'b_hair_lock_r', atlasMap: sAtlas, cropKey: 'b_hair_lock_r', x: CX + 36, y: 280, w: 74, h: 184, z: 17.1, parent: 'b_hairLockR' }),
  imgPart({ id: 'b_hair_curtain', atlasMap: sAtlas, cropKey: 'b_hair_curtain', x: CX - 112, y: 264, w: 224, h: 210, z: 17.5, parent: 'b_hairCurtainWarp', cols: 6, rows: 6 }),
  imgPart({ id: 'b_hair_dome', atlasMap: sAtlas, cropKey: 'b_hair_dome', x: CX - 105, y: 202, w: 210, h: 174, z: 18.2, parent: 'b_head' }),
  imgPart({ id: 'b_ahoge', atlasMap: sAtlas, cropKey: 'b_ahoge', x: CX - 24, y: 128, w: 62, h: 90, z: 19.0, parent: 'b_ahoge' }),

  // -------------------- VIEW 3: FRONT SIT (`fs_*`) --------------------
  imgPart({ id: 'fs_hair_back', atlasMap: sAtlas, cropKey: 'f_hair_back', x: CX - 102, y: 248, w: 204, h: 248, z: 2.0, parent: 'fs_hairBack' }),
  imgPart({ id: 'fs_shin_r', atlasMap: sAtlas, cropKey: 'f_shin_shoe_l', x: CX - 90, y: 664, w: 78, h: 208, z: 5.0, parent: 'fs_shinR' }),
  imgPart({ id: 'fs_shin_l', atlasMap: sAtlas, cropKey: 'f_shin_shoe_r', x: CX - 26, y: 668, w: 78, h: 208, z: 5.1, parent: 'fs_shinL' }),
  imgPart({ id: 'fs_skirt_sit', atlasMap: sAtlas, cropKey: 'f_skirt_sit', x: CX - 96, y: 516, w: 222, h: 206, z: 8.0, parent: 'fs_hip' }),
  imgPart({ id: 'fs_arm_free', atlasMap: sAtlas, cropKey: 'f_arm_bent_l', x: CX - 114, y: 406, w: 138, h: 138, z: 9.5, parent: 'fs_torsoBone' }),
  imgPart({ id: 'fs_torso', atlasMap: sAtlas, cropKey: 'f_torso', x: CX - 96, y: 366, w: 192, h: 284, z: 11.0, parent: 'fs_torsoBone' }),
  imgPart({ id: 'fs_arm_cup', atlasMap: sAtlas, cropKey: 'f_arm_latte', x: CX - 4, y: 398, w: 164, h: 142, z: 14.0, parent: 'fs_armCup' }),
  imgPart({ id: 'fs_face_open', atlasMap: sAtlas, cropKey: 'f_face_open', x: CX - 88, y: 246, w: 176, h: 178, z: 18.0, parent: 'fs_head' }),
  imgPart({ id: 'fs_face_happy', atlasMap: sAtlas, cropKey: 'f_face_happy', x: CX - 88, y: 246, w: 176, h: 178, z: 18.1, parent: 'fs_head' }),
  imgPart({ id: 'fs_hair_side_r', atlasMap: sAtlas, cropKey: 'f_hair_side_l', x: CX - 98, y: 286, w: 50, h: 152, z: 19.0, parent: 'fs_sideLockR' }),
  imgPart({ id: 'fs_hair_side_l', atlasMap: sAtlas, cropKey: 'f_hair_side_r', x: CX + 44, y: 286, w: 62, h: 152, z: 19.1, parent: 'fs_sideLockL' }),
  imgPart({ id: 'fs_bangs', atlasMap: sAtlas, cropKey: 'f_bangs', x: CX - 92, y: 226, w: 184, h: 148, z: 20.0, parent: 'fs_head' }),
  imgPart({ id: 'fs_ahoge', atlasMap: sAtlas, cropKey: 'f_ahoge', x: CX - 10, y: 178, w: 48, h: 58, z: 21.0, parent: 'fs_ahoge' }),

  // -------------------- VIEW 4: SIDE SIT (`ss_*`, Facing +X) --------------------
  imgPart({ id: 'ss_hair_back', atlasMap: sAtlas, cropKey: 's_hair_back', x: CX - 122, y: 234, w: 188, h: 260, z: 2.5, parent: 'ss_hairBack' }),
  imgPart({ id: 'ss_shin_far', atlasMap: sAtlas, cropKey: 's_shin_far', x: CX + 34, y: 644, w: 62, h: 172, z: 4.2, parent: 'ss_shinFar' }),
  imgPart({ id: 'ss_shoe_far', atlasMap: sAtlas, cropKey: 's_shoe_far', x: CX + 30, y: 784, w: 102, h: 52, z: 4.4, parent: 'ss_shinFar' }),
  imgPart({ id: 'ss_shin_near', atlasMap: sAtlas, cropKey: 's_shin', x: CX + 24, y: 654, w: 62, h: 172, z: 6.2, parent: 'ss_shinNear' }),
  imgPart({ id: 'ss_shoe_near', atlasMap: sAtlas, cropKey: 's_shoe', x: CX + 20, y: 794, w: 102, h: 52, z: 6.4, parent: 'ss_shinNear' }),
  imgPart({ id: 'ss_skirt_sit', atlasMap: sAtlas, cropKey: 's_skirt_sit', x: CX - 102, y: 528, w: 234, h: 158, z: 8.0, parent: 'ss_hip' }),
  imgPart({ id: 'ss_torso', atlasMap: sAtlas, cropKey: 's_torso', x: CX - 88, y: 370, w: 142, h: 278, z: 11.0, parent: 'ss_torsoBone' }),
  imgPart({ id: 'ss_hair_side', atlasMap: sAtlas, cropKey: 's_hair_side', x: CX - 44, y: 320, w: 52, h: 142, z: 15.0, parent: 'ss_sideLock' }),
  imgPart({ id: 'ss_head_open', atlasMap: sAtlas, cropKey: 's_head_open', x: CX - 96, y: 234, w: 170, h: 190, z: 16.0, parent: 'ss_head' }),
  imgPart({ id: 'ss_head_happy', atlasMap: sAtlas, cropKey: 's_head_happy', x: CX - 96, y: 234, w: 170, h: 190, z: 16.1, parent: 'ss_head' }),
  imgPart({ id: 'ss_ahoge', atlasMap: sAtlas, cropKey: 's_ahoge', x: CX - 50, y: 188, w: 58, h: 55, z: 18.0, parent: 'ss_ahoge' }),
  imgPart({ id: 'ss_arm_cup', atlasMap: sAtlas, cropKey: 's_arm_latte', x: CX - 66, y: 402, w: 180, h: 138, z: 20.0, parent: 'ss_armCup' }),

  // -------------------- VIEW 5: BACK SIT (`bs_*`) --------------------
  imgPart({ id: 'bs_shin_l', atlasMap: sAtlas, cropKey: 'b_shin_shoe_l', x: CX - 90, y: 654, w: 88, h: 196, z: 5.0, parent: 'bs_shinL' }),
  imgPart({ id: 'bs_shin_r', atlasMap: sAtlas, cropKey: 'b_shin_shoe_r', x: CX + 2, y: 654, w: 88, h: 196, z: 5.1, parent: 'bs_shinR' }),
  imgPart({ id: 'bs_skirt', atlasMap: sAtlas, cropKey: 'b_skirt', x: CX - 108, y: 514, w: 216, h: 174, z: 8.0, parent: 'bs_hip' }),
  imgPart({ id: 'bs_arm_l', atlasMap: sAtlas, cropKey: 'b_arm_l', x: CX - 114, y: 406, w: 80, h: 242, z: 9.5, parent: 'bs_torsoBone' }),
  imgPart({ id: 'bs_arm_r', atlasMap: sAtlas, cropKey: 'b_arm_r', x: CX + 34, y: 406, w: 80, h: 242, z: 9.6, parent: 'bs_torsoBone' }),
  imgPart({ id: 'bs_torso', atlasMap: sAtlas, cropKey: 'b_torso', x: CX - 98, y: 368, w: 196, h: 278, z: 11.0, parent: 'bs_torsoBone' }),
  imgPart({ id: 'bs_hair_lock_l', atlasMap: sAtlas, cropKey: 'b_hair_lock_l', x: CX - 110, y: 310, w: 74, h: 184, z: 17.0, parent: 'bs_hairLockL' }),
  imgPart({ id: 'bs_hair_lock_r', atlasMap: sAtlas, cropKey: 'b_hair_lock_r', x: CX + 36, y: 310, w: 74, h: 184, z: 17.1, parent: 'bs_hairLockR' }),
  imgPart({ id: 'bs_hair_curtain', atlasMap: sAtlas, cropKey: 'b_hair_curtain', x: CX - 112, y: 294, w: 224, h: 210, z: 17.5, parent: 'bs_hairCurtain' }),
  imgPart({ id: 'bs_hair_dome', atlasMap: sAtlas, cropKey: 'b_hair_dome', x: CX - 105, y: 232, w: 210, h: 174, z: 18.2, parent: 'bs_head' }),
  imgPart({ id: 'bs_ahoge', atlasMap: sAtlas, cropKey: 'b_ahoge', x: CX - 24, y: 158, w: 62, h: 90, z: 19.0, parent: 'bs_ahoge' }),
];

const SLACKER_SKIN_GROUPS = {
  'view/front': slackerParts.filter((p) => p.id.startsWith('f_')).map((p) => p.id),
  'view/side': slackerParts.filter((p) => p.id.startsWith('s_')).map((p) => p.id),
  'view/back': slackerParts.filter((p) => p.id.startsWith('b_')).map((p) => p.id),
  'view/front_sit': slackerParts.filter((p) => p.id.startsWith('fs_')).map((p) => p.id),
  'view/side_sit': slackerParts.filter((p) => p.id.startsWith('ss_')).map((p) => p.id),
  'view/back_sit': slackerParts.filter((p) => p.id.startsWith('bs_')).map((p) => p.id),
};

const VIEW_PREFIX_TO_ID = {
  f_: 0,
  s_: 1,
  b_: 2,
  fs_: 3,
  ss_: 4,
  bs_: 5,
};

const slackerOpacityBindings = slackerParts.map((part) => {
  const prefix = Object.keys(VIEW_PREFIX_TO_ID).find((pf) => part.id.startsWith(pf));
  const vid = VIEW_PREFIX_TO_ID[prefix];
  if (part.id.endsWith('_open')) {
    return viewOpacityBinding(part.id, vid, 0);
  }
  if (part.id.endsWith('_happy')) {
    return viewOpacityBinding(part.id, vid, 1);
  }
  return viewOpacityBinding(part.id, vid, null);
});

const slackerModel = {
  format: 'rev2d',
  version: 1,
  meta: {
    name: 'cozy_slacker',
    width: CW,
    height: CH,
    background: 'rgba(0,0,0,0)',
    fps: 30,
    author: 'Slacker Survivors AI Cutout + Rev2D Pipeline',
    description: '2.5D Cozy Studio protagonist rigged from AI-generated modular Spine cutout part sheets.',
  },
  textures: [
    { id: 'partsAtlas', path: manifest.slacker_atlas.file },
  ],
  parameters: [
    { id: 'ViewId', min: 0, max: 5, default: 0, group: 'View', description: '0=Front, 1=Side, 2=Back, 3=FrontSit, 4=SideSit, 5=BackSit' },
    { id: 'EyeSmile', min: 0, max: 1, default: 0, group: 'Face', description: '0=open eyes, 1=happy/blinking closed eyes' },
    { id: 'Breath', min: 0, max: 1, default: 0, group: 'Body', description: 'Chest breathing cycle' },
    { id: 'BodyBounce', min: -24, max: 24, default: 0, group: 'Body', description: 'Vertical hip bounce (px)' },
    { id: 'BodySway', min: -12, max: 12, default: 0, group: 'Body', description: 'Torso lean angle (deg)' },
    { id: 'HeadTilt', min: -14, max: 14, default: 0, group: 'Head', description: 'Head tilt/nod angle (deg)' },
    { id: 'CupLift', min: -20, max: 24, default: 0, group: 'Arms', description: 'Iced-latte forearm rotation delta (deg)' },
    { id: 'AhogeSway', min: -35, max: 35, default: 0, group: 'Physics', description: 'Cowlick pendulum angle' },
    { id: 'HairSway', min: -25, max: 25, default: 0, group: 'Physics', description: 'Hair locks pendulum angle' },
  ],
  bones: [
    { id: 'ground', x: CX, y: GY, length: 0, description: 'World floor contact (288, 888)' },

    // ---- View 0: Front Stand ----
    { id: 'f_hip', parent: 'ground', x: 0, y: -308, length: 0 }, // (288, 580)
    { id: 'f_skirtBone', parent: 'f_hip', x: 0, y: -64, length: 0 },
    { id: 'f_torsoBone', parent: 'f_hip', x: 0, y: -92, length: 0 }, // (288, 488)
    { id: 'f_head', parent: 'f_torsoBone', x: 0, y: -116, length: 0 }, // (288, 372)
    { id: 'f_hairBack', parent: 'f_head', x: 0, y: -110, rotation: 90, length: 140 },
    { id: 'f_sideLockR', parent: 'f_head', x: -72, y: -88, rotation: 90, length: 110 },
    { id: 'f_sideLockL', parent: 'f_head', x: 72, y: -88, rotation: 90, length: 110 },
    { id: 'f_ahoge', parent: 'f_head', x: 6, y: -172, rotation: -85, length: 48 },
    { id: 'f_upperArmR', parent: 'f_torsoBone', x: -72, y: -88, rotation: 94, length: 112 },
    { id: 'f_foreArmR', parent: 'f_upperArmR', x: 112, y: 0, rotation: -6, length: 118 },
    { id: 'f_armCup', parent: 'f_torsoBone', x: 42, y: -92, rotation: 0, length: 90 },
    { id: 'f_thighR', parent: 'f_hip', x: -40, y: 18, rotation: 90, length: 120 },
    { id: 'f_shinR', parent: 'f_thighR', x: 120, y: 0, rotation: 0, length: 150 },
    { id: 'f_thighL', parent: 'f_hip', x: 40, y: 18, rotation: 90, length: 120 },
    { id: 'f_shinL', parent: 'f_thighL', x: 120, y: 0, rotation: 0, length: 150 },

    // ---- View 1: Side Stand (Facing +X, 2-Bone Leg IK + Counter Arm Swing) ----
    { id: 's_hip', parent: 'ground', x: 0, y: -294, length: 0 }, // (288, 594)
    { id: 's_skirtBone', parent: 's_hip', x: 0, y: -76, length: 0 },
    { id: 's_torsoBone', parent: 's_hip', x: 0, y: -102, length: 0 }, // (288, 492)
    { id: 's_head', parent: 's_torsoBone', x: 4, y: -116, length: 0 }, // (292, 376)
    { id: 's_sideLock', parent: 's_head', x: 8, y: -84, rotation: 90, length: 110 },
    { id: 's_ahoge', parent: 's_head', x: -8, y: -168, rotation: -80, length: 48 },
    { id: 's_upperArmFar', parent: 's_torsoBone', x: 10, y: -92, rotation: 88, length: 104 },
    { id: 's_foreArmFar', parent: 's_upperArmFar', x: 104, y: 0, rotation: -10, length: 108 },
    { id: 's_armCup', parent: 's_torsoBone', x: -16, y: -96, rotation: 0, length: 110 },
    // Near Leg 2-Bone IK (`bendPositive: true` -> forward +X knee): (286, 603) -> knee (312, 731) -> ankle (286, 854)
    { id: 's_thighNear', parent: 's_hip', x: -2, y: 9, rotation: 78, length: 131 },
    { id: 's_shinNear', parent: 's_thighNear', x: 131, y: 0, rotation: 24, length: 131 },
    { id: 's_footNear', parent: 's_shinNear', x: 131, y: 0, rotation: -102, length: 54 },
    { id: 's_footTargetNear', parent: 'ground', x: -2, y: -34, length: 0 },
    // Far Leg 2-Bone IK (`bendPositive: true` -> forward +X knee): (292, 603) -> knee (318, 731) -> ankle (292, 854)
    { id: 's_thighFar', parent: 's_hip', x: 4, y: 9, rotation: 78, length: 131 },
    { id: 's_shinFar', parent: 's_thighFar', x: 131, y: 0, rotation: 24, length: 131 },
    { id: 's_footFar', parent: 's_shinFar', x: 131, y: 0, rotation: -102, length: 54 },
    { id: 's_footTargetFar', parent: 'ground', x: 4, y: -34, length: 0 },

    // ---- View 2: Back Stand ----
    { id: 'b_hip', parent: 'ground', x: 0, y: -304, length: 0 },
    { id: 'b_skirtBone', parent: 'b_hip', x: 0, y: -72, length: 0 },
    { id: 'b_torsoBone', parent: 'b_hip', x: 0, y: -96, length: 0 },
    { id: 'b_head', parent: 'b_torsoBone', x: 0, y: -116, length: 0 },
    { id: 'b_hairLockL', parent: 'b_head', x: -74, y: -82, rotation: 90, length: 140 },
    { id: 'b_hairLockR', parent: 'b_head', x: 74, y: -82, rotation: 90, length: 140 },
    { id: 'b_ahoge', parent: 'b_head', x: 4, y: -168, rotation: -85, length: 64 },
    { id: 'b_upperArmL', parent: 'b_torsoBone', x: -74, y: -88, rotation: 96, length: 108 },
    { id: 'b_foreArmL', parent: 'b_upperArmL', x: 108, y: 0, rotation: -6, length: 112 },
    { id: 'b_upperArmR', parent: 'b_torsoBone', x: 74, y: -88, rotation: 84, length: 108 },
    { id: 'b_foreArmR', parent: 'b_upperArmR', x: 108, y: 0, rotation: 6, length: 112 },
    { id: 'b_thighL', parent: 'b_hip', x: -45, y: 18, rotation: 90, length: 120 },
    { id: 'b_shinL', parent: 'b_thighL', x: 120, y: 0, rotation: 0, length: 150 },
    { id: 'b_thighR', parent: 'b_hip', x: 45, y: 18, rotation: 90, length: 120 },
    { id: 'b_shinR', parent: 'b_thighR', x: 120, y: 0, rotation: 0, length: 150 },

    // ---- View 3: Front Sit ----
    { id: 'fs_hip', parent: 'ground', x: 0, y: -278, length: 0 },
    { id: 'fs_torsoBone', parent: 'fs_hip', x: 0, y: -92, length: 0 },
    { id: 'fs_head', parent: 'fs_torsoBone', x: 0, y: -116, length: 0 },
    { id: 'fs_hairBack', parent: 'fs_head', x: 0, y: -110, rotation: 90, length: 140 },
    { id: 'fs_sideLockR', parent: 'fs_head', x: -72, y: -88, rotation: 90, length: 110 },
    { id: 'fs_sideLockL', parent: 'fs_head', x: 72, y: -88, rotation: 90, length: 110 },
    { id: 'fs_ahoge', parent: 'fs_head', x: 6, y: -172, rotation: -85, length: 48 },
    { id: 'fs_armCup', parent: 'fs_torsoBone', x: 42, y: -90, rotation: 0, length: 90 },
    { id: 'fs_shinR', parent: 'fs_hip', x: -51, y: 64, rotation: 90, length: 150 },
    { id: 'fs_shinL', parent: 'fs_hip', x: 13, y: 68, rotation: 90, length: 150 },

    // ---- View 4: Side Sit ----
    { id: 'ss_hip', parent: 'ground', x: -20, y: -278, length: 0 },
    { id: 'ss_torsoBone', parent: 'ss_hip', x: 0, y: -96, length: 0 },
    { id: 'ss_head', parent: 'ss_torsoBone', x: 4, y: -116, length: 0 },
    { id: 'ss_hairBack', parent: 'ss_head', x: -24, y: -96, rotation: 90, length: 150 },
    { id: 'ss_sideLock', parent: 'ss_head', x: 8, y: -84, rotation: 90, length: 110 },
    { id: 'ss_ahoge', parent: 'ss_head', x: -8, y: -168, rotation: -80, length: 48 },
    { id: 'ss_armCup', parent: 'ss_torsoBone', x: -16, y: -94, rotation: 0, length: 110 },
    { id: 'ss_shinNear', parent: 'ss_hip', x: 76, y: 56, rotation: 90, length: 156 },
    { id: 'ss_shinFar', parent: 'ss_hip', x: 86, y: 46, rotation: 90, length: 156 },

    // ---- View 5: Back Sit ----
    { id: 'bs_hip', parent: 'ground', x: 0, y: -278, length: 0 },
    { id: 'bs_torsoBone', parent: 'bs_hip', x: 0, y: -92, length: 0 },
    { id: 'bs_head', parent: 'bs_torsoBone', x: 0, y: -116, length: 0 },
    { id: 'bs_hairLockL', parent: 'bs_head', x: -74, y: -82, rotation: 90, length: 140 },
    { id: 'bs_hairLockR', parent: 'bs_head', x: 74, y: -82, rotation: 90, length: 140 },
    { id: 'bs_hairCurtain', parent: 'bs_head', x: 0, y: -82, rotation: 90, length: 150 },
    { id: 'bs_ahoge', parent: 'bs_head', x: 4, y: -168, rotation: -85, length: 64 },
    { id: 'bs_shinL', parent: 'bs_hip', x: -46, y: 56, rotation: 90, length: 156 },
    { id: 'bs_shinR', parent: 'bs_hip', x: 46, y: 56, rotation: 90, length: 156 },
  ],
  ik: [
    {
      id: 's_ikLegNear',
      bones: ['s_thighNear', 's_shinNear'],
      target: 's_footTargetNear',
      bendPositive: true,
      softness: 4,
      mix: 1,
    },
    {
      id: 's_ikLegFar',
      bones: ['s_thighFar', 's_shinFar'],
      target: 's_footTargetFar',
      bendPositive: true,
      softness: 4,
      mix: 1,
    },
  ],
  warps: [
    { id: 'f_torsoWarp', parent: 'f_torsoBone', rect: [CX - 106, 326, 212, 310], cols: 4, rows: 4 },
    { id: 's_torsoWarp', parent: 's_torsoBone', rect: [CX - 78, 330, 162, 302], cols: 4, rows: 4 },
    { id: 's_hairBackWarp', parent: 's_head', rect: [CX - 112, 194, 208, 280], cols: 4, rows: 4 },
    { id: 'b_torsoWarp', parent: 'b_torsoBone', rect: [CX - 108, 328, 216, 302], cols: 4, rows: 4 },
    { id: 'b_hairCurtainWarp', parent: 'b_head', rect: [CX - 122, 254, 244, 230], cols: 4, rows: 4 },
  ],
  physics: [
    {
      id: 'ahogePendulum',
      inputs: [
        { param: 'BodyBounce', type: 'y', weight: 0.55 },
        { param: 'BodySway', type: 'x', weight: 0.9 },
        { param: 'HeadTilt', type: 'x', weight: 1.0 },
      ],
      outputs: [{ param: 'AhogeSway', type: 'angle', segment: 0, scale: 0.9 }],
      segments: [{ length: 34, mass: 1.0 }],
      damping: 0.14,
      stiffness: 16,
    },
    {
      id: 'hairPendulum',
      inputs: [
        { param: 'BodyBounce', type: 'y', weight: 0.42 },
        { param: 'BodySway', type: 'x', weight: 0.85 },
        { param: 'HeadTilt', type: 'x', weight: 0.95 },
      ],
      outputs: [{ param: 'HairSway', type: 'angle', segment: 0, scale: 0.85 }],
      segments: [{ length: 56, mass: 1.15 }],
      damping: 0.18,
      stiffness: 12,
    },
  ],
  parts: slackerParts,
  bindings: [
    ...slackerOpacityBindings,

    // Hip vertical bounce across all 6 views
    { target: 'bone:f_hip.y', params: ['BodyBounce'], keys: [{ at: [-24], value: -332 }, { at: [0], value: -308 }, { at: [24], value: -284 }] },
    { target: 'bone:s_hip.y', params: ['BodyBounce'], keys: [{ at: [-24], value: -318 }, { at: [0], value: -294 }, { at: [24], value: -270 }] },
    { target: 'bone:b_hip.y', params: ['BodyBounce'], keys: [{ at: [-24], value: -328 }, { at: [0], value: -304 }, { at: [24], value: -280 }] },
    { target: 'bone:fs_hip.y', params: ['BodyBounce'], keys: [{ at: [-24], value: -302 }, { at: [0], value: -278 }, { at: [24], value: -254 }] },
    { target: 'bone:ss_hip.y', params: ['BodyBounce'], keys: [{ at: [-24], value: -302 }, { at: [0], value: -278 }, { at: [24], value: -254 }] },
    { target: 'bone:bs_hip.y', params: ['BodyBounce'], keys: [{ at: [-24], value: -302 }, { at: [0], value: -278 }, { at: [24], value: -254 }] },

    // Torso sway across all 6 views
    ...['f_torsoBone', 's_torsoBone', 'b_torsoBone', 'fs_torsoBone', 'ss_torsoBone', 'bs_torsoBone'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['BodySway'],
      keys: [{ at: [-12], value: -5.5 }, { at: [0], value: 0 }, { at: [12], value: 5.5 }],
    })),

    // Skirt gentle counter-sway on standing views
    ...['f_skirtBone', 's_skirtBone', 'b_skirtBone'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['BodySway'],
      keys: [{ at: [-12], value: 2.8 }, { at: [0], value: 0 }, { at: [12], value: -2.8 }],
    })),

    // Head tilt across all 6 views
    ...['f_head', 's_head', 'b_head', 'fs_head', 'ss_head', 'bs_head'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['HeadTilt'],
      keys: [{ at: [-14], value: -8.5 }, { at: [0], value: 0 }, { at: [14], value: 8.5 }],
    })),

    // Iced-latte forearm lift (`CupLift`, negative = raise cup upward!)
    ...['f_armCup', 's_armCup', 'fs_armCup', 'ss_armCup'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['CupLift'],
      keys: [{ at: [-20], value: -20 }, { at: [0], value: 0 }, { at: [24], value: 18 }],
    })),

    // Ahoge spring pendulum across all 6 views
    ...['f_ahoge', 'fs_ahoge', 'b_ahoge', 'bs_ahoge'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['AhogeSway'],
      keys: [{ at: [-35], value: -107 }, { at: [0], value: -85 }, { at: [35], value: -63 }],
    })),
    ...['s_ahoge', 'ss_ahoge'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['AhogeSway'],
      keys: [{ at: [-35], value: -102 }, { at: [0], value: -80 }, { at: [35], value: -58 }],
    })),

    // Side & Back Hair Pendulum Sway (`HairSway`)
    ...['f_hairBack', 'fs_hairBack', 'f_sideLockR', 'f_sideLockL', 'fs_sideLockR', 'fs_sideLockL', 's_sideLock', 'ss_sideLock', 'ss_hairBack', 'b_hairLockL', 'b_hairLockR', 'bs_hairLockL', 'bs_hairLockR', 'bs_hairCurtain'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['HairSway'],
      keys: [{ at: [-25], value: 81 }, { at: [0], value: 90 }, { at: [25], value: 99 }],
    })),
    {
      target: 'warp:s_hairBackWarp.offsets',
      params: ['HairSway'],
      keys: [
        { at: [-25], value: makeWarpMap(4, 4, (_c, _r, _u, v) => [-12.0 * (v ** 1.6), -2.0 * (v ** 2)]) },
        { at: [0], value: {} },
        { at: [25], value: makeWarpMap(4, 4, (_c, _r, _u, v) => [12.0 * (v ** 1.6), -2.0 * (v ** 2)]) },
      ],
    },
    {
      target: 'warp:b_hairCurtainWarp.offsets',
      params: ['HairSway'],
      keys: [
        { at: [-25], value: makeWarpMap(4, 4, (_c, _r, _u, v) => [-11.0 * (v ** 1.5), -1.5 * (v ** 2)]) },
        { at: [0], value: {} },
        { at: [25], value: makeWarpMap(4, 4, (_c, _r, _u, v) => [11.0 * (v ** 1.5), -1.5 * (v ** 2)]) },
      ],
    },

    // Chest breathing lattices
    ...['f_torsoWarp', 's_torsoWarp', 'b_torsoWarp'].map((w) => ({
      target: `warp:${w}.offsets`,
      params: ['Breath'],
      keys: [
        { at: [0], value: {} },
        {
          at: [1],
          value: makeWarpMap(4, 4, (_c, _r, u, v) => {
            const chestBand = Math.sin(Math.PI * Math.min(1, v * 1.2));
            return [(u - 0.5) * 6.5 * chestBand, -4.5 * (1 - v * 0.7)];
          }),
        },
      ],
    })),
  ],
  animations: [
    // ---- IDLE ANIMATIONS (2.6s cozy breathing + periodic eye blink + hair sway) ----
    ...[
      ['front_idle', 0, 'f'],
      ['side_idle', 1, 's'],
      ['back_idle', 2, 'b'],
    ].map(([id, vid, pf]) => ({
      id,
      duration: 2.6,
      loop: true,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: vid, ease: 'step' }] },
        { target: 'param:EyeSmile', keys: blinkTrackKeys(2.6, 1.38) },
        { target: 'param:Breath', keys: periodicKeys(2.6, 10, (p) => 0.5 - 0.5 * Math.cos(2 * Math.PI * p)) },
        { target: 'param:BodyBounce', keys: periodicKeys(2.6, 10, (p) => 2.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(2.6, 10, (p) => 2.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(2.6, 10, (p) => 3.4 * Math.sin(2 * Math.PI * (p - 0.16))) },
        { target: 'param:CupLift', keys: periodicKeys(2.6, 10, (p) => -2.2 * Math.sin(2 * Math.PI * (p - 0.08))) },
        ...(pf === 'f'
          ? [
              { target: 'bone:f_upperArmR.rotation', keys: periodicKeys(2.6, 10, (p) => 94 + 2.4 * Math.sin(2 * Math.PI * p)) },
              { target: 'bone:f_foreArmR.rotation', keys: periodicKeys(2.6, 10, (p) => -6 - 2.0 * Math.sin(2 * Math.PI * p)) },
            ]
          : []),
      ],
    })),

    // ---- FRONT WALK (0.72s loop: Z-foreshortened alternating leg step + free arm swing + cup cushion!) ----
    {
      id: 'front_walk',
      duration: 0.72,
      loop: true,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: 0, ease: 'step' }] },
        { target: 'param:EyeSmile', keys: [{ t: 0, v: 0, ease: 'step' }] },
        { target: 'param:BodyBounce', keys: periodicKeys(0.72, 16, (p) => 7.0 * Math.cos(4 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(0.72, 16, (p) => 4.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(0.72, 16, (p) => -3.5 * Math.sin(2 * Math.PI * (p - 0.12))) },
        { target: 'param:CupLift', keys: periodicKeys(0.72, 16, (p) => -3.5 + 3.2 * Math.cos(4 * Math.PI * p)) },
        // Free left-screen arm swings rhythmically beside hip with elbow bend!
        { target: 'bone:f_upperArmR.rotation', keys: periodicKeys(0.72, 16, (p) => 96 + 8.5 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:f_foreArmR.rotation', keys: periodicKeys(0.72, 16, (p) => -6 - 8.0 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        // Right & Left legs Z-foreshortened step lift (only foreshortens lifted swing leg; planted foot stays inside canvas!)
        { target: 'bone:f_thighR.y', keys: periodicKeys(0.72, 16, (p) => 18 - 18.0 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        { target: 'bone:f_thighR.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.11 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        { target: 'bone:f_shinR.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.09 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        { target: 'bone:f_thighL.y', keys: periodicKeys(0.72, 16, (p) => 18 - 18.0 * Math.max(0, Math.sin(2 * Math.PI * ((p + 0.5) % 1)))) },
        { target: 'bone:f_thighL.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.11 * Math.max(0, Math.sin(2 * Math.PI * ((p + 0.5) % 1)))) },
        { target: 'bone:f_shinL.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.09 * Math.max(0, Math.sin(2 * Math.PI * ((p + 0.5) % 1)))) },
      ],
    },

    // ---- SIDE WALK (0.72s loop: Full 2-Bone Leg IK + Forward Knee + Ankle Roll + Counter-Swinging Far Arm!) ----
    {
      id: 'side_walk',
      duration: 0.72,
      loop: true,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: 1, ease: 'step' }] },
        { target: 'param:EyeSmile', keys: [{ t: 0, v: 0, ease: 'step' }] },
        // Contact (`p=0, 0.5`) = low hip (`+4.2`), Passing (`p=0.25, 0.75`) = high hip (`-4.2`)
        { target: 'param:BodyBounce', keys: periodicKeys(0.72, 16, (p) => 4.2 * Math.cos(4 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(0.72, 16, (p) => 2.8 + 2.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(0.72, 16, (p) => 2.6 * Math.sin(4 * Math.PI * (p - 0.1))) },
        { target: 'param:CupLift', keys: periodicKeys(0.72, 16, (p) => -3.0 + 3.0 * Math.sin(4 * Math.PI * p)) },
        // Far arm swings forward/back counter-phase to Far leg!
        { target: 'bone:s_upperArmFar.rotation', keys: periodicKeys(0.72, 16, (p) => 88 - 22.0 * Math.cos(2 * Math.PI * p)) },
        { target: 'bone:s_foreArmFar.rotation', keys: periodicKeys(0.72, 16, (p) => -14 - 14.0 * Math.max(0, Math.cos(2 * Math.PI * p))) },
        // Near leg 2-Bone IK target & ankle roll (`bendPositive: true` -> natural forward knee!)
        { target: 'bone:s_footTargetNear.x', keys: periodicKeys(0.72, 16, (p) => -2 + 38.0 * Math.cos(2 * Math.PI * p)) },
        {
          target: 'bone:s_footTargetNear.y',
          keys: periodicKeys(0.72, 16, (p) => {
            const sw = -Math.sin(2 * Math.PI * p);
            return -34 + (sw > 0 ? -30.0 * (sw ** 1.15) : -1.5 * (-sw));
          }),
        },
        { target: 'bone:s_footNear.rotation', keys: periodicKeys(0.72, 16, (p) => -101 - 14.0 * Math.cos(2 * Math.PI * p)) },
        // Far leg 2-Bone IK target (180 deg out of phase)
        { target: 'bone:s_footTargetFar.x', keys: periodicKeys(0.72, 16, (p) => 4 + 38.0 * Math.cos(2 * Math.PI * ((p + 0.5) % 1))) },
        {
          target: 'bone:s_footTargetFar.y',
          keys: periodicKeys(0.72, 16, (p) => {
            const sw = -Math.sin(2 * Math.PI * ((p + 0.5) % 1));
            return -34 + (sw > 0 ? -30.0 * (sw ** 1.15) : -1.5 * (-sw));
          }),
        },
        { target: 'bone:s_footFar.rotation', keys: periodicKeys(0.72, 16, (p) => -101 - 14.0 * Math.cos(2 * Math.PI * ((p + 0.5) % 1))) },
      ],
    },

    // ---- BACK WALK (0.72s loop: Dual arm swing + alternating leg lift + flowing back hair sway!) ----
    {
      id: 'back_walk',
      duration: 0.72,
      loop: true,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: 2, ease: 'step' }] },
        { target: 'param:BodyBounce', keys: periodicKeys(0.72, 16, (p) => 6.0 * Math.cos(4 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(0.72, 16, (p) => -4.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(0.72, 16, (p) => 3.4 * Math.sin(2 * Math.PI * (p - 0.12))) },
        { target: 'bone:b_upperArmL.rotation', keys: periodicKeys(0.72, 16, (p) => 96 + 11.0 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:b_foreArmL.rotation', keys: periodicKeys(0.72, 16, (p) => -6 - 8.0 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        { target: 'bone:b_upperArmR.rotation', keys: periodicKeys(0.72, 16, (p) => 84 + 11.0 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:b_foreArmR.rotation', keys: periodicKeys(0.72, 16, (p) => 6 + 8.0 * Math.max(0, -Math.sin(2 * Math.PI * p))) },
        { target: 'bone:b_thighL.y', keys: periodicKeys(0.72, 16, (p) => 18 - 18.0 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        { target: 'bone:b_thighL.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.11 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        { target: 'bone:b_shinL.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.09 * Math.max(0, Math.sin(2 * Math.PI * p))) },
        { target: 'bone:b_thighR.y', keys: periodicKeys(0.72, 16, (p) => 18 - 18.0 * Math.max(0, Math.sin(2 * Math.PI * ((p + 0.5) % 1)))) },
        { target: 'bone:b_thighR.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.11 * Math.max(0, Math.sin(2 * Math.PI * ((p + 0.5) % 1)))) },
        { target: 'bone:b_shinR.scaleX', keys: periodicKeys(0.72, 16, (p) => 1.0 - 0.09 * Math.max(0, Math.sin(2 * Math.PI * ((p + 0.5) % 1)))) },
      ],
    },

    // ---- CHEER ANIMATIONS (0.66s one-shot: Happy `^ ^` eyes + Iced-Latte Toast Lift + Hop!) ----
    ...[
      ['front_cheer', 0, 'f'],
      ['side_cheer', 1, 's'],
      ['back_cheer', 2, 'b'],
    ].map(([id, vid, pf]) => ({
      id,
      duration: 0.66,
      loop: false,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: vid, ease: 'step' }] },
        {
          target: 'param:EyeSmile',
          keys: [
            { t: 0.0, v: 0, ease: 'step' },
            { t: 0.06, v: 1, ease: 'step' },
            { t: 0.58, v: 0, ease: 'step' },
            { t: 0.66, v: 0, ease: 'step' },
          ],
        },
        {
          target: 'param:BodyBounce',
          keys: [
            { t: 0.0, v: 0, ease: 'smooth' },
            { t: 0.10, v: 7, ease: 'smooth' },
            { t: 0.28, v: -15, ease: 'smooth' },
            { t: 0.48, v: 4, ease: 'smooth' },
            { t: 0.66, v: 0, ease: 'smooth' },
          ],
        },
        {
          target: 'param:CupLift',
          keys: [
            { t: 0.0, v: 0, ease: 'smooth' },
            { t: 0.24, v: -18, ease: 'smooth' },
            { t: 0.44, v: -14, ease: 'smooth' },
            { t: 0.66, v: 0, ease: 'smooth' },
          ],
        },
        {
          target: 'param:HeadTilt',
          keys: [
            { t: 0.0, v: 0, ease: 'smooth' },
            { t: 0.24, v: -7.5, ease: 'smooth' },
            { t: 0.46, v: 3.5, ease: 'smooth' },
            { t: 0.66, v: 0, ease: 'smooth' },
          ],
        },
        ...(pf === 'f'
          ? [
              {
                target: 'bone:f_upperArmR.rotation',
                keys: [
                  { t: 0.0, v: 94, ease: 'smooth' },
                  { t: 0.25, v: 122, ease: 'smooth' },
                  { t: 0.66, v: 94, ease: 'smooth' },
                ],
              },
            ]
          : []),
        // Lift IK foot targets during celebratory hop so side feet leave the floor cleanly and stay in reach
        ...['s_footTargetNear', 's_footTargetFar'].map((tb) => ({
          target: `bone:${tb}.y`,
          keys: [
            { t: 0.0, v: -34, ease: 'smooth' },
            { t: 0.10, v: -30, ease: 'smooth' },
            { t: 0.28, v: -49, ease: 'smooth' },
            { t: 0.48, v: -32, ease: 'smooth' },
            { t: 0.66, v: -34, ease: 'smooth' },
          ],
        })),
      ],
    })),

    // ---- SEATED ANIMATIONS (2.4s loop: Dangling Lower-Leg Kick Swing + Blink + Sipping Breath!) ----
    {
      id: 'front_sit',
      duration: 2.4,
      loop: true,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: 3, ease: 'step' }] },
        { target: 'param:EyeSmile', keys: blinkTrackKeys(2.4, 1.15) },
        { target: 'param:BodyBounce', keys: periodicKeys(2.4, 10, (p) => 1.6 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(2.4, 10, (p) => 2.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(2.4, 10, (p) => 3.5 * Math.sin(2 * Math.PI * (p - 0.15))) },
        { target: 'param:CupLift', keys: periodicKeys(2.4, 10, (p) => -3.5 * (0.5 - 0.5 * Math.cos(2 * Math.PI * p))) },
        { target: 'bone:fs_shinR.y', keys: periodicKeys(2.4, 10, (p) => 64 - 8.0 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:fs_shinR.rotation', keys: periodicKeys(2.4, 10, (p) => 90 + 4.5 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:fs_shinL.y', keys: periodicKeys(2.4, 10, (p) => 68 + 8.0 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:fs_shinL.rotation', keys: periodicKeys(2.4, 10, (p) => 90 - 4.5 * Math.sin(2 * Math.PI * p)) },
      ],
    },
    {
      id: 'side_sit',
      duration: 2.4,
      loop: true,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: 4, ease: 'step' }] },
        { target: 'param:EyeSmile', keys: blinkTrackKeys(2.4, 1.15) },
        { target: 'param:BodyBounce', keys: periodicKeys(2.4, 10, (p) => 1.6 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(2.4, 10, (p) => 2.0 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(2.4, 10, (p) => 3.2 * Math.sin(2 * Math.PI * (p - 0.15))) },
        { target: 'param:CupLift', keys: periodicKeys(2.4, 10, (p) => -4.2 * (0.5 - 0.5 * Math.cos(2 * Math.PI * p))) },
        // Dangling near & far shins swing gently out of phase (`rotation < 90` kicks forward +X!)
        { target: 'bone:ss_shinNear.rotation', keys: periodicKeys(2.4, 12, (p) => 87 + 10.0 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:ss_shinFar.rotation', keys: periodicKeys(2.4, 12, (p) => 87 - 10.0 * Math.sin(2 * Math.PI * p)) },
      ],
    },
    {
      id: 'back_sit',
      duration: 2.4,
      loop: true,
      tracks: [
        { target: 'param:ViewId', keys: [{ t: 0, v: 5, ease: 'step' }] },
        { target: 'param:BodyBounce', keys: periodicKeys(2.4, 10, (p) => 1.6 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(2.4, 10, (p) => -2.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(2.4, 10, (p) => 3.5 * Math.sin(2 * Math.PI * (p - 0.15))) },
        { target: 'bone:bs_shinL.y', keys: periodicKeys(2.4, 10, (p) => 56 - 8.0 * Math.sin(2 * Math.PI * p)) },
        { target: 'bone:bs_shinR.y', keys: periodicKeys(2.4, 10, (p) => 56 + 8.0 * Math.sin(2 * Math.PI * p)) },
      ],
    },
  ],
};

const slackerR2dPath = path.join(__dirname, 'cozy_slacker.r2d.json');
fs.writeFileSync(slackerR2dPath, JSON.stringify(slackerModel, null, 2));

// ============================================================================
// 3. Build `cozy_partner.r2d.json` (Sleepy Lavender-Haired Studio Partner Girl)
// ============================================================================
const partnerParts = [
  imgPart({ id: 'p_hair_back', atlasMap: pAtlas, cropKey: 'p_hair_back', x: CX - 108, y: 194, w: 216, h: 204, z: 2.0, parent: 'p_hairBack', texture: 'partnerAtlas' }),
  imgPart({
    id: 'p_leg_l',
    atlasMap: pAtlas,
    cropKey: 'p_leg_l',
    x: CX - 86,
    y: 566,
    w: 92,
    h: 322,
    z: 4.0,
    cols: 6,
    rows: 10,
    skin: { bones: ['p_hip', 'p_kneeL'], weights: 'auto', falloff: 2.0 },
    texture: 'partnerAtlas',
  }),
  imgPart({
    id: 'p_leg_r',
    atlasMap: pAtlas,
    cropKey: 'p_leg_r',
    x: CX - 4,
    y: 566,
    w: 112,
    h: 322,
    z: 4.1,
    cols: 6,
    rows: 10,
    skin: { bones: ['p_hip', 'p_kneeR'], weights: 'auto', falloff: 2.0 },
    texture: 'partnerAtlas',
  }),
  imgPart({ id: 'p_torso', atlasMap: pAtlas, cropKey: 'p_torso', x: CX - 104, y: 318, w: 208, h: 314, z: 8.0, parent: 'p_torsoWarp', cols: 6, rows: 8, texture: 'partnerAtlas' }),
  imgPart({ id: 'p_arm_upper_l', atlasMap: pAtlas, cropKey: 'p_arm_upper_r', x: CX - 122, y: 368, w: 126, h: 104, z: 9.0, parent: 'p_torsoBone', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_arm_upper_r', atlasMap: pAtlas, cropKey: 'p_arm_upper_l', x: CX - 4, y: 368, w: 126, h: 104, z: 9.1, parent: 'p_torsoBone', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_tablet', atlasMap: pAtlas, cropKey: 'p_tablet', x: CX - 84, y: 400, w: 132, h: 154, z: 11.0, parent: 'p_tabletBone', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_arm_cradle', atlasMap: pAtlas, cropKey: 'p_arm_cradle', x: CX - 22, y: 432, w: 154, h: 96, z: 12.0, parent: 'p_tabletBone', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_arm_stylus', atlasMap: pAtlas, cropKey: 'p_arm_stylus', x: CX - 118, y: 416, w: 168, h: 112, z: 13.0, parent: 'p_stylusArm', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_headphones', atlasMap: pAtlas, cropKey: 'p_headphones', x: CX - 64, y: 312, w: 128, h: 118, z: 14.0, parent: 'p_torsoBone', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_hair_side_l', atlasMap: pAtlas, cropKey: 'p_hair_side_l', x: CX - 102, y: 278, w: 58, h: 134, z: 15.0, parent: 'p_sideLockL', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_hair_side_r', atlasMap: pAtlas, cropKey: 'p_hair_side_r', x: CX + 44, y: 278, w: 68, h: 134, z: 15.1, parent: 'p_sideLockR', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_head_open', atlasMap: pAtlas, cropKey: 'p_head_open', x: CX - 102, y: 190, w: 204, h: 196, z: 16.0, parent: 'p_head', texture: 'partnerAtlas' }),
  imgPart({ id: 'p_head_blink', atlasMap: pAtlas, cropKey: 'p_head_blink', x: CX - 102, y: 190, w: 204, h: 196, z: 16.1, parent: 'p_head', texture: 'partnerAtlas' }),
];

const partnerModel = {
  format: 'rev2d',
  version: 1,
  meta: {
    name: 'cozy_partner',
    width: CW,
    height: CH,
    background: 'rgba(0,0,0,0)',
    fps: 30,
    author: 'Slacker Survivors AI Cutout + Rev2D Pipeline',
    description: '2.5D Cozy Studio sleepy indie-artist companion rigged from AI-generated Spine cutout parts.',
  },
  textures: [
    { id: 'partnerAtlas', path: manifest.partner_atlas.file },
  ],
  parameters: [
    { id: 'EyeBlink', min: 0, max: 1, default: 0, group: 'Face', description: '0=open eyes, 1=sleepy closed blink' },
    { id: 'Breath', min: 0, max: 1, default: 0, group: 'Body', description: 'Hoodie chest breathing' },
    { id: 'BodyBounce', min: -16, max: 16, default: 0, group: 'Body', description: 'Hip vertical breathing bob' },
    { id: 'BodySway', min: -10, max: 10, default: 0, group: 'Body', description: 'Sleepy torso sway' },
    { id: 'HeadTilt', min: -12, max: 12, default: 0, group: 'Head', description: 'Head nod/tilt' },
    { id: 'StylusStroke', min: -10, max: 10, default: 0, group: 'Arms', description: 'Stylus sketching micro-motion' },
    { id: 'BobHairSway', min: -24, max: 24, default: 0, group: 'Physics', description: 'Lavender bob hair pendulum sway' },
  ],
  bones: [
    { id: 'ground', x: CX, y: GY, length: 0 },
    { id: 'p_hip', parent: 'ground', x: 0, y: -308, length: 0 },
    { id: 'p_kneeL', parent: 'p_hip', x: -40, y: 146, rotation: 90, length: 140 },
    { id: 'p_kneeR', parent: 'p_hip', x: 40, y: 146, rotation: 90, length: 140 },
    { id: 'p_torsoBone', parent: 'p_hip', x: 0, y: -96, length: 0 },
    { id: 'p_tabletBone', parent: 'p_torsoBone', x: 0, y: -12, length: 0 },
    { id: 'p_stylusArm', parent: 'p_torsoBone', x: -64, y: -24, rotation: 0, length: 110 },
    { id: 'p_head', parent: 'p_torsoBone', x: 0, y: -118, length: 0 },
    { id: 'p_hairBack', parent: 'p_head', x: 0, y: -104, rotation: 90, length: 130 },
    { id: 'p_sideLockL', parent: 'p_head', x: -76, y: -82, rotation: 90, length: 105 },
    { id: 'p_sideLockR', parent: 'p_head', x: 76, y: -82, rotation: 90, length: 105 },
  ],
  warps: [
    { id: 'p_torsoWarp', parent: 'p_torsoBone', rect: [CX - 114, 308, 228, 334], cols: 4, rows: 4 },
  ],
  physics: [
    {
      id: 'bobHairPendulum',
      inputs: [
        { param: 'BodyBounce', type: 'y', weight: 0.45 },
        { param: 'BodySway', type: 'x', weight: 0.9 },
        { param: 'HeadTilt', type: 'x', weight: 1.0 },
      ],
      outputs: [{ param: 'BobHairSway', type: 'angle', segment: 0, scale: 0.85 }],
      segments: [{ length: 52, mass: 1.1 }],
      damping: 0.18,
      stiffness: 12,
    },
  ],
  parts: partnerParts,
  bindings: [
    { target: 'part:p_head_open.opacity', params: ['EyeBlink'], interpolation: 'step', keys: [{ at: [0], value: 1 }, { at: [1], value: 0 }] },
    { target: 'part:p_head_blink.opacity', params: ['EyeBlink'], interpolation: 'step', keys: [{ at: [0], value: 0 }, { at: [1], value: 1 }] },
    { target: 'bone:p_hip.y', params: ['BodyBounce'], keys: [{ at: [-16], value: -324 }, { at: [0], value: -308 }, { at: [16], value: -292 }] },
    { target: 'bone:p_torsoBone.rotation', params: ['BodySway'], keys: [{ at: [-10], value: -4.2 }, { at: [0], value: 0 }, { at: [10], value: 4.2 }] },
    { target: 'bone:p_tabletBone.y', params: ['Breath'], keys: [{ at: [0], value: -12 }, { at: [1], value: -16 }] },
    { target: 'bone:p_stylusArm.rotation', params: ['StylusStroke'], keys: [{ at: [-10], value: -5.5 }, { at: [0], value: 0 }, { at: [10], value: 5.5 }] },
    { target: 'bone:p_head.rotation', params: ['HeadTilt'], keys: [{ at: [-12], value: -7.5 }, { at: [0], value: 0 }, { at: [12], value: 7.5 }] },
    ...['p_hairBack', 'p_sideLockL', 'p_sideLockR'].map((b) => ({
      target: `bone:${b}.rotation`,
      params: ['BobHairSway'],
      keys: [{ at: [-24], value: 82 }, { at: [0], value: 90 }, { at: [24], value: 98 }],
    })),
    {
      target: 'warp:p_torsoWarp.offsets',
      params: ['Breath'],
      keys: [
        { at: [0], value: {} },
        {
          at: [1],
          value: makeWarpMap(4, 4, (_c, _r, u, v) => {
            const band = Math.sin(Math.PI * Math.min(1, v * 1.15));
            return [(u - 0.5) * 6.5 * band, -4.5 * (1 - v * 0.65)];
          }),
        },
      ],
    },
  ],
  animations: [
    {
      id: 'idle',
      duration: 3.2,
      loop: true,
      tracks: [
        {
          target: 'param:EyeBlink',
          keys: [
            { t: 0, v: 0, ease: 'step' },
            { t: 1.55, v: 1, ease: 'step' },
            { t: 1.76, v: 0, ease: 'step' },
            { t: 3.2, v: 0, ease: 'step' },
          ],
        },
        { target: 'param:Breath', keys: periodicKeys(3.2, 12, (p) => 0.5 - 0.5 * Math.cos(2 * Math.PI * p)) },
        { target: 'param:BodyBounce', keys: periodicKeys(3.2, 12, (p) => 2.2 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:BodySway', keys: periodicKeys(3.2, 12, (p) => 2.6 * Math.sin(2 * Math.PI * p)) },
        { target: 'param:HeadTilt', keys: periodicKeys(3.2, 12, (p) => 4.2 * Math.sin(2 * Math.PI * (p - 0.18))) },
        { target: 'param:StylusStroke', keys: periodicKeys(3.2, 16, (p) => 4.8 * Math.sin(6 * Math.PI * p)) },
      ],
    },
  ],
};

const partnerR2dPath = path.join(__dirname, 'cozy_partner.r2d.json');
fs.writeFileSync(partnerR2dPath, JSON.stringify(partnerModel, null, 2));

// ============================================================================
// 4. Validate, Analyze & Export Spine 4.2 Assets via `rev2d` CLI
// ============================================================================
console.log('=== 1. Validating Rev2D Models ===');
console.log(runRev2d(['validate', slackerR2dPath, partnerR2dPath]));

console.log('=== 2. Analyzing Key Animations (Physics + IK + Loop Seam) ===');
console.log(runRev2d(['analyze', slackerR2dPath, '--anim', 'side_walk', '--warmup', '5']));
console.log(runRev2d(['analyze', slackerR2dPath, '--anim', 'front_walk', '--warmup', '5']));
console.log(runRev2d(['analyze', slackerR2dPath, '--anim', 'side_sit', '--warmup', '5']));
console.log(runRev2d(['analyze', partnerR2dPath, '--anim', 'idle', '--warmup', '5']));

console.log('=== 3. Exporting Spine 4.2 Skeletons + Atlases ===');
console.log(
  runRev2d([
    'export', 'spine', slackerR2dPath,
    '-o', OUT_SPINES_DIR,
    '--name', 'spn_cozy_studio_slacker',
    '--straight-alpha',
  ])
);
console.log(
  runRev2d([
    'export', 'spine', partnerR2dPath,
    '-o', OUT_SPINES_DIR,
    '--name', 'spn_cozy_studio_partner',
    '--straight-alpha',
  ])
);

// ============================================================================
// 5. Partition Slacker Slots into Native Spine 4.2 View Skins & Clean Opacity
// ============================================================================
const slackerRawJsonPath = path.join(OUT_SPINES_DIR, 'spn_cozy_studio_slacker.json');
const slackerFinalJsonPath = path.join(OUT_SPINES_DIR, 'spn_cozy_studio_slacker.spine-json');
const slackerSpine = JSON.parse(fs.readFileSync(slackerRawJsonPath, 'utf8'));

const slotToSkin = new Map();
for (const [skinName, slots] of Object.entries(SLACKER_SKIN_GROUPS)) {
  for (const s of slots) {
    slotToSkin.set(s, skinName);
  }
}

// Ensure setup slot color alpha is `ffffffff` for all default-visible parts of each view skin
// (in Rev2D setup pose `ViewId=0`, non-front views had `opacity=0`, whereas in Spine 4.2 the
// active view skin itself isolates visibility, and `_happy` faces stay `ffffff00` until blinked!)
if (Array.isArray(slackerSpine.slots)) {
  for (const slot of slackerSpine.slots) {
    if (slotToSkin.has(slot.name)) {
      slot.color = slot.name.endsWith('_happy') ? 'ffffff00' : 'ffffffff';
    }
  }
}

const defaultSkin = slackerSpine.skins.find((s) => s.name === 'default');
const defaultAtts = defaultSkin.attachments || {};
const newSkins = [{ name: 'default', attachments: {} }];

for (const [slotName, attMap] of Object.entries(defaultAtts)) {
  if (!slotToSkin.has(slotName)) {
    newSkins[0].attachments[slotName] = attMap;
  }
}
for (const [skinName, slots] of Object.entries(SLACKER_SKIN_GROUPS)) {
  const skinEntry = { name: skinName, attachments: {} };
  for (const slotName of slots) {
    if (defaultAtts[slotName]) {
      skinEntry.attachments[slotName] = defaultAtts[slotName];
    }
  }
  newSkins.push(skinEntry);
}
slackerSpine.skins = newSkins;

if (slackerSpine.animations) {
  for (const animData of Object.values(slackerSpine.animations)) {
    if (animData.attachments && animData.attachments.default) {
      const srcDef = animData.attachments.default;
      for (const [slotName, slotDeform] of Object.entries(srcDef)) {
        const targetSkin = slotToSkin.get(slotName);
        if (targetSkin) {
          if (!animData.attachments[targetSkin]) {
            animData.attachments[targetSkin] = {};
          }
          animData.attachments[targetSkin][slotName] = slotDeform;
          delete srcDef[slotName];
        }
      }
      if (Object.keys(srcDef).length === 0) {
        delete animData.attachments.default;
      }
    }
  }
}

fs.writeFileSync(slackerFinalJsonPath, JSON.stringify(slackerSpine));
fs.unlinkSync(slackerRawJsonPath);

const partnerRawJsonPath = path.join(OUT_SPINES_DIR, 'spn_cozy_studio_partner.json');
const partnerFinalJsonPath = path.join(OUT_SPINES_DIR, 'spn_cozy_studio_partner.spine-json');
if (fs.existsSync(partnerFinalJsonPath)) {
  fs.unlinkSync(partnerFinalJsonPath);
}
fs.renameSync(partnerRawJsonPath, partnerFinalJsonPath);

console.log('=== 6. Cozy Studio AI Cutout Spine 4.2 Export Complete ===');
console.log('Slacker skins:', slackerSpine.skins.map((s) => s.name));
