from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,time,uuid
import ApplicationServices as AX
from AppKit import NSRunningApplication,NSApplicationActivateIgnoringOtherApps,NSWorkspace
from CoreFoundation import CFEqual,CFHash
from Foundation import NSRunLoop,NSDate,NSURL
import Quartz
from probe_support import unique_control,trace_owned_ancestors,semantic_labels,saved_book_matches,process_state,exited,ProbeInstrumentationError,CandidateProcessError

out=Path(sys.argv[1]).resolve();prepared=json.loads((out/'prepare.json').read_text());app=Path(prepared['app']);exe=app/'Contents/MacOS/Frit'
result={'status':'NOT_RUN','axTrusted':bool(AX.AXIsProcessTrusted()),'forcedTerminationNeeded':False,'cases':{},'limits':['Bounded smoke only','Print dialog cancellation only; no print submission or PDF export','Hosted OS versions are recorded; latest macOS 27.2 is not verified','No fourteen-day field use','No App Store approval proof']}
owned=None;fixture=None;launched=False;owned_start=None;deadline=time.monotonic()+180

def write(): (out/'runtime.json').write_text(json.dumps(result,indent=2)+'\n')
if not result['axTrusted']:
 result['reason']='Accessibility trust is absent. No prompt, TCC change or app launch was attempted.';write();raise SystemExit(0)

def identity():
 if owned is None:raise ProbeInstrumentationError('Owned PID is not established')
 evidence=process_state(owned.processIdentifier(),str(exe),owned_start)
 if exited(evidence):raise CandidateProcessError('Owned candidate process exited during the probe')
 if not evidence['safeToSignal']:raise ProbeInstrumentationError('Owned PID executable or start time is uncertain')
 return evidence
def attr(element,key):
 if time.monotonic()>deadline: raise TimeoutError('Bounded AX deadline expired')
 code,value=AX.AXUIElementCopyAttributeValue(element,key,None)
 return value if code==0 else None
def walk(element,depth=0,seen=None):
 if depth>20:return
 if seen is None:seen={}
 bucket=seen.setdefault(int(CFHash(element)),[])
 if any(CFEqual(element,prior) for prior in bucket):
  result['axIdentityDuplicatesSkipped']=result.get('axIdentityDuplicatesSkipped',0)+1;return
 bucket.append(element)
 yield element
 for child in attr(element,'AXChildren') or []:yield from walk(child,depth+1,seen)
def window():
 identity();matches=[w for w in attr(target,'AXWindows') or [] if 'QA-hosted.glazebook' in str(attr(w,'AXTitle') or '')]
 if len(matches)!=1: raise RuntimeError('Exactly one owned book window is required')
 return matches[0]
def capture_owned_windows(label):
 diagnostics={'status':'NOT_CAPTURED','windows':[]}
 try:
  if not hasattr(Quartz,'CGPreflightScreenCaptureAccess') or not Quartz.CGPreflightScreenCaptureAccess():
   diagnostics['reason']='Screen capture permission is absent or cannot be checked. No request was made.'
  else:
   identity();pid=owned.processIdentifier()
   windows=[w for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly,0) if int(w.get('kCGWindowOwnerPID',-1))==pid and int(w.get('kCGWindowLayer',-1))==0]
   diagnostics['ownWindowCount']=len(windows);diagnostics['captureLimit']=3
   for item in windows[:3]:
    identity();window_id=int(item['kCGWindowNumber'])
    current=Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionIncludingWindow,window_id)
    if len(current)!=1 or int(current[0].get('kCGWindowOwnerPID',-1))!=pid:
     diagnostics['windows'].append({'id':window_id,'status':'NOT_CAPTURED','reason':'Window ownership changed'});continue
    image=Quartz.CGWindowListCreateImage(Quartz.CGRectNull,Quartz.kCGWindowListOptionIncludingWindow,window_id,Quartz.kCGWindowImageBoundsIgnoreFraming|Quartz.kCGWindowImageShouldBeOpaque)
    if image is None:
     diagnostics['windows'].append({'id':window_id,'pid':pid,'status':'NOT_CAPTURED','reason':'Owned-window image unavailable'});continue
    path=out/(label+'-window-'+str(window_id)+'.png')
    writer=Quartz.CGImageDestinationCreateWithURL(NSURL.fileURLWithPath_(str(path)),'public.png',1,None)
    if writer is None:
     diagnostics['windows'].append({'id':window_id,'pid':pid,'status':'NOT_CAPTURED','reason':'Image encoder unavailable'});continue
    Quartz.CGImageDestinationAddImage(writer,image,None)
    saved=bool(Quartz.CGImageDestinationFinalize(writer))
    diagnostics['windows'].append({'id':window_id,'pid':pid,'status':'CAPTURED' if saved else 'NOT_CAPTURED','file':path.name if saved else None})
   if any(w['status']=='CAPTURED' for w in diagnostics['windows']):diagnostics['status']='CAPTURED'
   elif not windows:diagnostics['reason']='No owned on-screen content window was found'
 except Exception as error:diagnostics['reason']='Optional owned-window diagnostic failed. '+str(error)
 result.setdefault('screenshotDiagnostics',{})[label]=diagnostics
 try:(out/(label+'-windows.json')).write_text(json.dumps(diagnostics,indent=2)+'\n')
 except OSError:pass

def diagnostic_value(element,key):
 try:
  value=attr(element,key)
  if value is None or isinstance(value,(str,int,float,bool)):return value
  if key in {'AXPosition','AXSize'}:
   kind=AX.kAXValueCGPointType if key=='AXPosition' else AX.kAXValueCGSizeType
   ok,point=AX.AXValueGetValue(value,kind,None)
   if ok:return {'x':float(point.x),'y':float(point.y)} if key=='AXPosition' else {'width':float(point.width),'height':float(point.height)}
  return str(value)
 except Exception as error:return {'diagnosticError':str(error)}

def owned_parent_trace(element):
 identity();book=window();pid=owned.processIdentifier()
 def belongs(parent):
  code,parent_pid=AX.AXUIElementGetPid(parent,None)
  return code==0 and parent_pid==pid
 return trace_owned_ancestors(element,lambda e:attr(e,'AXParent'),CFEqual,belongs,lambda e:CFEqual(e,book),max_depth=8)
def verified_nested_ancestor(outer,inner):
 trace=owned_parent_trace(inner)
 return trace['complete'] and not trace['cycle'] and any(CFEqual(outer,parent) for parent in trace['nodes'])
def parent_diagnostic(element,elements):
 trace=owned_parent_trace(element);nodes=[]
 for parent in trace['nodes']:
  node={k:str(attr(parent,k) or '') for k in ['AXRole','AXTitle','AXDescription','AXIdentifier']}
  node.update({k:diagnostic_value(parent,k) for k in ['AXPosition','AXSize']})
  node['sameAsSnapshotRows']=[i for i,(e,_) in enumerate(elements) if CFEqual(parent,e)]
  nodes.append(node)
 return {'completeToOwnedBookWindow':trace['complete'],'cycleDetected':trace['cycle'],'reason':trace['reason'],'nodes':nodes}

def snapshot(label,root_element=None):
 rows=[];elements=[]
 identity()
 if root_element is None:root_element=window()
 code,root_pid=AX.AXUIElementGetPid(root_element,None)
 if code!=0 or root_pid!=owned.processIdentifier():raise ProbeInstrumentationError('Snapshot root is not owned by candidate PID')
 for element in walk(root_element):
  if len(rows)>=1800:raise RuntimeError('AX node bound exceeded')
  row={k:str(attr(element,k) or '') for k in ['AXRole','AXTitle','AXDescription','AXIdentifier','AXValue']}
  row.update({k:diagnostic_value(element,k) for k in ['AXEnabled','AXVisible','AXHidden','AXPosition','AXSize']})
  rows.append(row);elements.append((element,row))
 for element,row in elements:
  if row.get('AXRole')=='AXButton' and 'batch sheet' in semantic_labels(row):
   try:row['AXParentPath']=parent_diagnostic(element,elements)
   except Exception as error:row['AXParentPath']={'completeToOwnedBookWindow':False,'reason':str(error)}
 (out/(label+'-ax.json')).write_text(json.dumps(rows,indent=2)+'\n')
 capture_owned_windows(label)
 return elements,' '.join(str(row.get(key) or '') for row in rows for key in ['AXRole','AXTitle','AXDescription','AXIdentifier','AXValue'])
def entries(root):
 return [(e,{k:str(attr(e,k) or '') for k in ['AXRole','AXTitle','AXDescription','AXIdentifier']}) for e in walk(root)]
def front_owned():
 identity();owned.activateWithOptions_(NSApplicationActivateIgnoringOtherApps)
 for _ in range(20):
  front=NSWorkspace.sharedWorkspace().frontmostApplication()
  if front is not None and front.processIdentifier()==owned.processIdentifier():return
  pump(.05)
 raise ProbeInstrumentationError('Owned candidate is not frontmost. No keyboard event was sent')
def menu_action(menu_label,item_label):
 front_owned();menu=unique_control(entries(attr(target,'AXMenuBar')),'AXMenuBarItem',menu_label,CFEqual)
 press(menu);pump(.15)
 item=unique_control(entries(menu),'AXMenuItem',item_label,CFEqual)
 if attr(item,'AXEnabled') is not True:raise ProbeInstrumentationError('Owned menu action is not enabled '+item_label)
 press(item);pump(.2)
def post_key(key,flags=0,text=None):
 if not hasattr(Quartz,'CGPreflightPostEventAccess') or not Quartz.CGPreflightPostEventAccess():raise ProbeInstrumentationError('Keyboard event posting permission is absent or cannot be checked. No event was sent')
 identity();front=NSWorkspace.sharedWorkspace().frontmostApplication()
 if front is None or front.processIdentifier()!=owned.processIdentifier():raise ProbeInstrumentationError('Keyboard recipient is not the owned frontmost process')
 for down in [True,False]:
  event=Quartz.CGEventCreateKeyboardEvent(None,key,down)
  if event is None:raise ProbeInstrumentationError('Keyboard event could not be created')
  Quartz.CGEventSetFlags(event,flags)
  if text is not None:Quartz.CGEventKeyboardSetUnicodeString(event,len(text),text)
  Quartz.CGEventPostToPid(owned.processIdentifier(),event)
 pump(.1)
def wait_for(description,predicate,seconds=6):
 stop=min(deadline,time.monotonic()+seconds)
 while time.monotonic()<stop:
  identity()
  if predicate():return
  pump(.1)
 raise ProbeInstrumentationError('Bounded observation did not complete '+description)
def book_windows():
 identity();return [w for w in attr(target,'AXWindows') or [] if 'QA-hosted.glazebook' in str(attr(w,'AXTitle') or '')]
def print_windows():
 identity();result_windows=[]
 for candidate in attr(target,'AXWindows') or []:
  code,pid=AX.AXUIElementGetPid(candidate,None)
  if code==0 and pid==owned.processIdentifier() and attr(candidate,'AXRole')=='AXWindow' and str(attr(candidate,'AXTitle') or '')=='Print':result_windows.append(candidate)
 return result_windows

def press(element):
 identity();code=AX.AXUIElementPerformAction(element,'AXPress')
 if code:raise ProbeInstrumentationError('Owned AXPress failed '+str(code))
def pump(seconds):
 NSRunLoop.currentRunLoop().runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(seconds))
def cleanup():
 global owned
 if owned is None and launched:
  candidates=[p for p in NSRunningApplication.runningApplicationsWithBundleIdentifier_('com.michaellip.frit') if p.executableURL() and p.executableURL().path()==str(exe)]
  if len(candidates)==1:owned=candidates[0]
 observations=[]
 if owned is not None:
  state=process_state(owned.processIdentifier(),str(exe),owned_start);observations.append(state)
  if state['safeToSignal']:
   result['normalTerminateRequestAccepted']=bool(owned.terminate())
   stop=time.monotonic()+5
   while time.monotonic()<stop:
    pump(.1);state=process_state(owned.processIdentifier(),str(exe),owned_start)
    if exited(state) or state['state']=='PID_REUSED':break
   observations.append(state)
   if state['safeToSignal'] and not exited(state):
    # Recheck identity immediately before any forced action.
    state=identity();result['forcedTerminationNeeded']=True
    result['forceTerminateRequestAccepted']=bool(owned.forceTerminate())
    result['status']='FAIL';result['cleanupFailureKind']='FORCED_TERMINATION';result['cleanupReason']='Candidate did not quit normally. Forced termination was required.'
    result.setdefault('reason',result['cleanupReason'])
    stop=time.monotonic()+2
    while time.monotonic()<stop:
     pump(.1);state=process_state(owned.processIdentifier(),str(exe),owned_start)
     if exited(state) or state['state']=='PID_REUSED':break
    observations.append(state)
  result['ownPidExited']=exited(state)
  if not result['ownPidExited']:
   result['status']='FAIL';result['cleanupFailureKind']='PROCESS_DEATH_UNVERIFIED';result['cleanupReason']='Authoritative process death was not established. No uncertain PID was forced.'
 else:result['ownPidExited']=not launched
 result['processCleanupEvidence']=observations
 result['binaryUnchanged']=hashlib.sha256(exe.read_bytes()).hexdigest()==prepared['signedExecutableSHA256']
 if not result['binaryUnchanged']:result['status']='FAIL';result['cleanupFailureKind']='CANDIDATE_BINARY_CHANGED'
 if fixture is not None and fixture.exists():
  opened=subprocess.run(['lsof','-nP','+D',str(fixture)],capture_output=True,text=True,timeout=10)
  if opened.returncode!=1:raise ProbeInstrumentationError('Fixture still has open files or lsof failed')
  with (out/'deletions-manifest.jsonl').open('a') as stream:
   for p in list(fixture.rglob('*'))+[fixture]:stream.write(json.dumps({'path':str(p),'size':p.lstat().st_size if p.is_file() else 0})+'\n')
  shutil.rmtree(fixture);result['fixtureRemoved']=True

try:
 quarantine=subprocess.run(['xattr','-p','com.apple.quarantine',str(app)],capture_output=True,text=True)
 if quarantine.returncode==0:
  result['reason']='Candidate has quarantine metadata. No quarantine change or first-open bypass was attempted.';write();raise SystemExit(0)
 existing=[p for p in NSRunningApplication.runningApplicationsWithBundleIdentifier_('com.michaellip.frit') if p.executableURL() and p.executableURL().path()==str(exe)]
 if existing:raise RuntimeError('Candidate already running. Refuse to adopt another PID')
 fixture=out/'owned-fixture';fixture.mkdir();book=fixture/'QA-hosted.glazebook'
 recipe={'id':str(uuid.uuid4()).upper(),'name':'QA hosted cone 6','cone':'6','notes':'Owned hosted probe book.','lines':[{'id':str(uuid.uuid4()).upper(),'materialID':m,'amount':n,'isAddition':False} for m,n in [('silica',60),('kaolin',30),('whiting',10)]]}
 book.write_text(json.dumps({'version':1,'recipes':[recipe],'customMaterials':[],'tests':[]}));(out/'fixture-input.json').write_text(book.read_text())
 subprocess.run(['open','-n','-a',str(app),str(book),'--args','-ApplePersistenceIgnoreState','YES'],check=True,capture_output=True,timeout=15)
 launched=True
 for _ in range(80):
  matches=[p for p in NSRunningApplication.runningApplicationsWithBundleIdentifier_('com.michaellip.frit') if p.executableURL() and p.executableURL().path()==str(exe)]
  if len(matches)==1:owned=matches[0];break
  time.sleep(.1)
 if owned is None:raise RuntimeError('Owned candidate did not appear')
 owned_start=identity()['startTime'];result['pid']=owned.processIdentifier();result['processStartTime']=owned_start;owned.activateWithOptions_(NSApplicationActivateIgnoringOtherApps)
 target=AX.AXUIElementCreateApplication(owned.processIdentifier());AX.AXUIElementSetMessagingTimeout(target,1.0);time.sleep(3)
 elements,text=snapshot('launch')
 result['cases']['owned_book_open']='PASS' if 'QA hosted cone 6' in text else 'FAIL'
 result['cases']['resource_chemistry']='PASS' if all(x in text for x in ['1.000','1.163','12.321','10.59']) else 'FAIL'
 batch=unique_control(elements,'AXButton','Batch Sheet',CFEqual,ancestor=verified_nested_ancestor)
 press(batch);time.sleep(.7);elements,text=snapshot('batch')
 result['cases']['batch_1000g']='PASS' if all(x in text for x in ['600.0','300.0','100.0']) else 'FAIL'
 done=unique_control(elements,'AXButton','Done',CFEqual)
 press(done);time.sleep(.3)
 menu_action('View','Materials');time.sleep(.5)
 elements,text=snapshot('materials');result['cases']['bundled_materials']='PASS' if all(x in text.lower() for x in ['silica','kaolin','whiting']) else 'FAIL'
 # Use normal focused keyboard input. Direct AX value assignment is not a save test.
 result['cases']['normal_edit_and_save']='NOT_RUN'
 menu_action('View','Recipes');pump(.3);elements,text=snapshot('recipe-before-edit')
 field=unique_control(elements,'AXTextField','Recipe name',CFEqual);front_owned()
 if attr(field,'AXEnabled') is not True or AX.AXUIElementSetAttributeValue(field,'AXFocused',True)!=0:raise ProbeInstrumentationError('Owned recipe name field could not take focus')
 pump(.1)
 if attr(field,'AXFocused') is not True:raise ProbeInstrumentationError('Owned recipe name field did not confirm focus')
 new_name='QA hosted saved'
 post_key(0,Quartz.kCGEventFlagMaskCommand);post_key(0,text=new_name);post_key(48)
 menu_action('File','Save')
 original=json.loads((out/'fixture-input.json').read_text())
 def expected_file():
  try:return saved_book_matches(original,json.loads(book.read_text()),new_name)
  except (OSError,ValueError):return False
 wait_for('saved owned JSON contains only the requested recipe edit',expected_file)
 saved_bytes=book.read_bytes();saved_sha=hashlib.sha256(saved_bytes).hexdigest();(out/'saved-book.json').write_bytes(saved_bytes)
 elements,text=snapshot('saved');name_field=unique_control(elements,'AXTextField','Recipe name',CFEqual)
 result['cases']['normal_edit_and_save']='PASS' if str(attr(name_field,'AXValue'))==new_name and expected_file() else 'FAIL'
 menu_action('File','Close');wait_for('owned book window closed',lambda:not book_windows())
 identity();subprocess.run(['open','-a',str(app),str(book)],check=True,capture_output=True,timeout=15)
 wait_for('same PID reopened the owned book',lambda:len(book_windows())==1)
 pump(.5);elements,text=snapshot('reopened');name_field=unique_control(elements,'AXTextField','Recipe name',CFEqual)
 after_sha=hashlib.sha256(book.read_bytes()).hexdigest()
 result['reopen']={'pid':owned.processIdentifier(),'beforeSHA256':saved_sha,'afterSHA256':after_sha,'recipeName':str(attr(name_field,'AXValue')),'sameProcessStartTime':owned_start}
 result['cases']['same_file_reopen']='PASS' if after_sha==saved_sha and str(attr(name_field,'AXValue'))==new_name and expected_file() else 'FAIL'
 # Open the native panel, observe both buttons, and press only Cancel.
 front_owned();post_key(35,Quartz.kCGEventFlagMaskCommand)
 result['printInvocation']='Command-P sent only to the owned candidate PID, as declared by PrintCommands'
 wait_for('one owned native Print window',lambda:len(print_windows())==1)
 panels=print_windows()
 if len(panels)!=1:raise ProbeInstrumentationError('Owned Print window count changed')
 panel=panels[0];panel_entries,panel_text=snapshot('print-dialog',panel)
 unique_control(panel_entries,'AXButton','Print',CFEqual)
 cancel=unique_control(panel_entries,'AXButton','Cancel',CFEqual)
 result['cases']['native_print_dialog']='PASS'
 if attr(cancel,'AXEnabled') is not True:raise ProbeInstrumentationError('Owned print Cancel button is not enabled')
 press(cancel)
 wait_for('owned Print dialog dismissed after Cancel',lambda:not print_windows())
 snapshot('print-cancelled');result['cases']['print_dialog_cancel']='PASS'
 result['printSubmissionRequested']=False;result['pdfExportRequested']=False
 result['status']='PASS' if all(x=='PASS' for x in result['cases'].values()) else 'FAIL'
 if result['status']=='FAIL':result['failureKind']='OBSERVED_UI_MISMATCH';result['reason']='Owned UI did not match the bounded probe expectations. This alone does not establish an app defect.'
except Exception as error:
 result['status']='FAIL';result['reason']=str(error)
 result['failureKind']='PROBE_INSTRUMENTATION_FAILURE' if isinstance(error,ProbeInstrumentationError) else ('CANDIDATE_PROCESS_EXITED' if isinstance(error,CandidateProcessError) else 'PROBE_EXECUTION_ERROR')
finally:
 try:cleanup()
 except Exception as error:result['status']='FAIL';result['cleanupError']=str(error)
 write()
