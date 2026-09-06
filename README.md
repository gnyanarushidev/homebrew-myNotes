# MyNotes

MyNotes is a native notebook app for iPhone, iPad, and Mac, built with SwiftUI. Create multi-page notebooks, write or sketch on customizable paper, and export your work as PDFs. Notes are stored locally, with no account or backend required.

## Features

- **Notebook library:** Create, rename, open, and delete notebooks, ordered by most recently updated.
- **Search:** Find notebooks by title or stored page text. Handwriting recognition is not included.
- **Multi-page notebooks:** Scroll vertically through pages, add pages manually, or scroll beyond the final ink-containing page to append a blank page.
- **Paper styles:** Choose blank, ruled, grid, or dotted paper with white, cream, or dark backgrounds. Set a notebook-wide style or customize individual pages.
- **PDF export:** Export the current page or the entire notebook, including paper backgrounds, templates, and ink.
- **Local persistence:** Notebook metadata is saved with SwiftData, with drawings stored in separate files.

### Platform-Specific Tools

| Platform | Drawing and Editing |
| --- | --- |
| iPhone and iPad | PencilKit canvas with touch and Apple Pencil input, the native drawing tool picker, pinch zoom, drawing clear, and a photo overlay per page. |
| Mac | Custom AppKit canvas with pen, pencil, highlighter, whole-stroke eraser, rectangle, ellipse, line, and arrow tools. Lasso-select strokes to move, resize, or rotate them. |

On Mac, a movable floating toolbar provides ink colors, stroke widths, highlighter opacity, and eraser size. The canvas also supports panning, pointer-centered zoom, fit-to-page and actual-size controls, and current-page deletion while keeping at least one page.

## Requirements

- A Mac with a recent full Xcode installation and its command-line tools selected.
- SDKs supporting the deployment targets below. The repository does not pin an exact Xcode version.
- A simulator or compatible device for running the iOS app.

| Target | Minimum OS | Xcode Scheme |
| --- | --- | --- |
| iPhone / iPad | iOS / iPadOS 17.0 | `MyNotes` |
| Mac | macOS 14.0 | `MyNotes macOS` |

The project uses Apple frameworks only. There are no third-party packages to install, required environment variables, API keys, or external services to configure.

## Install on Mac with Homebrew

The repository includes a Homebrew cask for the macOS app. Once a matching GitHub release exists and the cask has been published to the tap repository, install it with:

```sh
brew tap gnyanarushi/mynotes https://github.com/gnyanarushi/homebrew-myNotes
brew install --cask mynotes
```

If Homebrew reports a tap remote mismatch, remove the existing tap and add it again with the URL above:

```sh
brew untap gnyanarushi/mynotes
brew tap gnyanarushi/mynotes https://github.com/gnyanarushi/homebrew-myNotes
```

The cask downloads `MyNotes-macOS-<version>.zip` from GitHub Releases and installs `MyNotes.app`. The first published release should match the cask version in `Casks/mynotes.rb`, currently `1.0`.

Release tags named `v<version>` automatically build and publish the macOS zip asset:

```sh
git tag v1.0
git push origin v1.0
```

The release workflow currently builds an unsigned app. Add Developer ID signing and notarization before using it as a polished public distribution channel.

## Getting Started

Run the following commands from the repository root.

### Run on Mac

The included script builds an unsigned Debug version and launches it:

```sh
zsh run-macos.sh
```

The built app is located at `build/Build/Products/Debug/MyNotes.app`.

To build without launching:

```sh
xcodebuild \
  -project MyNotes.xcodeproj \
  -scheme "MyNotes macOS" \
  -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This unsigned build is for local development, not a signed or notarized distribution package.

### Run in Xcode

```sh
open MyNotes.xcodeproj
```

1. Select the `MyNotes` scheme for iPhone/iPad or `MyNotes macOS` for Mac.
2. Choose an iOS simulator, a connected iOS device, or **My Mac** as the run destination.
3. For a physical iOS device, select your development team in the target's **Signing & Capabilities** settings. Adjust the bundle identifier if needed.
4. Build and run with **Command-R**.

## Using the App

1. Select **New Notebook** in the library to create a notebook with an initial blank page.
2. Open the notebook and choose a drawing tool. On iPhone/iPad, use the PencilKit tool picker; on Mac, use the floating writing toolbar.
3. Change the notebook's paper style or override the appearance of an individual page.
4. Add pages as needed. Scrolling beyond the last page appends another only when that last page contains ink.
5. Export a page or the full notebook as a PDF using the export controls.

Notebook and drawing changes are saved automatically to local storage.

## Architecture

The app shares SwiftUI screens and SwiftData models across platforms, with separate native drawing implementations for iOS and macOS.

| Path | Purpose |
| --- | --- |
| `App/` | Application entry point and shared model-container setup. |
| `Core/Models/` | Notebook and page models, paper styles, and page dimensions. |
| `Core/Persistence/` | SwiftData container configuration. |
| `Core/Storage/` | Drawing-file locations. |
| `Core/Utilities/` | Notebook layout and viewport calculations. |
| `Features/Library/` | Notebook list, search, creation, and deletion. |
| `Features/Notebook/` | Multi-page navigation, paper controls, and notebook actions. |
| `Features/Editor/` | Page editing UI and platform-specific controls. |
| `Drawing/PencilCanvas/` | PencilKit and AppKit canvases, camera handling, and rendering. |
| `Drawing/Cursor/` | macOS drawing cursor state and native cursor creation. |
| `Drawing/DrawingStorage/` | Drawing serialization and PDF export. |
| `Resources/` | Asset catalog and application icons. |
| `MyNotes.xcodeproj/` | Xcode project and shared schemes. |
| `Tests/` | Standalone macOS regression harness and runner. |

### Data Storage

- SwiftData stores notebook and page metadata using the `MyNotes` model configuration at its default persistent-store location.
- Drawings are written under `Drawings/` in the user-domain Documents directory resolved by the app.
- iOS drawings use PencilKit `.pkdrawing` files; macOS drawings use `.drawing.json` files.
- Page image data uses SwiftData's external-storage attribute.
- Deleting a notebook also deletes its pages and associated drawing files.

There is no implemented cloud sync or drawing-format conversion between platforms. PDF export is not a complete backup of the editable notebook data.

## Regression Tests

The repository includes a standalone Swift/AppKit regression harness, rather than an XCTest target. It requires macOS, Xcode command-line tools, and a graphical desktop session.

```sh
bash Tests/run-regressions.sh
```

An optional first argument filters test names by a case-insensitive substring:

```sh
bash Tests/run-regressions.sh continuation
```

**Current blockers:** The harness does not compile against the current application sources because it still references `PageContinuationTrigger` and `MacCanvasNSView.onWritingNearBottom`. The runner also hardcodes a machine-specific `TEMP_ROOT`; that path must be replaced with an existing writable temporary directory on other machines. These issues must be resolved before the suite can run successfully.

## Current Limitations

- Typed-text editing is not fully connected to the visible editor, even though the model and search support stored text.
- Photo overlays are currently exposed on iOS, not in the main macOS notebook view.
- PDF export includes paper and ink, but not stored text or photo overlays.
- iOS and macOS have different drawing tools and file formats; editable notebooks are not synchronized between them.
- OCR, PDF import, and cloud synchronization are not implemented.
