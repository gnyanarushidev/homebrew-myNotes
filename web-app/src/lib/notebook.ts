import { z } from "zod";

export const templates = ["blank", "ruled", "grid", "dots"] as const;
export const paperColors = ["white", "cream", "dark"] as const;
export const pageSizes = ["letterPortrait", "a4Portrait"] as const;
export type Template = typeof templates[number];
export type PaperColor = typeof paperColors[number];
export type PageSize = typeof pageSizes[number];
export const drawingTools = ["pen", "pencil", "highlighter", "eraser", "lasso", "rectangle", "circle", "line", "arrow", "hand"] as const;
export type Tool = typeof drawingTools[number];

const finite = z.number().finite();
export const rgbaSchema = z.object({ red: finite.min(0).max(1), green: finite.min(0).max(1), blue: finite.min(0).max(1), alpha: finite.min(0).max(1) });
export const pointSchema = z.object({ x: finite.min(-10000).max(10000), y: finite.min(-10000).max(10000) });
export const strokeSchema = z.object({
  id: z.uuid(),
  tool: z.enum(["pen", "pencil", "highlighter", "rectangle", "circle", "line", "arrow"]),
  points: z.array(pointSchema).min(1).max(50000),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  width: finite.min(0.1).max(100),
  opacity: finite.min(0.01).max(1),
  // Native shapes already contain their final path, including rotation/resize.
  geometry: z.enum(["shape", "polyline"]).optional(),
  rgba: rgbaSchema.optional(),
});
export const imageSchema = z.object({ mimeType: z.enum(["image/png", "image/jpeg"]), data: z.string().max(2_800_000).regex(/^[A-Za-z0-9+/]*={0,2}$/) });
export const pageSchema = z.object({
  id: z.uuid(), template: z.enum(templates), color: z.enum(paperColors), size: z.enum(pageSizes),
  inheritsStyle: z.boolean(), strokes: z.array(strokeSchema).max(20000), text: z.string().max(100000).default(""),
  image: imageSchema.optional(),
});
export const documentSchema = z.object({
  schemaVersion: z.literal(1), title: z.string().trim().min(1).max(120),
  template: z.enum(templates), color: z.enum(paperColors),
  pages: z.array(pageSchema).min(1).max(300),
}).superRefine((document, context) => {
  const ids = document.pages.map(page => page.id);
  if (new Set(ids).size !== ids.length) context.addIssue({ code: "custom", message: "Duplicate page IDs." });
  for (const page of document.pages) {
    if (new Set(page.strokes.map(stroke => stroke.id)).size !== page.strokes.length) {
      context.addIssue({ code: "custom", message: "Duplicate stroke IDs." });
    }
  }
});

export type Point = z.infer<typeof pointSchema>;
export type Stroke = z.infer<typeof strokeSchema>;
export type NotePage = z.infer<typeof pageSchema>;
export type NotebookDocument = z.infer<typeof documentSchema>;
export type NotebookRecord = { id: string; document: NotebookDocument; revision: number; mutation_id: string; created_at: string; updated_at: string };
export type NotebookSummary = { id: string; title: string; template: Template; color: PaperColor; pageCount: number; updated_at: string; text: string };
export type Account = { id: string; email: string; isAdmin: boolean };

export function dimensions(size: PageSize) { return size === "a4Portrait" ? { width: 595, height: 842 } : { width: 612, height: 792 }; }
export function newPage(size: PageSize = "letterPortrait"): NotePage {
  return { id: crypto.randomUUID(), template: "blank", color: "white", size, inheritsStyle: true, strokes: [], text: "" };
}
export function newDocument(title = "Untitled Notebook", template: Template = "blank", color: PaperColor = "white", size: PageSize = "letterPortrait"): NotebookDocument {
  return { schemaVersion: 1, title, template, color, pages: [newPage(size)] };
}
export function effectiveStyle(document: NotebookDocument, page: NotePage) {
  return page.inheritsStyle ? { template: document.template, color: document.color } : { template: page.template, color: page.color };
}
export const paperHex: Record<PaperColor, string> = { white: "#ffffff", cream: "#faf5e0", dark: "#1f1f21" };
