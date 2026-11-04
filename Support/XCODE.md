# Frit Xcode release path

This branch prepares Frit 1.1 build 3. It does not change the shipped app. Hosted run 41036866724 built an unsigned archive with Xcode 26.3. Signing, export and app runtime remain unverified.

Open `Frit.xcodeproj`. Select the shared `Frit` scheme. The app uses all Swift files in `Sources/GlazeApp`. It links the `GlazeCore` library from this repository as a local Swift package. That package owns its two JSON resources. Do not add the test fixtures to the app.

The app target uses the existing sandbox, file access and printing entitlements. It includes the existing privacy manifest and document declarations. The app icon catalog uses the existing Frit PNG files. Xcode must compile the catalog and write its own SDK and build metadata.

## Before the first archive

Install full Xcode. Select it for the command with `DEVELOPER_DIR` if needed. Do not change the global developer path for other work. Check the signing team and the local provisioning profile. The scripts do not request provisioning updates.

Make at least 20 GB of disk space available. Keep at least 25 percent of memory free. The scripts use the host build semaphore. They stop if full Xcode, disk or memory is missing. They do not delete old archives.

Commit the intended release source. Run the unit tests with the release toolchain. Record the result for that commit. These scripts do not replace the unit test gate.

## Archive and export

Run these commands from the repository root.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  FRIT_VERSION=1.1 FRIT_BUILD_NUMBER=3 tools/xcode_archive.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  tools/xcode_export.sh /absolute/path/to/Frit.xcarchive
```

Use `FRIT_RUN_DIR` to set an absolute archive run directory. Use a new directory for each run. The default is under `build/xcode`. The archive receipt records the source commit and the Xcode version.

The default export method is `app-store-connect`. Its destination is local export. It does not upload the app. To export the same archive for direct distribution, set `FRIT_EXPORT_METHOD=developer-id`. Check the available signing identity first. If manual signing is required, set `FRIT_PROFILE_SPECIFIER` to the existing profile name. Use `FRIT_TEAM_ID` only when the actual signing team changes.

Run the archive verifier on the actual archive. It checks resources, privacy, document registration, signed entitlements, signature, architectures, generated build metadata and the compiled catalog. It never fills missing metadata.

```sh
python3 tools/verify_xcode_archive.py /absolute/path/to/Frit.xcarchive \
  --version 1.3.1 --build 6
```

Test the exact exported app on macOS 14 and the current macOS. Test sample loading, new books, save and reopen, printing, file permissions and error recovery. Record the actual platform versions and results. Do not claim supported runtime behavior from static checks.

## Keep the submission gates

No script here uploads or submits an app. The hosted archive is unsigned and is not a release. Follow the current six submission gates before any Apple write. An Xcode project does not establish that Apple accepts the app concept under 4.3.

Regenerate the project after adding or removing app Swift files.

```sh
python3 tools/generate_xcode_project.py
```
