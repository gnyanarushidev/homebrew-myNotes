# Existing Mac notebooks → cloud library

The web workspace now uses a notebook sidebar, continuous pages on a dark canvas, and a movable writing palette like the Mac app. Pen, pencil, highlighter, shapes, whole-stroke erasing, lasso selection/move/resize/rotate, undo/redo, zoom/pan, page settings, and PDF export are connected to the account's cloud notebook document.

## Bring an existing notebook across

1. Build/run the updated Mac app (`zsh "desktop app/run-macos.sh"` from the repository root).
2. Open a local notebook. In the export menu, choose **Export for web (.json)** and save the file.
3. Sign into the web app and open `/notebooks`.
4. Click the import icon beside **New notebook** in the sidebar and select the exported JSON file. On a small screen, open the sidebar first.
5. The imported notebook opens from your private cloud library. Its strokes remain editable. Reload to verify it is stored, then continue drawing on the web.

The Mac export uses live committed strokes from loaded canvases and reads remaining pages from disk. It fails on missing/unreadable drawing content instead of replacing it with blank pages. Source notebooks and drawing files are not changed or deleted.

You can also select a raw Mac `.drawing.json` file from the app's `Documents/Drawings` directory. This transfers a **single page of ink**, including legacy default styles. Raw drawing files contain no notebook metadata, text, images, or paper settings; those imports start with US Letter blank paper and can be customized through **Paper & page**. The full notebook export is the preferred transfer path.

## What is preserved

- Notebook source ID, page order and IDs, stroke IDs, page-local coordinates.
- Native shapes as their already-transformed polylines; rotated/resized shapes are not reconstructed from a bounding box.
- Original floating-point RGB/alpha, width, and opacity.
- Notebook paper style, per-page overrides, Letter/A4 sizes, and page text.
- Page images converted to PNG in the export, stored/displayed read-only with the document.

Native export format: `{ format: "mynotes-mac", version: 1, notebook: { id, title, template, color, pages } }`. Each page includes `strokes` using native `MacStroke` serialization. The server validates and converts it to the web document schema.

Web JSON v1 now supports `geometry: "polyline"` and optional full-precision `rgba` on strokes, and an optional PNG/JPEG `image` on pages. Older web JSON remains readable. Web drawing tools create explicit polylines; transformations change point coordinates while retaining stable stroke IDs and styles.

## Cloud and retry behavior

`POST /api/notebooks/import` accepts `{ value, filename, id, mutationId }` and requires the signed-in account and a same-origin JSON request. Native imports derive their cloud ID from the **verified account + source notebook ID + converted content**:

- Importing the same export again opens the existing cloud notebook, including any newer web edits.
- A changed local export creates a separate cloud notebook so web edits remain intact.
- Another account gets its own private import and cannot access your copy.
- A deleted import can be imported again explicitly. This import path is not a synchronization deletion protocol.

Drawing edits use the existing revision-checked notebook API. Each completed gesture enters the local recovery draft, then autosaves to Supabase. A conflicting cloud revision offers **Save conflict copy**. PDF export renders paper, ink, text, and images at 2× page resolution; JSON export retains editable document data.

## Setup and current boundaries

Cloud access requires the migration and server environment in [ADMIN_SETUP.md](ADMIN_SETUP.md). Drawings are stored in Supabase Postgres inside the notebook document. Images are currently bounded inline data; B2-backed large assets and staged uploads remain a later storage increment.

Imports are limited to **2.9 MB**, saves to **3 MB**, and notebooks to **300 pages**. Oversized or unsupported exports report an error. PencilKit `.pkdrawing` files are not supported by this Mac transfer path.

This is an explicit import, not automatic desktop sync. Desktop sign-in, per-account local stores, downloads, the native web-document decoder, and bidirectional synchronization are specified in [DESKTOP_AUTH_PLAN.md](../DESKTOP_AUTH_PLAN.md). The current desktop app still opens its existing local library without authentication.
