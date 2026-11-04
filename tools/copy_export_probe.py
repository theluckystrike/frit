#!/usr/bin/env python3
"""Perform one real Copy App export. Never sign, notarize, upload, or fabricate an export."""
from pathlib import Path, PurePosixPath
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import time

SOURCE = '0e9d4d181d9e5a8673a83018d7b2fe1a10f6921b'
INPUT_COMMIT = '80123aa80ab48542cdcab8c764be8dc5dd53d229'
INPUT_TAR_SHA = '42d426b40c33cc5918c4190a7b052379e991dd4e71b82a117e323079fcf2fcbc'
EXE_SHA = '8ea129bc3a9df8299f2cf19de62de85ec4bd6192f7beea8a9ad2b10c7c37be81'
TEAM = '55R57JNHZX'
ENTITLEMENTS = {key: True for key in (
    'com.apple.security.app-sandbox', 'com.apple.security.files.user-selected.read-write',
    'com.apple.security.files.bookmarks.app-scope', 'com.apple.security.print')}
LIMIT = 50 * 1024 * 1024


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(root):
    result = {}
    for path in sorted(root.rglob('*')):
        name = str(path.relative_to(root))
        if path.is_symlink():
            result[name] = {'link': os.readlink(path), 'mode': path.lstat().st_mode}
        elif path.is_file():
            result[name] = {'sha256': sha(path), 'bytes': path.stat().st_size,
                            'mode': path.stat().st_mode}
    return result


def method_supported(help_text):
    block = re.search(r'(?ms)^\s*method\s*:\s*String\s*\n(.*?)(?=^\s*[A-Za-z]\w*\s*:\s*(?:String|Bool|Dictionary|Array|Number)\b|\Z)', help_text)
    return bool(block and re.search(r'\bmac-application\b', block.group(1)))


def validate_members(members):
    if sum(member.size for member in members) > LIMIT:
        raise ValueError('Input archive exceeds 50 MiB')
    names = set()
    for member in members:
        path = PurePosixPath(member.name)
        if not path.parts or path.parts[0] != 'Frit.xcarchive' or path.is_absolute() or '..' in path.parts or '\\' in member.name:
            raise ValueError('Unsafe tar path')
        if member.name in names or not (member.isdir() or member.isfile()):
            raise ValueError('Duplicate path, link, or special tar member')
        if path.suffix.lower() in {'.p12', '.p8', '.pem', '.key', '.pfx'}:
            raise ValueError('Key material is refused')
        names.add(member.name)


def command(args, out, name, timeout=45):
    started = time.monotonic()
    try:
        run = subprocess.run([str(arg) for arg in args], stdin=subprocess.DEVNULL,
                             capture_output=True, timeout=timeout)
        result = {'args': [str(arg) for arg in args], 'exitCode': run.returncode,
                  'timedOut': False}
        stdout, stderr = run.stdout, run.stderr
    except subprocess.TimeoutExpired as error:
        result = {'args': [str(arg) for arg in args], 'exitCode': None, 'timedOut': True}
        stdout, stderr = error.stdout or b'', error.stderr or b''
    (out / (name + '.stdout.log')).write_bytes(stdout)
    (out / (name + '.stderr.log')).write_bytes(stderr)
    result['seconds'] = round(time.monotonic() - started, 3)
    (out / (name + '.json')).write_text(json.dumps(result, indent=2) + '\n')
    return result, stdout.decode(errors='replace'), stderr.decode(errors='replace')


def signature(app, out, name):
    verify, _, _ = command(['codesign', '--verify', '--deep', '--strict', app], out, name + '-verify')
    display, stdout, stderr = command(['codesign', '-d', '--verbose=4', app], out, name + '-signature')
    text = stdout + stderr
    ent_result, ent_stdout, _ = command(['codesign', '-d', '--entitlements', ':-', app], out, name + '-entitlements')
    try:
        entitlements = plistlib.loads(ent_stdout.encode())
    except Exception:
        entitlements = None
    return {'verification': verify, 'display': display, 'entitlementsCommand': ent_result,
            'entitlements': entitlements, 'teamMatches': 'TeamIdentifier=' + TEAM in text,
            'developerIDMatches': 'Authority=Developer ID Application: Michael Lip (' + TEAM + ')' in text,
            'hardenedRuntime': 'flags=0x10000(runtime)' in text, 'timestamped': 'Timestamp=' in text}


def preserve_distribution_logs(text, out):
    saved = []
    for name in sorted(set(re.findall(r'["\']([^"\'\n]+\.xcdistributionlogs)["\']', text))):
        path = Path(name)
        if not path.is_dir() or path.suffix != '.xcdistributionlogs' or not path.name.startswith('Frit_'):
            continue
        files = [p for p in path.rglob('*') if p.is_file() and not p.is_symlink()]
        if sum(p.stat().st_size for p in files) > LIMIT:
            saved.append({'path': name, 'saved': False, 'reason': 'Logs exceed 50 MiB'})
            continue
        # Only diagnostics are copied. The export app always comes from xcodebuild.
        target = out / 'distribution-logs' / path.name
        shutil.copytree(path, target, symlinks=True)
        saved.append({'path': name, 'saved': True, 'relative': str(target.relative_to(out))})
    return saved


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    base, out = args.input.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    receipt = {'checkedAt': datetime.datetime.now().astimezone().isoformat(),
               'status': 'NOT_RUN', 'method': 'mac-application', 'sourceCommit': SOURCE,
               'inputCommit': INPUT_COMMIT, 'privateKeyProvided': False,
               'appleCredentialsProvided': False, 'notarized': False, 'published': False,
               'appStoreUploaded': False, 'developerIDExportVerified': False,
               'appStoreExportVerified': False, 'g3Passed': False,
               'limits': ['Copy App export only. No signing, notarization, release or submission.',
                          'The selected hosted OS is not proof of current latest macOS runtime coverage.']}
    archive = None
    before = None
    try:
        help_result, stdout, stderr = command(['xcodebuild', '-help'], out, 'xcodebuild-help')
        receipt['help'] = help_result
        receipt['methodSupportedByActualHelp'] = method_supported(stdout + '\n' + stderr)
        if help_result['exitCode'] != 0 or not receipt['methodSupportedByActualHelp']:
            receipt['status'] = 'METHOD_NOT_PROVED'
            return 1
        command(['xcodebuild', '-version'], out, 'xcode-version')
        command(['sw_vers'], out, 'macos-version')
        meta = json.loads((base / 'input.json').read_text())
        if meta['sourceCommit'] != SOURCE or meta['signedExecutableSHA256'] != EXE_SHA or meta['team'] != TEAM:
            raise ValueError('Unexpected candidate provenance')
        if meta['archiveSha256'] != INPUT_TAR_SHA or sha(base / 'signed-QA-archive.tar.gz') != INPUT_TAR_SHA:
            raise ValueError('Input archive digest mismatch')
        with tarfile.open(base / 'signed-QA-archive.tar.gz', 'r:gz') as stream:
            members = stream.getmembers()
            validate_members(members)
            stream.extractall(out / 'input', members=members, filter='data')
        archive = out / 'input/Frit.xcarchive'
        app = archive / 'Products/Applications/Frit.app'
        before = manifest(archive)
        input_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if sha(app / 'Contents/MacOS/Frit') != EXE_SHA:
            raise ValueError('Input executable digest mismatch')
        input_signature = signature(app, out, 'input')
        receipt['inputSignature'] = input_signature
        if input_signature['verification']['exitCode'] != 0 or not input_signature['teamMatches'] or input_signature['entitlements'] != ENTITLEMENTS:
            raise ValueError('Input signature or entitlements differ')
        options = {'method': 'mac-application', 'destination': 'export',
                   'manageAppVersionAndBuildNumber': False, 'stripSwiftSymbols': False}
        options_path = out / 'ExportOptions.plist'
        options_path.write_bytes(plistlib.dumps(options))
        receipt['requestedOptions'] = options
        export, stdout, stderr = command(['xcodebuild', '-exportArchive', '-archivePath', archive,
                                         '-exportPath', out / 'export', '-exportOptionsPlist', options_path],
                                        out, 'export', timeout=360)
        receipt['export'] = export
        receipt['distributionLogs'] = preserve_distribution_logs(stdout + '\n' + stderr, out)
        receipt['inputArchiveUnchanged'] = manifest(archive) == before
        receipt['outputFiles'] = manifest(out / 'export') if (out / 'export').is_dir() else {}
        exported = out / 'export/Frit.app'
        if export['exitCode'] != 0 or not exported.is_dir():
            receipt['status'] = 'EXPORT_NOT_VERIFIED'
            return 1
        output_info = plistlib.loads((exported / 'Contents/Info.plist').read_bytes())
        output_signature = signature(exported, out, 'output')
        receipt['outputSignature'] = output_signature
        receipt['inputExecutableSHA256'] = EXE_SHA
        receipt['outputExecutableSHA256'] = sha(exported / 'Contents/MacOS/Frit')
        receipt['executableByteIdentical'] = receipt['outputExecutableSHA256'] == EXE_SHA
        receipt['allAppFileBytesAndModesIdentical'] = manifest(exported) == manifest(app)
        receipt['infoPlistIdentical'] = output_info == input_info
        receipt['signatureAndEntitlementsPreserved'] = (output_signature['verification']['exitCode'] == 0
            and output_signature['teamMatches'] and output_signature['developerIDMatches']
            and output_signature['entitlements'] == ENTITLEMENTS and output_signature['hardenedRuntime']
            and receipt['executableByteIdentical'])
        if output_info.get('CFBundleIdentifier') != 'com.michaellip.frit' or not receipt['inputArchiveUnchanged']:
            receipt['status'] = 'EXPORT_CHANGED_PROVENANCE'
            return 1
        size = sum(p.stat().st_size for p in (out / 'export').rglob('*') if p.is_file() and not p.is_symlink())
        if size > LIMIT:
            raise ValueError('Export exceeds bounded artifact size')
        with tarfile.open(out / 'CopyApp-Export.tar.gz', 'w:gz') as stream:
            stream.add(out / 'export', arcname='Export')
        receipt['exportTarSHA256'] = sha(out / 'CopyApp-Export.tar.gz')
        receipt['status'] = 'EXPORTED_SIGNATURE_PRESERVED' if receipt['signatureAndEntitlementsPreserved'] else 'EXPORTED_SIGNING_NEEDED'
        return 0
    except Exception as error:
        receipt['status'] = 'PROBE_FAILED'
        receipt['error'] = str(error)
        return 1
    finally:
        if archive is not None and before is not None:
            receipt['inputArchiveUnchanged'] = manifest(archive) == before
        (out / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    sys.exit(main())
