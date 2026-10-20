#!/bin/bash
# App Store Connect'ga yuklash (CI, macOS): tarqatish sertifikati (.p12) va App Store profili GitHub maxfiy o'zgaruvchilaridan,
# yuklash — App Store Connect API kaliti bilan. Build raqami: BUILD_NUMBER (GitHub run raqami). Kalitlar repozitoriyga tushmaydi.
# Kerakli o'zgaruvchilar: TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, DIST_P12_B64, DIST_P12_PASS, PROFILE_B64, BUILD_NUMBER
set -euo pipefail
cd "$(dirname "$0")/.."
for v in TEAM_ID ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 DIST_P12_B64 DIST_P12_PASS PROFILE_B64 BUILD_NUMBER; do
  [ -n "${!v:-}" ] || { echo "yo'q: $v"; exit 1; }
done
TMP=${RUNNER_TEMP:-$(mktemp -d)}
KC="$TMP/prohisob.keychain-db"
KC_PASS=$(uuidgen)
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
printf '%s' "$DIST_P12_B64" | base64 --decode > "$TMP/dist.p12"
security import "$TMP/dist.p12" -P "$DIST_P12_PASS" -A -t cert -f pkcs12 -k "$KC"
# Apple WWDR oraliq sertifikati (Apple Distribution shu bilan imzolangan)
curl -fsSL -o "$TMP/AppleWWDRCAG3.cer" https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security import "$TMP/AppleWWDRCAG3.cer" -k "$KC" -t cert -f DER || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" > /dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
printf '%s' "$PROFILE_B64" | base64 --decode > "$TMP/prohisob.mobileprovision"
security cms -D -i "$TMP/prohisob.mobileprovision" > "$TMP/profile.plist"
P_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$TMP/profile.plist")
P_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' "$TMP/profile.plist")
for d in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$d" && cp "$TMP/prohisob.mobileprovision" "$d/$P_UUID.mobileprovision"
done
mkdir -p "$HOME/.appstoreconnect/private_keys"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_KEY_P8" > "$KEY"
echo "profil: $P_NAME ($P_UUID), build: $BUILD_NUMBER"
xcodebuild -project Prohisob.xcodeproj -scheme Prohisob -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$TMP/Prohisob.xcarchive" archive \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER="$P_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" 2>&1 | tee build.log | xcbeautify --quiet
cat > "$TMP/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key><dict><key>com.prohisob.app</key><string>$P_NAME</string></dict>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$TMP/Prohisob.xcarchive" -exportOptionsPlist "$TMP/ExportOptions.plist" -exportPath "$TMP/export" \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" 2>&1 | tee -a build.log | xcbeautify --quiet
rm -f "$KEY" "$TMP/dist.p12"
security delete-keychain "$KC" || true
echo "yuklandi: build $BUILD_NUMBER — App Store Connect → TestFlight (qayta ishlash 5–30 daqiqa)"
