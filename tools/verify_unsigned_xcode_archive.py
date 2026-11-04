#!/usr/bin/env python3
"""Check real Xcode compile output. This is never a signed release verifier."""
from pathlib import Path
import json,plistlib,re,subprocess,sys
from xcode_resources import validate_glazecore_bundle

ROOT=Path(__file__).resolve().parents[1]
if len(sys.argv)!=2:
    raise SystemExit('Usage verify_unsigned_xcode_archive.py /path/Frit.xcarchive')
archive=Path(sys.argv[1])
failures=[]
checks=[]
def check(name,passed):
    checks.append({'check':name,'passed':bool(passed)})
    if not passed: failures.append(name)
def plist(path):
    try: return plistlib.loads(path.read_bytes())
    except (OSError,ValueError,plistlib.InvalidFileException):
        check('Readable plist '+str(path),False)
        return {}
def run(args):
    try: return subprocess.run(args,capture_output=True,text=True,check=False)
    except OSError: return subprocess.CompletedProcess(args,127,stdout='',stderr='Required local tool is missing')

archive_info=plist(archive/'Info.plist')
check('Archive has the Frit app product',archive_info.get('ApplicationProperties',{}).get('ApplicationPath')=='Applications/Frit.app')
app=archive/'Products/Applications/Frit.app'
info=plist(app/'Contents/Info.plist')
check('Bundle ID is the existing Frit record',info.get('CFBundleIdentifier')=='com.michaellip.frit')
import os
VERSION=os.environ.get('FRIT_VERSION','1.3.1');BUILD=os.environ.get('FRIT_BUILD_NUMBER','6')
check(f'Version is {VERSION} build {BUILD}',info.get('CFBundleShortVersionString')==VERSION and info.get('CFBundleVersion')==BUILD)
check('Minimum macOS is 14.0',info.get('LSMinimumSystemVersion')=='14.0')
check('Xcode generated build metadata',bool(info.get('DTXcode')) and bool(info.get('DTSDKName')) and bool(info.get('DTXcodeBuild')))
resources=app/'Contents/Resources'
car=resources/'Assets.car'
check('Xcode compiled a nonempty asset catalog',car.is_file() and car.stat().st_size>0)
check('App icon was compiled',any(resources.glob('*.icns')))
bundle_result=validate_glazecore_bundle(resources/'Glaze_GlazeCore.bundle',ROOT/'Sources/GlazeCore/Resources')
for item in bundle_result['checks']:
    check(item['check'],item['passed'])
check('Privacy manifest matches source',plist(resources/'PrivacyInfo.xcprivacy')==plist(ROOT/'Support/PrivacyInfo.xcprivacy'))
source_docs=plist(ROOT/'Support/GlazeApp-DocumentTypes.plist')
for key in ['CFBundleDocumentTypes','UTExportedTypeDeclarations']:
    check('Document declaration matches '+key,info.get(key)==source_docs.get(key) and bool(source_docs.get(key)))
executable=app/'Contents/MacOS'/info.get('CFBundleExecutable','Frit')
archs=run(['lipo','-archs',str(executable)])
check('Executable contains both Mac architectures',archs.returncode==0 and {'arm64','x86_64'}<=set(archs.stdout.split()))
for arch in ['arm64','x86_64']:
    load=run(['otool','-arch',arch,'-l',str(executable)])
    minimum=re.findall(r'\bminos\s+([\d.]+)',load.stdout)
    check('Executable deployment target is 14.0 for '+arch,load.returncode==0 and bool(minimum) and set(minimum)=={'14.0'})
signature=run(['codesign','-dvv',str(app)])
team=re.search(r'^TeamIdentifier=(.+)$',signature.stderr,re.MULTILINE)
check('No Apple signing identity was used','Authority=' not in signature.stderr and (team is None or team.group(1)=='not set'))
result={'status':'fail' if failures else 'pass','scope':'unsigned compile evidence only','archive':str(archive),'checks':checks,'failures':failures,'xcodeMetadata':{k:info.get(k) for k in ['DTXcode','DTXcodeBuild','DTSDKName','DTSDKBuild']},'architectures':archs.stdout.strip(),'resourceBundle':bundle_result,'notVerified':['Apple distribution signature and signed entitlements','App Store or Developer ID export','Notarization and stapling','First launch and app workflows','macOS 14 runtime','Current macOS runtime','App Store approval']}
print(json.dumps(result,indent=2))
raise SystemExit(1 if failures else 0)
