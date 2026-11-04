#!/usr/bin/env python3
"""Static App Store checks on an assembled Frit.app (W6 X5). tools/bundle.sh runs it before signing.

Usage: python3 -I tools/compliance.py <path/to/App.app> <path/to/App.entitlements>
Exit 0 = all checks pass. Exit 1 = a check failed (each failure is printed).
"""
import os
import plistlib
import sys

ALLOWED_ENTITLEMENTS = {
    "com.apple.security.app-sandbox",                    # required on the Mac App Store
    "com.apple.security.files.user-selected.read-write", # open and save books
    "com.apple.security.files.bookmarks.app-scope",      # test-log photo links (TestLogView)
    "com.apple.security.print",                          # File > Print Batch Sheet
}
REQUIRED_INFO = ("LSApplicationCategoryType", "NSHumanReadableCopyright", "LSMinimumSystemVersion",
                 "CFBundleDocumentTypes", "UTExportedTypeDeclarations")
BANNED_DATA = (b"glazy",)  # Glazy data is CC BY-NC-SA 4.0: test fixture only, never bundled (W5 V6)


def load(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


def check_info(info):
    errs = [f"Info.plist: missing {k}" for k in REQUIRED_INFO if k not in info]
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        errs.append("Info.plist: ITSAppUsesNonExemptEncryption must be false")
    errs += [f"Info.plist: unused permission string {k}" for k in info if k.endswith("UsageDescription")]
    if "NSAppTransportSecurity" in info:
        errs.append("Info.plist: NSAppTransportSecurity exception present (the app makes no network requests)")
    return errs


def check_entitlements(ent):
    errs = [] if ent.get("com.apple.security.app-sandbox") is True else ["entitlements: sandbox is off"]
    errs += [f"entitlements: unexpected key {k}" for k in ent if k not in ALLOWED_ENTITLEMENTS]
    return errs


def check_resources(resources):
    errs = []
    for root, _dirs, files in os.walk(resources):
        for name in files:
            path = os.path.join(root, name)
            with open(path, "rb") as f:
                body = f.read().lower()
            errs += [f"resources: {path} contains {b.decode()}" for b in BANNED_DATA
                     if b in body or b in name.lower().encode()]
    if not os.path.isfile(os.path.join(resources, "PrivacyInfo.xcprivacy")):
        errs.append("resources: PrivacyInfo.xcprivacy missing")
    return errs


def main(argv):
    assert len(argv) == 3, "usage: compliance.py <App.app> <App.entitlements>"
    app, ent_path = argv[1], argv[2]
    assert os.path.isdir(app), f"not a directory: {app}"
    errs = check_info(load(os.path.join(app, "Contents", "Info.plist")))
    errs += check_entitlements(load(ent_path))
    errs += check_resources(os.path.join(app, "Contents", "Resources"))
    for e in errs:
        print(f"compliance: FAIL {e}", file=sys.stderr)
    print(f"compliance: {'FAIL' if errs else 'ok'} ({len(errs)} problems)", file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
