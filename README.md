# Prohisob — iOS ilova

Prorablar uchun qurilish hisobi: obyektlar, ustalar, magazinlar, kirim-chiqim, cheklar, hisobot va Excel.
Ma'lumot — [cabinet.prohisob.com](https://cabinet.prohisob.com) kabineti bilan bir xil (server API, `docs/API.md`).
Ikki rejim: **prorab / xodim** (to'liq kabinet) va **obyekt egasi** (faqat o'z obyektining hisobini ko'radi).

SwiftUI, iOS 17+, Xcode 26 (iOS 26 da Liquid Glass o'zi yoqiladi), faqat iPhone, interfeys o'zbekcha. Paket: `com.prohisob.app`.

## Tuzilishi
- `project.yml` — XcodeGen loyihasi (`.xcodeproj` gitda yo'q, CI'da `xcodegen generate`).
- `Prohisob/App` — ilova qobig'i (`ProhisobApp.swift`: kirish/kabinet/mijoz, pastki menyu, «Yangi yozuv», Face ID qulfi),
  `Session` (token Keychain'da, /api/me, kabinet, dataVersion, xabarlar), `Router` (bo'limlar, Route), `ShotMode` (skrinshotlar).
- `Prohisob/Data` — `API` (Bearer token, X-Kabinet, multipart), `Models`, `EntryType` (10 amal turi), `Format` (so'm, sana), `Keychain`.
- `Prohisob/UI` — `Theme` (ranglar), `Glass` (Liquid Glass), `Components` (karta, summa, yozuv qatori, chek ko'rish…).
- `Prohisob/Screens` — Home (Asosiy), Objects, Workers, Shops, Entries (ro'yxat, yozuv, yangi yozuv), Report, Account
  (kirish, Yana, sozlamalar, mijozlar, xodimlar), Client (obyekt egasi rejimi).
- `tools/appicon.mjs` — ikonka va ranglar; `tools/asc.mjs` — App Store Connect API (serverdan).

## Yig'ish (Mac kerak emas — GitHub Actions, `.github/workflows/ios.yml`)
- Har push — simulyator uchun yig'ish (kompilyatsiya xatolari Actions'da).
- `gh workflow run iOS -f mode=shots` — App Store skrinshotlari (demo kabinet; login-parol GitHub secrets'da) → artifact `shots`.
- `gh workflow run iOS -f mode=release` — App Store Connect'ga yuklash (TestFlight). Build raqami — Actions run raqami.
  Kerak: secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `DIST_P12_B64`, `DIST_P12_PASS`, `PROFILE_B64`, variable `APPLE_TEAM_ID`.

Kalitlar, sertifikatlar va demo parollar repoda **yo'q** (serverda `/root/zaxira/prohisob-ios`, GitHub secrets).
