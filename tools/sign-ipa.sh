#!/bin/bash
# sign-ipa.sh — Re-sign an unsigned OpenMinis AutoPilot IPA for sideloading.
# Must run on macOS (uses codesign / PlistBuddy / ditto). The signing certificate
# must already be imported into the active keychain.
#
# Usage:
#   sign-ipa.sh <unsigned.ipa> <identity> <profile.mobileprovision> <output.ipa> [bundle_id]
#
# What it does:
#   1. Unpack the IPA (ditto, keeps symlinks/permissions)
#   2. Strip PlugIns — extensions need their own matching profiles and a single
#      concrete App ID profile cannot cover them
#   3. Rewrite CFBundleIdentifier to match the provisioning profile's App ID
#   4. Build a clean entitlements plist (compatible subset of the profile)
#   5. Sign inside-out: Frameworks Mach-O → .framework bundles → app bundle
#   6. Embed the provisioning profile and repack the IPA
set -euo pipefail

IPA="$1"
IDENTITY="$2"
PROFILE="$3"
OUT="$4"
BUNDLE_ID="${5:-}"

[ -f "$IPA" ] || { echo "✗ IPA not found: $IPA"; exit 1; }
[ -f "$PROFILE" ] || { echo "✗ Profile not found: $PROFILE"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "▶ workdir: $WORK"

# ── 1. Unpack ──────────────────────────────────────────
cd "$WORK"
ditto -x -k "$IPA" unpacked
APP=""
for d in unpacked/Payload/*.app; do
  if [ -d "$d" ]; then APP="$d"; break; fi
done
[ -n "$APP" ] || { echo "✗ No .app found in Payload"; exit 1; }
echo "▶ app: $APP"

# ── 2. Strip extensions ───────────────────────────────
if [ -d "$APP/PlugIns" ]; then
  echo "▶ stripping PlugIns: $(ls "$APP/PlugIns" | tr '\n' ' ')"
  rm -rf "$APP/PlugIns"
fi
find "$APP" -name "*.appex" -exec rm -rf {} + 2>/dev/null || true

# ── 3. Read provisioning profile ──────────────────────
echo "▶ reading provisioning profile"
security cms -D -i "$PROFILE" > profile.plist
PROFILE_APPID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" profile.plist)
PROFILE_TEAM=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" profile.plist)
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" profile.plist)
if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID="${PROFILE_APPID#*.}"
fi
echo "▶ profile: $PROFILE_NAME"
echo "▶ profile app-id: $PROFILE_APPID"
echo "▶ target bundle id: $BUNDLE_ID"

# ── 4. Rewrite bundle id ──────────────────────────────
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
echo "▶ CFBundleIdentifier → $BUNDLE_ID"

# ── 5. Entitlements (subset compatible with profile) ──
cat > entitlements.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>$PROFILE_APPID</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$PROFILE_TEAM</string>
	<key>keychain-access-groups</key>
	<array>
		<string>$PROFILE_APPID</string>
	</array>
	<key>get-task-allow</key>
	<false/>
	<key>com.apple.developer.kernel.increased-memory-limit</key>
	<true/>
	<key>com.apple.developer.kernel.extended-virtual-addressing</key>
	<true/>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array>
		<string>health-records</string>
	</array>
	<key>com.apple.developer.homekit</key>
	<true/>
	<key>com.apple.developer.weatherkit</key>
	<true/>
	<key>com.apple.developer.nfc.readersession.formats</key>
	<array>
		<string>TAG</string>
		<string>PACE</string>
	</array>
</dict>
</plist>
EOF
echo "▶ entitlements written"

# ── 6. Embed provisioning profile ─────────────────────
cp "$PROFILE" "$APP/embedded.mobileprovision"

# ── 7. Sign inside-out ────────────────────────────────
echo "▶ signing Frameworks Mach-O files..."
if [ -d "$APP/Frameworks" ]; then
  find "$APP/Frameworks" -type f -print0 | while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q "Mach-O"; then
      codesign --force --sign "$IDENTITY" "$f" || echo "  warn: sign failed: $f"
    fi
  done
  echo "▶ signing .framework bundles..."
  find "$APP/Frameworks" -depth -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
    codesign --force --sign "$IDENTITY" "$fw" || echo "  warn: sign failed: $fw"
  done
fi

echo "▶ signing app bundle..."
codesign --force --sign "$IDENTITY" --entitlements entitlements.plist "$APP"

echo "▶ verifying..."
codesign --verify --deep --strict "$APP"

# ── 8. Repack ─────────────────────────────────────────
echo "▶ repacking IPA"
ditto -c -k --sequesterRsrc --keepParent unpacked/Payload "$OUT"
echo "✓ done: $OUT ($(stat -f%z "$OUT") bytes)"
echo "   md5: $(md5 -q "$OUT")"
