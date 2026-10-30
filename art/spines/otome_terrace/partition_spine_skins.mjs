import fs from 'node:fs';
import path from 'node:path';

const spinesDir = '/Users/krace/Code/GodotProject/slacker-survivors/src/test/otome_terrace/assets/spines';
const srcJsonPath = path.join(spinesDir, 'spn_otome_terrace_hero.json');
const dstSpineJsonPath = path.join(spinesDir, 'spn_otome_terrace_hero.spine-json');

const rawPath = fs.existsSync(srcJsonPath) ? srcJsonPath : dstSpineJsonPath;
const doc = JSON.parse(fs.readFileSync(rawPath, 'utf8'));

const SKIN_MAP = {
  'outfit/cardigan': [
    'cardiganArmLUpper',
    'cardiganArmLLower',
    'cardiganTorso',
    'cardiganArmRUpper',
    'cardiganArmRLower',
  ],
  'outfit/barista': [
    'baristaArmLUpper',
    'baristaArmLLower',
    'baristaTorso',
    'baristaArmRUpper',
    'baristaArmRLower',
  ],
  'outfit/trench': [
    'trenchArmLUpper',
    'trenchArmLLower',
    'trenchTorso',
    'trenchArmRUpper',
    'trenchArmRLower',
  ],
  'expr/gentle': [
    'expGentleHead',
    'expGentleBlink',
  ],
  'expr/happy': [
    'expHappyHead',
  ],
  'expr/blush': [
    'expBlushHead',
  ],
  'prop/none': [],
  'prop/coffee_cup': [
    'propCoffeeCup',
  ],
  'prop/poetry_book': [
    'propPoetryBook',
  ],
  'prop/flower_sprig': [
    'propFlowerSprig',
  ],
};

const defaultSkinEntry = doc.skins.find((s) => s.name === 'default');
if (!defaultSkinEntry) {
  throw new Error('Missing default skin in exported Spine JSON');
}

const sourceAttachments = { ...defaultSkinEntry.attachments };
const modularSlotToSkin = new Map();
for (const [skinName, slotNames] of Object.entries(SKIN_MAP)) {
  for (const slotName of slotNames) {
    modularSlotToSkin.set(slotName, skinName);
  }
}

const baseAttachments = {};
for (const [slotName, attMap] of Object.entries(sourceAttachments)) {
  if (!modularSlotToSkin.has(slotName)) {
    baseAttachments[slotName] = attMap;
  }
}

const newSkins = [
  {
    name: 'default',
    attachments: baseAttachments,
  },
];

for (const [skinName, slotNames] of Object.entries(SKIN_MAP)) {
  const skinAttachments = {};
  for (const slotName of slotNames) {
    if (!sourceAttachments[slotName]) {
      throw new Error(`Missing attachment for modular slot "${slotName}" in skin "${skinName}"`);
    }
    skinAttachments[slotName] = sourceAttachments[slotName];
  }
  newSkins.push({
    name: skinName,
    attachments: skinAttachments,
  });
}

doc.skins = newSkins;

// Keep slot.attachment = slot.name so SpineSkin.add_skin() activates each skin's slot attachment cleanly,
// while slots absent from the active combined skin remain empty (unattached in that combined skin).
fs.writeFileSync(dstSpineJsonPath, JSON.stringify(doc));
if (fs.existsSync(srcJsonPath)) {
  fs.unlinkSync(srcJsonPath);
}

console.log(
  `Partitioned ${Object.keys(sourceAttachments).length} slots into ${newSkins.length} Spine 4.2 skins -> ${dstSpineJsonPath}`,
);
for (const s of newSkins) {
  console.log(`  - ${s.name}: ${Object.keys(s.attachments).length} slot(s)`);
}
