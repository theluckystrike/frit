from pathlib import Path
import copy,json,operator,os,subprocess,sys,unittest
from unittest.mock import patch
from probe_support import unique_control,trace_owned_ancestors,strict_contains,saved_book_matches,semantic_labels,process_state,exited,ProbeInstrumentationError

FIXTURES=Path(__file__).resolve().parent/'fixtures'
def rows(name):return json.loads((FIXTURES/name).read_text())
def entries(name):return list(enumerate(rows(name)))

class RecordedSelectorChecks(unittest.TestCase):
 def test_macos27_batch_description_is_unique(self):
  unique_control(entries('macos27-launch.json'),'AXButton','Batch Sheet',operator.eq)
 def test_macos27_done_uses_description_not_empty_title(self):
  selected=unique_control(entries('macos27-batch.json'),'AXButton','Done',operator.eq)
  self.assertEqual(rows('macos27-batch.json')[selected]['AXDescription'],'Done')
 def test_macos14_serialized_duplicates_remain_ambiguous(self):
  # A flat snapshot cannot prove whether two rows are the same CF element.
  with self.assertRaisesRegex(ProbeInstrumentationError,'observed 2'):
   unique_control(entries('macos14-launch.json'),'AXButton','Batch Sheet',operator.eq)
 def test_same_real_element_repeated_in_graph_is_one_control(self):
  identity=object();row={'AXRole':'AXButton','AXDescription':'Batch Sheet'}
  self.assertIs(unique_control([(identity,row),(identity,dict(row))],'AXButton','Batch Sheet',operator.is_),identity)
 def test_distinct_matching_elements_cannot_pick_first(self):
  with self.assertRaises(ProbeInstrumentationError):
   unique_control([(object(),{'AXRole':'AXButton','AXTitle':'Done'}),(object(),{'AXRole':'AXButton','AXDescription':'Done'})],'AXButton','Done',operator.is_)
 def test_nonbutton_label_does_not_match(self):
  with self.assertRaises(ProbeInstrumentationError):
   unique_control([(object(),{'AXRole':'AXStaticText','AXTitle':'Done'})],'AXButton','Done',operator.is_)
 def test_identifier_can_supply_unique_semantic_label(self):
  identity=object();self.assertIs(unique_control([(identity,{'AXRole':'AXButton','AXIdentifier':'Done'})],'AXButton','Done',operator.is_),identity)

class NestedToolbarChecks(unittest.TestCase):
 def data(self):return entries('macos14-diagnostics.json')
 def ancestry(self,outer,inner):return outer==115 and inner==116
 def choose(self,data=None,ancestor=None):
  return unique_control(self.data() if data is None else data,'AXButton','Batch Sheet',operator.eq,ancestor=self.ancestry if ancestor is None else ancestor)
 def test_observed_frames_require_verified_ancestry_to_select_inner(self):
  self.assertTrue(strict_contains(self.data()[115][1],self.data()[116][1]));self.assertEqual(self.choose(),116)
 def test_observed_geometry_without_ancestry_stays_ambiguous(self):
  with self.assertRaises(ProbeInstrumentationError):self.choose(ancestor=lambda a,b:False)
 def test_missing_geometry_stays_ambiguous(self):
  data=self.data();data[116][1]['AXPosition']=None
  with self.assertRaises(ProbeInstrumentationError):self.choose(data)
 def test_disjoint_geometry_stays_ambiguous(self):
  data=self.data();data[116][1]['AXPosition']['x']=2000
  with self.assertRaises(ProbeInstrumentationError):self.choose(data)
 def test_disabled_hidden_or_invisible_candidates_stay_ambiguous(self):
  for key,value in [('AXEnabled',False),('AXHidden',True),('AXVisible',False)]:
   for index in [115,116]:
    data=self.data();data[index][1][key]=value
    with self.assertRaises(ProbeInstrumentationError):self.choose(data)
 def test_invalid_geometry_stays_ambiguous(self):
  for value in [0,-1,float('nan'),'103']:
   data=self.data();data[116][1]['AXSize']['width']=value
   with self.assertRaises(ProbeInstrumentationError):self.choose(data)
 def test_third_matching_control_stays_ambiguous(self):
  data=self.data();data.append((999,copy.deepcopy(data[116][1])))
  with self.assertRaises(ProbeInstrumentationError):self.choose(data)
 def test_parent_trace_reaches_exact_owned_window(self):
  trace=trace_owned_ancestors(0,lambda x:{0:1,1:2,2:3}.get(x),operator.eq,lambda x:True,lambda x:x==3)
  self.assertTrue(trace['complete']);self.assertEqual(trace['nodes'],[1,2,3])
 def test_parent_cycle_fails_closed(self):
  trace=trace_owned_ancestors(0,lambda x:{0:1,1:0}[x],operator.eq,lambda x:True,lambda x:False)
  self.assertFalse(trace['complete']);self.assertTrue(trace['cycle'])
 def test_missing_or_foreign_parent_fails_closed(self):
  for parent,owned in [(lambda x:None,lambda x:True),(lambda x:1,lambda x:False)]:
   trace=trace_owned_ancestors(0,parent,operator.eq,owned,lambda x:False)
   self.assertFalse(trace['complete'])
 def test_parent_traversal_is_bounded(self):
  trace=trace_owned_ancestors(0,lambda x:x+1,operator.eq,lambda x:True,lambda x:False,max_depth=3)
  self.assertFalse(trace['complete']);self.assertEqual(len(trace['nodes']),3)

class DocumentAndPrintChecks(unittest.TestCase):
 def original(self):return {'version':1,'recipes':[{'id':'OWNED','name':'QA hosted cone 6','notes':'Owned probe book','lines':[{'materialID':'silica','amount':60}]}],'customMaterials':[],'tests':[]}
 def saved(self):
  value=self.original();value['recipes'][0]['name']='QA hosted saved';return value
 def test_only_requested_name_change_passes(self):
  self.assertTrue(saved_book_matches(self.original(),self.saved(),'QA hosted saved'))
 def test_display_only_change_without_saved_json_fails(self):
  self.assertFalse(saved_book_matches(self.original(),self.original(),'QA hosted saved'))
 def test_accidental_ingredient_edit_fails(self):
  value=self.saved();value['recipes'][0]['lines'][0]['amount']=61
  self.assertFalse(saved_book_matches(self.original(),value,'QA hosted saved'))
 def test_accidental_note_change_fails(self):
  value=self.saved();value['recipes'][0]['notes']='unexpected'
  self.assertFalse(saved_book_matches(self.original(),value,'QA hosted saved'))
 def test_extra_recipe_fails(self):
  value=self.saved();value['recipes'].append(copy.deepcopy(value['recipes'][0]))
  self.assertFalse(saved_book_matches(self.original(),value,'QA hosted saved'))
 def test_recorded_owned_print_and_cancel_are_distinct(self):
  data=entries('local-owned-document-print-controls.json')
  cancel=unique_control(data,'AXButton','Cancel',operator.eq);printing=unique_control(data,'AXButton','Print',operator.eq)
  self.assertNotEqual(cancel,printing)
 def test_duplicate_cancel_is_ambiguous(self):
  data=entries('local-owned-document-print-controls.json');cancel=next(r for _,r in data if r.get('AXRole')=='AXButton' and 'cancel' in semantic_labels(r))
  data.append((999,dict(cancel)))
  with self.assertRaises(ProbeInstrumentationError):unique_control(data,'AXButton','Cancel',operator.eq)
 def test_recipe_name_field_and_save_menu_are_exact(self):
  data=entries('local-owned-document-print-controls.json')
  unique_control(data,'AXTextField','Recipe name',operator.eq);unique_control(data,'AXMenuItem','Save',operator.eq)

class OwnedProcessChecks(unittest.TestCase):
 def test_real_owned_child_death_is_authoritative(self):
  child=subprocess.Popen(['/bin/sleep','15'])
  try:
   alive=process_state(child.pid,'/bin/sleep')
   self.assertEqual(alive['state'],'ALIVE_OWNED');self.assertTrue(alive['safeToSignal'])
   token=alive['startTime'];child.terminate();child.wait(timeout=3)
   gone=process_state(child.pid,'/bin/sleep',token)
   self.assertTrue(exited(gone));self.assertFalse(gone['safeToSignal'])
  finally:
   if child.poll() is None:child.terminate();child.wait(timeout=3)
 def test_wrong_executable_never_allows_signal(self):
  state=process_state(os.getpid(),'/not-the-owned-candidate')
  self.assertEqual(state['state'],'PID_REUSED');self.assertFalse(state['safeToSignal'])
 def test_start_time_mismatch_never_allows_signal(self):
  state=process_state(os.getpid(),sys.executable,'not-the-original-start-time')
  self.assertEqual(state['state'],'PID_REUSED');self.assertFalse(state['safeToSignal'])
 def test_ps_error_is_unknown_not_exit(self):
  with patch('probe_support.subprocess.run',return_value=subprocess.CompletedProcess([],1,stdout='',stderr='ps failed')):
   state=process_state(123,'/candidate')
  self.assertEqual(state['state'],'UNKNOWN');self.assertFalse(state['safeToSignal']);self.assertFalse(exited(state))

if __name__=='__main__':unittest.main(verbosity=2)
