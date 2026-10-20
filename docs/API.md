# Prohisob API (iOS ilova uchun)

Server: `https://cabinet.prohisob.com` (kodi serverda `/opt/prorab`, bu repoda emas). Namuna javoblar — `docs/samples/*.json`
(demo kabinet, soxta ma'lumot). Ilovada hamma so'rov `API.shared` orqali (`Prohisob/Data/API.swift`), modellar —
`Prohisob/Data/Models.swift`. Kalitlar snake_case → Swift'da camelCase (dekoder o'zi o'giradi, CodingKeys yozilmaydi).

## Kirish
| | |
|---|---|
| `POST /api/login` `{username, password, app:"ios", device}` | → `{user, token}` (prorab/xodim/egasi). Xato: 401/429 `{error}` |
| `POST /api/mijoz/login` `{login, password, device}` | → `{token, mijoz}` (obyekt egasi) |
| `POST /api/logout`, `POST /api/mijoz/logout` | token bekor qilinadi |
| `GET /api/me` | `{user, company, kabinet, kabinetlar}` (`kabinetlar` faqat egasiga) |
| `POST /api/parol` `{eski, yangi}` | parol almashadi, boshqa qurilmalar chiqadi |
| `GET /api/app/config` | `{ios:{minBuild, latestBuild, storeUrl}, sayt, yordam}` (sessiyasiz) |

Token: `Authorization: Bearer <64 hex>`. Egasi kabinet tanlasa: `X-Kabinet: <id>`. 401 → sessiya tugagan (API o'zi chiqaradi).

## Prorab / xodim
| | |
|---|---|
| `GET /api/dashboard?from&to` | `Dashboard`: stats, oxirgi (12), obyektlar (6), qarzdor_ustalar, qarzdor_magazinlar |
| `GET /api/objects` · `GET /api/objects/:id` | `[ObjectItem]` · `ObjectDetail` (summary, ustalar, magazinlar, tarix ≤500, mijozlar) |
| `POST /api/objects` · `PUT /api/objects/:id` | `ObjectBody` → obyekt |
| `DELETE /api/objects/:id` | faqat prorab/egasi; yozuvi bor obyekt o'chmaydi (server xabari) |
| `GET/POST/PUT/DELETE /api/workers[/:id]` | `Worker`, `WorkerDetail`, `WorkerBody` |
| `GET/POST/PUT/DELETE /api/shops[/:id]` | `Shop`, `ShopDetail`, `ShopBody` |
| `GET /api/entries?object_id&worker_id&shop_id&type&from&to&q&limit&offset` | `EntriesPage {rows, total}` (limit ≤ 2000, standart 200) |
| `POST /api/entries` | `NewEntryBody` → yaratilgan yozuv `{id,…}`; xarid + paid_now → bog'liq magazin_tolov ham yoziladi |
| `GET /api/entries/:id` | `EntryDetail` (cheklar ro'yxati, bogliq) |
| `DELETE /api/entries/:id` | xodim — faqat o'zinikini; bog'liq to'lov ham o'chadi |
| `POST /api/entries/:id/files` | multipart `files` (jpg/png/webp/heic/pdf, ≤10 ta, ≤20 MB) → `{ok, cheklar}` |
| `GET /api/files/:id` · `DELETE /api/files/:id` | chek fayli (token bilan) · o'chirish |
| `GET /api/report?from&to` | `Report`: stats, perObject, perMonth (24 oy), ustalar, magazinlar |
| `GET /api/export.xlsx?object_id&worker_id&shop_id&type&from&to&q` | Excel fayl (bezatilgan, 2 varaq) |
| `GET/POST/PUT/DELETE /api/clients[/:id]` | obyekt egalari (faqat prorab/egasi): `ClientsResponse`, `ClientBody` |
| `GET/POST/PUT/DELETE /api/users[/:id]` | xodimlar (prorab — faqat o'z kabinetidagi xodimlar): `UserRow`, `UserBody` |

## Obyekt egasi (mijoz)
| | |
|---|---|
| `GET /api/mijoz/me` | `MijozMe`: mijoz, prorab, obyektlar (qisqa hisobi bilan) |
| `GET /api/mijoz/objects/:id` | `MijozObjectDetail`: hisob, tarkib, ustalarga/magazinlarga berilgan |
| `GET /api/mijoz/objects/:id/entries?limit&offset` | `MijozEntriesPage` (limit ≤ 100) |
| `GET /api/mijoz/entries/:id/files` | `[FileInfo]` (xarid bilan to'langan bo'lsa — xarid cheki) |
| `GET /api/mijoz/files/:id` | chek fayli |

Mijoz faqat o'zi bergan pulni va real xarajatni ko'radi: ustaga hisoblangan haq, qarzlar, prorab foydasi, kim kiritgani — yo'q.

## Hisob qoidasi (prorab talabi, 2026-10-04)
- **Jami xarajat** = haqiqatda berilgan pul (`usta_tolov + magazin_tolov + obyekt_xarajat + ovqat + xarajat`) — `jamiXarajat`.
- **Qo'ldagi pul** = kirim − jami xarajat (`qoldagiPul`).
- Ustaga hisoblangan, lekin berilmagan haq va magazinga to'lanmagan mol — **qarzlarda** (`ustaQarz`, `magazinQarz`).
- **Sof foyda** faqat **tugagan** obyektda ko'rsatiladi (`ObjectItem.foydaKorinadi`, dashboard `tugaganFoyda`).
