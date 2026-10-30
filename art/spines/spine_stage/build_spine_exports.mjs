#!/usr/bin/env node
/**
 * Builds Rev2D 2D action rigs (`hero_knight.r2d.json` & `straw_golem.r2d.json`),
 * runs Rev2D validation + contact sheet rendering, exports Spine 4.2.00 JSON + Atlas + PNG
 * (`--straight-alpha` for crisp 3D Alpha-Scissor silhouettes), and partitions equipment
 * parts into native Spine 4.2 Mix-and-Match Skins (`weapon/*`, `outfit/*`).
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../../..');
const OUT_SPINES_DIR = path.join(REPO_ROOT, 'src/test/spine_stage/assets/spines');
const DEFAULT_ADDON_BIN = path.join(REPO_ROOT, 'addons/rev2d/runtime/bin/rev2d.js');
const DEFAULT_GLOBAL_BIN = path.join(os.homedir(), '.gemini/config/plugins/rev2d/runtime/bin/rev2d.js');
const REV2D_BIN =
  process.env.REV2D_BIN ||
  (fs.existsSync(DEFAULT_ADDON_BIN) ? DEFAULT_ADDON_BIN : DEFAULT_GLOBAL_BIN);
const SCRATCH_PREVIEW_DIR = process.env.REV2D_PREVIEW_DIR || '';

if (!REV2D_BIN || !fs.existsSync(REV2D_BIN)) {
  console.error('Missing Rev2D CLI binary (checked REV2D_BIN, addons/rev2d, and ~/.gemini/config/plugins/rev2d)');
  process.exit(1);
}

fs.mkdirSync(__dirname, { recursive: true });
fs.mkdirSync(OUT_SPINES_DIR, { recursive: true });
if (SCRATCH_PREVIEW_DIR) {
  fs.mkdirSync(SCRATCH_PREVIEW_DIR, { recursive: true });
}

// ============================================================================
// 1. HERO KNIGHT RIG (`hero_knight.r2d.json`)
//    Canvas: 512x512, Ground contact at (256, 468), Facing +X (Screen Right)
// ============================================================================
const heroModel = {
  format: 'rev2d',
  version: 1,
  meta: {
    name: 'hero_knight',
    width: 512,
    height: 512,
    background: 'rgba(0,0,0,0)',
    fps: 30,
    author: 'Slacker Survivors Rev2D Pipeline',
    description: '2.5D HD-2D Action Hero with dual-leg IK, 3-segment pendulum cape & plume physics, 5 combat animations, 3 weapons and 3 armor outfits.'
  },
  parameters: [
    { id: 'BodyBobY', min: -40, max: 40, default: 0, group: 'Body', description: 'Vertical hip offset (+ = down crouch, - = up leap).' },
    { id: 'BodyLean', min: -35, max: 35, default: 0, group: 'Body', description: 'Torso forward/back tilt in degrees (+ = forward clockwise).' },
    { id: 'HeadNod', min: -25, max: 25, default: 0, group: 'Head', description: 'Head pitch in degrees.' },
    { id: 'EyeBlink', min: 0, max: 1, default: 0, group: 'Head', description: '0 = open, 1 = closed.' },
    { id: 'FootFX', min: -80, max: 80, default: 0, group: 'LegIK', description: 'Front foot horizontal stride offset.' },
    { id: 'FootFY', min: -70, max: 20, default: 0, group: 'LegIK', description: 'Front foot vertical lift (- = up).' },
    { id: 'FootBX', min: -80, max: 80, default: 0, group: 'LegIK', description: 'Back foot horizontal stride offset.' },
    { id: 'FootBY', min: -70, max: 20, default: 0, group: 'LegIK', description: 'Back foot vertical lift (- = up).' },
    { id: 'ArmBackRot', min: -90, max: 90, default: 0, group: 'Arms', description: 'Back arm swing delta.' },
    { id: 'ArmFrontShoulder', min: -130, max: 120, default: 0, group: 'Arms', description: 'Weapon shoulder swing delta.' },
    { id: 'ArmFrontElbow', min: -90, max: 90, default: 0, group: 'Arms', description: 'Weapon elbow bend delta.' },
    { id: 'WeaponWrist', min: -120, max: 140, default: 0, group: 'Arms', description: 'Weapon wrist rotation delta.' },
    { id: 'SlashAlpha', min: 0, max: 1, default: 0, group: 'VFX', description: 'Downward slash crescent opacity.' },
    { id: 'SlashUpAlpha', min: 0, max: 1, default: 0, group: 'VFX', description: 'Uppercut slash crescent opacity.' },
    { id: 'Cape1', min: -55, max: 55, default: 0, group: 'Physics', description: 'Cape segment 1 pendulum angle.' },
    { id: 'Cape2', min: -55, max: 55, default: 0, group: 'Physics', description: 'Cape segment 2 pendulum angle.' },
    { id: 'Cape3', min: -55, max: 55, default: 0, group: 'Physics', description: 'Cape segment 3 pendulum angle.' },
    { id: 'Plume1', min: -50, max: 50, default: 0, group: 'Physics', description: 'Helm plume segment 1 pendulum angle.' },
    { id: 'Plume2', min: -50, max: 50, default: 0, group: 'Physics', description: 'Helm plume segment 2 pendulum angle.' }
  ],
  bones: [
    { id: 'ground', x: 256, y: 468, length: 0, description: 'Ground contact anchor (y=0 in 3D).' },
    { id: 'hip', parent: 'ground', x: 0, y: -86, length: 0, description: 'Pelvis center (256, 382).' },
    { id: 'torso', parent: 'hip', x: 0, y: -64, length: 0, description: 'Chest pivot (256, 318).' },
    { id: 'head', parent: 'torso', x: 4, y: -28, length: 0, description: 'Neck/head pivot (260, 290).' },

    // Cape 3-segment pendulum chain from upper back (236, 304)
    { id: 'cape1', parent: 'torso', x: -20, y: -14, rotation: 118, length: 48 },
    { id: 'cape2', parent: 'cape1', x: 48, y: 0, rotation: -8, length: 48 },
    { id: 'cape3', parent: 'cape2', x: 48, y: 0, rotation: -8, length: 46 },

    // Plume 2-segment pendulum chain from crown of head (240, 200)
    { id: 'plume1', parent: 'head', x: -20, y: -90, rotation: 148, length: 34 },
    { id: 'plume2', parent: 'plume1', x: 34, y: 0, rotation: -14, length: 30 },

    // Back leg 2-bone IK chain: hip(-10, 6) = (246, 388) -> footBackTarget (238, 468)
    { id: 'thighBack', parent: 'hip', x: -10, y: 6, rotation: 72, length: 48 },
    { id: 'shinBack', parent: 'thighBack', x: 48, y: 0, rotation: 28, length: 46 },
    { id: 'footBackTarget', parent: 'ground', x: -18, y: 0, length: 0 },

    // Front leg 2-bone IK chain: hip(10, 6) = (266, 388) -> footFrontTarget (276, 468)
    { id: 'thighFront', parent: 'hip', x: 10, y: 6, rotation: 62, length: 48 },
    { id: 'shinFront', parent: 'thighFront', x: 48, y: 0, rotation: 30, length: 46 },
    { id: 'footFrontTarget', parent: 'ground', x: 20, y: 0, length: 0 },

    // Offhand arm (screen right / forward side)
    { id: 'armBack', parent: 'torso', x: 22, y: -8, rotation: 48, length: 48 },

    // Main weapon arm & grip socket
    { id: 'upperArmFront', parent: 'torso', x: -16, y: -8, rotation: 62, length: 38 },
    { id: 'foreArmFront', parent: 'upperArmFront', x: 38, y: 0, rotation: -46, length: 38 },
    { id: 'weaponGrip', parent: 'foreArmFront', x: 36, y: 0, rotation: -66, length: 110 },

    // Slash arc anchor in front of chest
    { id: 'slashOrigin', parent: 'torso', x: 28, y: -10, length: 0 }
  ],
  parts: [
    // --- OUTFIT CLOAKS (skinned to torso + cape1..3, z = 4) ---
    {
      id: 'cloakRanger',
      skin: { bones: ['torso', 'cape1', 'cape2', 'cape3'], weights: 'auto', falloff: 2.2 },
      shape: {
        type: 'polygon',
        points: [
          248, 294, 224, 304, 198, 338, 178, 384, 166, 434,
          198, 444, 228, 436, 250, 404, 258, 356, 258, 304
        ],
        detail: 6
      },
      fill: {
        type: 'linear',
        from: [248, 294],
        to: [176, 438],
        stops: [[0, '#1f6f54'], [0.6, '#14533d'], [1, '#0d3628']]
      },
      stroke: { color: '#111622', width: 3.5 },
      z: 4
    },
    {
      id: 'cloakRoyal',
      skin: { bones: ['torso', 'cape1', 'cape2', 'cape3'], weights: 'auto', falloff: 2.2 },
      shape: {
        type: 'polygon',
        points: [
          250, 292, 222, 302, 192, 336, 170, 386, 158, 442,
          194, 452, 232, 442, 252, 408, 260, 356, 260, 304
        ],
        detail: 6
      },
      fill: {
        type: 'linear',
        from: [250, 292],
        to: [168, 446],
        stops: [[0, '#b91c1c'], [0.65, '#7f1d1d'], [1, '#450a0a']]
      },
      stroke: { color: '#f59e0b', width: 3.5 },
      z: 4.1
    },
    {
      id: 'cloakAbyss',
      skin: { bones: ['torso', 'cape1', 'cape2', 'cape3'], weights: 'auto', falloff: 2.2 },
      shape: {
        type: 'polygon',
        points: [
          248, 292, 220, 302, 188, 340, 164, 392, 152, 448,
          182, 430, 198, 454, 222, 428, 244, 444, 256, 388, 260, 304
        ],
        detail: 6
      },
      fill: {
        type: 'linear',
        from: [248, 292],
        to: [160, 448],
        stops: [[0, '#4c1d95'], [0.55, '#2e1065'], [1, '#090d16']]
      },
      stroke: { color: '#38bdf8', width: 3.0 },
      z: 4.2
    },

    // --- BACK ARM & BUCKLER (z = 8..9) ---
    {
      id: 'armBackSleeve',
      parent: 'armBack',
      shape: { type: 'rect', x: 268, y: 298, w: 22, h: 46, radius: 10 },
      fill: '#334155',
      stroke: { color: '#111622', width: 3.2 },
      z: 8
    },
    {
      id: 'armBackGauntlet',
      parent: 'armBack',
      shape: { type: 'ellipse', cx: 296, cy: 342, rx: 11, ry: 11, detail: 4 },
      fill: '#94a3b8',
      stroke: { color: '#111622', width: 3.2 },
      z: 9
    },

    // --- BACK LEG (z = 12..14) ---
    {
      id: 'legBackThigh',
      parent: 'thighBack',
      shape: { type: 'rect', x: 235, y: 384, w: 22, h: 48, radius: 9 },
      fill: '#1e293b',
      stroke: { color: '#111622', width: 3.2 },
      z: 12
    },
    {
      id: 'legBackShin',
      parent: 'shinBack',
      shape: {
        type: 'path',
        d: 'M 232 426 L 254 426 L 258 466 L 228 466 Q 228 450 232 426 Z',
        detail: 6
      },
      fill: '#334155',
      stroke: { color: '#111622', width: 3.2 },
      z: 13
    },

    // --- FRONT LEG (z = 16..18) ---
    {
      id: 'legFrontThigh',
      parent: 'thighFront',
      shape: { type: 'rect', x: 256, y: 384, w: 24, h: 48, radius: 10 },
      fill: '#334155',
      stroke: { color: '#111622', width: 3.4 },
      z: 16
    },
    {
      id: 'legFrontBoot',
      parent: 'shinFront',
      shape: {
        type: 'path',
        d: 'M 258 424 L 282 424 L 292 466 L 254 466 Z',
        detail: 6
      },
      fill: {
        type: 'linear',
        from: [258, 424],
        to: [288, 466],
        stops: [[0, '#64748b'], [1, '#334155']]
      },
      stroke: { color: '#111622', width: 3.5 },
      z: 18
    },

    // --- TORSO & TUNIC (z = 22..26) ---
    {
      id: 'torsoArmor',
      parent: 'torso',
      shape: {
        type: 'path',
        d: 'M 226 294 Q 256 284 288 294 L 294 388 Q 258 398 222 388 Z',
        detail: 8
      },
      fill: {
        type: 'linear',
        from: [226, 290],
        to: [290, 392],
        stops: [[0, '#94a3b8'], [0.45, '#64748b'], [1, '#334155']]
      },
      stroke: { color: '#111622', width: 3.8 },
      z: 22
    },
    {
      id: 'torsoTabard',
      parent: 'torso',
      shape: {
        type: 'path',
        d: 'M 244 304 L 276 304 L 280 404 L 260 418 L 240 404 Z',
        detail: 6
      },
      fill: '#e2e8f0',
      stroke: { color: '#111622', width: 3.0 },
      z: 24
    },
    {
      id: 'torsoBelt',
      parent: 'torso',
      shape: { type: 'rect', x: 223, y: 368, w: 70, h: 15, radius: 4 },
      fill: '#78350f',
      stroke: { color: '#111622', width: 3.0 },
      z: 25
    },
    {
      id: 'torsoBuckle',
      parent: 'torso',
      shape: { type: 'rect', x: 252, y: 365, w: 18, h: 20, radius: 4 },
      fill: '#fbbf24',
      stroke: { color: '#111622', width: 2.8 },
      z: 26
    },

    // --- HEAD & EXPRESSIVE FACE (z = 32..38) ---
    {
      id: 'headBase',
      parent: 'head',
      shape: { type: 'ellipse', cx: 262, cy: 244, rx: 44, ry: 42, detail: 10 },
      fill: {
        type: 'radial',
        center: [272, 234],
        radius: 52,
        stops: [[0, '#fde68a'], [0.55, '#fcd34d'], [1, '#d97706']]
      },
      stroke: { color: '#111622', width: 3.8 },
      z: 32
    },
    {
      id: 'faceVisorShadow',
      parent: 'head',
      shape: { type: 'ellipse', cx: 272, cy: 246, rx: 32, ry: 24, detail: 8 },
      fill: '#1e293b',
      stroke: { color: '#0f172a', width: 2.5 },
      z: 34
    },
    {
      id: 'eyeLeft',
      parent: 'head',
      shape: { type: 'ellipse', cx: 264, cy: 246, rx: 5.5, ry: 9.5, detail: 5 },
      fill: '#f8fafc',
      z: 36
    },
    {
      id: 'eyeRight',
      parent: 'head',
      shape: { type: 'ellipse', cx: 288, cy: 246, rx: 5.0, ry: 9.0, detail: 5 },
      fill: '#f8fafc',
      z: 36
    },
    {
      id: 'scarfNeck',
      parent: 'torso',
      shape: { type: 'rect', x: 230, y: 280, w: 62, h: 22, radius: 10 },
      fill: '#dc2626',
      stroke: { color: '#111622', width: 3.2 },
      z: 38
    },

    // --- OUTFIT HEADGEAR & PLUMES (z = 42..46) ---
    {
      id: 'plumeRanger',
      skin: { bones: ['head', 'plume1', 'plume2'], weights: 'auto', falloff: 2.0 },
      shape: {
        type: 'polygon',
        points: [242, 200, 212, 178, 184, 174, 198, 198, 226, 212],
        detail: 5
      },
      fill: '#34d399',
      stroke: { color: '#111622', width: 3.0 },
      z: 41
    },
    {
      id: 'hoodRanger',
      parent: 'head',
      shape: {
        type: 'path',
        d: 'M 212 258 C 210 206 244 186 286 196 C 304 202 312 218 308 232 C 288 220 250 222 232 258 Z',
        detail: 10
      },
      fill: {
        type: 'linear',
        from: [216, 192],
        to: [304, 256],
        stops: [[0, '#10b981'], [1, '#065f46']]
      },
      stroke: { color: '#111622', width: 3.6 },
      z: 43
    },

    {
      id: 'plumeRoyal',
      skin: { bones: ['head', 'plume1', 'plume2'], weights: 'auto', falloff: 2.0 },
      shape: {
        type: 'polygon',
        points: [250, 194, 214, 162, 176, 168, 188, 202, 224, 214],
        detail: 5
      },
      fill: {
        type: 'linear',
        from: [250, 170],
        to: [176, 204],
        stops: [[0, '#ef4444'], [1, '#991b1b']]
      },
      stroke: { color: '#111622', width: 3.2 },
      z: 41.2
    },
    {
      id: 'crownRoyal',
      parent: 'head',
      shape: {
        type: 'path',
        d: 'M 214 238 L 220 194 L 244 212 L 266 182 L 286 210 L 308 192 L 308 236 Q 262 224 214 238 Z',
        detail: 8
      },
      fill: {
        type: 'linear',
        from: [214, 184],
        to: [308, 238],
        stops: [[0, '#fde047'], [0.5, '#f59e0b'], [1, '#b45309']]
      },
      stroke: { color: '#111622', width: 3.6 },
      z: 44
    },

    {
      id: 'plumeAbyss',
      skin: { bones: ['head', 'plume1', 'plume2'], weights: 'auto', falloff: 2.0 },
      shape: {
        type: 'polygon',
        points: [244, 198, 206, 170, 172, 182, 192, 210, 228, 216],
        detail: 5
      },
      fill: '#38bdf8',
      stroke: { color: '#0f172a', width: 3.0 },
      z: 41.4
    },
    {
      id: 'hornsAbyss',
      parent: 'head',
      shape: {
        type: 'path',
        d: 'M 216 244 C 204 202 222 162 246 154 C 238 184 242 204 256 212 L 280 212 C 292 200 298 180 292 154 C 316 166 322 206 308 240 Q 262 224 216 244 Z',
        detail: 10
      },
      fill: {
        type: 'linear',
        from: [216, 154],
        to: [312, 244],
        stops: [[0, '#e2e8f0'], [0.45, '#64748b'], [1, '#1e1b4b']]
      },
      stroke: { color: '#111622', width: 3.6 },
      z: 45
    },

    // --- WEAPONS ON `weaponGrip` (z = 52..58) ---
    // Grip origin in setup pose: let's check bone math!
    // hip=(256,382), torso=(256,318)
    // upperArmFront=(240,310), rot=62, len=38 -> tip = (240 + 38*cos62, 310 + 38*sin62) = (257.8, 343.5)
    // foreArmFront rot=62-46=16, len=36 -> weaponGrip origin = (257.8 + 36*cos16, 343.5 + 36*sin16) = (292.4, 353.5)
    // weaponGrip world rot = 16 - 66 = -50 deg (pointing up-right along +0.643x, -0.766y)!
    // Weapon 1: Silver Knight Greatsword (`weapon/sword`)
    {
      id: 'wpnSwordBlade',
      parent: 'weaponGrip',
      shape: {
        type: 'polygon',
        points: [
          296, 340, 384, 234, 408, 216, 398, 246, 310, 352
        ],
        detail: 4
      },
      fill: {
        type: 'linear',
        from: [296, 346],
        to: [408, 216],
        stops: [[0, '#94a3b8'], [0.45, '#f8fafc'], [1, '#bae6fd']]
      },
      stroke: { color: '#111622', width: 3.8 },
      z: 52
    },
    {
      id: 'wpnSwordGuard',
      parent: 'weaponGrip',
      shape: {
        type: 'polygon',
        points: [
          278, 332, 326, 366, 318, 376, 270, 342
        ],
        detail: 2
      },
      fill: '#fbbf24',
      stroke: { color: '#111622', width: 3.4 },
      z: 54
    },
    {
      id: 'wpnSwordPommel',
      parent: 'weaponGrip',
      shape: {
        type: 'polygon',
        points: [
          292, 352, 274, 376, 284, 384, 302, 360
        ],
        detail: 2
      },
      fill: '#38bdf8',
      stroke: { color: '#111622', width: 3.2 },
      z: 53
    },

    // Weapon 2: Crimson Reaper Scythe (`weapon/scythe`)
    {
      id: 'wpnScytheShaft',
      parent: 'weaponGrip',
      shape: {
        type: 'polygon',
        points: [
          264, 388, 392, 232, 402, 240, 274, 396
        ],
        detail: 3
      },
      fill: '#3f3f46',
      stroke: { color: '#111622', width: 3.6 },
      z: 52.2
    },
    {
      id: 'wpnScytheBlade',
      parent: 'weaponGrip',
      shape: {
        type: 'path',
        d: 'M 378 242 C 414 218 458 242 474 298 C 442 268 408 262 368 264 Z',
        detail: 10
      },
      fill: {
        type: 'linear',
        from: [374, 242],
        to: [474, 298],
        stops: [[0, '#fca5a5'], [0.35, '#ef4444'], [1, '#7f1d1d']]
      },
      stroke: { color: '#111622', width: 3.8 },
      z: 53.2
    },
    {
      id: 'wpnScytheCore',
      parent: 'weaponGrip',
      shape: { type: 'ellipse', cx: 390, cy: 244, rx: 10, ry: 10, detail: 4 },
      fill: '#fef08a',
      stroke: { color: '#111622', width: 3.0 },
      z: 54.2
    },

    // Weapon 3: Thunder Rune Warhammer (`weapon/hammer`)
    {
      id: 'wpnHammerShaft',
      parent: 'weaponGrip',
      shape: {
        type: 'polygon',
        points: [
          270, 382, 376, 252, 388, 262, 282, 392
        ],
        detail: 3
      },
      fill: '#78350f',
      stroke: { color: '#111622', width: 3.6 },
      z: 52.4
    },
    {
      id: 'wpnHammerHead',
      parent: 'weaponGrip',
      shape: {
        type: 'polygon',
        points: [
          344, 232, 386, 198, 434, 254, 392, 288
        ],
        detail: 4
      },
      fill: {
        type: 'linear',
        from: [344, 212],
        to: [432, 274],
        stops: [[0, '#cbd5e1'], [0.5, '#64748b'], [1, '#1e293b']]
      },
      stroke: { color: '#111622', width: 4.0 },
      z: 53.4
    },
    {
      id: 'wpnHammerRune',
      parent: 'weaponGrip',
      shape: { type: 'ellipse', cx: 389, cy: 243, rx: 13, ry: 13, detail: 5 },
      fill: '#38bdf8',
      stroke: { color: '#0f172a', width: 3.0 },
      z: 54.4
    },

    // --- FRONT WEAPON ARM & OUTFIT PAULDRONS (z = 60..68) ---
    {
      id: 'armFrontUpper',
      parent: 'upperArmFront',
      shape: { type: 'rect', x: 232, y: 306, w: 24, h: 44, radius: 10 },
      fill: '#475569',
      stroke: { color: '#111622', width: 3.4 },
      z: 60
    },
    {
      id: 'armFrontFore',
      parent: 'foreArmFront',
      shape: { type: 'rect', x: 254, y: 336, w: 42, h: 22, radius: 9 },
      fill: '#94a3b8',
      stroke: { color: '#111622', width: 3.4 },
      z: 62
    },
    {
      id: 'handFront',
      parent: 'foreArmFront',
      shape: { type: 'ellipse', cx: 294, cy: 352, rx: 11, ry: 11, detail: 4 },
      fill: '#fcd34d',
      stroke: { color: '#111622', width: 3.2 },
      z: 63
    },

    {
      id: 'pauldronRanger',
      parent: 'upperArmFront',
      shape: { type: 'ellipse', cx: 242, cy: 312, rx: 20, ry: 16, detail: 6 },
      fill: '#059669',
      stroke: { color: '#111622', width: 3.4 },
      z: 66
    },
    {
      id: 'pauldronRoyal',
      parent: 'upperArmFront',
      shape: {
        type: 'path',
        d: 'M 220 318 C 220 294 246 288 264 306 L 258 328 Q 238 330 220 318 Z',
        detail: 6
      },
      fill: '#f59e0b',
      stroke: { color: '#111622', width: 3.6 },
      z: 66.2
    },
    {
      id: 'pauldronAbyss',
      parent: 'upperArmFront',
      shape: {
        type: 'polygon',
        points: [218, 320, 212, 290, 238, 300, 254, 286, 264, 316, 240, 328],
        detail: 4
      },
      fill: '#7c3aed',
      stroke: { color: '#111622', width: 3.6 },
      z: 66.4
    },

    // --- ATTACK SLASH ARCS (z = 75..76, opacity driven by SlashAlpha / SlashUpAlpha) ---
    {
      id: 'slashArcDown',
      parent: 'slashOrigin',
      shape: {
        type: 'path',
        d: 'M 290 198 C 398 206 472 288 462 406 C 430 326 368 258 282 232 Z',
        detail: 12
      },
      fill: {
        type: 'linear',
        from: [290, 198],
        to: [462, 406],
        stops: [[0, '#fef08a'], [0.5, '#38bdf8'], [1, '#818cf8']]
      },
      opacity: 0,
      z: 75
    },
    {
      id: 'slashArcUp',
      parent: 'slashOrigin',
      shape: {
        type: 'path',
        d: 'M 286 432 C 398 424 474 338 460 212 C 426 300 366 376 280 398 Z',
        detail: 12
      },
      fill: {
        type: 'linear',
        from: [286, 432],
        to: [460, 212],
        stops: [[0, '#fca5a5'], [0.5, '#fbbf24'], [1, '#fef9c3']]
      },
      opacity: 0,
      z: 76
    }
  ],
  bindings: [
    {
      target: 'bone:hip.y',
      params: ['BodyBobY'],
      keys: [
        { at: [-40], value: -126 },
        { at: [0], value: -86 },
        { at: [40], value: -46 }
      ]
    },
    {
      target: 'bone:torso.rotation',
      params: ['BodyLean'],
      keys: [
        { at: [-35], value: -35 },
        { at: [0], value: 0 },
        { at: [35], value: 35 }
      ]
    },
    {
      target: 'bone:head.rotation',
      params: ['HeadNod'],
      keys: [
        { at: [-25], value: -25 },
        { at: [0], value: 0 },
        { at: [25], value: 25 }
      ]
    },
    {
      target: 'part:eyeLeft.shape.ry',
      params: ['EyeBlink'],
      keys: [
        { at: [0], value: 9.5 },
        { at: [1], value: 1.2 }
      ]
    },
    {
      target: 'part:eyeRight.shape.ry',
      params: ['EyeBlink'],
      keys: [
        { at: [0], value: 9.0 },
        { at: [1], value: 1.2 }
      ]
    },
    {
      target: 'bone:footFrontTarget.x',
      params: ['FootFX'],
      keys: [
        { at: [-80], value: -60 },
        { at: [0], value: 20 },
        { at: [80], value: 100 }
      ]
    },
    {
      target: 'bone:footFrontTarget.y',
      params: ['FootFY'],
      keys: [
        { at: [-70], value: -70 },
        { at: [0], value: 0 },
        { at: [20], value: 20 }
      ]
    },
    {
      target: 'bone:footBackTarget.x',
      params: ['FootBX'],
      keys: [
        { at: [-80], value: -98 },
        { at: [0], value: -18 },
        { at: [80], value: 62 }
      ]
    },
    {
      target: 'bone:footBackTarget.y',
      params: ['FootBY'],
      keys: [
        { at: [-70], value: -70 },
        { at: [0], value: 0 },
        { at: [20], value: 20 }
      ]
    },
    {
      target: 'bone:armBack.rotation',
      params: ['ArmBackRot'],
      keys: [
        { at: [-90], value: -42 },
        { at: [0], value: 48 },
        { at: [90], value: 138 }
      ]
    },
    {
      target: 'bone:upperArmFront.rotation',
      params: ['ArmFrontShoulder'],
      keys: [
        { at: [-130], value: -68 },
        { at: [0], value: 62 },
        { at: [120], value: 182 }
      ]
    },
    {
      target: 'bone:foreArmFront.rotation',
      params: ['ArmFrontElbow'],
      keys: [
        { at: [-90], value: -136 },
        { at: [0], value: -46 },
        { at: [90], value: 44 }
      ]
    },
    {
      target: 'bone:weaponGrip.rotation',
      params: ['WeaponWrist'],
      keys: [
        { at: [-120], value: -186 },
        { at: [0], value: -66 },
        { at: [140], value: 74 }
      ]
    },
    {
      target: 'part:slashArcDown.opacity',
      params: ['SlashAlpha'],
      keys: [
        { at: [0], value: 0 },
        { at: [1], value: 0.92 }
      ]
    },
    {
      target: 'part:slashArcUp.opacity',
      params: ['SlashUpAlpha'],
      keys: [
        { at: [0], value: 0 },
        { at: [1], value: 0.92 }
      ]
    },
    // Cape pendulum output bindings
    {
      target: 'bone:cape1.rotation',
      params: ['Cape1'],
      keys: [
        { at: [-55], value: 78 },
        { at: [0], value: 118 },
        { at: [55], value: 168 }
      ]
    },
    {
      target: 'bone:cape2.rotation',
      params: ['Cape2'],
      keys: [
        { at: [-55], value: -48 },
        { at: [0], value: -8 },
        { at: [55], value: 36 }
      ]
    },
    {
      target: 'bone:cape3.rotation',
      params: ['Cape3'],
      keys: [
        { at: [-55], value: -48 },
        { at: [0], value: -8 },
        { at: [55], value: 36 }
      ]
    },
    // Plume pendulum output bindings
    {
      target: 'bone:plume1.rotation',
      params: ['Plume1'],
      keys: [
        { at: [-50], value: 112 },
        { at: [0], value: 148 },
        { at: [50], value: 184 }
      ]
    },
    {
      target: 'bone:plume2.rotation',
      params: ['Plume2'],
      keys: [
        { at: [-50], value: -48 },
        { at: [0], value: -14 },
        { at: [50], value: 22 }
      ]
    }
  ],
  ik: [
    {
      id: 'legBackIk',
      bones: ['thighBack', 'shinBack'],
      target: 'footBackTarget',
      mix: 1,
      bendPositive: false,
      softness: 8
    },
    {
      id: 'legFrontIk',
      bones: ['thighFront', 'shinFront'],
      target: 'footFrontTarget',
      mix: 1,
      bendPositive: false,
      softness: 8
    }
  ],
  physics: [
    {
      id: 'capeSwing',
      inputs: [
        { param: 'FootFX', type: 'x', weight: 0.35 },
        { param: 'BodyLean', type: 'x', weight: 0.9 },
        { param: 'BodyBobY', type: 'y', weight: 0.6 },
        { param: 'ArmFrontShoulder', type: 'x', weight: 0.2 }
      ],
      outputs: [
        { param: 'Cape1', type: 'angle', segment: 0, scale: 0.9 },
        { param: 'Cape2', type: 'angle', segment: 1, scale: 1.0 },
        { param: 'Cape3', type: 'angle', segment: 2, scale: 1.1 }
      ],
      segments: [
        { length: 42, mass: 1.0 },
        { length: 42, mass: 1.1 },
        { length: 40, mass: 1.3 }
      ],
      damping: 0.12,
      stiffness: 14
    },
    {
      id: 'plumeSwing',
      inputs: [
        { param: 'HeadNod', type: 'x', weight: 0.8 },
        { param: 'BodyBobY', type: 'y', weight: 0.5 },
        { param: 'BodyLean', type: 'x', weight: 0.6 }
      ],
      outputs: [
        { param: 'Plume1', type: 'angle', segment: 0, scale: 0.85 },
        { param: 'Plume2', type: 'angle', segment: 1, scale: 1.0 }
      ],
      segments: [
        { length: 28, mass: 0.9 },
        { length: 26, mass: 1.1 }
      ],
      damping: 0.14,
      stiffness: 18
    }
  ],
  animations: [
    {
      id: 'idle',
      duration: 1.6,
      loop: true,
      tracks: [
        {
          target: 'param:BodyBobY',
          keys: [
            { t: 0.0, v: 0, ease: 'inOutSine' },
            { t: 0.8, v: 5.5, ease: 'inOutSine' },
            { t: 1.6, v: 0 }
          ]
        },
        {
          target: 'param:BodyLean',
          keys: [
            { t: 0.0, v: 2, ease: 'inOutSine' },
            { t: 0.8, v: -1.5, ease: 'inOutSine' },
            { t: 1.6, v: 2 }
          ]
        },
        {
          target: 'param:HeadNod',
          keys: [
            { t: 0.0, v: -2, ease: 'inOutSine' },
            { t: 0.8, v: 3, ease: 'inOutSine' },
            { t: 1.6, v: -2 }
          ]
        },
        {
          target: 'param:ArmFrontShoulder',
          keys: [
            { t: 0.0, v: 0, ease: 'inOutSine' },
            { t: 0.8, v: 8, ease: 'inOutSine' },
            { t: 1.6, v: 0 }
          ]
        },
        {
          target: 'param:WeaponWrist',
          keys: [
            { t: 0.0, v: 0, ease: 'inOutSine' },
            { t: 0.8, v: -6, ease: 'inOutSine' },
            { t: 1.6, v: 0 }
          ]
        },
        {
          target: 'param:EyeBlink',
          keys: [
            { t: 0.0, v: 0 },
            { t: 1.12, v: 0 },
            { t: 1.2, v: 1 },
            { t: 1.3, v: 0 },
            { t: 1.6, v: 0 }
          ]
        }
      ]
    },
    {
      id: 'run',
      duration: 0.64,
      loop: true,
      tracks: [
        {
          target: 'param:BodyLean',
          keys: [
            { t: 0.0, v: 13, ease: 'inOutSine' },
            { t: 0.16, v: 16, ease: 'inOutSine' },
            { t: 0.32, v: 13, ease: 'inOutSine' },
            { t: 0.48, v: 16, ease: 'inOutSine' },
            { t: 0.64, v: 13 }
          ]
        },
        {
          target: 'param:BodyBobY',
          keys: [
            { t: 0.0, v: 6, ease: 'inOutSine' },
            { t: 0.16, v: -9, ease: 'inOutSine' },
            { t: 0.32, v: 6, ease: 'inOutSine' },
            { t: 0.48, v: -9, ease: 'inOutSine' },
            { t: 0.64, v: 6 }
          ]
        },
        {
          target: 'param:FootFX',
          keys: [
            { t: 0.0, v: 34, ease: 'smooth' },
            { t: 0.16, v: 0, ease: 'smooth' },
            { t: 0.32, v: -36, ease: 'smooth' },
            { t: 0.48, v: 4, ease: 'smooth' },
            { t: 0.64, v: 34 }
          ]
        },
        {
          target: 'param:FootFY',
          keys: [
            { t: 0.0, v: 0, ease: 'smooth' },
            { t: 0.16, v: 0, ease: 'smooth' },
            { t: 0.32, v: -4, ease: 'smooth' },
            { t: 0.48, v: -30, ease: 'smooth' },
            { t: 0.64, v: 0 }
          ]
        },
        {
          target: 'param:FootBX',
          keys: [
            { t: 0.0, v: -36, ease: 'smooth' },
            { t: 0.16, v: 4, ease: 'smooth' },
            { t: 0.32, v: 34, ease: 'smooth' },
            { t: 0.48, v: 0, ease: 'smooth' },
            { t: 0.64, v: -36 }
          ]
        },
        {
          target: 'param:FootBY',
          keys: [
            { t: 0.0, v: -4, ease: 'smooth' },
            { t: 0.16, v: -34, ease: 'smooth' },
            { t: 0.32, v: 0, ease: 'smooth' },
            { t: 0.48, v: 0, ease: 'smooth' },
            { t: 0.64, v: -4 }
          ]
        },
        {
          target: 'param:ArmBackRot',
          keys: [
            { t: 0.0, v: -36, ease: 'inOutSine' },
            { t: 0.32, v: 36, ease: 'inOutSine' },
            { t: 0.64, v: -36 }
          ]
        },
        {
          target: 'param:ArmFrontShoulder',
          keys: [
            { t: 0.0, v: 26, ease: 'inOutSine' },
            { t: 0.32, v: -20, ease: 'inOutSine' },
            { t: 0.64, v: 26 }
          ]
        },
        {
          target: 'param:HeadNod',
          keys: [
            { t: 0.0, v: -4, ease: 'inOutSine' },
            { t: 0.16, v: 3, ease: 'inOutSine' },
            { t: 0.32, v: -4, ease: 'inOutSine' },
            { t: 0.48, v: 3, ease: 'inOutSine' },
            { t: 0.64, v: -4 }
          ]
        }
      ]
    },
    {
      id: 'jump',
      duration: 0.72,
      loop: false,
      tracks: [
        {
          target: 'param:BodyBobY',
          keys: [
            { t: 0.0, v: 12, ease: 'outQuad' },
            { t: 0.12, v: -24, ease: 'outQuad' },
            { t: 0.42, v: -28, ease: 'inQuad' },
            { t: 0.72, v: -6 }
          ]
        },
        {
          target: 'param:BodyLean',
          keys: [
            { t: 0.0, v: 10, ease: 'outQuad' },
            { t: 0.18, v: -12, ease: 'inOutSine' },
            { t: 0.52, v: 8, ease: 'inOutSine' },
            { t: 0.72, v: 4 }
          ]
        },
        {
          target: 'param:FootFY',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.16, v: -44, ease: 'inOutSine' },
            { t: 0.5, v: -32, ease: 'inQuad' },
            { t: 0.72, v: -8 }
          ]
        },
        {
          target: 'param:FootFX',
          keys: [
            { t: 0.0, v: 12, ease: 'outQuad' },
            { t: 0.25, v: 30, ease: 'inOutSine' },
            { t: 0.72, v: 18 }
          ]
        },
        {
          target: 'param:FootBY',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.2, v: -38, ease: 'inOutSine' },
            { t: 0.72, v: -10 }
          ]
        },
        {
          target: 'param:FootBX',
          keys: [
            { t: 0.0, v: -12, ease: 'outQuad' },
            { t: 0.25, v: -32, ease: 'inOutSine' },
            { t: 0.72, v: -16 }
          ]
        },
        {
          target: 'param:ArmFrontShoulder',
          keys: [
            { t: 0.0, v: 20, ease: 'outQuad' },
            { t: 0.2, v: -55, ease: 'inOutSine' },
            { t: 0.72, v: -18 }
          ]
        },
        {
          target: 'param:ArmBackRot',
          keys: [
            { t: 0.0, v: 15, ease: 'outQuad' },
            { t: 0.22, v: -52, ease: 'inOutSine' },
            { t: 0.72, v: -14 }
          ]
        }
      ]
    },
    {
      id: 'attack_1',
      duration: 0.42,
      loop: false,
      tracks: [
        {
          target: 'param:BodyLean',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.11, v: -14, ease: 'inQuad' },
            { t: 0.2, v: 20, ease: 'outQuad' },
            { t: 0.42, v: 0 }
          ]
        },
        {
          target: 'param:BodyBobY',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.11, v: -6, ease: 'inQuad' },
            { t: 0.2, v: 12, ease: 'outQuad' },
            { t: 0.42, v: 0 }
          ]
        },
        {
          target: 'param:FootFX',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.11, v: -8, ease: 'inQuad' },
            { t: 0.2, v: 32, ease: 'outQuad' },
            { t: 0.42, v: 0 }
          ]
        },
        {
          target: 'param:ArmFrontShoulder',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.11, v: -64, ease: 'inQuad' },
            { t: 0.19, v: 14, ease: 'outQuad' },
            { t: 0.28, v: 22, ease: 'inOutSine' },
            { t: 0.42, v: 0 }
          ]
        },
        {
          target: 'param:ArmFrontElbow',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.11, v: -22, ease: 'inQuad' },
            { t: 0.19, v: 26, ease: 'outQuad' },
            { t: 0.42, v: 0 }
          ]
        },
        {
          target: 'param:WeaponWrist',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.11, v: -28, ease: 'inQuad' },
            { t: 0.19, v: 64, ease: 'outQuad' },
            { t: 0.28, v: 74, ease: 'inOutSine' },
            { t: 0.42, v: 0 }
          ]
        },
        {
          target: 'param:SlashAlpha',
          keys: [
            { t: 0.0, v: 0, ease: 'step' },
            { t: 0.15, v: 1, ease: 'outQuad' },
            { t: 0.3, v: 0 },
            { t: 0.42, v: 0 }
          ]
        }
      ],
      events: [{ t: 0.18, name: 'hit_frame' }]
    },
    {
      id: 'attack_2',
      duration: 0.44,
      loop: false,
      tracks: [
        {
          target: 'param:BodyLean',
          keys: [
            { t: 0.0, v: 18, ease: 'outQuad' },
            { t: 0.1, v: 22, ease: 'inQuad' },
            { t: 0.21, v: -14, ease: 'outQuad' },
            { t: 0.44, v: 0 }
          ]
        },
        {
          target: 'param:BodyBobY',
          keys: [
            { t: 0.0, v: 10, ease: 'outQuad' },
            { t: 0.1, v: 14, ease: 'inQuad' },
            { t: 0.21, v: -10, ease: 'outQuad' },
            { t: 0.44, v: 0 }
          ]
        },
        {
          target: 'param:ArmFrontShoulder',
          keys: [
            { t: 0.0, v: 20, ease: 'outQuad' },
            { t: 0.1, v: 32, ease: 'inQuad' },
            { t: 0.21, v: -62, ease: 'outQuad' },
            { t: 0.44, v: 0 }
          ]
        },
        {
          target: 'param:WeaponWrist',
          keys: [
            { t: 0.0, v: 58, ease: 'outQuad' },
            { t: 0.1, v: 76, ease: 'inQuad' },
            { t: 0.21, v: -38, ease: 'outQuad' },
            { t: 0.44, v: 0 }
          ]
        },
        {
          target: 'param:SlashUpAlpha',
          keys: [
            { t: 0.0, v: 0, ease: 'step' },
            { t: 0.15, v: 1, ease: 'outQuad' },
            { t: 0.32, v: 0 },
            { t: 0.44, v: 0 }
          ]
        }
      ],
      events: [{ t: 0.19, name: 'hit_frame' }]
    }
  ]
};

// ============================================================================
// 2. RUNE SCARECROW GOLEM (`straw_golem.r2d.json`)
//    Canvas: 384x384, Ground contact at (192, 352)
// ============================================================================
const dummyModel = {
  format: 'rev2d',
  version: 1,
  meta: {
    name: 'straw_golem',
    width: 384,
    height: 384,
    background: 'rgba(0,0,0,0)',
    fps: 30,
    author: 'Slacker Survivors Rev2D Pipeline',
    description: '2.5D Rune Scarecrow Golem target dummy with swaying lantern physics and hit recoil animation.'
  },
  parameters: [
    { id: 'Sway', min: -35, max: 35, default: 0, group: 'Body' },
    { id: 'Squash', min: -25, max: 25, default: 0, group: 'Body' },
    { id: 'ArmRattle', min: -40, max: 40, default: 0, group: 'Arms' },
    { id: 'LanternSwing', min: -55, max: 55, default: 0, group: 'Physics' }
  ],
  bones: [
    { id: 'ground', x: 192, y: 352, length: 0 },
    { id: 'post', parent: 'ground', x: 0, y: -74, length: 0 },
    { id: 'chest', parent: 'post', x: 0, y: -58, length: 0 },
    { id: 'head', parent: 'chest', x: 0, y: -44, length: 0 },
    { id: 'armL', parent: 'chest', x: -38, y: -12, rotation: 168, length: 52 },
    { id: 'armR', parent: 'chest', x: 38, y: -12, rotation: 12, length: 52 },
    { id: 'lanternChain', parent: 'armR', x: 46, y: 0, rotation: 78, length: 34 }
  ],
  parts: [
    {
      id: 'woodenPost',
      parent: 'post',
      shape: { type: 'rect', x: 179, y: 246, w: 26, h: 106, radius: 6 },
      fill: '#78350f',
      stroke: { color: '#111622', width: 3.6 },
      z: 5
    },
    {
      id: 'postBase',
      parent: 'ground',
      shape: { type: 'ellipse', cx: 192, cy: 348, rx: 38, ry: 10, detail: 6 },
      fill: '#451a03',
      stroke: { color: '#111622', width: 3.4 },
      z: 4
    },
    {
      id: 'crossbarL',
      parent: 'armL',
      shape: { type: 'rect', x: 96, y: 198, w: 66, h: 18, radius: 6 },
      fill: '#92400e',
      stroke: { color: '#111622', width: 3.4 },
      z: 8
    },
    {
      id: 'crossbarR',
      parent: 'armR',
      shape: { type: 'rect', x: 222, y: 198, w: 66, h: 18, radius: 6 },
      fill: '#92400e',
      stroke: { color: '#111622', width: 3.4 },
      z: 8
    },
    {
      id: 'lanternBody',
      parent: 'lanternChain',
      shape: {
        type: 'polygon',
        points: [268, 222, 290, 222, 296, 254, 279, 266, 262, 254],
        detail: 3
      },
      fill: {
        type: 'radial',
        center: [279, 242],
        radius: 22,
        stops: [[0, '#fef08a'], [0.6, '#f59e0b'], [1, '#78350f']]
      },
      stroke: { color: '#111622', width: 3.2 },
      z: 10
    },
    {
      id: 'burlapTorso',
      parent: 'chest',
      shape: {
        type: 'path',
        d: 'M 148 184 Q 192 172 236 184 L 244 274 Q 192 288 140 274 Z',
        detail: 8
      },
      fill: {
        type: 'linear',
        from: [148, 178],
        to: [240, 282],
        stops: [[0, '#d97706'], [0.55, '#b45309'], [1, '#78350f']]
      },
      stroke: { color: '#111622', width: 3.8 },
      z: 14
    },
    {
      id: 'targetBullseyeOuter',
      parent: 'chest',
      shape: { type: 'ellipse', cx: 192, cy: 230, rx: 26, ry: 26, detail: 6 },
      fill: '#f8fafc',
      stroke: { color: '#111622', width: 3.0 },
      z: 15
    },
    {
      id: 'targetBullseyeInner',
      parent: 'chest',
      shape: { type: 'ellipse', cx: 192, cy: 230, rx: 13, ry: 13, detail: 5 },
      fill: '#ef4444',
      z: 16
    },
    {
      id: 'pumpkinHead',
      parent: 'head',
      shape: { type: 'ellipse', cx: 192, cy: 138, rx: 42, ry: 36, detail: 8 },
      fill: {
        type: 'radial',
        center: [184, 128],
        radius: 48,
        stops: [[0, '#fb923c'], [0.6, '#ea580c'], [1, '#9a3412']]
      },
      stroke: { color: '#111622', width: 3.8 },
      z: 20
    },
    {
      id: 'witchHat',
      parent: 'head',
      shape: {
        type: 'path',
        d: 'M 134 118 Q 192 104 250 118 L 222 104 L 202 52 L 166 104 Z',
        detail: 8
      },
      fill: '#312e81',
      stroke: { color: '#111622', width: 3.6 },
      z: 22
    },
    {
      id: 'golemEyeL',
      parent: 'head',
      shape: { type: 'polygon', points: [168, 140, 180, 126, 186, 142], detail: 2 },
      fill: '#fef08a',
      z: 21
    },
    {
      id: 'golemEyeR',
      parent: 'head',
      shape: { type: 'polygon', points: [198, 142, 204, 126, 216, 140], detail: 2 },
      fill: '#fef08a',
      z: 21
    }
  ],
  bindings: [
    {
      target: 'bone:post.rotation',
      params: ['Sway'],
      keys: [
        { at: [-35], value: -28 },
        { at: [0], value: 0 },
        { at: [35], value: 28 }
      ]
    },
    {
      target: 'bone:head.rotation',
      params: ['Sway'],
      keys: [
        { at: [-35], value: -18 },
        { at: [0], value: 0 },
        { at: [35], value: 18 }
      ]
    },
    {
      target: 'bone:chest.y',
      params: ['Squash'],
      keys: [
        { at: [-25], value: -72 },
        { at: [0], value: -58 },
        { at: [25], value: -42 }
      ]
    },
    {
      target: 'bone:armL.rotation',
      params: ['ArmRattle'],
      keys: [
        { at: [-40], value: 138 },
        { at: [0], value: 168 },
        { at: [40], value: 198 }
      ]
    },
    {
      target: 'bone:armR.rotation',
      params: ['ArmRattle'],
      keys: [
        { at: [-40], value: -18 },
        { at: [0], value: 12 },
        { at: [40], value: 42 }
      ]
    },
    {
      target: 'bone:lanternChain.rotation',
      params: ['LanternSwing'],
      keys: [
        { at: [-55], value: 28 },
        { at: [0], value: 78 },
        { at: [55], value: 128 }
      ]
    }
  ],
  physics: [
    {
      id: 'lanternPhys',
      inputs: [
        { param: 'Sway', type: 'x', weight: 1.1 },
        { param: 'ArmRattle', type: 'x', weight: 0.7 }
      ],
      outputs: [{ param: 'LanternSwing', type: 'angle', segment: 0, scale: 1.0 }],
      segments: [{ length: 34, mass: 1.2 }],
      damping: 0.08,
      stiffness: 12
    }
  ],
  animations: [
    {
      id: 'idle',
      duration: 2.0,
      loop: true,
      tracks: [
        {
          target: 'param:Sway',
          keys: [
            { t: 0.0, v: -3.5, ease: 'inOutSine' },
            { t: 1.0, v: 3.5, ease: 'inOutSine' },
            { t: 2.0, v: -3.5 }
          ]
        },
        {
          target: 'param:Squash',
          keys: [
            { t: 0.0, v: 0, ease: 'inOutSine' },
            { t: 0.5, v: 4, ease: 'inOutSine' },
            { t: 1.0, v: 0, ease: 'inOutSine' },
            { t: 1.5, v: 4, ease: 'inOutSine' },
            { t: 2.0, v: 0 }
          ]
        }
      ]
    },
    {
      id: 'hit',
      duration: 0.46,
      loop: false,
      tracks: [
        {
          target: 'param:Sway',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.08, v: 30, ease: 'inOutSine' },
            { t: 0.2, v: -18, ease: 'inOutSine' },
            { t: 0.33, v: 9, ease: 'inOutSine' },
            { t: 0.46, v: 0 }
          ]
        },
        {
          target: 'param:Squash',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.08, v: 18, ease: 'outQuad' },
            { t: 0.22, v: -10, ease: 'inOutSine' },
            { t: 0.46, v: 0 }
          ]
        },
        {
          target: 'param:ArmRattle',
          keys: [
            { t: 0.0, v: 0, ease: 'outQuad' },
            { t: 0.09, v: -36, ease: 'inOutSine' },
            { t: 0.22, v: 26, ease: 'inOutSine' },
            { t: 0.46, v: 0 }
          ]
        }
      ]
    }
  ]
};

function runRev2d(args) {
  return execFileSync(process.execPath, [REV2D_BIN, ...args], { encoding: 'utf8' });
}

const heroJsonPath = path.join(__dirname, 'hero_knight.r2d.json');
const dummyJsonPath = path.join(__dirname, 'straw_golem.r2d.json');

fs.writeFileSync(heroJsonPath, JSON.stringify(heroModel, null, 2) + '\n');
fs.writeFileSync(dummyJsonPath, JSON.stringify(dummyModel, null, 2) + '\n');

console.log('=== 1. Validating Rev2D Models ===');
console.log(runRev2d(['validate', heroJsonPath]));
console.log(runRev2d(['validate', dummyJsonPath]));

if (SCRATCH_PREVIEW_DIR) {
  console.log('=== 2. Rendering Rev2D Verification Sheets ===');
  runRev2d(['render', heroJsonPath, '-o', path.join(SCRATCH_PREVIEW_DIR, 'hero_setup_overlay.png'), '--overlay', 'bones,labels']);
  runRev2d(['sheet', heroJsonPath, '-o', path.join(SCRATCH_PREVIEW_DIR, 'hero_run_sheet.png'), '--anim', 'run', '--frames', '8', '--warmup', '3']);
  runRev2d(['sheet', heroJsonPath, '-o', path.join(SCRATCH_PREVIEW_DIR, 'hero_attack_sheet.png'), '--anim', 'attack_1', '--frames', '6']);
  runRev2d(['render', dummyJsonPath, '-o', path.join(SCRATCH_PREVIEW_DIR, 'dummy_setup_overlay.png'), '--overlay', 'bones,labels']);
}

console.log('=== 3. Exporting Spine 4.2.00 Skeletons ===');
console.log(runRev2d([
  'export', 'spine', heroJsonPath,
  '-o', OUT_SPINES_DIR,
  '--name', 'spn_spine_stage_hero',
  '--straight-alpha'
]));
console.log(runRev2d([
  'export', 'spine', dummyJsonPath,
  '-o', OUT_SPINES_DIR,
  '--name', 'spn_spine_stage_dummy',
  '--straight-alpha'
]));

// ============================================================================
// 4. Partition Hero Equipment Slots into Native Spine 4.2 Mix-and-Match Skins
//    and rename `.json` -> `.spine-json` for `spine-godot` resource importer!
// ============================================================================
const heroSpineRawPath = path.join(OUT_SPINES_DIR, 'spn_spine_stage_hero.json');
const heroSpineFinalPath = path.join(OUT_SPINES_DIR, 'spn_spine_stage_hero.spine-json');
const heroSpine = JSON.parse(fs.readFileSync(heroSpineRawPath, 'utf8'));

const SKIN_PART_GROUPS = {
  'weapon/sword': ['wpnSwordBlade', 'wpnSwordGuard', 'wpnSwordPommel'],
  'weapon/scythe': ['wpnScytheShaft', 'wpnScytheBlade', 'wpnScytheCore'],
  'weapon/hammer': ['wpnHammerShaft', 'wpnHammerHead', 'wpnHammerRune'],
  'outfit/ranger': ['cloakRanger', 'plumeRanger', 'hoodRanger', 'pauldronRanger'],
  'outfit/royal': ['cloakRoyal', 'plumeRoyal', 'crownRoyal', 'pauldronRoyal'],
  'outfit/abyss': ['cloakAbyss', 'plumeAbyss', 'hornsAbyss', 'pauldronAbyss']
};

const allModularSlots = new Set(Object.values(SKIN_PART_GROUPS).flat());
const defaultSkin = heroSpine.skins.find((s) => s.name === 'default');
const defaultAttachments = defaultSkin.attachments;

const newSkins = [{ name: 'default', attachments: {} }];
for (const [slotName, slotAtts] of Object.entries(defaultAttachments)) {
  if (!allModularSlots.has(slotName)) {
    newSkins[0].attachments[slotName] = slotAtts;
  }
}

for (const [skinName, slotList] of Object.entries(SKIN_PART_GROUPS)) {
  const skinEntry = { name: skinName, attachments: {} };
  for (const slotName of slotList) {
    if (defaultAttachments[slotName]) {
      skinEntry.attachments[slotName] = defaultAttachments[slotName];
    }
  }
  newSkins.push(skinEntry);
}

// Keep `slot.attachment` pointing to each slot's attachment name!
// In Spine 4.2, when a custom combined skin (`default` + `weapon/sword` + `outfit/ranger`)
// is applied and `setSlotsToSetupPose()` runs, slots present in the active skin show their
// attachment, while slots belonging to inactive weapons/outfits resolve to `null` (hidden)!
heroSpine.skins = newSkins;

fs.writeFileSync(heroSpineFinalPath, JSON.stringify(heroSpine));
fs.unlinkSync(heroSpineRawPath);

const dummySpineRawPath = path.join(OUT_SPINES_DIR, 'spn_spine_stage_dummy.json');
const dummySpineFinalPath = path.join(OUT_SPINES_DIR, 'spn_spine_stage_dummy.spine-json');
fs.renameSync(dummySpineRawPath, dummySpineFinalPath);

console.log('=== 5. Spine 4.2 Mix-and-Match Skins Ready ===');
console.log('Hero skins:', heroSpine.skins.map((s) => s.name));
