#!/bin/bash
# Create and verify an archive. No upload or provisioning changes are requested.
set -euo pipefail
FRIT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$FRIT_ROOT/tools/xcode_preflight.sh"
frit_xcode_preflight
cd "$FRIT_ROOT"
FRIT_GIT_STATUS=$(git status --porcelain --untracked-files=all) || { echo "Cannot read the release source status." >&2; exit 65; }
if [[ -n "$FRIT_GIT_STATUS" ]]; then
  echo "Commit the intended release changes before archiving. The source must be traceable." >&2
  exit 65
fi
FRIT_VERSION="${FRIT_VERSION:-1.3.1}"
FRIT_BUILD_NUMBER="${FRIT_BUILD_NUMBER:-6}"
FRIT_RUN_DIR="${FRIT_RUN_DIR:-$FRIT_ROOT/build/xcode/$(date -u +%Y%m%dT%H%M%SZ)}"
[[ "$FRIT_RUN_DIR" = /* ]] || { echo "FRIT_RUN_DIR must be absolute." >&2; exit 64; }
FRIT_ARCHIVE="$FRIT_RUN_DIR/Frit.xcarchive"
[[ ! -e "$FRIT_ARCHIVE" ]] || { echo "Archive already exists. Choose a new FRIT_RUN_DIR. No files were removed." >&2; exit 73; }
mkdir -p "$FRIT_RUN_DIR"
git rev-parse HEAD > "$FRIT_RUN_DIR/source-commit.txt"
/usr/bin/xcrun xcodebuild -version > "$FRIT_RUN_DIR/xcode-version.txt"
FRIT_SIGNING_ARGS=()
if [[ -n "${FRIT_PROFILE_SPECIFIER:-}" ]]; then
  FRIT_SIGNING_ARGS+=(CODE_SIGN_STYLE=Manual "PROVISIONING_PROFILE_SPECIFIER=$FRIT_PROFILE_SPECIFIER")
fi
# The scoped threshold matches the task's 20 GB rule. The host semaphore still limits concurrency.
BUILDSLOT_MIN_FREE_GB=20 BUILDSLOT_MAX_WAIT=60 timeout 1800 "$HOME/bin/buildslot" \
  /usr/bin/xcrun xcodebuild -project Frit.xcodeproj -scheme Frit -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$FRIT_ARCHIVE" \
  -derivedDataPath "$FRIT_RUN_DIR/DerivedData" \
  "MARKETING_VERSION=$FRIT_VERSION" "CURRENT_PROJECT_VERSION=$FRIT_BUILD_NUMBER" \
  "DEVELOPMENT_TEAM=${FRIT_TEAM_ID:-55R57JNHZX}" "${FRIT_SIGNING_ARGS[@]}" archive \
  2>&1 | tee "$FRIT_RUN_DIR/archive.log"
python3 "$FRIT_ROOT/tools/verify_xcode_archive.py" "$FRIT_ARCHIVE" \
  --version "$FRIT_VERSION" --build "$FRIT_BUILD_NUMBER" \
  > "$FRIT_RUN_DIR/archive-verification.json"
echo "Verified archive at $FRIT_ARCHIVE. This command did not export or upload it."
