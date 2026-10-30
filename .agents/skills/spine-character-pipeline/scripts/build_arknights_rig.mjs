#!/usr/bin/env node
/**
 * Steps 4 & 5 of `spine-character-pipeline`:
 * Deterministic 2.8-Head Arknights 2.5D Rig Compiler, 17-Ring Hermite Skinned Mesh Builder,
 * Snappy Motion Synthesizer (4-Phase Hop-Walk + 3:1:2:4 Snap-Slash Smear VFX + 60Hz Pendulum Physics),
 * and Spine 4.2 (`--straight-alpha` + Mix-and-Match Skins) Exporter.
 */

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../../../..');
const REV2D_CLI = path.join(REPO_ROOT, 'addons/rev2d/runtime/bin/rev2d.js');

function parseArgs() {
  const idx = process.argv.indexOf('--spec');
  if (idx === -1 || !process.argv[idx + 1]) {
    throw new Error('Usage: node build_arknights_rig.mjs --spec <path/to/operator_spec.json>');
  }
  return path.resolve(process.argv[idx + 1]);
}

function runRev2d(args, cwd = REPO_ROOT) {
  return execFileSync(process.execPath, [REV2D_CLI, ...args], {
    cwd,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
}

function smoothstep(edge0, edge1, x) {
  const t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

/**
 * Builds a 17-ring joint-dense custom `mesh` part oriented along a 2-bone chain `(P0 -> P1 -> P2)`
 * in setup space, with smooth Hermite partition-of-unity bone weights `[w_upper, w_lower]`.
 */
function buildTwoBoneLimbMesh({
  id,
  crop,
  p0,
  p1,
  p2,
  widthPx,
  capTopPx = 12,
  capBotPx = 10,
  bones,
  z,
  opacity = 1,
}) {
  // 17 non-uniform longitudinal rings concentrated around the joint at v = 0.50
  const vRings = [0.0, 0.09, 0.19, 0.29, 0.36, 0.41, 0.45, 0.48, 0.50, 0.52, 0.55, 0.59, 0.64, 0.72, 0.82, 0.91, 1.0];
  const cols = 6; // 7 vertices per ring

  const d01x = p1[0] - p0[0];
  const d01y = p1[1] - p0[1];
  const len01 = Math.max(1, Math.hypot(d01x, d01y));
  const u01 = [d01x / len01, d01y / len01];

  const d12x = p2[0] - p1[0];
  const d12y = p2[1] - p1[1];
  const len12 = Math.max(1, Math.hypot(d12x, d12y));
  const u12 = [d12x / len12, d12y / len12];

  const startPt = [p0[0] - u01[0] * capTopPx, p0[1] - u01[1] * capTopPx];
  const endPt = [p2[0] + u12[0] * capBotPx, p2[1] + u12[1] * capBotPx];

  const segA = len01 + capTopPx;
  const segB = len12 + capBotPx;
  const totalLen = segA + segB;
  const jointV = segA / totalLen;

  const vertices = [];
  const uvs = [];
  const weights = [];

  for (let r = 0; r < vRings.length; r++) {
    const v = vRings[r];
    const dist = v * totalLen;
    let cx, cy;
    if (dist <= segA) {
      cx = startPt[0] + u01[0] * dist;
      cy = startPt[1] + u01[1] * dist;
    } else {
      const rem = dist - segA;
      cx = p1[0] + u12[0] * rem;
      cy = p1[1] + u12[1] * rem;
    }

    // Smooth blended tangent & right-hand normal across the joint so inner crease never self-intersects
    const blendDir = smoothstep(jointV - 0.18, jointV + 0.18, v);
    let tx = u01[0] * (1 - blendDir) + u12[0] * blendDir;
    let ty = u01[1] * (1 - blendDir) + u12[1] * blendDir;
    const tNorm = Math.max(1e-5, Math.hypot(tx, ty));
    tx /= tNorm;
    ty /= tNorm;
    // Screen coords (+x right, +y down): for downward limb (tx~0, ty~1), normal (+ty, -tx) = (+1, 0) points right (+u)!
    const nx = ty;
    const ny = -tx;

    const wLow = smoothstep(jointV - 0.18, jointV + 0.18, v);
    const wUp = 1 - wLow;

    for (let c = 0; c <= cols; c++) {
      const u = c / cols;
      const offset = (u - 0.5) * widthPx;
      vertices.push(Number((cx + nx * offset).toFixed(2)), Number((cy + ny * offset).toFixed(2)));
      const texU = crop.u0 + (crop.u1 - crop.u0) * u;
      const texV = crop.v0 + (crop.v1 - crop.v0) * v;
      uvs.push(Number(texU.toFixed(6)), Number(texV.toFixed(6)));
      weights.push([Number(wUp.toFixed(5)), Number(wLow.toFixed(5))]);
    }
  }

  const triangles = [];
  const stride = cols + 1;
  for (let r = 0; r < vRings.length - 1; r++) {
    for (let c = 0; c < cols; c++) {
      const i0 = r * stride + c;
      const i1 = i0 + 1;
      const i2 = i0 + stride;
      const i3 = i2 + 1;
      triangles.push(i0, i1, i2, i1, i3, i2);
    }
  }

  return {
    id,
    shape: {
      type: 'mesh',
      texture: 'partsAtlas',
      vertices,
      triangles,
      uvs,
    },
    skin: {
      bones,
      weights,
    },
    opacity,
    z,
  };
}

/**
 * Builds a Rectangular Custom-Weighted Mesh where top root (`v <= rootLockV`) is 100% locked
 * to `anchorBone` (preventing scalp/waist detachment!), smoothly cascading down `chainBones`.
 */
function buildRootLockedClothMesh({
  id,
  crop,
  x,
  y,
  w,
  h,
  cols = 8,
  rows = 12,
  bones,
  weightFn,
  z,
  opacity = 1,
}) {
  const vertices = [];
  const uvs = [];
  const weights = [];

  for (let r = 0; r <= rows; r++) {
    const v = r / rows;
    for (let c = 0; c <= cols; c++) {
      const u = c / cols;
      vertices.push(Number((x + u * w).toFixed(2)), Number((y + v * h).toFixed(2)));
      uvs.push(
        Number((crop.u0 + (crop.u1 - crop.u0) * u).toFixed(6)),
        Number((crop.v0 + (crop.v1 - crop.v0) * v).toFixed(6)),
      );
      const rawW = weightFn(u, v);
      const sum = rawW.reduce((a, b) => a + b, 0) || 1;
      weights.push(rawW.map((val) => Number((val / sum).toFixed(5))));
    }
  }

  const triangles = [];
  const stride = cols + 1;
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const i0 = r * stride + c;
      const i1 = i0 + 1;
      const i2 = i0 + stride;
      const i3 = i2 + 1;
      triangles.push(i0, i1, i2, i1, i3, i2);
    }
  }

  return {
    id,
    shape: {
      type: 'mesh',
      texture: 'partsAtlas',
      vertices,
      triangles,
      uvs,
    },
    skin: {
      bones,
      weights,
    },
    opacity,
    z,
  };
}

function makeRigidImagePart({ id, crop, x, y, w, h, parent, z, opacity = 1, cols = 2, rows = 2 }) {
  return {
    id,
    parent,
    shape: {
      type: 'image',
      texture: 'partsAtlas',
      crop: [crop.x, crop.y, crop.w, crop.h],
      x: Math.round(x),
      y: Math.round(y),
      w: Math.round(w ?? crop.w),
      h: Math.round(h ?? crop.h),
      cols,
      rows,
    },
    opacity,
    z,
  };
}

/**
 * Builds an orientation-preserving 4-vertex rotated textured quad around `pivot` (`u=0.5, v=gripRatioY`)
 * with blade tip (`v=0`) oriented along `angleDeg` in setup space (`-52 deg` = Arknights forward-up ready poise).
 */
function makeRotatedWeaponQuadPart({
  id,
  crop,
  pivot,
  gripRatioY = 0.78,
  angleDeg = -52,
  parent,
  z,
  opacity = 1,
}) {
  const rad = (angleDeg * Math.PI) / 180;
  const tx = Math.cos(rad);
  const ty = Math.sin(rad);
  const nx = -Math.sin(rad);
  const ny = Math.cos(rad);

  const w = crop.w;
  const h = crop.h;
  const vertices = [];
  const uvs = [];

  for (const v of [0, 1]) {
    const along = (gripRatioY - v) * h;
    for (const u of [0, 1]) {
      const across = (u - 0.5) * w;
      const px = pivot[0] + tx * along + nx * across;
      const py = pivot[1] + ty * along + ny * across;
      vertices.push(Number(px.toFixed(2)), Number(py.toFixed(2)));
      uvs.push(
        Number((crop.u0 + (crop.u1 - crop.u0) * u).toFixed(6)),
        Number((crop.v0 + (crop.v1 - crop.v0) * v).toFixed(6)),
      );
    }
  }

  return {
    id,
    parent,
    shape: {
      type: 'mesh',
      texture: 'partsAtlas',
      vertices,
      triangles: [0, 1, 2, 1, 3, 2],
      uvs,
    },
    opacity,
    z,
  };
}

function makeWarpMap(cols, rows, fn) {
  const map = {};
  for (let r = 0; r <= rows; r++) {
    const v = r / rows;
    for (let c = 0; c <= cols; c++) {
      const u = c / cols;
      const [dx, dy] = fn(u, v);
      if (Math.abs(dx) > 0.01 || Math.abs(dy) > 0.01) {
        map[String(r * (cols + 1) + c)] = [Number(dx.toFixed(2)), Number(dy.toFixed(2))];
      }
    }
  }
  return map;
}

function buildRig(specPath) {
  const charDir = path.dirname(specPath);
  const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
  const manifestPath = path.join(charDir, 'textures/part_manifest.json');
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`Missing ${manifestPath}. Run slice_and_inpaint_caps.py first!`);
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const crops = manifest.atlas.parts;

  const CW = manifest.canvas.width;      // 512
  const CH = manifest.canvas.height;     // 512
  const CX = manifest.canvas.center_x;   // 256
  const GY = manifest.canvas.ground_y;   // 448
  const TH = manifest.canvas.target_height; // 336

  const tune = spec.rig_tuning || {};
  const style = spec.style || {};
  const slashColor = style.slash_primary_color || '#38bdf8';
  const slashCore = style.slash_core_color || '#e0f2fe';
  const skillColor = style.skill_ring_color || '#f43f5e';

  // ==========================================================================
  // 1. Master-Calibrated 2.8-Head Arknights Skeleton Coordinates (Zero Deformity!)
  // ==========================================================================
  const legLen = crops.leg_near.h;
  const legCapTop = Math.round(legLen * 0.10);
  const legCapBot = Math.round(legLen * 0.10);
  const hipWorldY = GY - (legLen - legCapTop); // Exact 1.0x unstretched leg height grounded at GY=448!
  const hipDy = hipWorldY - GY;

  const torsoW = crops.torso.w;
  const torsoH = crops.torso.h;
  const torsoDy = Math.round(-torsoH * 0.53);
  const torsoWorldY = hipWorldY + torsoDy;

  const neckOffset = tune.neck_offset || [0, Math.round(-torsoH * 0.51)];
  const headWorldX = CX + neckOffset[0];
  const headWorldY = torsoWorldY + neckOffset[1]; // Chin/neck pivot (~270, right above white collar!)

  const headW = crops.face_open.w;
  const headH = crops.face_open.h;
  const headBoxX = Math.round(headWorldX - headW * 0.49);
  const headBoxY = Math.round(headWorldY - headH + 2);

  // Straight Vertical Rest Legs (+1px imperceptible forward knee seed + 0.2 IK softness -> 100% straight setup legs!)
  const hipNearOff = tune.hip_near_offset || [-15, 0];
  const hipFarOff = tune.hip_far_offset || [15, -1];

  const hipNearWorld = [CX + hipNearOff[0], hipWorldY + hipNearOff[1]];
  const ankleNearWorld = [hipNearWorld[0], GY - legCapBot];
  const kneeNearWorld = [hipNearWorld[0] + 1, Math.round((hipNearWorld[1] + ankleNearWorld[1]) * 0.5)];

  const hipFarWorld = [CX + hipFarOff[0], hipWorldY + hipFarOff[1]];
  const ankleFarWorld = [hipFarWorld[0], GY - legCapBot - 1];
  const kneeFarWorld = [hipFarWorld[0] + 1, Math.round((hipFarWorld[1] + ankleFarWorld[1]) * 0.5)];

  const deg = (rad) => Number(((rad * 180) / Math.PI).toFixed(2));
  const thighAng = deg(Math.atan2(kneeNearWorld[1] - hipNearWorld[1], kneeNearWorld[0] - hipNearWorld[0]));
  const shinWorldAng = deg(Math.atan2(ankleNearWorld[1] - kneeNearWorld[1], ankleNearWorld[0] - kneeNearWorld[0]));
  const shinLocalAng = Number((shinWorldAng - thighAng).toFixed(2));
  const thighLen = Number((Math.hypot(kneeNearWorld[0] - hipNearWorld[0], kneeNearWorld[1] - hipNearWorld[1]) + 0.2).toFixed(2));
  const shinLen = Number((Math.hypot(ankleNearWorld[0] - kneeNearWorld[0], ankleNearWorld[1] - kneeNearWorld[1]) + 0.2).toFixed(2));

  // Balanced 25-deg Arknights A-Pose Arms (gloved hands clear waist/midriff cleanly at rest!)
  const armLen = crops.arm_near.h;
  const armCapTop = Math.round(armLen * 0.14);
  const armCapBot = Math.round(armLen * 0.12);
  const armBoneSpan = Math.max(24, armLen - armCapTop - armCapBot);
  const upperArmLen = Math.round(armBoneSpan * 0.50);
  const foreArmLen = armBoneSpan - upperArmLen;

  const shNearOff = tune.shoulder_near_offset || [Math.round(-torsoW * 0.34), Math.round(-torsoH * 0.32)];
  const shFarOff = tune.shoulder_far_offset || [Math.round(torsoW * 0.33), Math.round(-torsoH * 0.32)];

  const shNearWorld = [CX + shNearOff[0], torsoWorldY + shNearOff[1]];
  const upperNearAng = 115;      // Clean 25-deg outward A-pose on left (-X)
  const foreNearLocalAng = -6;   // Natural slight forward wrist poise (world = 109 deg)
  const elbNearWorld = [
    shNearWorld[0] + Math.cos((upperNearAng * Math.PI) / 180) * upperArmLen,
    shNearWorld[1] + Math.sin((upperNearAng * Math.PI) / 180) * upperArmLen,
  ];
  const foreNearWorldAng = upperNearAng + foreNearLocalAng;
  const handNearWorld = [
    elbNearWorld[0] + Math.cos((foreNearWorldAng * Math.PI) / 180) * foreArmLen,
    elbNearWorld[1] + Math.sin((foreNearWorldAng * Math.PI) / 180) * foreArmLen,
  ];

  const shFarWorld = [CX + shFarOff[0], torsoWorldY + shFarOff[1]];
  const upperFarAng = 65;        // Clean 25-deg outward A-pose on right (+X)
  const foreFarLocalAng = 5;
  const elbFarWorld = [
    shFarWorld[0] + Math.cos((upperFarAng * Math.PI) / 180) * upperArmLen,
    shFarWorld[1] + Math.sin((upperFarAng * Math.PI) / 180) * upperArmLen,
  ];
  const foreFarWorldAng = upperFarAng + foreFarLocalAng;
  const handFarWorld = [
    elbFarWorld[0] + Math.cos((foreFarWorldAng * Math.PI) / 180) * foreArmLen,
    elbFarWorld[1] + Math.sin((foreFarWorldAng * Math.PI) / 180) * foreArmLen,
  ];

  // Weapon held in sleek Arknights side-swept low-back poise (`+128 deg`, 100% clear of face & body!)
  const gripRatioY = tune.weapon_grip_ratio_y ?? 0.80;
  const weaponRestAngleDeg = tune.weapon_rest_angle_deg ?? 128;

  // Torso (collar + jacket + exposed midriff) & Pleated Skirt (`coat_tail` overlaps bottom belly rim cleanly!)
  const torsoBoxX = Math.round(CX - torsoW * 0.50);
  const torsoBoxY = Math.round(headWorldY - 6);
  const coatW = crops.coat_tail.w;
  const coatH = crops.coat_tail.h;
  const coatBoxX = Math.round(CX - coatW * 0.50 + (tune.coat_offset ? tune.coat_offset[0] : 0));
  const coatBoxY = Math.round(torsoBoxY + torsoH - 13 + (tune.coat_offset ? tune.coat_offset[1] : 0));

  const hairBackW = crops.hair_back.w;
  const hairBackH = crops.hair_back.h;
  const hairBackX = Math.round(CX - hairBackW * 0.50 - 2);
  const hairBackY = Math.round(headBoxY - 12);

  const bangsW = crops.hair_bangs.w;
  const bangsH = crops.hair_bangs.h;
  const bangsOff = tune.bangs_offset || [0, -5];
  const bangsX = Math.round(CX - bangsW * 0.50 + bangsOff[0]);
  const bangsY = Math.round(headBoxY - 13 + bangsOff[1]);

  const accW = crops.head_acc.w;
  const accH = crops.head_acc.h;
  const accOff = tune.head_acc_offset || [0, -42];
  const accX = Math.round(CX - accW * 0.50 + 2 + accOff[0]);
  const accY = Math.round(headBoxY - 13 + accOff[1]);

  // ==========================================================================
  // 2. Assemble Rev2D Model (`*.r2d.json`)
  // ==========================================================================
  const model = {
    format: 'rev2d',
    version: 1,
    meta: {
      name: spec.char_id,
      width: CW,
      height: CH,
      background: 'rgba(0,0,0,0)',
      fps: 30,
      author: 'spine-character-pipeline (Arknights 2.8-Head 2.5D Standard)',
      description: spec.title || `${spec.char_id} 2.5D Spine Operator`,
    },
    textures: [{ id: 'partsAtlas', path: manifest.atlas.file }],
    parameters: [
      { id: 'ExprMode', min: 0, max: 2, default: 0, group: 'Face', description: '0=Open, 1=Blink, 2=Skill/Shout' },
      { id: 'WeaponMode', min: 0, max: 2, default: 0, group: 'Equipment', description: '0=Primary, 1=Secondary, 2=Unarmed' },
      { id: 'Breath', min: 0, max: 1, default: 0, group: 'Body', description: 'Chest breathing expansion' },
      { id: 'BodyBobY', min: -36, max: 28, default: 0, group: 'Body', description: 'Vertical hip offset (+ = crouch, - = leap)' },
      { id: 'BodyLean', min: -32, max: 36, default: 0, group: 'Body', description: 'Torso pitch (+ = forward lean CW)' },
      { id: 'Squash', min: -1, max: 1, default: 0, group: 'Body', description: '+1 = impact squash, -1 = airborne stretch' },
      { id: 'HeadNod', min: -24, max: 24, default: 0, group: 'Head', description: 'Head pitch angle (deg)' },
      { id: 'FootNearX', min: -68, max: 68, default: 0, group: 'LegIK', description: 'Near foot stride X' },
      { id: 'FootNearY', min: -56, max: 12, default: 0, group: 'LegIK', description: 'Near foot lift Y (- = up)' },
      { id: 'FootFarX', min: -68, max: 68, default: 0, group: 'LegIK', description: 'Far foot stride X' },
      { id: 'FootFarY', min: -56, max: 12, default: 0, group: 'LegIK', description: 'Far foot lift Y (- = up)' },
      { id: 'ArmNearShoulder', min: -145, max: 125, default: 0, group: 'Arms', description: 'Weapon shoulder swing delta' },
      { id: 'ArmNearElbow', min: -95, max: 95, default: 0, group: 'Arms', description: 'Weapon elbow bend delta' },
      { id: 'WeaponWrist', min: -165, max: 165, default: 0, group: 'Arms', description: 'Weapon wrist pitch delta' },
      { id: 'ArmFarSwing', min: -85, max: 85, default: 0, group: 'Arms', description: 'Offhand arm counter-swing' },
      { id: 'SlashDownAlpha', min: 0, max: 1, default: 0, group: 'VFX', description: 'Primary downward crescent slash smear' },
      { id: 'SlashDownSweep', min: 0, max: 1, default: 0, group: 'VFX', description: 'Downward slash arc sweep expansion' },
      { id: 'SlashUpAlpha', min: 0, max: 1, default: 0, group: 'VFX', description: 'Secondary upward crescent slash smear' },
      { id: 'SkillBurstAlpha', min: 0, max: 1, default: 0, group: 'VFX', description: 'Originium skill ground ring alpha' },
      { id: 'SkillBurstScale', min: 0.4, max: 1.6, default: 1, group: 'VFX', description: 'Skill ring expansion scale' },
      { id: 'CoatSway1', min: -42, max: 42, default: 0, group: 'Physics', description: 'Coat hem segment 1 angle' },
      { id: 'CoatSway2', min: -48, max: 48, default: 0, group: 'Physics', description: 'Coat hem segment 2 angle' },
      { id: 'HairBackSway1', min: -35, max: 35, default: 0, group: 'Physics', description: 'Back hair segment 1 angle' },
      { id: 'HairBackSway2', min: -42, max: 42, default: 0, group: 'Physics', description: 'Back hair segment 2 angle' },
      { id: 'SideLockSway', min: -32, max: 32, default: 0, group: 'Physics', description: 'Cheek hair locks sway angle' },
      { id: 'EarAccSway', min: -36, max: 36, default: 0, group: 'Physics', description: 'Animal ears / ahoge sway angle' },
    ],
    bones: [
      { id: 'ground', x: CX, y: GY, length: 0, description: '3D ground shadow contact anchor' },
      { id: 'skillRingBone', parent: 'ground', x: 4, y: -4, length: 0 },
      { id: 'hip', parent: 'ground', x: 0, y: hipDy, length: 0 },
      { id: 'torso', parent: 'hip', x: 0, y: torsoDy, length: 0 },
      { id: 'head', parent: 'torso', x: neckOffset[0], y: neckOffset[1], length: 0 },

      // 60Hz Secondary Motion Chains (Coat, Back Hair, Side Locks, Ears/Ahoge)
      { id: 'coat1', parent: 'hip', x: -4, y: -8, rotation: 96, length: Math.round(coatH * 0.45) },
      { id: 'coat2', parent: 'coat1', x: Math.round(coatH * 0.45), y: 0, rotation: 4, length: Math.round(coatH * 0.45) },

      { id: 'hairBack1', parent: 'head', x: -12, y: Math.round(-headH * 0.45), rotation: 100, length: Math.round(hairBackH * 0.42) },
      { id: 'hairBack2', parent: 'hairBack1', x: Math.round(hairBackH * 0.42), y: 0, rotation: 4, length: Math.round(hairBackH * 0.42) },

      { id: 'sideLockBack', parent: 'head', x: Math.round(-headW * 0.34), y: Math.round(-headH * 0.36), rotation: 92, length: Math.round(bangsH * 0.52) },
      { id: 'sideLockFront', parent: 'head', x: Math.round(headW * 0.34), y: Math.round(-headH * 0.36), rotation: 88, length: Math.round(bangsH * 0.52) },
      { id: 'headAccBone', parent: 'head', x: accOff[0], y: Math.round(-headH * 0.78), rotation: -86, length: Math.round(accH * 0.65) },

      // Far & Near 2-Bone IK Legs
      { id: 'thighFar', parent: 'hip', x: hipFarOff[0], y: hipFarOff[1], rotation: thighAng, length: thighLen },
      { id: 'shinFar', parent: 'thighFar', x: thighLen, y: 0, rotation: shinLocalAng, length: shinLen },
      { id: 'footTargetFar', parent: 'ground', x: ankleFarWorld[0] - CX, y: ankleFarWorld[1] - GY, length: 0 },

      { id: 'thighNear', parent: 'hip', x: hipNearOff[0], y: hipNearOff[1], rotation: thighAng, length: thighLen },
      { id: 'shinNear', parent: 'thighNear', x: thighLen, y: 0, rotation: shinLocalAng, length: shinLen },
      { id: 'footTargetNear', parent: 'ground', x: ankleNearWorld[0] - CX, y: ankleNearWorld[1] - GY, length: 0 },

      // Far Offhand 2-Bone Arm
      { id: 'upperArmFar', parent: 'torso', x: shFarOff[0], y: shFarOff[1], rotation: upperFarAng, length: upperArmLen },
      { id: 'foreArmFar', parent: 'upperArmFar', x: upperArmLen, y: 0, rotation: foreFarLocalAng, length: foreArmLen },

      // Near Weapon 2-Bone Arm + Grip Socket
      { id: 'upperArmNear', parent: 'torso', x: shNearOff[0], y: shNearOff[1], rotation: upperNearAng, length: upperArmLen },
      { id: 'foreArmNear', parent: 'upperArmNear', x: upperArmLen, y: 0, rotation: foreNearLocalAng, length: foreArmLen },
      { id: 'weaponGrip', parent: 'foreArmNear', x: Math.round(foreArmLen * 0.88), y: 0, rotation: -42, length: 96 },

      // Slash Arc Origin in front of chest (+X)
      { id: 'slashOrigin', parent: 'torso', x: 26, y: -6, length: 0 },
    ],
    ik: [
      { id: 'ikLegFar', bones: ['thighFar', 'shinFar'], target: 'footTargetFar', bendPositive: true, softness: 0.2, mix: 1 },
      { id: 'ikLegNear', bones: ['thighNear', 'shinNear'], target: 'footTargetNear', bendPositive: true, softness: 0.2, mix: 1 },
    ],
    warps: [
      {
        id: 'torsoWarp',
        parent: 'torso',
        rect: [torsoBoxX - 10, torsoBoxY - 10, torsoW + 20, torsoH + 20],
        cols: 4,
        rows: 4,
      },
    ],
    physics: [
      {
        id: 'coatPendulum',
        inputs: [
          { param: 'BodyBobY', type: 'y', weight: 0.75 },
          { param: 'BodyLean', type: 'x', weight: 1.15 },
        ],
        outputs: [
          { param: 'CoatSway1', type: 'angle', segment: 0, scale: 0.85 },
          { param: 'CoatSway2', type: 'angle', segment: 1, scale: 1.15 },
        ],
        segments: [
          { length: 38, mass: 1.0 },
          { length: 42, mass: 0.85 },
        ],
        damping: 0.24,
        stiffness: 0.24,
        gravity: 960,
      },
      {
        id: 'hairBackPendulum',
        inputs: [
          { param: 'BodyBobY', type: 'y', weight: 0.65 },
          { param: 'BodyLean', type: 'x', weight: 0.85 },
          { param: 'HeadNod', type: 'x', weight: 1.05 },
        ],
        outputs: [
          { param: 'HairBackSway1', type: 'angle', segment: 0, scale: 0.8 },
          { param: 'HairBackSway2', type: 'angle', segment: 1, scale: 1.1 },
        ],
        segments: [
          { length: 36, mass: 1.0 },
          { length: 38, mass: 0.85 },
        ],
        damping: 0.25,
        stiffness: 0.26,
        gravity: 940,
      },
      {
        id: 'sideLockPendulum',
        inputs: [
          { param: 'BodyBobY', type: 'y', weight: 0.55 },
          { param: 'HeadNod', type: 'x', weight: 1.1 },
        ],
        outputs: [{ param: 'SideLockSway', type: 'angle', segment: 0, scale: 0.9 }],
        segments: [{ length: 32, mass: 0.9 }],
        damping: 0.26,
        stiffness: 0.30,
        gravity: 920,
      },
      {
        id: 'earAccPendulum',
        inputs: [
          { param: 'BodyBobY', type: 'y', weight: 0.7 },
          { param: 'HeadNod', type: 'x', weight: 1.2 },
        ],
        outputs: [{ param: 'EarAccSway', type: 'angle', segment: 0, scale: 0.95 }],
        segments: [{ length: 26, mass: 0.8 }],
        damping: 0.24,
        stiffness: 0.36,
        gravity: 950,
      },
    ],
    parts: [
      // z = 0.5: Ground Originium Skill Ring VFX
      {
        id: 'fx_skill_ring',
        parent: 'skillRingBone',
        shape: { type: 'ellipse', cx: CX + 4, cy: GY - 2, rx: 86, ry: 26, segments: 48 },
        fill: {
          type: 'radial',
          center: [CX + 4, GY - 2],
          radius: 86,
          stops: [
            [0.0, 'rgba(255,255,255,0.0)'],
            [0.68, `${skillColor}55`],
            [0.92, `${skillColor}ee`],
            [1.0, 'rgba(255,255,255,0.0)'],
          ],
        },
        stroke: { color: slashCore, width: 2.5 },
        opacity: 0,
        z: 0.5,
      },

      // z = 1.0: Root-locked Back Hair (`head` at top, `hairBack1..2` below)
      buildRootLockedClothMesh({
        id: 'hair_back',
        crop: crops.hair_back,
        x: hairBackX,
        y: hairBackY,
        w: hairBackW,
        h: hairBackH,
        bones: ['head', 'hairBack1', 'hairBack2'],
        weightFn: (_u, v) => {
          const w0 = 1 - smoothstep(0.18, 0.52, v);
          const w2 = smoothstep(0.55, 0.92, v);
          const w1 = Math.max(0, 1 - w0 - w2);
          return [w0, w1, w2];
        },
        z: 1.0,
      }),

      // z = 2.2: Far Offhand 17-Ring Continuous Skinned Arm
      buildTwoBoneLimbMesh({
        id: 'arm_far',
        crop: crops.arm_far,
        p0: shFarWorld,
        p1: elbFarWorld,
        p2: handFarWorld,
        widthPx: crops.arm_far.w,
        capTopPx: armCapTop,
        capBotPx: armCapBot,
        bones: ['upperArmFar', 'foreArmFar'],
        z: 2.2,
      }),

      // z = 4.0 & 5.2: Far & Near 17-Ring Continuous Straight Vertical IK Legs (NO knee/ankle cut, NO boomerang warp!)
      buildTwoBoneLimbMesh({
        id: 'leg_far',
        crop: crops.leg_far,
        p0: hipFarWorld,
        p1: kneeFarWorld,
        p2: ankleFarWorld,
        widthPx: crops.leg_far.w,
        capTopPx: legCapTop,
        capBotPx: legCapBot,
        bones: ['thighFar', 'shinFar'],
        z: 4.0,
      }),
      buildTwoBoneLimbMesh({
        id: 'leg_near',
        crop: crops.leg_near,
        p0: hipNearWorld,
        p1: kneeNearWorld,
        p2: ankleNearWorld,
        widthPx: crops.leg_near.w,
        capTopPx: legCapTop,
        capBotPx: legCapBot,
        bones: ['thighNear', 'shinNear'],
        z: 5.2,
      }),

      // z = 6.8: Breathing Torso + Cropped Jacket + Exposed Midriff (lower belly tucks cleanly into skirt waistband!)
      makeRigidImagePart({
        id: 'torso',
        crop: crops.torso,
        x: torsoBoxX,
        y: torsoBoxY,
        w: torsoW,
        h: torsoH,
        parent: 'torsoWarp',
        cols: 6,
        rows: 6,
        z: 6.8,
      }),
      // z = 7.2: Dark Cloth Shoulder Socket Under-Cap
      {
        id: 'torso_shoulder_cap',
        parent: 'torso',
        shape: {
          type: 'ellipse',
          cx: shNearWorld[0] + 2,
          cy: shNearWorld[1] + 4,
          rx: 10,
          ry: 13,
          segments: 24,
        },
        fill: style.shoulder_cap_color || '#232f3b',
        stroke: { color: '#141923', width: 2.0 },
        z: 7.2,
      },

      // z = 7.6: Root-Locked Pleated Tactical Skirt (`coat_tail` waistband cleanly wraps lower midriff & hip caps!)
      buildRootLockedClothMesh({
        id: 'coat_tail',
        crop: crops.coat_tail,
        x: coatBoxX,
        y: coatBoxY,
        w: coatW,
        h: coatH,
        bones: ['hip', 'coat1', 'coat2'],
        weightFn: (_u, v) => {
          const w0 = 1 - smoothstep(0.18, 0.50, v);
          const w2 = smoothstep(0.56, 0.92, v);
          const w1 = Math.max(0, 1 - w0 - w2);
          return [w0, w1, w2];
        },
        z: 7.6,
      }),

      // z = 10.0..10.2: Zero-Jitter Head Shell + Fused Blink & Skill Faces
      makeRigidImagePart({
        id: 'face_open',
        crop: crops.face_open,
        x: headBoxX,
        y: headBoxY,
        w: headW,
        h: headH,
        parent: 'head',
        cols: 2,
        rows: 2,
        z: 10.0,
      }),
      makeRigidImagePart({
        id: 'face_blink',
        crop: crops.face_blink,
        x: headBoxX,
        y: headBoxY,
        w: headW,
        h: headH,
        parent: 'head',
        opacity: 0,
        cols: 2,
        rows: 2,
        z: 10.1,
      }),
      makeRigidImagePart({
        id: 'face_skill',
        crop: crops.face_skill,
        x: headBoxX,
        y: headBoxY,
        w: headW,
        h: headH,
        parent: 'head',
        opacity: 0,
        cols: 2,
        rows: 2,
        z: 10.2,
      }),

      // z = 12.0: Crown-Locked Front Bangs + Pendulum Cheek Side-Locks (zero scalp seam!)
      buildRootLockedClothMesh({
        id: 'hair_bangs',
        crop: crops.hair_bangs,
        x: bangsX,
        y: bangsY,
        w: bangsW,
        h: bangsH,
        bones: ['head', 'sideLockBack', 'sideLockFront'],
        weightFn: (u, v) => {
          const vertSway = smoothstep(0.38, 0.88, v);
          const leftMask = 1 - smoothstep(0.20, 0.40, u);
          const rightMask = smoothstep(0.60, 0.80, u);
          const wL = vertSway * leftMask * 0.78;
          const wR = vertSway * rightMask * 0.78;
          const wHead = Math.max(0, 1 - wL - wR);
          return [wHead, wL, wR];
        },
        z: 12.0,
      }),

      // z = 11.5: Root-Locked Animal Ears / Ahoge (`v=1` bottom tucks seamlessly behind `hair_bangs` crown at z=12.0!)
      buildRootLockedClothMesh({
        id: 'head_acc',
        crop: crops.head_acc,
        x: accX,
        y: accY,
        w: accW,
        h: accH,
        cols: 6,
        rows: 8,
        bones: ['head', 'headAccBone'],
        weightFn: (_u, v) => {
          // Bottom of `head_acc` (v -> 1) touches crown of head -> lock to `head`!
          const wTip = (1 - smoothstep(0.18, 0.78, v)) * 0.85;
          return [1 - wTip, wTip];
        },
        z: 11.5,
      }),

      // z = 14.2 & 14.3: Modular Weapons (`weapon/primary` & `weapon/secondary` Mix-and-Match Skins)
      // Oriented at `-52 deg` forward-up Arknights ready stance (clear of face!) and placed under `arm_near` (`z = 15.0`)
      makeRotatedWeaponQuadPart({
        id: 'weapon_primary',
        crop: crops.weapon_primary,
        pivot: handNearWorld,
        gripRatioY,
        angleDeg: weaponRestAngleDeg,
        parent: 'weaponGrip',
        opacity: 1,
        z: 14.2,
      }),
      makeRotatedWeaponQuadPart({
        id: 'weapon_secondary',
        crop: crops.weapon_secondary,
        pivot: handNearWorld,
        gripRatioY,
        angleDeg: weaponRestAngleDeg,
        parent: 'weaponGrip',
        opacity: 0,
        z: 14.3,
      }),

      // z = 15.0: Near Weapon-Hand 17-Ring Continuous Skinned Arm
      buildTwoBoneLimbMesh({
        id: 'arm_near',
        crop: crops.arm_near,
        p0: shNearWorld,
        p1: elbNearWorld,
        p2: handNearWorld,
        widthPx: crops.arm_near.w,
        capTopPx: armCapTop,
        capBotPx: armCapBot,
        bones: ['upperArmNear', 'foreArmNear'],
        z: 15.0,
      }),

      // z = 18.0 & 18.5: Arknights Crescent Slash Smear Meshes (Hand-Crafted Motion Blur VFX!)
      {
        id: 'fx_slash_down',
        parent: 'slashOrigin',
        shape: {
          type: 'path',
          d: `M ${CX + 18} ${torsoWorldY - 122} C ${CX + 138} ${torsoWorldY - 96}, ${CX + 178} ${torsoWorldY + 18}, ${CX + 96} ${GY - 6} C ${CX + 132} ${torsoWorldY + 4}, ${CX + 102} ${torsoWorldY - 72}, ${CX + 18} ${torsoWorldY - 122} Z`,
          detail: 10,
        },
        fill: {
          type: 'linear',
          from: [CX + 24, torsoWorldY - 118],
          to: [CX + 148, GY - 16],
          stops: [
            [0.0, 'rgba(255,255,255,0.0)'],
            [0.45, slashColor],
            [0.85, slashCore],
            [1.0, 'rgba(255,255,255,0.0)'],
          ],
        },
        stroke: { color: slashCore, width: 2.0 },
        opacity: 0,
        z: 18.0,
      },
      {
        id: 'fx_slash_up',
        parent: 'slashOrigin',
        shape: {
          type: 'path',
          d: `M ${CX + 26} ${GY - 14} C ${CX + 156} ${torsoWorldY + 42}, ${CX + 172} ${torsoWorldY - 76}, ${CX + 56} ${torsoWorldY - 138} C ${CX + 124} ${torsoWorldY - 64}, ${CX + 114} ${torsoWorldY + 24}, ${CX + 26} ${GY - 14} Z`,
          detail: 10,
        },
        fill: {
          type: 'linear',
          from: [CX + 34, GY - 16],
          to: [CX + 92, torsoWorldY - 132],
          stops: [
            [0.0, 'rgba(255,255,255,0.0)'],
            [0.5, slashColor],
            [0.88, slashCore],
            [1.0, 'rgba(255,255,255,0.0)'],
          ],
        },
        stroke: { color: slashCore, width: 2.0 },
        opacity: 0,
        z: 18.5,
      },
    ],
    bindings: [
      // 3-State Zero-Jitter Expression Bindings (`0=Open, 1=Blink, 2=Skill`)
      {
        target: 'part:face_open.opacity',
        params: ['ExprMode'],
        interpolation: 'step',
        keys: [
          { at: [0], value: 1 },
          { at: [1], value: 0 },
          { at: [2], value: 0 },
        ],
      },
      {
        target: 'part:face_blink.opacity',
        params: ['ExprMode'],
        interpolation: 'step',
        keys: [
          { at: [0], value: 0 },
          { at: [1], value: 1 },
          { at: [2], value: 0 },
        ],
      },
      {
        target: 'part:face_skill.opacity',
        params: ['ExprMode'],
        interpolation: 'step',
        keys: [
          { at: [0], value: 0 },
          { at: [1], value: 0 },
          { at: [2], value: 1 },
        ],
      },
      {
        target: 'part:weapon_primary.opacity',
        params: ['WeaponMode'],
        interpolation: 'step',
        keys: [
          { at: [0], value: 1 },
          { at: [1], value: 0 },
          { at: [2], value: 0 },
        ],
      },
      {
        target: 'part:weapon_secondary.opacity',
        params: ['WeaponMode'],
        interpolation: 'step',
        keys: [
          { at: [0], value: 0 },
          { at: [1], value: 1 },
          { at: [2], value: 0 },
        ],
      },

      // Core Body Locomotion & Squash-Stretch
      {
        target: 'bone:hip.y',
        params: ['BodyBobY'],
        keys: [
          { at: [-36], value: hipDy - 36 },
          { at: [0], value: hipDy },
          { at: [28], value: hipDy + 28 },
        ],
      },
      {
        target: 'bone:torso.rotation',
        params: ['BodyLean'],
        keys: [
          { at: [-32], value: -32 },
          { at: [0], value: 0 },
          { at: [36], value: 36 },
        ],
      },
      {
        target: 'bone:hip.scaleX',
        params: ['Squash'],
        keys: [
          { at: [-1], value: 0.95 },
          { at: [0], value: 1.0 },
          { at: [1], value: 1.05 },
        ],
      },
      {
        target: 'bone:hip.scaleY',
        params: ['Squash'],
        keys: [
          { at: [-1], value: 1.05 },
          { at: [0], value: 1.0 },
          { at: [1], value: 0.95 },
        ],
      },
      {
        target: 'bone:head.rotation',
        params: ['HeadNod'],
        keys: [
          { at: [-24], value: -24 },
          { at: [0], value: 0 },
          { at: [24], value: 24 },
        ],
      },

      // Chest Breathing Lattice Warp
      {
        target: 'warp:torsoWarp.offsets',
        params: ['Breath'],
        keys: [
          { at: [0], value: {} },
          {
            at: [1],
            value: makeWarpMap(4, 4, (u, v) => {
              const chest = Math.sin(Math.PI * Math.min(1, v * 1.15));
              return [(u - 0.5) * 5.0 * chest, -3.5 * (1 - v * 0.7)];
            }),
          },
        ],
      },

      // 2-Bone Leg IK Targets
      {
        target: 'bone:footTargetNear.x',
        params: ['FootNearX'],
        keys: [
          { at: [-68], value: ankleNearWorld[0] - CX - 68 },
          { at: [0], value: ankleNearWorld[0] - CX },
          { at: [68], value: ankleNearWorld[0] - CX + 68 },
        ],
      },
      {
        target: 'bone:footTargetNear.y',
        params: ['FootNearY'],
        keys: [
          { at: [-56], value: ankleNearWorld[1] - GY - 56 },
          { at: [0], value: ankleNearWorld[1] - GY },
          { at: [12], value: ankleNearWorld[1] - GY + 12 },
        ],
      },
      {
        target: 'bone:footTargetFar.x',
        params: ['FootFarX'],
        keys: [
          { at: [-68], value: ankleFarWorld[0] - CX - 68 },
          { at: [0], value: ankleFarWorld[0] - CX },
          { at: [68], value: ankleFarWorld[0] - CX + 68 },
        ],
      },
      {
        target: 'bone:footTargetFar.y',
        params: ['FootFarY'],
        keys: [
          { at: [-56], value: ankleFarWorld[1] - GY - 56 },
          { at: [0], value: ankleFarWorld[1] - GY },
          { at: [12], value: ankleFarWorld[1] - GY + 12 },
        ],
      },

      // Arms & Weapon Grip Articulation
      {
        target: 'bone:upperArmNear.rotation',
        params: ['ArmNearShoulder'],
        keys: [
          { at: [-145], value: upperNearAng - 145 },
          { at: [0], value: upperNearAng },
          { at: [125], value: upperNearAng + 125 },
        ],
      },
      {
        target: 'bone:foreArmNear.rotation',
        params: ['ArmNearElbow'],
        keys: [
          { at: [-95], value: foreNearLocalAng - 95 },
          { at: [0], value: foreNearLocalAng },
          { at: [95], value: foreNearLocalAng + 95 },
        ],
      },
      {
        target: 'bone:weaponGrip.rotation',
        params: ['WeaponWrist'],
        keys: [
          { at: [-165], value: -42 - 165 },
          { at: [0], value: -42 },
          { at: [165], value: -42 + 165 },
        ],
      },
      {
        target: 'bone:upperArmFar.rotation',
        params: ['ArmFarSwing'],
        keys: [
          { at: [-85], value: upperFarAng - 85 },
          { at: [0], value: upperFarAng },
          { at: [85], value: upperFarAng + 85 },
        ],
      },

      // Slash Smear & Skill Burst VFX
      {
        target: 'part:fx_slash_down.opacity',
        params: ['SlashDownAlpha'],
        keys: [
          { at: [0], value: 0 },
          { at: [1], value: 0.92 },
        ],
      },
      {
        target: 'bone:slashOrigin.scaleX',
        params: ['SlashDownSweep'],
        keys: [
          { at: [0], value: 0.86 },
          { at: [1], value: 1.16 },
        ],
      },
      {
        target: 'part:fx_slash_up.opacity',
        params: ['SlashUpAlpha'],
        keys: [
          { at: [0], value: 0 },
          { at: [1], value: 0.92 },
        ],
      },
      {
        target: 'part:fx_skill_ring.opacity',
        params: ['SkillBurstAlpha'],
        keys: [
          { at: [0], value: 0 },
          { at: [1], value: 0.9 },
        ],
      },
      {
        target: 'bone:skillRingBone.scaleX',
        params: ['SkillBurstScale'],
        keys: [
          { at: [0.4], value: 0.4 },
          { at: [1], value: 1.0 },
          { at: [1.6], value: 1.6 },
        ],
      },
      {
        target: 'bone:skillRingBone.scaleY',
        params: ['SkillBurstScale'],
        keys: [
          { at: [0.4], value: 0.4 },
          { at: [1], value: 1.0 },
          { at: [1.6], value: 1.6 },
        ],
      },

      // 60Hz Secondary Physics Outputs -> Hair, Ears & Coat Chains
      {
        target: 'bone:coat1.rotation',
        params: ['CoatSway1'],
        keys: [
          { at: [-42], value: 96 - 24 },
          { at: [0], value: 96 },
          { at: [42], value: 96 + 24 },
        ],
      },
      {
        target: 'bone:coat2.rotation',
        params: ['CoatSway2'],
        keys: [
          { at: [-48], value: 4 - 28 },
          { at: [0], value: 4 },
          { at: [48], value: 4 + 28 },
        ],
      },
      {
        target: 'bone:hairBack1.rotation',
        params: ['HairBackSway1'],
        keys: [
          { at: [-35], value: 100 - 18 },
          { at: [0], value: 100 },
          { at: [35], value: 100 + 18 },
        ],
      },
      {
        target: 'bone:hairBack2.rotation',
        params: ['HairBackSway2'],
        keys: [
          { at: [-42], value: 4 - 22 },
          { at: [0], value: 4 },
          { at: [42], value: 4 + 22 },
        ],
      },
      {
        target: 'bone:sideLockBack.rotation',
        params: ['SideLockSway'],
        keys: [
          { at: [-32], value: 92 - 18 },
          { at: [0], value: 92 },
          { at: [32], value: 92 + 18 },
        ],
      },
      {
        target: 'bone:sideLockFront.rotation',
        params: ['SideLockSway'],
        keys: [
          { at: [-32], value: 88 - 18 },
          { at: [0], value: 88 },
          { at: [32], value: 88 + 18 },
        ],
      },
      {
        target: 'bone:headAccBone.rotation',
        params: ['EarAccSway'],
        keys: [
          { at: [-36], value: -86 - 20 },
          { at: [0], value: -86 },
          { at: [36], value: -86 + 20 },
        ],
      },
    ],

    // ========================================================================
    // 3. Arknights Canonical Motion Library (Zero Robotic Pure Sine!)
    // ========================================================================
    animations: [
      // 3.1 IDLE (2.40s seamless loop: phase-lagged breathing, subtle poise, crisp step blink)
      {
        id: 'idle',
        duration: 2.4,
        loop: true,
        tracks: [
          {
            target: 'param:ExprMode',
            keys: [
              { t: 0, v: 0, ease: 'step' },
              { t: 1.42, v: 1, ease: 'step' },
              { t: 1.55, v: 0, ease: 'step' },
              { t: 2.4, v: 0, ease: 'step' },
            ],
          },
          {
            target: 'param:Breath',
            keys: [
              { t: 0.0, v: 0.0, ease: 'inOutSine' },
              { t: 1.1, v: 1.0, ease: 'inOutSine' },
              { t: 2.4, v: 0.0 },
            ],
          },
          {
            target: 'param:BodyBobY',
            keys: [
              { t: 0.0, v: 0.0, ease: 'inOutSine' },
              { t: 0.65, v: 2.5, ease: 'inOutSine' },
              { t: 1.25, v: 0.4, ease: 'inOutSine' },
              { t: 1.85, v: 1.8, ease: 'inOutSine' },
              { t: 2.4, v: 0.0 },
            ],
          },
          {
            target: 'param:HeadNod',
            offset: 0.18,
            keys: [
              { t: 0.0, v: 0.0, ease: 'smooth' },
              { t: 0.8, v: 2.8, ease: 'smooth' },
              { t: 1.7, v: -2.4, ease: 'smooth' },
              { t: 2.4, v: 0.0 },
            ],
          },
          {
            target: 'param:ArmNearElbow',
            offset: 0.14,
            keys: [
              { t: 0.0, v: 0, ease: 'smooth' },
              { t: 1.15, v: -5, ease: 'smooth' },
              { t: 2.4, v: 0 },
            ],
          },
        ],
      },

      // 3.2 MOVE / RUN (0.48s 4-Phase Athletic Hop-Stride: lowered pelvis keeps 2-Bone IK 100% within reach!)
      {
        id: 'run',
        duration: 0.48,
        loop: true,
        tracks: [
          {
            target: 'param:BodyBobY',
            keys: [
              { t: 0.0, v: 6, ease: 'outQuad' },
              { t: 0.08, v: 11, ease: 'inOutSine' },
              { t: 0.19, v: 2, ease: 'inQuad' },
              { t: 0.24, v: 6, ease: 'outQuad' },
              { t: 0.32, v: 11, ease: 'inOutSine' },
              { t: 0.43, v: 2, ease: 'inQuad' },
              { t: 0.48, v: 6 },
            ],
          },
          {
            target: 'param:Squash',
            keys: [
              { t: 0.0, v: 0.12, ease: 'outQuad' },
              { t: 0.08, v: 0.50, ease: 'inOutSine' },
              { t: 0.19, v: -0.35, ease: 'inQuad' },
              { t: 0.24, v: 0.12, ease: 'outQuad' },
              { t: 0.32, v: 0.50, ease: 'inOutSine' },
              { t: 0.43, v: -0.35, ease: 'inQuad' },
              { t: 0.48, v: 0.12 },
            ],
          },
          {
            target: 'param:BodyLean',
            keys: [
              { t: 0.0, v: 9, ease: 'smooth' },
              { t: 0.12, v: 12, ease: 'smooth' },
              { t: 0.24, v: 9, ease: 'smooth' },
              { t: 0.36, v: 12, ease: 'smooth' },
              { t: 0.48, v: 9 },
            ],
          },
          {
            target: 'param:HeadNod',
            keys: [
              { t: 0.0, v: -4, ease: 'smooth' },
              { t: 0.12, v: 2.5, ease: 'smooth' },
              { t: 0.24, v: -4, ease: 'smooth' },
              { t: 0.36, v: 2.5, ease: 'smooth' },
              { t: 0.48, v: -4 },
            ],
          },
          // Near Leg 4-Phase Stride (0 IK hyper-extension, snappy lifted swing!)
          {
            target: 'param:FootNearX',
            keys: [
              { t: 0.0, v: 20, ease: 'linear' },
              { t: 0.24, v: -20, ease: 'inOutCubic' },
              { t: 0.48, v: 20 },
            ],
          },
          {
            target: 'param:FootNearY',
            keys: [
              { t: 0.0, v: 0, ease: 'linear' },
              { t: 0.18, v: -4, ease: 'outQuad' },
              { t: 0.35, v: -22, ease: 'inQuad' },
              { t: 0.48, v: 0 },
            ],
          },
          // Far Leg exact half-cycle phase shift (`offset = 0.24s`)
          {
            target: 'param:FootFarX',
            offset: 0.24,
            keys: [
              { t: 0.0, v: 20, ease: 'linear' },
              { t: 0.24, v: -20, ease: 'inOutCubic' },
              { t: 0.48, v: 20 },
            ],
          },
          {
            target: 'param:FootFarY',
            offset: 0.24,
            keys: [
              { t: 0.0, v: 0, ease: 'linear' },
              { t: 0.18, v: -4, ease: 'outQuad' },
              { t: 0.35, v: -22, ease: 'inQuad' },
              { t: 0.48, v: 0 },
            ],
          },
          // Counter-swinging arms
          {
            target: 'param:ArmNearShoulder',
            keys: [
              { t: 0.0, v: -22, ease: 'inOutSine' },
              { t: 0.24, v: 22, ease: 'inOutSine' },
              { t: 0.48, v: -22 },
            ],
          },
          {
            target: 'param:ArmFarSwing',
            keys: [
              { t: 0.0, v: 26, ease: 'inOutSine' },
              { t: 0.24, v: -24, ease: 'inOutSine' },
              { t: 0.48, v: 26 },
            ],
          },
        ],
      },

      // 3.3 JUMP (0.56s airborne arc compatible with `SpineActor3D`)
      {
        id: 'jump',
        duration: 0.56,
        loop: false,
        tracks: [
          {
            target: 'param:BodyBobY',
            keys: [
              { t: 0.0, v: 10, ease: 'outCubic' },
              { t: 0.22, v: -26, ease: 'inOutSine' },
              { t: 0.44, v: 8, ease: 'outQuad' },
              { t: 0.56, v: 0 },
            ],
          },
          {
            target: 'param:Squash',
            keys: [
              { t: 0.0, v: 0.6, ease: 'outQuad' },
              { t: 0.16, v: -0.75, ease: 'inOutSine' },
              { t: 0.44, v: 0.5, ease: 'outQuad' },
              { t: 0.56, v: 0 },
            ],
          },
          {
            target: 'param:FootNearY',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.22, v: -34, ease: 'inQuad' },
              { t: 0.46, v: 0 },
            ],
          },
          {
            target: 'param:FootFarY',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.22, v: -24, ease: 'inQuad' },
              { t: 0.46, v: 0 },
            ],
          },
          {
            target: 'param:ArmNearShoulder',
            keys: [
              { t: 0.0, v: 14, ease: 'outQuad' },
              { t: 0.22, v: -42, ease: 'inOutSine' },
              { t: 0.56, v: 0 },
            ],
          },
        ],
      },

      // 3.4 ATTACK_1 (0.46s Arknights 3:1:2:4 Snappy Overhead Cleave + Crescent Smear VFX!)
      {
        id: 'attack_1',
        duration: 0.46,
        loop: false,
        events: [{ t: 0.16, name: 'hit' }],
        tracks: [
          {
            target: 'param:ExprMode',
            keys: [
              { t: 0.0, v: 0, ease: 'step' },
              { t: 0.11, v: 2, ease: 'step' },
              { t: 0.36, v: 0, ease: 'step' },
            ],
          },
          // Exact CW cleave from `+128 deg` side-swept rest -> `-112 deg` overhead -> 0.05s SNAP `+38 deg` forward-down!
          {
            target: 'param:ArmNearShoulder',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.13, v: -116, ease: [0.12, 0.92, 0.22, 1.0] },
              { t: 0.18, v: -44, ease: 'outBack' },
              { t: 0.28, v: -38, ease: 'inOutCubic' },
              { t: 0.46, v: 0 },
            ],
          },
          {
            target: 'param:ArmNearElbow',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.13, v: -32, ease: [0.12, 0.92, 0.22, 1.0] },
              { t: 0.18, v: 14, ease: 'outQuad' },
              { t: 0.28, v: 12, ease: 'inOutSine' },
              { t: 0.46, v: 0 },
            ],
          },
          {
            target: 'param:WeaponWrist',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.13, v: -82, ease: [0.12, 0.92, 0.22, 1.0] },
              { t: 0.18, v: -76, ease: 'outBack' },
              { t: 0.29, v: -70, ease: 'inOutCubic' },
              { t: 0.46, v: 0 },
            ],
          },
          {
            target: 'param:BodyLean',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.13, v: -10, ease: [0.15, 0.9, 0.25, 1.0] },
              { t: 0.19, v: 16, ease: 'outQuad' },
              { t: 0.30, v: 12, ease: 'inOutSine' },
              { t: 0.46, v: 0 },
            ],
          },
          {
            target: 'param:BodyBobY',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.13, v: 4, ease: 'inQuad' },
              { t: 0.19, v: 11, ease: 'outQuad' },
              { t: 0.46, v: 0 },
            ],
          },
          {
            target: 'param:FootNearX',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.13, v: -8, ease: 'outCubic' },
              { t: 0.19, v: 20, ease: 'inOutSine' },
              { t: 0.46, v: 0 },
            ],
          },
          // Crescent Slash Smear Arc flashes precisely across the 2-frame snap!
          {
            target: 'param:SlashDownAlpha',
            keys: [
              { t: 0.0, v: 0, ease: 'step' },
              { t: 0.14, v: 1, ease: 'outQuad' },
              { t: 0.27, v: 0 },
            ],
          },
          {
            target: 'param:SlashDownSweep',
            keys: [
              { t: 0.14, v: 0, ease: 'outCubic' },
              { t: 0.26, v: 1 },
            ],
          },
        ],
      },

      // 3.5 ATTACK_2 (0.48s Rising Reverse Slash Combo + Upward Smear VFX)
      {
        id: 'attack_2',
        duration: 0.48,
        loop: false,
        events: [{ t: 0.16, name: 'hit' }],
        tracks: [
          {
            target: 'param:ExprMode',
            keys: [
              { t: 0.0, v: 2, ease: 'step' },
              { t: 0.36, v: 0, ease: 'step' },
            ],
          },
          {
            target: 'param:ArmNearShoulder',
            keys: [
              { t: 0.0, v: -36, ease: 'outQuad' },
              { t: 0.12, v: -36, ease: [0.12, 0.92, 0.22, 1.0] },
              { t: 0.18, v: -110, ease: 'outBack' },
              { t: 0.30, v: -96, ease: 'inOutCubic' },
              { t: 0.48, v: 0 },
            ],
          },
          {
            target: 'param:ArmNearElbow',
            keys: [
              { t: 0.0, v: 12, ease: 'outQuad' },
              { t: 0.12, v: 12, ease: [0.12, 0.92, 0.22, 1.0] },
              { t: 0.18, v: -24, ease: 'outQuad' },
              { t: 0.48, v: 0 },
            ],
          },
          {
            target: 'param:WeaponWrist',
            keys: [
              { t: 0.0, v: -68, ease: 'outQuad' },
              { t: 0.12, v: -68, ease: [0.12, 0.92, 0.22, 1.0] },
              { t: 0.18, v: -82, ease: 'outBack' },
              { t: 0.48, v: 0 },
            ],
          },
          {
            target: 'param:BodyBobY',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.12, v: 9, ease: 'outCubic' },
              { t: 0.19, v: 2, ease: 'inOutSine' },
              { t: 0.48, v: 0 },
            ],
          },
          {
            target: 'param:BodyLean',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.12, v: 14, ease: 'outQuad' },
              { t: 0.18, v: -10, ease: 'inOutSine' },
              { t: 0.48, v: 0 },
            ],
          },
          {
            target: 'param:SlashUpAlpha',
            keys: [
              { t: 0.0, v: 0, ease: 'step' },
              { t: 0.13, v: 1, ease: 'outQuad' },
              { t: 0.27, v: 0 },
            ],
          },
        ],
      },

      // 3.6 SKILL (0.76s Arknights Ultimate Arts Burst: Airborne Leap Charge -> Ground Ring + Heavy Cleave)
      {
        id: 'skill',
        duration: 0.76,
        loop: false,
        events: [{ t: 0.38, name: 'skill_hit' }],
        tracks: [
          {
            target: 'param:ExprMode',
            keys: [
              { t: 0.0, v: 2, ease: 'step' },
              { t: 0.64, v: 0, ease: 'step' },
            ],
          },
          {
            target: 'param:BodyBobY',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.08, v: 6, ease: 'outCubic' },
              { t: 0.28, v: -18, ease: 'inCubic' },
              { t: 0.38, v: 10, ease: 'outBack' },
              { t: 0.76, v: 0 },
            ],
          },
          {
            target: 'param:FootNearY',
            keys: [
              { t: 0.0, v: 0, ease: 'outCubic' },
              { t: 0.28, v: -20, ease: 'inCubic' },
              { t: 0.38, v: 0, ease: 'outQuad' },
              { t: 0.76, v: 0 },
            ],
          },
          {
            target: 'param:FootFarY',
            keys: [
              { t: 0.0, v: 0, ease: 'outCubic' },
              { t: 0.28, v: -15, ease: 'inCubic' },
              { t: 0.38, v: 0, ease: 'outQuad' },
              { t: 0.76, v: 0 },
            ],
          },
          {
            target: 'param:FootNearX',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.30, v: -8, ease: 'outQuad' },
              { t: 0.38, v: 18, ease: 'outBack' },
              { t: 0.76, v: 0 },
            ],
          },
          {
            target: 'param:ArmNearShoulder',
            keys: [
              { t: 0.0, v: 0, ease: 'outCubic' },
              { t: 0.30, v: -122, ease: [0.1, 0.95, 0.2, 1.0] },
              { t: 0.37, v: -64, ease: 'outBack' },
              { t: 0.54, v: -56, ease: 'inOutCubic' },
              { t: 0.76, v: 0 },
            ],
          },
          {
            target: 'param:ArmNearElbow',
            keys: [
              { t: 0.0, v: 0, ease: 'outCubic' },
              { t: 0.30, v: -28, ease: [0.1, 0.95, 0.2, 1.0] },
              { t: 0.37, v: 12, ease: 'outQuad' },
              { t: 0.76, v: 0 },
            ],
          },
          {
            target: 'param:WeaponWrist',
            keys: [
              { t: 0.0, v: 0, ease: 'outCubic' },
              { t: 0.30, v: -88, ease: [0.1, 0.95, 0.2, 1.0] },
              { t: 0.37, v: -46, ease: 'outBack' },
              { t: 0.76, v: 0 },
            ],
          },
          {
            target: 'param:SkillBurstAlpha',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.14, v: 0.75, ease: 'linear' },
              { t: 0.38, v: 1.0, ease: 'outQuad' },
              { t: 0.68, v: 0 },
            ],
          },
          {
            target: 'param:SkillBurstScale',
            keys: [
              { t: 0.0, v: 0.45, ease: 'outCubic' },
              { t: 0.34, v: 0.95, ease: 'outCubic' },
              { t: 0.68, v: 1.55 },
            ],
          },
          {
            target: 'param:SlashDownAlpha',
            keys: [
              { t: 0.0, v: 0, ease: 'step' },
              { t: 0.34, v: 1, ease: 'outQuad' },
              { t: 0.52, v: 0 },
            ],
          },
          {
            target: 'param:SlashDownSweep',
            keys: [
              { t: 0.34, v: 0, ease: 'outCubic' },
              { t: 0.50, v: 1 },
            ],
          },
        ],
      },

      // 3.7 HIT (0.40s Recoil)
      {
        id: 'hit',
        duration: 0.4,
        loop: false,
        tracks: [
          {
            target: 'param:ExprMode',
            keys: [
              { t: 0.0, v: 1, ease: 'step' },
              { t: 0.28, v: 0, ease: 'step' },
            ],
          },
          {
            target: 'param:BodyLean',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.08, v: -22, ease: 'inOutSine' },
              { t: 0.24, v: 8, ease: 'inOutSine' },
              { t: 0.4, v: 0 },
            ],
          },
          {
            target: 'param:Squash',
            keys: [
              { t: 0.0, v: 0, ease: 'outQuad' },
              { t: 0.07, v: 0.65, ease: 'inOutSine' },
              { t: 0.4, v: 0 },
            ],
          },
        ],
      },
    ],
  };

  const r2dPath = path.join(charDir, `${spec.char_id}.r2d.json`);
  fs.writeFileSync(r2dPath, JSON.stringify(model, null, 2) + '\n', 'utf8');
  console.log(`[RIG_WRITTEN] ${r2dPath}`);

  // 4. Validate via `rev2d validate`
  const valOut = runRev2d(['validate', r2dPath]);
  console.log(valOut.trim());

  // 5. Export Spine 4.2 (`--straight-alpha`) + Mix-and-Match Weapon Skins
  const exportCfg = spec.export || {};
  const outSpinesDir = path.resolve(charDir, exportCfg.out_dir || 'exports');
  const spineName = exportCfg.spine_name || `spn_${spec.char_id}`;
  fs.mkdirSync(outSpinesDir, { recursive: true });

  const expOut = runRev2d([
    'export',
    'spine',
    r2dPath,
    '-o',
    outSpinesDir,
    '--name',
    spineName,
    '--straight-alpha',
  ]);
  console.log(expOut.trim());

  // Partition `weapon_primary` and `weapon_secondary` into native Spine 4.2 Mix-and-Match Skins
  // (also aliases `weapon/sword` and `weapon/scythe` if requested for drop-in `SpineActor3D` compatibility!)
  const rawSpineJsonPath = path.join(outSpinesDir, `${spineName}.json`);
  const finalSpineJsonPath = path.join(outSpinesDir, `${spineName}.spine-json`);
  const spineDoc = JSON.parse(fs.readFileSync(rawSpineJsonPath, 'utf8'));

  const skinMap = exportCfg.weapon_skin_names || {
    'weapon/primary': ['weapon_primary'],
    'weapon/secondary': ['weapon_secondary'],
  };

  const modularSet = new Set(Object.values(skinMap).flat());
  if (Array.isArray(spineDoc.slots)) {
    for (const slot of spineDoc.slots) {
      if (modularSet.has(slot.name)) {
        slot.color = 'ffffffff';
      }
    }
  }
  if (spineDoc.animations) {
    for (const anim of Object.values(spineDoc.animations)) {
      if (anim.slots) {
        for (const sName of modularSet) {
          delete anim.slots[sName];
        }
      }
    }
  }

  const defaultSkin = spineDoc.skins.find((s) => s.name === 'default');
  const defaultAtts = defaultSkin.attachments || {};
  const partitionedSkins = [{ name: 'default', attachments: {} }];
  for (const [slotName, attObj] of Object.entries(defaultAtts)) {
    if (!modularSet.has(slotName)) {
      partitionedSkins[0].attachments[slotName] = attObj;
    }
  }
  for (const [skinName, slotNames] of Object.entries(skinMap)) {
    const entry = { name: skinName, attachments: {} };
    for (const sName of slotNames) {
      if (defaultAtts[sName]) {
        entry.attachments[sName] = defaultAtts[sName];
      }
    }
    partitionedSkins.push(entry);
  }
  spineDoc.skins = partitionedSkins;

  fs.writeFileSync(finalSpineJsonPath, JSON.stringify(spineDoc), 'utf8');
  fs.unlinkSync(rawSpineJsonPath);

  if (exportCfg.write_godot_tres !== false) {
    const relFromRepo = path.relative(REPO_ROOT, outSpinesDir).replace(/\\/g, '/');
    const resDir = `res://${relFromRepo}`;
    const mix = exportCfg.default_mix ?? 0.12;
    const tresContent = `[gd_resource type="SpineSkeletonDataResource" format=3]

[ext_resource type="SpineAtlasResource" path="${resDir}/${spineName}.atlas" id="1_atlas"]
[ext_resource type="SpineSkeletonFileResource" path="${resDir}/${spineName}.spine-json" id="2_skel"]

[resource]
atlas_res = ExtResource("1_atlas")
skeleton_file_res = ExtResource("2_skel")
default_mix = ${mix}
`;
    const tresPath = path.join(outSpinesDir, `${spineName}_data.tres`);
    fs.writeFileSync(tresPath, tresContent, 'utf8');
    console.log(`[GODOT_TRES_READY] ${tresPath}`);
  }

  console.log(
    `[BUILD_ARKNIGHTS_RIG_OK] spine=${finalSpineJsonPath} skins=${spineDoc.skins.map((s) => s.name).join(',')}`,
  );
}

buildRig(parseArgs());
