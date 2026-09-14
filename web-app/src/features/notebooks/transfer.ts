import { dimensions, effectiveStyle, paperHex, type NotebookDocument } from "@/lib/notebook";
import { parseNotebookImport } from "@/lib/notebook-import";
import { inkColor, strokePoints } from "@/lib/drawing";

export async function importDocument(file: File): Promise<NotebookDocument> {
  if (file.size > 2_900_000) throw new Error("This file exceeds the notebook import limit of 2.9 MB.");
  let value: unknown;
  try { value = JSON.parse(await file.text()); }
  catch { throw new Error("Choose a valid MyNotes JSON export."); }
  return parseNotebookImport(value, file.name).document;
}

export function exportDocument(document: NotebookDocument) {
  download(new Blob([JSON.stringify(document)], { type: "application/json" }), document.title, "json");
}

function download(blob: Blob, title: string, extension: string) {
  const url = URL.createObjectURL(blob);
  const link = window.document.createElement("a");
  link.href = url;
  link.download = `${title.replace(/[^\p{L}\p{N} _-]/gu, "_").slice(0, 100) || "notebook"}.${extension}`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export async function exportPDF(document: NotebookDocument, currentPage?: number) {
  const { PDFDocument } = await import("pdf-lib");
  const pdf = await PDFDocument.create();
  const pages = currentPage === undefined ? document.pages : [document.pages[currentPage]];
  for (const page of pages) {
    const { width, height } = dimensions(page.size), paper = effectiveStyle(document, page);
    const canvas = window.document.createElement("canvas");
    canvas.width = width * 2; canvas.height = height * 2;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("PDF rendering is unavailable in this browser.");
    ctx.scale(2, 2); ctx.fillStyle = paperHex[paper.color]; ctx.fillRect(0, 0, width, height);
    ctx.fillStyle = ctx.strokeStyle = paper.color === "dark" ? "rgba(115,166,255,.32)" : "rgba(0,0,255,.16)"; ctx.lineWidth = .7;
    if (paper.template === "ruled" || paper.template === "grid") {
      ctx.beginPath();
      for (let y = paper.template === "ruled" ? 36 : 0; y <= height; y += 32) { ctx.moveTo(0, y); ctx.lineTo(width, y); }
      if (paper.template === "grid") for (let x = 0; x <= width; x += 32) { ctx.moveTo(x, 0); ctx.lineTo(x, height); }
      ctx.stroke();
    } else if (paper.template === "dots") for (let x = 16; x <= width; x += 24) for (let y = 16; y <= height; y += 24) { ctx.beginPath(); ctx.arc(x, y, .75, 0, Math.PI * 2); ctx.fill(); }
    if (page.image) {
      const image = new Image(); image.src = `data:${page.image.mimeType};base64,${page.image.data}`; await image.decode();
      const scale = Math.min((width - 100) / image.width, (height - 120) / image.height);
      ctx.drawImage(image, (width - image.width * scale) / 2, 60, image.width * scale, image.height * scale);
    }
    ctx.fillStyle = paper.color === "dark" ? "white" : "#1f1f1f"; ctx.font = "18px Georgia"; ctx.textBaseline = "top";
    let y = 35;
    for (const paragraph of page.text.split("\n")) {
      let line = "";
      for (const char of paragraph) {
        if (ctx.measureText(line + char).width > width - 100) { ctx.fillText(line, 50, y); y += 32; line = ""; }
        line += char;
      }
      if (y < height - 35) ctx.fillText(line, 50, y);
      y += 32;
      if (y >= height - 35) break;
    }
    ctx.lineCap = ctx.lineJoin = "round";
    for (const stroke of page.strokes) {
      const points = strokePoints(stroke); ctx.globalAlpha = stroke.opacity; ctx.strokeStyle = ctx.fillStyle = inkColor(stroke); ctx.lineWidth = stroke.width;
      ctx.beginPath(); ctx.moveTo(points[0].x, points[0].y);
      if (points.length === 1) { ctx.arc(points[0].x, points[0].y, stroke.width / 2, 0, Math.PI * 2); ctx.fill(); }
      else { for (const point of points.slice(1)) ctx.lineTo(point.x, point.y); ctx.stroke(); }
    }
    const image = await pdf.embedPng(canvas.toDataURL("image/png"));
    pdf.addPage([width, height]).drawImage(image, { x: 0, y: 0, width, height });
    canvas.width = canvas.height = 0;
  }
  download(new Blob([new Uint8Array(await pdf.save())], { type: "application/pdf" }), `${document.title}${currentPage === undefined ? "" : `-Page-${currentPage + 1}`}`, "pdf");
}
