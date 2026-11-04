from pathlib import Path
import hashlib,json,os,plistlib,signal,subprocess,sys,tarfile
out=Path(sys.argv[1]).resolve();p=json.loads((out/'prepare.json').read_text());archive=Path(p['archive']);destination=out/'export';destination.mkdir()
options={'method':'developer-id','destination':'export','teamID':'55R57JNHZX','signingStyle':'manual','signingCertificate':'Developer ID Application','stripSwiftSymbols':False,'manageAppVersionAndBuildNumber':False}
(out/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
result={'status':'NOT_VERIFIED','privateKeyProvided':False,'appleCredentialsProvided':False,'requestedOptions':options,'limits':['Probe only. No notarization or Apple upload.']}
args=['xcodebuild','-exportArchive','-archivePath',str(archive),'-exportPath',str(destination),'-exportOptionsPlist',str(out/'ExportOptions.plist')]
with (out/'export.log').open('w') as log:
 process=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 try:process.wait(timeout=300)
 except subprocess.TimeoutExpired:
  os.killpg(process.pid,signal.SIGTERM)
  try:process.wait(timeout=5)
  except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
  result['reason']='Export exceeded the five minute bound'
 result['exitCode']=process.returncode
if process.returncode!=0:result.setdefault('reason','Real xcodebuild export failed. Inspect export.log. No key was imported or substituted.')
else:
 apps=list(destination.rglob('Frit.app'))
 result['exportedApps']=[str(x) for x in apps]
 if len(apps)==1:
  app=apps[0];verify=subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True,text=True)
  details=subprocess.run(['codesign','-dvv',str(app)],capture_output=True,text=True)
  ents=subprocess.run(['codesign','-d','--entitlements',':-',str(app)],capture_output=True)
  try:signed=plistlib.loads(ents.stdout)
  except Exception:signed={}
  sha=hashlib.sha256((app/'Contents/MacOS/Frit').read_bytes()).hexdigest()
  result.update({'signatureExit':verify.returncode,'signatureDetails':details.stderr,'signedEntitlements':signed,'exportedExecutableSHA256':sha})
  if verify.returncode==0 and 'TeamIdentifier=55R57JNHZX' in details.stderr and signed==p['signedEntitlements'] and sha==p['signedExecutableSHA256']:result['status']='PASS'
  else:result['reason']='Export returned success but candidate identity or signature checks did not all pass'
 else:result['reason']='Export returned success without exactly one inspectable Frit.app'
result['inputBinaryUnchanged']=hashlib.sha256((Path(p['app'])/'Contents/MacOS/Frit').read_bytes()).hexdigest()==p['signedExecutableSHA256']
if not result['inputBinaryUnchanged']:result['status']='FAIL';result['reason']='Export changed its input candidate'
result['outputFiles']=[{'path':str(x.relative_to(destination)),'bytes':x.stat().st_size,'sha256':hashlib.sha256(x.read_bytes()).hexdigest()} for x in destination.rglob('*') if x.is_file()]
# Preserve only real xcodebuild output. A partial export never becomes a successful export.
limit=50*1024*1024
files=[x for x in destination.rglob('*') if x.is_file()]
packed=out/'export-output.tar.gz'
if not files:
 result['outputPreservation']={'status':'NOT_SAVED','reason':'The real export produced no files'}
elif sum(x.stat().st_size for x in files)>limit:
 result['outputPreservation']={'status':'NOT_SAVED','reason':'Real export output exceeds the 50 MB preservation bound'}
 if result['status']=='PASS':result['status']='NOT_VERIFIED'
else:
 class BoundedWriter:
  def __init__(self,stream):self.stream=stream;self.count=0
  def write(self,data):
   if self.count+len(data)>limit:raise OverflowError('Export archive exceeds the 50 MB bound')
   written=self.stream.write(data);self.count+=written;return written
  def __getattr__(self,name):return getattr(self.stream,name)
 try:
  with packed.open('wb') as stream:
   with tarfile.open(fileobj=BoundedWriter(stream),mode='w:gz') as tar:tar.add(destination,arcname='export')
  result['outputPreservation']={'status':'SAVED','path':packed.name,'bytes':packed.stat().st_size,'sha256':hashlib.sha256(packed.read_bytes()).hexdigest(),'exportStatus':result['status']}
 except (OSError,OverflowError) as error:
  result['outputPreservation']={'status':'NOT_SAVED','reason':str(error)}
  if result['status']=='PASS':result['status']='NOT_VERIFIED'
  if packed.exists():
   opened=subprocess.run(['lsof','-nP',str(packed)],capture_output=True,text=True)
   if opened.returncode!=1:raise RuntimeError('Partial export archive is open or lsof failed')
   with (out/'deletions-manifest.jsonl').open('a') as manifest:manifest.write(json.dumps({'path':str(packed),'size':packed.stat().st_size})+'\n')
   packed.unlink()
(out/'export.json').write_text(json.dumps(result,indent=2)+'\n')
