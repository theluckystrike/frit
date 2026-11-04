#!/bin/bash
# Build a universal release binary and assemble build/<APP_NAME>.app, signed ad hoc for local testing only.
# Usage: tools/bundle.sh            (needs ~/bin/buildslot; no Xcode, Command Line Tools only)
#        GLAZE_CONFIG=debug GLAZE_ARCHS=arm64 tools/bundle.sh   -> build/debug/<APP_NAME>.app, QA only (G11):
#        the debug build alone reads the QA launch argument -FritQAVisibleSize WxH. Never ship it.
# The ad hoc signature is not for distribution. Nothing here talks to Apple.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

# ---- Names (placeholders until the owner picks the final name: change them here only) ----
APP_NAME="${APP_NAME:-Frit}"
BUNDLE_ID="${BUNDLE_ID:-com.michaellip.frit}"
VERSION="1.3.1"
BUILD_NUMBER="6"
COPYRIGHT="Copyright © 2026 Michael Lip. All rights reserved."
PRODUCT="GlazeApp"                       # SwiftPM executable product
RESOURCE_BUNDLE="Glaze_GlazeCore.bundle" # SwiftPM resource bundle: <package name>_<target name>
ICON="$HOME/glaze-work/brand/icon/AppIcon.icns"
ENTITLEMENTS="$ROOT/Support/App.entitlements"
DOC_TYPES="$ROOT/Support/GlazeApp-DocumentTypes.plist"
PRIVACY="$ROOT/Support/PrivacyInfo.xcprivacy"
TIMEOUT="${GLAZE_BUILD_TIMEOUT:-1500}"
ARCHS="${GLAZE_ARCHS:-arm64 x86_64}"   # GLAZE_ARCHS=arm64 for a quicker local-only build
CONFIG="${GLAZE_CONFIG:-release}"      # release (the product) or debug (QA only)
case "$CONFIG" in
  release) APP="$ROOT/build/$APP_NAME.app" ;;
  debug)   APP="$ROOT/build/debug/$APP_NAME.app" ;;
  *) echo "bundle: GLAZE_CONFIG must be release or debug" >&2; exit 1 ;;
esac
say() { echo "bundle: $*" >&2; }

for f in "$ICON" "$ENTITLEMENTS" "$DOC_TYPES" "$PRIVACY"; do
  [ -f "$f" ] || { say "missing $f"; exit 1; }
done

# ---- Build: one slice per architecture, then lipo (universal --arch builds need Xcode's xcbuild) ----
BIN_DIRS=()
for arch in $ARCHS; do
  triple="$arch-apple-macosx14.0"
  say "building $arch"
  timeout "$TIMEOUT" "$HOME/bin/buildslot" swift build -c "$CONFIG" --triple "$triple" --product "$PRODUCT"
  BIN_DIRS+=("$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)")
done

# ---- Assemble ----
rm -rf "$APP"
mkdir -p "$(dirname "$APP")" "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINS=(); for d in "${BIN_DIRS[@]}"; do BINS+=("$d/$PRODUCT"); done
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
# Resources are the same for both slices. GlazeCore looks for the bundle in Contents/Resources first.
cp -R "${BIN_DIRS[0]}/$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$PRIVACY" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Info.plist: base keys plus the document types and exported UTI from Support/.
/usr/bin/python3 -I - "$APP/Contents/Info.plist" "$DOC_TYPES" <<PY
import plistlib, sys
out, doc_types = sys.argv[1], sys.argv[2]
info = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleExecutable": "$APP_NAME",
    "CFBundleIdentifier": "$BUNDLE_ID",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$APP_NAME",
    "CFBundleDisplayName": "$APP_NAME",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$VERSION",
    "CFBundleVersion": "$BUILD_NUMBER",
    "CFBundleIconFile": "AppIcon",
    "CFBundleSupportedPlatforms": ["MacOSX"],
    "LSMinimumSystemVersion": "14.0",
    "LSApplicationCategoryType": "public.app-category.education",
    "NSHumanReadableCopyright": "$COPYRIGHT",
    "NSPrincipalClass": "NSApplication",
    "NSHighResolutionCapable": True,
    "NSSupportsSuddenTermination": False,
    "ITSAppUsesNonExemptEncryption": False,
}
with open(doc_types, "rb") as f:
    extra = plistlib.load(f)
for key in ("CFBundleDocumentTypes", "UTExportedTypeDeclarations"):
    info[key] = extra[key]
with open(out, "wb") as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_XML, sort_keys=True)
PY

# ---- Static App Store checks (W6 X5): entitlements, Info.plist keys, no Glazy data, privacy manifest ----
/usr/bin/python3 -I "$ROOT/tools/compliance.py" "$APP" "$ENTITLEMENTS"

# ---- Sign ad hoc (local testing only) ----
xattr -cr "$APP"
codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" -s - "$APP"

# ---- Verify ----
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" "$ENTITLEMENTS"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"
say "done: $APP"
