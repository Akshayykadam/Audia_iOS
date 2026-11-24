#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
WORKING_LOCATION="$(pwd)"
IPA_PATH="$WORKING_LOCATION/build/Audia.ipa"

if [ ! -f "$IPA_PATH" ]; then
    echo "IPA not found at $IPA_PATH. Building IPA first..."
    ./build_ipa.sh
fi

# Detect connected device
DEV_LINE="$(xcrun devicectl list devices 2>/dev/null | grep "connected" | grep "physical" | head -n 1 || true)"
if [ -z "$DEV_LINE" ]; then
    echo "ERROR: No physical iOS device connected in 'connected' state."
    echo "Please connect your iPhone via USB / WiFi and unlock it."
    exit 1
fi

DEV_ID="$(echo "$DEV_LINE" | awk '{print $3}')"
DEV_NAME="$(echo "$DEV_LINE" | awk '{print $1}')"
echo "Detected connected device: $DEV_NAME ($DEV_ID)"

PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [ ! -d "$PROFILES_DIR" ]; then
    PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
fi

MAIN_PROF="$(find "$PROFILES_DIR" -name "*.mobileprovision" -exec grep -l "com.akshayysk.Audia" {} + 2>/dev/null | head -n 1 || true)"
if [ -z "$MAIN_PROF" ]; then
    echo "ERROR: No provisioning profile found for com.akshayysk.Audia."
    exit 1
fi

CERT="$(security find-identity -p codesigning -v | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')"
if [ -z "$CERT" ]; then
    echo "ERROR: No valid Apple Development certificate found in keychain."
    exit 1
fi

STAGE_DIR="/tmp/audia_device_install"
APP_DIR="$STAGE_DIR/Payload/Audia.app"

echo "=== Staging and signing for direct installation ==="
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
unzip -q "$IPA_PATH" -d "$STAGE_DIR"

# Extract main entitlements from profile
security cms -D -i "$MAIN_PROF" > /tmp/main_profile.plist
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" /tmp/main_profile.plist > /tmp/main_entitlements.plist
cp "$MAIN_PROF" "$APP_DIR/embedded.mobileprovision"

# Sign frameworks
for fw in "$APP_DIR/Frameworks"/*.framework; do
    [ -d "$fw" ] || continue
    codesign --force --sign "$CERT" --timestamp=none "$fw" 2>/dev/null || true
done

# Sign extensions if profiles exist, otherwise strip for direct single-profile install
for ext in "$APP_DIR/PlugIns"/*.appex; do
    [ -d "$ext" ] || continue
    EXT_NAME="$(basename "$ext" .appex)"
    EXT_PROF="$(find "$PROFILES_DIR" -name "*.mobileprovision" -exec grep -l "com.akshayysk.Audia.$EXT_NAME" {} + 2>/dev/null | head -n 1 || true)"
    if [ -n "$EXT_PROF" ]; then
        security cms -D -i "$EXT_PROF" > /tmp/ext_profile.plist
        /usr/libexec/PlistBuddy -x -c "Print :Entitlements" /tmp/ext_profile.plist > /tmp/ext_entitlements.plist
        cp "$EXT_PROF" "$ext/embedded.mobileprovision"
        codesign --force --sign "$CERT" --entitlements /tmp/ext_entitlements.plist --timestamp=none "$ext"
    else
        echo "Note: No specific profile for $EXT_NAME, removing for direct device install."
        rm -rf "$ext"
    fi
done

# Sign main app
codesign --force --sign "$CERT" --entitlements /tmp/main_entitlements.plist --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "=== Installing directly to $DEV_NAME ==="
xcrun devicectl device install app --device "$DEV_ID" "$APP_DIR"

echo "=== Launching Audia ==="
xcrun devicectl device process launch --device "$DEV_ID" com.akshayysk.Audia

echo "=== Done! Audia is running on $DEV_NAME ==="
