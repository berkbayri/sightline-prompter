#!/usr/bin/env bash
# Builds the Mac App Store package: a universal, sandboxed, distribution-signed .app inside a signed .pkg.
#
# Without signing variables it only assembles and checks the bundle (safe to run any time).
# To produce the uploadable package, set all of these:
#   TEAM_ID          Apple Developer team ID (10 characters, App Store Connect > Membership)
#   APP_SIGN         e.g. "Apple Distribution: Your Name (TEAMID)"   (see: security find-identity -v -p codesigning)
#   PKG_SIGN         e.g. "3rd Party Mac Developer Installer: Your Name (TEAMID)" or "Mac Installer Distribution: ..."
#   PROFILE          path to the "Mac App Store Connect" .provisionprofile for com.berkbayri.SightlinePrompter
# Optional:
#   BUILD_NUMBER     CFBundleVersion for this upload (must be higher than every earlier upload). Default: current value.
#   VERSION          CFBundleShortVersionString. Default: current value.
#
# Upload the resulting .pkg with the Transporter app (or: xcrun altool --upload-package).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

OUT="$HOME/Library/Caches/SightlinePrompter/appstore"
SCRATCH="$HOME/Library/Caches/SightlinePrompter/build-universal"
APP="$OUT/Sightline Prompter.app"
PKG="$OUT/SightlinePrompter.pkg"
PLIST="$APP/Contents/Info.plist"

echo "==> Building universal release (arm64 + x86_64)..."
mkdir -p "$OUT" "$SCRATCH"
swift build -c release --product SightlinePrompter --scratch-path "$SCRATCH" --arch arm64 --arch x86_64
BIN="$(swift build -c release --product SightlinePrompter --scratch-path "$SCRATCH" --arch arm64 --arch x86_64 --show-bin-path)/SightlinePrompter"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SightlinePrompter"
cp "$ROOT/macOS/Resources/Info.plist" "$PLIST"
cp "$ROOT/macOS/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/macOS/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
[ -n "${VERSION:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
[ -n "${BUILD_NUMBER:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

echo "==> Checks"
lipo -archs "$APP/Contents/MacOS/SightlinePrompter"
if otool -L "$APP/Contents/MacOS/SightlinePrompter" | awk '/^\t/' | grep -E "@rpath|/Users/|/Library/Caches" ; then
  echo "!! the binary links a library outside the system; it must be embedded in Contents/Frameworks" >&2; exit 1
fi
plutil -lint "$PLIST" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" "$ROOT/macOS/Resources/SightlinePrompter.entitlements"
echo "version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST") build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

if [ -z "${TEAM_ID:-}" ] || [ -z "${APP_SIGN:-}" ] || [ -z "${PKG_SIGN:-}" ] || [ -z "${PROFILE:-}" ]; then
  echo "==> TEAM_ID / APP_SIGN / PKG_SIGN / PROFILE not set: bundle assembled and checked, not signed."
  exit 0
fi

echo "==> Signing"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
ENT="$OUT/entitlements.plist"
cp "$ROOT/macOS/Resources/SightlinePrompter.entitlements" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENT"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
xattr -cr "$APP"
codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$APP_SIGN" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Packaging $PKG"
rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$PKG_SIGN" "$PKG"
pkgutil --check-signature "$PKG" | head -4
echo "==> Done. Upload $PKG with the Transporter app."
