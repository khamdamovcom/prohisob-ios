#!/bin/bash
# App Store skrinshotlari (CI, macOS): ilovani simulyatorda -shot rejimida ochib rasmga oladi — iPhone 6.9" (1320×2868).
# Ilova demo kabinetga o'zi kiradi: login-parol GitHub secrets → SIMCTL_CHILD_* (ilova muhitiga o'tadi, logga chiqmaydi).
# Natija: shots/phone/<n>-<nom>.png. Boshqa ro'yxat: SHOT_LIST="home=bosh entry-new=yozuv" (ekran=nom), THEME=dark
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${OUT:-shots}
WAIT=${WAIT:-7}
xcodebuild -project Prohisob.xcodeproj -scheme Prohisob -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build.log | xcbeautify --quiet
APP=$(find build/Build/Products -maxdepth 2 -name 'Prohisob.app' -path '*iphonesimulator*' | head -1)
[ -d "$APP" ] || { echo "Prohisob.app topilmadi"; exit 1; }
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
r = [x for x in json.load(sys.stdin)['runtimes'] if x.get('platform') == 'iOS' and x.get('isAvailable')]
r.sort(key=lambda x: [int(p) for p in x['version'].split('.')])
print(r[-1]['identifier'])")
PHONE=$(xcrun simctl list devicetypes -j | python3 -c "
import json, re, sys
ts = json.load(sys.stdin)['devicetypes']
c = sorted([t for t in ts if re.search(r'^iPhone 1[6-9] Pro Max$', t['name'])], key=lambda t: t['name'])
print(c[-1]['identifier'] if c else '')")
echo "runtime=$RUNTIME phone=$PHONE"
# App Store to'plami: 1 asosiy, 2 obyekt, 3 yangi yozuv, 4 ustalar, 5 usta, 6 yozuvlar, 7 hisobot, 8 obyekt egasi, 9 qorong'i mavzu
SHOTS=("home" "object" "entry-new" "workers" "worker" "entries" "report" "client-object" "home")
NAMES=("home" "object" "entry-new" "workers" "worker" "entries" "report" "client" "dark")
if [ -n "${SHOT_LIST:-}" ]; then
  SHOTS=(); NAMES=()
  for p in $SHOT_LIST; do SHOTS+=("${p%%=*}"); NAMES+=("${p##*=}"); done
fi
export SIMCTL_CHILD_DEMO_LOGIN="${DEMO_LOGIN:-}" SIMCTL_CHILD_DEMO_PAROL="${DEMO_PAROL:-}"
export SIMCTL_CHILD_DEMO_MIJOZ_LOGIN="${DEMO_MIJOZ_LOGIN:-}" SIMCTL_CHILD_DEMO_MIJOZ_PAROL="${DEMO_MIJOZ_PAROL:-}"
UDID=$(xcrun simctl create "shot-phone" "$PHONE" "$RUNTIME")
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"
# birinchi ochilish — tizim oynalari o'tib ketsin
xcrun simctl launch "$UDID" com.prohisob.app -shot home > /dev/null; sleep ${WARMUP:-25}
mkdir -p "$OUT/phone"
for i in "${!SHOTS[@]}"; do
  theme=${THEME:-light}; [ "${NAMES[$i]}" = dark ] && theme=dark
  xcrun simctl terminate "$UDID" com.prohisob.app 2> /dev/null || true
  xcrun simctl launch "$UDID" com.prohisob.app -shot "${SHOTS[$i]}" -theme "$theme" > /dev/null
  sleep "$WAIT"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/phone/$((i + 1))-${NAMES[$i]}.png" > /dev/null
  echo "$((i + 1)) ${NAMES[$i]} ($theme)"
done
xcrun simctl shutdown "$UDID" || true
xcrun simctl delete "$UDID" || true
