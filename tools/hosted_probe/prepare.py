from pathlib import Path,PurePosixPath
import hashlib,json,os,plistlib,re,subprocess,sys,tarfile

SOURCE='0e9d4d181d9e5a8673a83018d7b2fe1a10f6921b'
EXE_SHA='8ea129bc3a9df8299f2cf19de62de85ec4bd6192f7beea8a9ad2b10c7c37be81'
TEAM='55R57JNHZX'
base=Path(sys.argv[1]).resolve(); out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
meta=json.loads((base/'input.json').read_text());tar=base/'signed-QA-archive.tar.gz'
assert meta['sourceCommit']==SOURCE and meta['signedExecutableSHA256']==EXE_SHA and meta['team']==TEAM
assert isinstance(meta.get('postSignTransform'),dict) and meta['postSignTransform'],'Post-sign transformation receipt is required'
assert meta['postSignTransform']['privateKeysExported'] is False and meta['postSignTransform']['SDKMetadataChanged'] is False
assert hashlib.sha256(tar.read_bytes()).hexdigest()==meta['archiveSha256'],'Input tar checksum mismatch'
with tarfile.open(tar,'r:gz') as stream:
 members=stream.getmembers();assert sum(x.size for x in members)<=50*1024*1024,'Input exceeds 50 MB'
 names=set()
 for member in members:
  p=PurePosixPath(member.name)
  assert p.parts and p.parts[0]=='Frit.xcarchive' and not p.is_absolute() and '..' not in p.parts and '\\' not in member.name
  assert member.name not in names,'Duplicate tar path';names.add(member.name)
  assert member.isdir() or member.isfile(),'Links and special tar entries are refused'
  assert p.suffix.lower() not in {'.p12','.p8','.pem','.key','.pfx'},'Key material is refused'
 stream.extractall(out/'input',members=members,filter='data')
archive=out/'input/Frit.xcarchive';app=archive/'Products/Applications/Frit.app';exe=app/'Contents/MacOS/Frit'
assert hashlib.sha256(exe.read_bytes()).hexdigest()==EXE_SHA,'Signed executable checksum mismatch'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
signature=subprocess.run(['codesign','-dvv',str(app)],capture_output=True,text=True,check=True).stderr
assert 'TeamIdentifier='+TEAM in signature and 'Authority=Developer ID Application:' in signature,'Unexpected signing identity'
ents=plistlib.loads(subprocess.run(['codesign','-d','--entitlements',':-',str(app)],capture_output=True,check=True).stdout)
expected={k:True for k in ['com.apple.security.app-sandbox','com.apple.security.files.user-selected.read-write','com.apple.security.files.bookmarks.app-scope','com.apple.security.print']}
assert ents==expected,'Signed entitlements differ from the candidate'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert info['CFBundleIdentifier']=='com.michaellip.frit'
assert info['DTXcode']=='2630' and info['DTXcodeBuild']=='17C529' and info['DTSDKName']=='macosx26.2','SDK metadata changed'
a=plistlib.loads((archive/'Info.plist').read_bytes())['ApplicationProperties'];assert a['Team']==TEAM and 'Developer ID Application:' in a['SigningIdentity'],'Archive signer receipt does not match actual signer'
(out/'prepare.json').write_text(json.dumps({'status':'PASS','sourceCommit':SOURCE,'signedExecutableSHA256':EXE_SHA,'team':TEAM,'archive':str(archive),'app':str(app),'input':meta,'signedEntitlements':ents,'signature':signature},indent=2)+'\n')
print('Exact signed candidate verified. No private key was supplied.')
