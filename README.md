# Frit

Frit is a glaze recipe book for potters on the Mac. It reworks a glaze recipe when a material changes, moves one oxide to a target, and finds each fired test tile by the code on its back. It works offline, and your recipes stay in your own files.

- Download the notarized app: https://frit-app.pages.dev/

The code is under the MIT License. See [LICENSE](LICENSE).

## Build

You need Xcode 16 or later on macOS 14 or later.

```sh
swift build
swift test
```

To build the Mac app bundle, open `Frit.xcodeproj` in Xcode. To build it from the terminal, run `tools/xcode_archive.sh`. Set `FRIT_TEAM_ID` to your own Apple team ID.

## Layout

- `Sources/GlazeCore`: recipe math (unity formula, oxide targets, material swaps, test tiles).
- `Sources/GlazeApp`: the AppKit and SwiftUI app.
- `Tests`: unit tests for the core and the app.
- `tools`: build, packaging and check scripts.

## Contact

Open an issue in this repository. Email: support@barframe.com.

