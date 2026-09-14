#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/Tests/NotebookRegression.swift"
if [[ "${1:-}" == "--selection" ]]; then
    HARNESS="$ROOT/Tests/SelectionRegression.swift"
    shift
fi
if [[ "${1:-}" == "--transfer" ]]; then
    HARNESS="$ROOT/Tests/TransferRegression.swift"
    shift
fi
if [[ "${1:-}" == "--cloud" ]]; then
    HARNESS="$ROOT/Tests/CloudRegression.swift"
    shift
fi
TEMP_ROOT="${MYNOTES_TEST_TEMP_ROOT:-${TMPDIR:-/tmp}}"
test -d "$TEMP_ROOT"
RUN_DIR="$(mktemp -d "$TEMP_ROOT/notebook-regressions.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT

swiftc -parse-as-library -module-name NotebookRegression \
    -module-cache-path "$RUN_DIR/module-cache" \
    "$ROOT/Core/Models/NotebookModel.swift" \
    "$ROOT/Core/Models/PageModel.swift" \
    "$ROOT/Core/Utilities/ViewportModel.swift" \
    "$ROOT/Core/Utilities/NotebookLayout.swift" \
    "$ROOT/Drawing/PencilCanvas/PencilCanvasView.swift" \
    "$ROOT/Drawing/PencilCanvas/MacNotebookCanvasView.swift" \
    "$ROOT/Drawing/PencilCanvas/EditorCamera.swift" \
    "$ROOT/Drawing/Cursor/CursorModel.swift" \
    "$ROOT/Drawing/Cursor/NativeCursorFactory.swift" \
    "$ROOT/Drawing/DrawingStorage/DrawingStorage.swift" \
    "$ROOT/Drawing/DrawingStorage/NotebookTransfer.swift" \
    "$ROOT/Core/Storage/FileStore.swift" \
    "$ROOT/Core/Persistence/DataController.swift" \
    "$ROOT/Core/Cloud/CloudModels.swift" \
    "$ROOT/Core/Cloud/CloudSession.swift" \
    "$ROOT/Core/Cloud/DesktopSyncEngine.swift" \
    "$ROOT/App/AccountRootView.swift" \
    "$ROOT/Features/Library/LibraryView.swift" \
    "$ROOT/Features/Editor/EditorView.swift" \
    "$ROOT/Features/Notebook/NotebookView.swift" \
    "$HARNESS" \
    -o "$RUN_DIR/NotebookRegression"
"$RUN_DIR/NotebookRegression" "$@"
