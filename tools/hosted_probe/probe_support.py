"""Bounded selector and process evidence helpers. No GUI or signal side effects."""
import copy,ctypes,math,os,subprocess

class ProbeInstrumentationError(RuntimeError): pass
class CandidateProcessError(RuntimeError): pass

def semantic_labels(row):
    return {' '.join(str(row.get(key,'')).split()).casefold() for key in ['AXTitle','AXDescription','AXIdentifier'] if row.get(key)}

def strict_contains(outer,inner):
    def rectangle(row):
        try:
            values=[row['AXPosition']['x'],row['AXPosition']['y'],row['AXSize']['width'],row['AXSize']['height']]
            if any(type(v) not in (int,float) or not math.isfinite(v) for v in values):return None
            x,y,width,height=values
            return (x,y,x+width,y+height) if width>0 and height>0 else None
        except (KeyError,TypeError):return None
    a,b=rectangle(outer),rectangle(inner)
    return bool(a and b and a[0]<b[0] and a[1]<b[1] and b[2]<a[2] and b[3]<a[3])

def trace_owned_ancestors(element,get_parent,same_element,is_owned,is_book_window,max_depth=8):
    nodes=[];seen=[element];current=element
    for _ in range(max_depth):
        parent=get_parent(current)
        if parent is None:return {'nodes':nodes,'complete':False,'cycle':False,'reason':'Parent chain is missing'}
        if not is_owned(parent):return {'nodes':nodes,'complete':False,'cycle':False,'reason':'Parent is outside the owned PID'}
        if any(same_element(parent,prior) for prior in seen):return {'nodes':nodes,'complete':False,'cycle':True,'reason':'AX parent cycle detected'}
        seen.append(parent);nodes.append(parent)
        if is_book_window(parent):return {'nodes':nodes,'complete':True,'cycle':False,'reason':'Reached the exact owned book window'}
        current=parent
    return {'nodes':nodes,'complete':False,'cycle':False,'reason':'AX parent traversal bound reached'}

def unique_control(entries,role,label,same_element,ancestor=None):
    wanted=' '.join(label.split()).casefold()
    matches=[]
    for element,row in entries:
        if row.get('AXRole')==role and wanted in semantic_labels(row):
            if not any(same_element(element,old[0]) for old in matches):matches.append((element,row))
    if len(matches)==1:return matches[0][0]
    # This opt-in rule is only used for the observed nested Batch Sheet toolbar control.
    if len(matches)==2 and role=='AXButton' and ancestor is not None:
        candidates=[]
        for inner,outer in [(matches[0],matches[1]),(matches[1],matches[0])]:
            rows=[inner[1],outer[1]]
            actionable=all(r.get('AXEnabled') is True and r.get('AXHidden') is not True and r.get('AXVisible') is not False for r in rows)
            if actionable and strict_contains(outer[1],inner[1]) and ancestor(outer[0],inner[0]):candidates.append(inner[0])
        if len(candidates)==1:return candidates[0]
    raise ProbeInstrumentationError(f'Owned {label} control requires one distinct AX element, observed {len(matches)}')

def process_state(pid,expected_executable,expected_start=None):
    """Read the exact PID. Never treat a cached NSRunningApplication flag as death."""
    evidence={'pid':int(pid),'state':'UNKNOWN','safeToSignal':False}
    try:
        observed=subprocess.run(['ps','-p',str(pid),'-o','lstart=','-o','stat='],capture_output=True,text=True,timeout=2)
    except (OSError,subprocess.TimeoutExpired) as error:
        evidence['reason']=str(error);return evidence
    if observed.returncode==1 and not observed.stdout.strip() and not observed.stderr.strip():
        evidence['state']='EXITED';evidence['reason']='ps confirms that the PID is absent';return evidence
    if observed.returncode!=0 or not observed.stdout.strip():
        evidence['reason']='ps did not establish process state';return evidence
    parts=observed.stdout.split();start=' '.join(parts[:-1]);status=parts[-1]
    evidence.update({'startTime':start,'psState':status})
    if expected_start is not None and start!=expected_start:
        evidence['state']='PID_REUSED';evidence['reason']='Process start time differs';return evidence
    if status.startswith('Z'):
        evidence['state']='EXITED_ZOMBIE';evidence['reason']='The process has exited and awaits reaping';return evidence
    try:
        library=ctypes.CDLL('/usr/lib/libproc.dylib',use_errno=True)
        library.proc_pidpath.argtypes=[ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32]
        library.proc_pidpath.restype=ctypes.c_int
        buffer=ctypes.create_string_buffer(4096)
        ctypes.set_errno(0);length=library.proc_pidpath(int(pid),buffer,len(buffer))
        if length<=0:
            evidence['reason']='proc_pidpath did not establish executable identity';evidence['procErrno']=ctypes.get_errno()
            confirmation=subprocess.run(['ps','-p',str(pid),'-o','stat='],capture_output=True,text=True,timeout=2)
            if confirmation.returncode==1 and not confirmation.stdout.strip() and not confirmation.stderr.strip():
                evidence['state']='EXITED';evidence['reason']='ps confirmed that the PID vanished during identity read'
            return evidence
        matches=os.path.realpath(os.fsdecode(buffer.value))==os.path.realpath(expected_executable)
    except (OSError,ValueError) as error:
        evidence['reason']=str(error);return evidence
    evidence['executableMatchesExpected']=matches
    evidence['state']='ALIVE_OWNED' if matches else 'PID_REUSED'
    evidence['safeToSignal']=matches
    return evidence

def exited(evidence): return evidence['state'] in {'EXITED','EXITED_ZOMBIE'}


def saved_book_matches(original,saved,new_name):
    if not isinstance(original,dict) or not isinstance(saved,dict):return False
    recipes=original.get('recipes')
    if not isinstance(recipes,list) or len(recipes)!=1 or not isinstance(recipes[0],dict):return False
    expected=copy.deepcopy(original);expected['recipes'][0]['name']=new_name
    return saved==expected
