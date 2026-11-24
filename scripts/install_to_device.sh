#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
WORKING_LOCATION="$(pwd)"
IPA_PATH="$WORKING_LOCATION/build/Audia.ipa"

if [ "${1:-}" != "--no-build" ] || [ ! -f "$IPA_PATH" ]; then
    echo "=== Building latest IPA ==="
    ./build_ipa.sh
fi

# Detect connected device
DEV_LINE="$(xcrun devicectl list devices 2>/dev/null | grep -v "unavailable" | grep -E "connected|available" | grep "physical" | head -n 1 || true)"
if [ -z "$DEV_LINE" ]; then
    echo "ERROR: No physical iOS device connected or available."
    echo "Please connect your iPhone via USB / WiFi and unlock it."
    exit 1
fi

DEV_ID="$(echo "$DEV_LINE" | awk '{print $3}')"
DEV_NAME="$(echo "$DEV_LINE" | awk '{print $1, $2}')"
echo "Detected connected device: $DEV_NAME ($DEV_ID)"

PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [ ! -d "$PROFILES_DIR" ]; then
    PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
fi

find_profile_for_bundle_id() {
    local target_id="$1"
    for p in "$PROFILES_DIR"/*.mobileprovision; do
        [ -f "$p" ] || continue
        local app_id
        app_id="$(security cms -D -i "$p" 2>/dev/null | plutil -extract "Entitlements.application-identifier" raw - 2>/dev/null || true)"
        if [[ "$app_id" == *".$target_id" || "$app_id" == "$target_id" ]]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

MAIN_PROF="$(find_profile_for_bundle_id "com.akshayysk.Audia")"
if [ -z "$MAIN_PROF" ]; then
    echo "ERROR: No provisioning profile found for com.akshayysk.Audia."
    exit 1
fi
echo "Found main app profile: $(basename "$MAIN_PROF")"

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
# Ensure explicit shared keychain access group is set
/usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" /tmp/main_entitlements.plist 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" /tmp/main_entitlements.plist
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string A3XSATPZS9.com.akshayysk.Audia" /tmp/main_entitlements.plist
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
    EXT_PROF="$(find_profile_for_bundle_id "com.akshayysk.Audia.$EXT_NAME")"
    if [ -n "$EXT_PROF" ]; then
        echo "Found profile for extension $EXT_NAME: $(basename "$EXT_PROF")"
        security cms -D -i "$EXT_PROF" > /tmp/ext_profile.plist
        /usr/libexec/PlistBuddy -x -c "Print :Entitlements" /tmp/ext_profile.plist > /tmp/ext_entitlements.plist
        # Ensure explicit shared keychain access group is set
        /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" /tmp/ext_entitlements.plist 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" /tmp/ext_entitlements.plist
        /usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string A3XSATPZS9.com.akshayysk.Audia" /tmp/ext_entitlements.plist
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
