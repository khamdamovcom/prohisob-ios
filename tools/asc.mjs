// Prohisob — App Store Connect API (serverdan). Kalit va tarqatish sertifikati sam.uz bilan bir jamoada — /root/zaxira/prohisob-ios (nusxa).
// Foydalanish: node tools/asc.mjs <buyruq>
//   check                 — kalit ishlayaptimi, ilovalar ro'yxati
//   signing <TEAM_ID>     — bundle ID (com.prohisob.app), tarqatish sertifikati (mavjudi qayta ishlatiladi), App Store profili → GitHub secrets
//   metadata              — App Store sahifasi matnlari (appstore/<til>/*.txt), toifa, mualliflik
//   screenshots <papka>   — skrinshotlar (<papka>/phone/*.png → en-US va ru, ilova o'zbekcha)
//   setup                 — kontent huquqi, bepul narx, mavjudlik (Xitoysiz)
//   review                — App Review: demo hisoblar (demo.json) va izoh, kontakt sam.uz dan
//   testflight | attach | submit — ichki sinov guruhi, buildni versiyaga biriktirish, ko'rib chiqishga yuborish (faqat egasi roziligi bilan)
//   status                — buildlar va versiya holati
// Kalit va sertifikatlar repozitoriyga tushmaydi: /root/zaxira/prohisob-ios (700).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const DIR = process.env.PH_ASC_DIR || '/root/zaxira/prohisob-ios';
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const REPO = 'khamdamovcom/prohisob-ios';
const BUNDLE = 'com.prohisob.app';
const API = 'https://api.appstoreconnect.apple.com';

function creds() {
  const j = JSON.parse(fs.readFileSync(path.join(DIR, 'asc.json'), 'utf8'));
  const key = fs.readFileSync(path.join(DIR, `AuthKey_${j.keyId}.p8`), 'utf8');
  return { ...j, key };
}

const b64u = (b) => Buffer.from(b).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
let tokenCache = null;
function token() {
  const now = Math.floor(Date.now() / 1000);
  if (tokenCache && tokenCache.exp - now > 60) return tokenCache.t;
  const c = creds();
  const head = b64u(JSON.stringify({ alg: 'ES256', kid: c.keyId, typ: 'JWT' }));
  const body = b64u(JSON.stringify({ iss: c.issuer, iat: now, exp: now + 1100, aud: 'appstoreconnect-v1' }));
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: c.key, dsaEncoding: 'ieee-p1363' });
  tokenCache = { t: `${head}.${body}.${b64u(sig)}`, exp: now + 1100 };
  return tokenCache.t;
}

async function api(method, p, body) {
  const r = await fetch(API + p, { method, headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let j = null;
  try { j = text ? JSON.parse(text) : null; } catch { j = { raw: text.slice(0, 300) }; }
  if (!r.ok) {
    const e = new Error(`${method} ${p} → ${r.status}: ${(j?.errors || []).map((x) => `${x.code} ${x.detail || x.title}`).join('; ') || text.slice(0, 300)}`);
    e.status = r.status; e.body = j;
    throw e;
  }
  return j;
}
const get = (p) => api('GET', p);

async function appId() {
  const r = await get(`/v1/apps?filter[bundleId]=${BUNDLE}&limit=1`);
  return r.data?.[0]?.id || null;
}

function gh(args, input) {
  return execFileSync('gh', args, { input, encoding: 'utf8', stdio: [input == null ? 'ignore' : 'pipe', 'pipe', 'pipe'] });
}

// ---------- check ----------
async function check() {
  const r = await get('/v1/apps?limit=20&fields[apps]=name,bundleId,sku');
  console.log('kalit ishlayapti. Ilovalar:', r.data.map((a) => `${a.attributes.name} (${a.attributes.bundleId}) id=${a.id}`).join(', ') || "yo'q");
  const b = await get(`/v1/bundleIds?filter[identifier]=${BUNDLE}`);
  console.log('bundle ID:', b.data.map((x) => `${x.attributes.identifier} id=${x.id} seed=${x.attributes.seedId}`).join(', ') || "ro'yxatdan o'tmagan");
}

// ---------- signing ----------
async function signing(team) {
  if (!/^[A-Z0-9]{10}$/.test(team || '')) throw new Error('TEAM_ID kerak (10 belgi)');
  fs.mkdirSync(DIR, { recursive: true, mode: 0o700 });
  // 1) bundle ID
  let b = (await get(`/v1/bundleIds?filter[identifier]=${BUNDLE}`)).data.find((x) => x.attributes.identifier === BUNDLE);
  if (!b) {
    // Apple: App ID nomida faqat harf, raqam va bo'sh joy (nuqta mumkin emas)
    b = (await api('POST', '/v1/bundleIds', { data: { type: 'bundleIds', attributes: { identifier: BUNDLE, name: 'Prohisob', platform: 'IOS' } } })).data;
    console.log('bundle ID yaratildi:', b.id);
  } else console.log('bundle ID bor:', b.id);
  // 3) tarqatish sertifikati: kalit va CSR serverda (kalit hech qayerga yuborilmaydi)
  const keyF = path.join(DIR, 'dist.key'), certF = path.join(DIR, 'dist.cer'), p12F = path.join(DIR, 'dist.p12'), passF = path.join(DIR, 'dist.p12.pass');
  let certId = fs.existsSync(path.join(DIR, 'dist.id')) ? fs.readFileSync(path.join(DIR, 'dist.id'), 'utf8').trim() : null;
  if (!certId || !fs.existsSync(certF)) {
    execFileSync('openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', keyF, '-out', path.join(DIR, 'dist.csr'), '-subj', '/CN=Prohisob Distribution/C=UZ']);
    fs.chmodSync(keyF, 0o600);
    const csr = fs.readFileSync(path.join(DIR, 'dist.csr'), 'utf8').replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
    const c = (await api('POST', '/v1/certificates', { data: { type: 'certificates', attributes: { certificateType: 'DISTRIBUTION', csrContent: csr } } })).data;
    certId = c.id;
    fs.writeFileSync(certF, Buffer.from(c.attributes.certificateContent, 'base64'), { mode: 0o600 });
    fs.writeFileSync(path.join(DIR, 'dist.id'), certId, { mode: 0o600 });
    console.log('sertifikat yaratildi:', certId, c.attributes.name, c.attributes.expirationDate);
  } else console.log('sertifikat bor:', certId);
  // .p12 (macOS keychain uchun eski algoritmlar bilan)
  const pass = fs.existsSync(passF) ? fs.readFileSync(passF, 'utf8').trim() : crypto.randomBytes(18).toString('base64url');
  fs.writeFileSync(passF, pass, { mode: 0o600 });
  execFileSync('openssl', ['x509', '-inform', 'DER', '-in', certF, '-out', path.join(DIR, 'dist.pem')]);
  execFileSync('openssl', ['pkcs12', '-export', '-inkey', keyF, '-in', path.join(DIR, 'dist.pem'), '-out', p12F, '-passout', `pass:${pass}`,
    '-name', 'Apple Distribution', '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1']);
  fs.chmodSync(p12F, 0o600);
  // 4) App Store profili (eskisini o'chirib, yangisini yaratamiz — sertifikat o'zgargan bo'lishi mumkin)
  const name = 'Prohisob App Store';
  const old = (await get(`/v1/profiles?filter[name]=${encodeURIComponent(name)}`)).data;
  for (const o of old) await api('DELETE', `/v1/profiles/${o.id}`);
  const prof = (await api('POST', '/v1/profiles', { data: { type: 'profiles', attributes: { name, profileType: 'IOS_APP_STORE' },
    relationships: { bundleId: { data: { type: 'bundleIds', id: b.id } }, certificates: { data: [{ type: 'certificates', id: certId }] } } } })).data;
  fs.writeFileSync(path.join(DIR, 'prohisob-appstore.mobileprovision'), Buffer.from(prof.attributes.profileContent, 'base64'), { mode: 0o600 });
  console.log('profil yaratildi:', prof.id, prof.attributes.expirationDate);
  // 5) GitHub secrets (shifrlangan; CI'da release.sh ishlatadi)
  const c = creds();
  gh(['secret', 'set', 'ASC_KEY_ID', '--repo', REPO], c.keyId);
  gh(['secret', 'set', 'ASC_ISSUER_ID', '--repo', REPO], c.issuer);
  gh(['secret', 'set', 'ASC_KEY_P8', '--repo', REPO], c.key);
  gh(['secret', 'set', 'DIST_P12_B64', '--repo', REPO], fs.readFileSync(p12F).toString('base64'));
  gh(['secret', 'set', 'DIST_P12_PASS', '--repo', REPO], pass);
  gh(['secret', 'set', 'PROFILE_B64', '--repo', REPO], prof.attributes.profileContent);
  gh(['variable', 'set', 'APPLE_TEAM_ID', '--repo', REPO, '--body', team]);
  console.log('GitHub secrets yangilandi. Endi: gh workflow run iOS -f mode=release');
}

// ---------- metadata ----------
const LOCS = { 'en-US': 'en-US', ru: 'ru' };
const read = (loc, f) => { const p = path.join(ROOT, 'appstore', loc, f); return fs.existsSync(p) ? fs.readFileSync(p, 'utf8').trim() : ''; };

async function editableVersion(id) {
  const vs = (await get(`/v1/apps/${id}/appStoreVersions?filter[platform]=IOS&limit=10`)).data;
  return vs.find((v) => ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'WAITING_FOR_REVIEW', 'INVALID_BINARY'].includes(v.attributes.appStoreState || v.attributes.appVersionState))
    || vs[0];
}

async function metadata() {
  const id = await appId();
  if (!id) throw new Error("App Store Connect'da ilova yo'q — avval Apps → «+» → New App (bundle com.prohisob.app)");
  // ilova ma'lumoti: nom, subtitle, maxfiylik havolasi; toifa
  const infos = (await get(`/v1/apps/${id}/appInfos`)).data;
  const info = infos.find((x) => !['READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_INFO'].includes(x.attributes.appStoreState || x.attributes.state)) || infos[0];
  await api('PATCH', `/v1/appInfos/${info.id}`, { data: { type: 'appInfos', id: info.id, relationships: {
    primaryCategory: { data: { type: 'appCategories', id: 'BUSINESS' } }, secondaryCategory: { data: { type: 'appCategories', id: 'FINANCE' } } } } });
  const il = (await get(`/v1/appInfos/${info.id}/appInfoLocalizations`)).data;
  for (const loc of Object.keys(LOCS)) {
    const attrs = { name: read(loc, 'name.txt'), subtitle: read(loc, 'subtitle.txt'), privacyPolicyUrl: read(loc, 'privacy_url.txt') };
    const ex = il.find((x) => x.attributes.locale === LOCS[loc]);
    if (ex) await api('PATCH', `/v1/appInfoLocalizations/${ex.id}`, { data: { type: 'appInfoLocalizations', id: ex.id, attributes: attrs } });
    else await api('POST', '/v1/appInfoLocalizations', { data: { type: 'appInfoLocalizations', attributes: { locale: LOCS[loc], ...attrs },
      relationships: { appInfo: { data: { type: 'appInfos', id: info.id } } } } });
    console.log('ilova nomi:', loc, attrs.name);
  }
  // versiya: 1.0.0, mualliflik, tavsif, kalit so'zlar, havolalar
  const v = await editableVersion(id);
  await api('PATCH', `/v1/appStoreVersions/${v.id}`, { data: { type: 'appStoreVersions', id: v.id, attributes: { versionString: '1.0.0', copyright: `${new Date().getFullYear()} Prohisob` } } });
  const vl = (await get(`/v1/appStoreVersions/${v.id}/appStoreVersionLocalizations`)).data;
  for (const loc of Object.keys(LOCS)) {
    const attrs = { description: read(loc, 'description.txt'), keywords: read(loc, 'keywords.txt'), promotionalText: read(loc, 'promotional_text.txt'),
      supportUrl: read(loc, 'support_url.txt'), marketingUrl: read(loc, 'marketing_url.txt') };
    const ex = vl.find((x) => x.attributes.locale === LOCS[loc]);
    if (ex) await api('PATCH', `/v1/appStoreVersionLocalizations/${ex.id}`, { data: { type: 'appStoreVersionLocalizations', id: ex.id, attributes: attrs } });
    else await api('POST', '/v1/appStoreVersionLocalizations', { data: { type: 'appStoreVersionLocalizations', attributes: { locale: LOCS[loc], ...attrs },
      relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: v.id } } } } });
    console.log('versiya matni:', loc);
  }
}

// ---------- screenshots ----------
const SETS = { phone: 'APP_IPHONE_67' };   // faqat iPhone (TARGETED_DEVICE_FAMILY=1)

async function uploadShot(setId, file) {
  const data = fs.readFileSync(file);
  const s = (await api('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots', attributes: { fileName: path.basename(file), fileSize: data.length },
    relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: setId } } } } })).data;
  for (const op of s.attributes.uploadOperations || []) {
    const part = data.subarray(op.offset, op.offset + op.length);
    const r = await fetch(op.url, { method: op.method, headers: Object.fromEntries((op.requestHeaders || []).map((h) => [h.name, h.value])), body: part });
    if (!r.ok) throw new Error(`yuklash ${r.status}`);
  }
  await api('PATCH', `/v1/appScreenshots/${s.id}`, { data: { type: 'appScreenshots', id: s.id, attributes: { uploaded: true,
    sourceFileChecksum: crypto.createHash('md5').update(data).digest('hex') } } });
}

async function screenshots(dir) {
  const id = await appId();
  if (!id) throw new Error("ilova yo'q");
  const v = await editableVersion(id);
  const vl = (await get(`/v1/appStoreVersions/${v.id}/appStoreVersionLocalizations`)).data;
  for (const loc of Object.keys(LOCS)) {
    const l = vl.find((x) => x.attributes.locale === LOCS[loc]);
    if (!l) { console.log('lokalizatsiya yo\'q:', loc, '— avval metadata'); continue; }
    const sets = (await get(`/v1/appStoreVersionLocalizations/${l.id}/appScreenshotSets`)).data;
    for (const [dev, type] of Object.entries(SETS)) {
      const src = path.join(dir, dev);   // ilova faqat o'zbekcha — ikkala tilga bir xil skrinshotlar
      if (!fs.existsSync(src)) continue;
      let set = sets.find((x) => x.attributes.screenshotDisplayType === type);
      if (set) { // eskilarini o'chiramiz
        for (const s of (await get(`/v1/appScreenshotSets/${set.id}/appScreenshots`)).data) await api('DELETE', `/v1/appScreenshots/${s.id}`);
      } else {
        set = (await api('POST', '/v1/appScreenshotSets', { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: type },
          relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: l.id } } } } })).data;
      }
      const files = fs.readdirSync(src).filter((f) => f.endsWith('.png')).sort((a, b) => parseInt(a) - parseInt(b)).slice(0, 10);
      for (const f of files) await uploadShot(set.id, path.join(src, f));
      console.log('skrinshotlar:', loc, dev, files.length);
    }
  }
}

// ---------- testflight: ichki sinov guruhi (jamoaning App Store Connect foydalanuvchilari), barcha buildlar avtomatik ----------
async function testflight() {
  const id = await appId();
  if (!id) throw new Error("ilova yo'q");
  let g = (await get(`/v1/apps/${id}/betaGroups?limit=50`)).data.find((x) => x.attributes.isInternalGroup);
  if (!g) {
    g = (await api('POST', '/v1/betaGroups', { data: { type: 'betaGroups', attributes: { name: 'Prohisob jamoa', isInternalGroup: true, hasAccessToAllBuilds: true },
      relationships: { app: { data: { type: 'apps', id } } } } })).data;
    console.log('ichki sinov guruhi yaratildi:', g.attributes.name);
  } else console.log('ichki sinov guruhi bor:', g.attributes.name);
  const users = (await get('/v1/users?limit=50')).data;
  const have = new Set((await get(`/v1/betaGroups/${g.id}/betaTesters?limit=200`)).data.map((t) => String(t.attributes.email || '').toLowerCase()));
  let added = 0;
  for (const u of users) {
    const email = String(u.attributes.username || '');
    if (!email || have.has(email.toLowerCase())) continue;
    await api('POST', '/v1/betaTesters', { data: { type: 'betaTesters', attributes: { email, firstName: u.attributes.firstName, lastName: u.attributes.lastName },
      relationships: { betaGroups: { data: [{ type: 'betaGroups', id: g.id }] } } } });
    added++;
  }
  console.log(`sinovchilar: jamoada ${users.length} foydalanuvchi, yangi qo'shildi ${added}`);
}

// ---------- attach: oxirgi tayyor (VALID) buildni tahrirlanadigan App Store versiyasiga biriktirish ----------
async function attach() {
  const id = await appId();
  if (!id) throw new Error("ilova yo'q");
  const b = (await get(`/v1/builds?filter[app]=${id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1`)).data[0];
  if (!b) throw new Error("tayyor build yo'q (qayta ishlanmoqda bo'lishi mumkin)");
  const v = await editableVersion(id);
  await api('PATCH', `/v1/appStoreVersions/${v.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
  console.log(`build ${b.attributes.version} → versiya ${v.attributes.versionString}`);
}

// ---------- submit: tahrirlanadigan versiyani Apple ko'rib chiqishiga yuborish (faqat egasining aniq roziligi bilan!) ----------
async function submit() {
  const id = await appId();
  if (!id) throw new Error("ilova yo'q");
  const v = await editableVersion(id);
  let sub = (await get(`/v1/reviewSubmissions?filter[app]=${id}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW&limit=1`)).data[0];
  if (!sub) sub = (await api('POST', '/v1/reviewSubmissions', { data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' },
    relationships: { app: { data: { type: 'apps', id } } } } })).data;
  const items = (await get(`/v1/reviewSubmissions/${sub.id}/items?include=appStoreVersion&limit=20`)).data;
  if (!items.some((x) => x.relationships?.appStoreVersion?.data?.id === v.id)) {
    await api('POST', '/v1/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: {
      reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } }, appStoreVersion: { data: { type: 'appStoreVersions', id: v.id } } } } });
  }
  const done = (await api('PATCH', `/v1/reviewSubmissions/${sub.id}`, { data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } } })).data;
  console.log(`yuborildi: ${v.attributes.versionString} — holat ${done.attributes.state}`);
}

// ---------- setup: kontent huquqi, bepul narx, mavjudlik (Xitoysiz — ICP talab qilinadi) ----------
async function setup() {
  const id = await appId();
  if (!id) throw new Error("ilova yo'q");
  await api('PATCH', `/v1/apps/${id}`, { data: { type: 'apps', id, attributes: { contentRightsDeclaration: 'DOES_NOT_USE_THIRD_PARTY_CONTENT' } } });
  console.log('kontent huquqi: uchinchi tomon kontenti yo\'q');
  // narx: bepul (asosiy hudud AQSH)
  const pts = await get(`/v1/apps/${id}/appPricePoints?filter[territory]=USA&limit=200`);
  const free = pts.data.find((x) => Number(x.attributes.customerPrice) === 0);
  if (!free) throw new Error('bepul narx nuqtasi topilmadi');
  try {
    await api('POST', '/v1/appPriceSchedules', { data: { type: 'appPriceSchedules', relationships: {
      app: { data: { type: 'apps', id } }, baseTerritory: { data: { type: 'territories', id: 'USA' } },
      manualPrices: { data: [{ type: 'appPrices', id: '${p0}' }] } } },
    included: [{ type: 'appPrices', id: '${p0}', attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: 'appPricePoints', id: free.id } } } }] });
    console.log('narx: bepul');
  } catch (e) { console.log('narx:', e.message); }
  // mavjudlik: barcha hududlar, Xitoydan tashqari; yangi hududlarga ham
  const terr = (await get('/v1/territories?limit=200')).data.map((t) => t.id);
  const inc = terr.map((t, i) => ({ type: 'territoryAvailabilities', id: `\${t${i}}`, attributes: { available: t !== 'CHN' },
    relationships: { territory: { data: { type: 'territories', id: t } } } }));
  try {
    await api('POST', '/v2/appAvailabilities', { data: { type: 'appAvailabilities', attributes: { availableInNewTerritories: true },
      relationships: { app: { data: { type: 'apps', id } }, territoryAvailabilities: { data: inc.map((x) => ({ type: x.type, id: x.id })) } } }, included: inc });
    console.log('mavjudlik:', terr.length - 1, 'hudud (Xitoysiz)');
  } catch (e) { console.log('mavjudlik:', e.message); }
}

// ---------- review: App Review uchun demo hisoblar va izoh (parollar /root/zaxira/prohisob-ios/demo.json dan, repoga tushmaydi) ----------
async function review() {
  const id = await appId();
  if (!id) throw new Error("ilova yo'q");
  const demo = JSON.parse(fs.readFileSync(path.join(DIR, 'demo.json'), 'utf8'));
  const v = await editableVersion(id);
  // aloqa ma'lumoti — jamoaning boshqa ilovasidagi (sam.uz) App Review kontaktidan
  let contact = {};
  const sam = (await get('/v1/apps?filter[bundleId]=uz.sam.app&limit=1')).data[0];
  if (sam) {
    const sv = (await get(`/v1/apps/${sam.id}/appStoreVersions?filter[platform]=IOS&limit=1`)).data[0];
    const rd = sv ? (await get(`/v1/appStoreVersions/${sv.id}/appStoreReviewDetail`).catch(() => null))?.data : null;
    if (rd) contact = Object.fromEntries(['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail'].map((k) => [k, rd.attributes[k]]));
  }
  const notes = [
    'Prohisob is a B2B bookkeeping app for construction foremen in Uzbekistan. The interface is in Uzbek.',
    'Accounts are created by us for each foreman (no in-app sign-up, no purchases). The demo workspace below contains sample data only.',
    '',
    `1) Foreman account — on the sign-in screen keep the "Prorab / xodim" tab: login ${demo.prorab.login}, password ${demo.prorab.parol}.`,
    '   Tabs: Asosiy (dashboard), Obyektlar (projects), Ustalar (workers), Yozuvlar (records), Yana (more). The "+ Yangi yozuv" button adds a record; a receipt photo can be attached from the camera.',
    `2) Property owner (client) account — choose the "Obyekt egasi" tab: login ${demo.mijoz.login}, password ${demo.mijoz.parol}. It shows a read-only view of the owner's own project.`,
    '',
    'Camera/photos are used only to attach receipts; Face ID is an optional app lock (Yana → Xavfsizlik). Feel free to add or delete records in the demo workspace.',
  ].join('\n');
  const attrs = { ...contact, demoAccountRequired: true, demoAccountName: demo.prorab.login, demoAccountPassword: demo.prorab.parol, notes };
  const ex = (await get(`/v1/appStoreVersions/${v.id}/appStoreReviewDetail`).catch(() => null))?.data;
  if (ex) await api('PATCH', `/v1/appStoreReviewDetails/${ex.id}`, { data: { type: 'appStoreReviewDetails', id: ex.id, attributes: attrs } });
  else await api('POST', '/v1/appStoreReviewDetails', { data: { type: 'appStoreReviewDetails', attributes: attrs,
    relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: v.id } } } } });
  console.log('App Review: demo hisob va izoh yozildi; kontakt:', Object.values(contact).filter(Boolean).length ? "bor (sam.uz dan)" : "YO'Q — UI'da to'ldiring");
}

// ---------- beta: tashqi sinovchilar (jamoa a'zosi emas — faqat email; birinchi build Apple Beta App Review'dan o'tadi) ----------
//   beta add <email> [ism]  — «Prohisob sinovchilar» guruhiga qo'shish (+ beta ma'lumotlari: demo hisob, izoh, aloqa)
//   beta build              — oxirgi VALID buildni guruhga berish va Beta App Review'ga yuborish (sinovchilarga email shundan keyin)
const BETA_GROUP = 'Prohisob sinovchilar';
async function betaGroup(id) {
  let g = (await get(`/v1/apps/${id}/betaGroups?limit=50`)).data.find((x) => !x.attributes.isInternalGroup && x.attributes.name === BETA_GROUP);
  if (!g) {
    g = (await api('POST', '/v1/betaGroups', { data: { type: 'betaGroups', attributes: { name: BETA_GROUP, publicLinkEnabled: false },
      relationships: { app: { data: { type: 'apps', id } } } } })).data;
    console.log('tashqi guruh yaratildi:', BETA_GROUP);
  }
  return g;
}
async function betaInfo(id) {
  const demo = JSON.parse(fs.readFileSync(path.join(DIR, 'demo.json'), 'utf8'));
  const v = await editableVersion(id);
  const rd = (await get(`/v1/appStoreVersions/${v.id}/appStoreReviewDetail`).catch(() => null))?.data?.attributes || {};
  const attrs = { contactFirstName: rd.contactFirstName, contactLastName: rd.contactLastName, contactPhone: rd.contactPhone, contactEmail: rd.contactEmail,
    demoAccountRequired: true, demoAccountName: demo.prorab.login, demoAccountPassword: demo.prorab.parol,
    notes: `Interface is in Uzbek. Foreman demo: ${demo.prorab.login} / ${demo.prorab.parol} ("Prorab / xodim" tab). Property owner demo: ${demo.mijoz.login} / ${demo.mijoz.parol} ("Obyekt egasi" tab). Sample data only.` };
  const d = (await get(`/v1/apps/${id}/betaAppReviewDetail`)).data;
  await api('PATCH', `/v1/betaAppReviewDetails/${d.id}`, { data: { type: 'betaAppReviewDetails', id: d.id, attributes: attrs } });
  const locs = (await get(`/v1/apps/${id}/betaAppLocalizations`)).data;
  const desc = { ru: 'Prohisob — учёт строительных объектов для прорабов: объекты, мастера, магазины, расходы и чеки. Интерфейс на узбекском.',
    'en-US': 'Prohisob — construction bookkeeping for foremen: projects, workers, suppliers, expenses and receipts. Uzbek interface.' };
  for (const [locale, description] of Object.entries(desc)) {
    const a = { description, feedbackEmail: rd.contactEmail, marketingUrl: 'https://prohisob.com', privacyPolicyUrl: 'https://cabinet.prohisob.com/maxfiylik' };
    const ex = locs.find((x) => x.attributes.locale === locale);
    if (ex) await api('PATCH', `/v1/betaAppLocalizations/${ex.id}`, { data: { type: 'betaAppLocalizations', id: ex.id, attributes: a } });
    else await api('POST', '/v1/betaAppLocalizations', { data: { type: 'betaAppLocalizations', attributes: { locale, ...a },
      relationships: { app: { data: { type: 'apps', id } } } } });
  }
  console.log('beta ma\'lumotlari: demo hisob, izoh, tavsif (ru, en-US)');
}
async function beta(sub, a1, a2) {
  const id = await appId();
  if (!id) throw new Error("ilova yo'q");
  const g = await betaGroup(id);
  if (sub === 'add') {
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(a1 || '')) throw new Error('email kerak');
    await betaInfo(id);
    const have = (await get(`/v1/betaGroups/${g.id}/betaTesters?limit=200`)).data.map((t) => String(t.attributes.email || '').toLowerCase());
    if (have.includes(a1.toLowerCase())) { console.log('allaqachon guruhda:', a1); return; }
    await api('POST', '/v1/betaTesters', { data: { type: 'betaTesters', attributes: { email: a1, firstName: a2 || undefined },
      relationships: { betaGroups: { data: [{ type: 'betaGroups', id: g.id }] } } } });
    console.log('qo\'shildi:', a1, '— taklif emaili build Beta App Review\'dan o\'tgach keladi (beta build)');
  } else if (sub === 'build') {
    const b = (await get(`/v1/builds?filter[app]=${id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1`)).data[0];
    if (!b) throw new Error("tayyor build yo'q");
    const bl = (await get(`/v1/builds/${b.id}/betaBuildLocalizations`)).data;
    const whatsNew = 'Birinchi versiya: obyektlar, ustalar, magazinlar, yozuvlar va cheklar, hisobot va Excel, obyekt egasi rejimi. Kamchilik topsangiz — TestFlight orqali skrinshot bilan yuboring.';
    for (const locale of ['ru', 'en-US']) {
      const ex = bl.find((x) => x.attributes.locale === locale);
      if (ex) await api('PATCH', `/v1/betaBuildLocalizations/${ex.id}`, { data: { type: 'betaBuildLocalizations', id: ex.id, attributes: { whatsNew } } });
      else await api('POST', '/v1/betaBuildLocalizations', { data: { type: 'betaBuildLocalizations', attributes: { locale, whatsNew },
        relationships: { build: { data: { type: 'builds', id: b.id } } } } });
    }
    await api('POST', `/v1/betaGroups/${g.id}/relationships/builds`, { data: [{ type: 'builds', id: b.id }] }).catch((e) => console.log('guruhga:', e.message));
    try {
      await api('POST', '/v1/betaAppReviewSubmissions', { data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: b.id } } } } });
      console.log(`build ${b.attributes.version} → Beta App Review'ga yuborildi`);
    } catch (e) { console.log('Beta App Review:', e.message); }
  } else {
    const ts = (await get(`/v1/betaGroups/${g.id}/betaTesters?limit=200`)).data;
    console.log(`${BETA_GROUP}: ${ts.map((t) => `${t.attributes.email} (${t.attributes.state || '-'})`).join(', ') || "bo'sh"}`);
  }
}

// ---------- status ----------
async function status() {
  const id = await appId();
  if (!id) { console.log("ilova yo'q"); return; }
  const builds = (await get(`/v1/builds?filter[app]=${id}&sort=-uploadedDate&limit=5`)).data;
  console.log('buildlar:', builds.map((b) => `${b.attributes.version} ${b.attributes.processingState} ${b.attributes.uploadedDate}`).join(' | ') || "yo'q");
  const vs = (await get(`/v1/apps/${id}/appStoreVersions?limit=5`)).data;
  console.log('versiyalar:', vs.map((v) => `${v.attributes.versionString} ${v.attributes.appStoreState || v.attributes.appVersionState}`).join(' | '));
}

const [cmd, arg, arg2, arg3] = process.argv.slice(2);
const run = { check, signing: () => signing(arg), metadata, setup, review, beta: () => beta(arg, arg2, arg3), screenshots: () => screenshots(arg), testflight, attach, submit, status }[cmd];
if (!run) { console.log('buyruqlar: check | signing <TEAM_ID> | metadata | setup | review | beta add <email> [ism] | beta build | beta | screenshots <papka> | testflight | attach | submit | status'); process.exit(1); }
run().catch((e) => { console.error('XATO:', e.message); process.exit(1); });
