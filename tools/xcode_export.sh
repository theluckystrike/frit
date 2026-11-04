#!/bin/bash
# Export a previously verified archive to local disk. No upload.
set -euo pipefail
FRIT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$FRIT_ROOT/tools/xcode_preflight.sh"
frit_xcode_preflight
[[ $# -eq 1 ]] || { echo "Usage xcode_export.sh /absolute/path/Frit.xcarchive" >&2; exit 64; }
FRIT_ARCHIVE="$1"
[[ "$FRIT_ARCHIVE" = /* && -d "$FRIT_ARCHIVE" ]] || { echo "Archive must be an existing absolute path." >&2; exit 64; }
FRIT_EXPORT_METHOD="${FRIT_EXPORT_METHOD:-app-store-connect}"
case "$FRIT_EXPORT_METHOD" in app-store-connect|developer-id) ;; *) echo "FRIT_EXPORT_METHOD must be app-store-connect or developer-id." >&2; exit 64 ;; esac
FRIT_EXPORT_DIR="${FRIT_EXPORT_DIR:-${FRIT_ARCHIVE%.xcarchive}-export-$FRIT_EXPORT_METHOD}"
[[ "$FRIT_EXPORT_DIR" = /* && ! -e "$FRIT_EXPORT_DIR" ]] || { echo "Export path must be absolute and must not exist. No files were removed." >&2; exit 73; }
python3 "$FRIT_ROOT/tools/verify_xcode_archive.py" "$FRIT_ARCHIVE" >/dev/null
mkdir -p "$FRIT_EXPORT_DIR"
python3 - "$FRIT_EXPORT_DIR/ExportOptions.plist" "$FRIT_EXPORT_METHOD" "${FRIT_TEAM_ID:-55R57JNHZX}" "${FRIT_PROFILE_SPECIFIER:-}" <<'PY'
import plistlib,sys
out,method,team,profile=sys.argv[1:]
options={'method':method,'destination':'export','teamID':team,'manageAppVersionAndBuildNumber':False,'stripSwiftSymbols':True,'uploadSymbols':False,'signingStyle':'automatic'}
if profile:
 options['signingStyle']='manual'
 options['provisioningProfiles']={'com.michaellip.frit':profile}
 options['signingCertificate']='Mac App Distribution' if method=='app-store-connect' else 'Developer ID Application'
with open(out,'wb') as stream: plistlib.dump(options,stream)
PY
BUILDSLOT_MIN_FREE_GB=20 BUILDSLOT_MAX_WAIT=60 timeout 1800 "$HOME/bin/buildslot" \
  /usr/bin/xcrun xcodebuild -exportArchive -archivePath "$FRIT_ARCHIVE" \
  -exportPath "$FRIT_EXPORT_DIR" -exportOptionsPlist "$FRIT_EXPORT_DIR/ExportOptions.plist" \
  2>&1 | tee "$FRIT_EXPORT_DIR/export.log"
python3 - "$FRIT_EXPORT_DIR" <<'PY'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]); artifacts=[]
for path in sorted(root.rglob('*')):
 if path.is_file() and path.suffix in {'.pkg','.zip','.dmg'}:
  artifacts.append({'file':str(path.relative_to(root)),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(root/'export-artifacts.json').write_text(json.dumps({'method':'local export only','artifacts':artifacts},indent=2)+'\n')
PY
echo "Export complete at $FRIT_EXPORT_DIR. No upload was requested."
