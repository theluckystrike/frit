#!/usr/bin/env python3
"""Validate a real Xcode archive. Never synthesizes Xcode or SDK metadata."""
from pathlib import Path
import argparse,json,plistlib,subprocess,sys
from xcode_resources import validate_glazecore_bundle

ROOT=Path(__file__).resolve().parents[1]

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive',type=Path)
parser.add_argument('--version')
parser.add_argument('--build')
args=parser.parse_args()
archive=args.archive
failures=[]
def require(ok,message):
    if not ok: failures.append(message)

def read_plist(path):
    try: return plistlib.loads(path.read_bytes())
    except (OSError,ValueError,plistlib.InvalidFileException):
        failures.append(f'Missing or invalid plist {path}')
        return {}

metadata=read_plist(archive/'Info.plist')
application=metadata.get('ApplicationProperties',{}).get('ApplicationPath')
require(application=='Applications/Frit.app','Archive ApplicationPath must be Applications/Frit.app')
app=archive/'Products/Applications/Frit.app'
info=read_plist(app/'Contents/Info.plist')
require(info.get('CFBundleIdentifier')=='com.michaellip.frit','Wrong bundle identifier')
require(info.get('LSMinimumSystemVersion')=='14.0','Minimum macOS must be 14.0')
if args.version: require(info.get('CFBundleShortVersionString')==args.version,'Wrong release version')
if args.build: require(info.get('CFBundleVersion')==args.build,'Wrong build number')
require(bool(info.get('DTXcode')) and bool(info.get('DTSDKName')),'Xcode must generate its build and SDK metadata')
require((app/'Contents/Resources/Assets.car').is_file(),'Compiled asset catalog is missing')
resources=app/'Contents/Resources'
bundle_result=validate_glazecore_bundle(resources/'Glaze_GlazeCore.bundle',ROOT/'Sources/GlazeCore/Resources')
for item in bundle_result['checks']:
    require(item['passed'],item['check'])
privacy=read_plist(resources/'PrivacyInfo.xcprivacy')
require(privacy.get('NSPrivacyTracking') is False,'Privacy tracking must be false')
require(privacy.get('NSPrivacyCollectedDataTypes')==[],'Unexpected data collection declaration')
require(bool(info.get('CFBundleDocumentTypes')) and bool(info.get('UTExportedTypeDeclarations')),'Document declarations are missing')
if app.exists():
    verified=subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True,text=True)
    require(verified.returncode==0,'Code signature does not verify')
    entitlements=subprocess.run(['codesign','-d','--entitlements',':-',str(app)],capture_output=True)
    try: ents=plistlib.loads(entitlements.stdout)
    except Exception: ents={}; failures.append('Cannot read signed entitlements')
    for key in ['com.apple.security.app-sandbox','com.apple.security.files.user-selected.read-write','com.apple.security.files.bookmarks.app-scope','com.apple.security.print']:
        require(ents.get(key) is True,f'Missing entitlement {key}')
    require(not ents.get('com.apple.security.network.client'),'Unexpected client network entitlement')
    executable=app/'Contents/MacOS'/info.get('CFBundleExecutable','Frit')
    archs=subprocess.run(['lipo','-archs',str(executable)],capture_output=True,text=True)
    require(archs.returncode==0 and {'arm64','x86_64'}<=set(archs.stdout.split()),'Release must contain arm64 and x86_64')
else:
    failures.append('Archive app is missing')
result={'archive':str(archive),'status':'fail' if failures else 'pass','version':info.get('CFBundleShortVersionString'),'build':info.get('CFBundleVersion'),'failures':failures,'resourceBundle':bundle_result,'limits':['First launch and document workflows need runtime tests.','Supported macOS versions need separate runtime verification.','Archive validation does not establish App Store review approval.']}
print(json.dumps(result,indent=2))
sys.exit(1 if failures else 0)
