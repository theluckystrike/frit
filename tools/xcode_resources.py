#!/usr/bin/env python3
"""Validate GlazeCore's native macOS resource bundle without changing it."""
from pathlib import Path
import hashlib
import json
import plistlib


def validate_glazecore_bundle(bundle, source_root):
    bundle=Path(bundle)
    source_root=Path(source_root)
    checks=[]
    resources={}
    def check(name,passed):
        checks.append({'check':name,'passed':bool(passed)})
    try:
        metadata=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
        check('Native GlazeCore bundle Info.plist is valid',isinstance(metadata,dict))
    except (OSError,ValueError,plistlib.InvalidFileException):
        metadata={}
        check('Native GlazeCore bundle Info.plist is valid',False)
    if not isinstance(metadata,dict): metadata={}
    check('Native GlazeCore bundle package type is BNDL',metadata.get('CFBundlePackageType')=='BNDL')
    check('Native GlazeCore bundle name matches product',metadata.get('CFBundleName')=='Glaze_GlazeCore')
    check('Native GlazeCore bundle supports MacOSX',isinstance(metadata.get('CFBundleSupportedPlatforms'),list) and 'MacOSX' in metadata['CFBundleSupportedPlatforms'])
    check('Native GlazeCore bundle identifier exists',isinstance(metadata.get('CFBundleIdentifier'),str) and bool(metadata.get('CFBundleIdentifier')))
    for name in ['materials.json','oxides.json']:
        built=bundle/'Contents/Resources'/name
        source=source_root/name
        try:
            data=built.read_bytes()
            contained=built.resolve().is_relative_to(bundle.resolve())
        except OSError:
            data=None
            contained=False
        check('Native package resource exists within bundle '+name,data is not None and contained)
        try:
            source_data=source.read_bytes()
        except OSError:
            source_data=None
        check('Expected source resource is readable '+name,source_data is not None)
        try:
            if data is None: raise ValueError('Resource is missing')
            json.loads(data)
            valid_json=True
        except (ValueError,UnicodeDecodeError,TypeError):
            valid_json=False
        check('Native package resource is valid JSON '+name,valid_json)
        intact=data is not None and source_data is not None and hashlib.sha256(data).digest()==hashlib.sha256(source_data).digest()
        check('Native package resource matches exact source hash '+name,intact)
        resources[name]={'path':str(built),'sha256':hashlib.sha256(data).hexdigest() if data is not None else None,'sourceSha256':hashlib.sha256(source_data).hexdigest() if source_data is not None else None}
    return {'checks':checks,'metadata':{key:metadata.get(key) for key in ['CFBundleIdentifier','CFBundleName','CFBundlePackageType','CFBundleSupportedPlatforms']},'resources':resources}
