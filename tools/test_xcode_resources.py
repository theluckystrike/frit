#!/usr/bin/env python3
"""Regression checks for native resource layout and the signed release boundary."""
from pathlib import Path
import datetime,json,os,plistlib,shutil,subprocess,sys,tempfile,unittest
from xcode_resources import validate_glazecore_bundle

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'Sources/GlazeCore/Resources'
WORK=ROOT/'build/resource-regressions'
MANIFEST=Path(os.environ.get('FRIT_REGRESSION_MANIFEST',str(ROOT/'build/resource-regression-deletions.jsonl')))

def cleanup_owned(path):
    if not path.exists(): return
    scan=subprocess.run(['lsof','-nP','+D',str(path)],capture_output=True,text=True)
    if scan.returncode not in [0,1] or scan.returncode==0:
        raise RuntimeError('Fixture cleanup stopped. Open files or lsof failure. '+scan.stdout+scan.stderr)
    members=list(path.rglob('*'))+[path]
    size=sum(p.lstat().st_size for p in members if p.is_file() and not p.is_symlink())
    if size>50*1024*1024: raise RuntimeError('Fixture exceeded 50 MB limit')
    MANIFEST.parent.mkdir(parents=True,exist_ok=True)
    with MANIFEST.open('a') as stream:
        for member in sorted(members,key=lambda p:len(p.parts),reverse=True):
            stream.write(json.dumps({'time':datetime.datetime.now().astimezone().isoformat(),'path':str(member),'size':member.lstat().st_size if not member.is_dir() else 0})+'\n')
    shutil.rmtree(path)

class NativeBundleRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls): WORK.mkdir(parents=True,exist_ok=True)
    def setUp(self):
        self.fixture=Path(tempfile.mkdtemp(prefix='native-bundle-',dir=WORK))
        self.bundle=self.fixture/'Glaze_GlazeCore.bundle'
    def tearDown(self): cleanup_owned(self.fixture)
    @classmethod
    def tearDownClass(cls):
        if WORK.exists() and not any(WORK.iterdir()): cleanup_owned(WORK)
    def create(self,omit=None,data_override=None,package_type='BNDL',info=True,flat=False):
        resources=self.bundle/('' if flat else 'Contents/Resources')
        resources.mkdir(parents=True,exist_ok=True)
        if info:
            metadata={'CFBundleName':'Glaze_GlazeCore','CFBundleIdentifier':'test.GlazeCore.resources','CFBundlePackageType':package_type,'CFBundleSupportedPlatforms':['MacOSX']}
            path=self.bundle/'Contents/Info.plist';path.parent.mkdir(exist_ok=True)
            path.write_bytes(plistlib.dumps(metadata))
        for name in ['materials.json','oxides.json']:
            if name==omit: continue
            (resources/name).write_bytes(data_override if data_override is not None and name=='materials.json' else (SOURCE/name).read_bytes())
    def result(self): return validate_glazecore_bundle(self.bundle,SOURCE)
    def test_native_contents_resources_pass(self):
        self.create();self.assertTrue(all(c['passed'] for c in self.result()['checks']))
    def test_missing_native_json_fails(self):
        self.create(omit='materials.json');self.assertTrue(any(not c['passed'] and 'materials.json' in c['check'] for c in self.result()['checks']))
    def test_corrupt_json_fails(self):
        self.create(data_override=b'{broken');self.assertFalse(next(c['passed'] for c in self.result()['checks'] if c['check']=='Native package resource is valid JSON materials.json'))
    def test_changed_valid_json_fails_exact_hash(self):
        self.create(data_override=b'{}');self.assertFalse(next(c['passed'] for c in self.result()['checks'] if c['check']=='Native package resource matches exact source hash materials.json'))
    def test_flat_files_do_not_substitute_for_native_resources(self):
        self.create(flat=True);self.assertTrue(any(not c['passed'] and 'exists within bundle' in c['check'] for c in self.result()['checks']))
    def test_wrong_bundle_package_type_fails(self):
        self.create(package_type='APPL');self.assertFalse(next(c['passed'] for c in self.result()['checks'] if c['check']=='Native GlazeCore bundle package type is BNDL'))
    def test_missing_bundle_info_fails(self):
        self.create(info=False);self.assertFalse(next(c['passed'] for c in self.result()['checks'] if c['check']=='Native GlazeCore bundle Info.plist is valid'))
    def test_json_symlink_outside_bundle_fails(self):
        self.create(omit='materials.json');(self.bundle/'Contents/Resources/materials.json').symlink_to(SOURCE/'materials.json')
        self.assertFalse(next(c['passed'] for c in self.result()['checks'] if c['check']=='Native package resource exists within bundle materials.json'))
    @unittest.skipUnless(os.environ.get('FRIT_UNSIGNED_REGRESSION_ARCHIVE'),'Set FRIT_UNSIGNED_REGRESSION_ARCHIVE to a real unsigned Xcode archive')
    def test_strict_signed_verifier_rejects_real_unsigned_archive(self):
        archive=Path(os.environ['FRIT_UNSIGNED_REGRESSION_ARCHIVE']);self.assertTrue(archive.is_dir())
        proc=subprocess.run([sys.executable,str(ROOT/'tools/verify_xcode_archive.py'),str(archive),'--version',os.environ.get('FRIT_VERSION','1.3.1'),'--build',os.environ.get('FRIT_BUILD_NUMBER','6')],capture_output=True,text=True)
        self.assertEqual(proc.returncode,1);report=json.loads(proc.stdout)
        self.assertIn('Code signature does not verify',report['failures'])
        self.assertTrue(any('signed entitlements' in x or 'Missing entitlement' in x for x in report['failures']))
        self.assertTrue(all(c['passed'] for c in report['resourceBundle']['checks']))

if __name__=='__main__': unittest.main(verbosity=2)
