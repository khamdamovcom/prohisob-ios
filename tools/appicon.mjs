// iOS ilova ikonkasi (1024: yorug' / qorong'i / tusli), ochilish belgisi va ranglar — prohisob.com dagi «P» belgisi:
// sariq fon, siyoh harf. Foydalanish: node tools/appicon.mjs   (sharp — /opt/sam/node_modules dan)
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire('/opt/sam/package.json');
const sharp = require('sharp');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const A = path.join(ROOT, 'Prohisob/Resources/Assets.xcassets');

// «P» harfi chizma sifatida (shrift kerak emas): ustun + halqa (evenodd)
const P = (fill) => `<g fill="${fill}" fill-rule="evenodd" transform="translate(-36 0)">
  <rect x="318" y="232" width="150" height="560" rx="30"/>
  <path d="M400 232 H585 A205 205 0 0 1 585 642 H400 Z M468 346 H572 A91 91 0 0 1 572 528 H468 Z"/>
</g>`;
// pastki o'ng burchakda kichik «hisob» chizig'i (daftar qatori) — belgiga qurilish/hisob ruhini beradi
const line = (fill, op) => `<rect x="524" y="712" width="190" height="56" rx="28" fill="${fill}" fill-opacity="${op}"/>`;
const icon = (bg, letter, extra = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
${bg}${P(letter)}${extra}</svg>`;
const yellowBg = `<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFD15C"/><stop offset="1" stop-color="#FFB21F"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#g)"/>`;
const darkBg = `<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#20262C"/><stop offset="1" stop-color="#0E1114"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#g)"/>`;

const set = path.join(A, 'AppIcon.appiconset');
fs.mkdirSync(set, { recursive: true });
const png = (svg, file) => sharp(Buffer.from(svg)).resize(1024, 1024).flatten({ background: '#000000' }).png().toFile(file);
await png(icon(yellowBg, '#171C20', line('#171C20', 0.9)), path.join(set, 'AppIcon.png'));
await png(icon(darkBg, '#FFBC32', line('#FFBC32', 0.9)), path.join(set, 'AppIcon-dark.png'));
await png(icon('<rect width="1024" height="1024" fill="#000000"/>', '#EDEDED', line('#EDEDED', 0.6)), path.join(set, 'AppIcon-tinted.png'));
fs.writeFileSync(path.join(set, 'Contents.json'), JSON.stringify({ images: [
  { filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
  { appearances: [{ appearance: 'luminosity', value: 'dark' }], filename: 'AppIcon-dark.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
  { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: 'AppIcon-tinted.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
], info: { author: 'xcode', version: 1 } }, null, 2));

// Ochilish belgisi: sariq kvadratda «P» (shaffof fon), 1x/2x/3x — 96 pt
const logo = path.join(A, 'LaunchMark.imageset');
fs.mkdirSync(logo, { recursive: true });
const markSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<rect width="1024" height="1024" rx="276" fill="#FFBC32"/>${P('#171C20')}${line('#171C20', 0.9)}</svg>`;
for (const [s, n] of [[1, 'LaunchMark.png'], [2, 'LaunchMark@2x.png'], [3, 'LaunchMark@3x.png']])
  await sharp(Buffer.from(markSvg)).resize(96 * s, 96 * s).png().toFile(path.join(logo, n));
fs.writeFileSync(path.join(logo, 'Contents.json'), JSON.stringify({ images: [
  { filename: 'LaunchMark.png', idiom: 'universal', scale: '1x' }, { filename: 'LaunchMark@2x.png', idiom: 'universal', scale: '2x' },
  { filename: 'LaunchMark@3x.png', idiom: 'universal', scale: '3x' },
], info: { author: 'xcode', version: 1 } }, null, 2));

// Ranglar
const rgb = (hex) => { const v = hex.replace('#', ''); return { red: `0x${v.slice(0, 2)}`, green: `0x${v.slice(2, 4)}`, blue: `0x${v.slice(4, 6)}`, alpha: '1.000' }; };
const color = (name, light, dark) => {
  const d = path.join(A, `${name}.colorset`);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, 'Contents.json'), JSON.stringify({ colors: [
    { color: { 'color-space': 'srgb', components: rgb(light) }, idiom: 'universal' },
    { appearances: [{ appearance: 'luminosity', value: 'dark' }], color: { 'color-space': 'srgb', components: rgb(dark) }, idiom: 'universal' },
  ], info: { author: 'xcode', version: 1 } }, null, 2));
};
color('AccentColor', '#8A5D00', '#FFC94D');
color('LaunchBackground', '#F4F4EF', '#0D1013');
fs.writeFileSync(path.join(A, 'Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2));
// App Store sahifasi va sayt uchun 1024 nusxa
fs.mkdirSync(path.join(ROOT, 'docs'), { recursive: true });
fs.copyFileSync(path.join(set, 'AppIcon.png'), path.join(ROOT, 'docs/icon-1024.png'));
console.log('tayyor');
