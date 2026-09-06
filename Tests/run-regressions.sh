#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="/var/folders/jf/rkbpmx49141_mng19sm95qrc0000gn/T/opencode"
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
    "$ROOT/Core/Storage/FileStore.swift" \
    "$ROOT/Core/Persistence/DataController.swift" \
    "$ROOT/Features/Library/LibraryView.swift" \
    "$ROOT/Features/Editor/EditorView.swift" \
    "$ROOT/Features/Notebook/NotebookView.swift" \
    "$ROOT/Tests/NotebookRegression.swift" \
    -o "$RUN_DIR/NotebookRegression"
"$RUN_DIR/NotebookRegression" "$@"
