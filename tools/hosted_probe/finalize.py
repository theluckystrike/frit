from pathlib import Path
import json,platform,sys
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
result={'status':'PROBE_FINISHED','g3Passed':False,'host':{'macOS':platform.mac_ver()[0],'architecture':platform.machine()},'limits':['Workflow completion does not establish runtime or export success','Read every individual probe result','No App Store or notarization upload occurred']}
for name in ['prepare','runtime','export']:
 path=out/(name+'.json')
 if path.exists():
  try:result[name]=json.loads(path.read_text())
  except ValueError:result[name]={'status':'NOT_VERIFIED','reason':'Result JSON is invalid'}
 else:result[name]={'status':'NOT_RUN','reason':'Prior step did not complete, or this platform did not request the probe'}
(out/'probe-summary.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'completion':result['status'],'runtime':result['runtime'].get('status'),'export':result['export'].get('status'),'g3Passed':False}))
