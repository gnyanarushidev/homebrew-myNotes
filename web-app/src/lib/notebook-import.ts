import { z } from "zod";
import { documentSchema, imageSchema, newDocument, pageSizes, paperColors, pointSchema, rgbaSchema, templates, type NotebookDocument } from "./notebook";

const styleSchema = rgbaSchema.extend({ width: z.number().finite().min(0.1).max(100), opacity: z.number().finite().min(0.01).max(1) });
const nativeStroke = z.object({ id: z.uuid(), points: z.array(pointSchema).min(1).max(50000), tool: z.enum(["pen", "pencil", "highlighter", "rectangle", "circle", "line", "arrow"]).default("pen"), style: styleSchema.optional() });
const nativeSchema = z.object({ format: z.literal("mynotes-mac"), version: z.literal(1), notebook: z.object({ id: z.uuid(), title: z.string().trim().min(1).max(120), template: z.enum(templates), color: z.enum(paperColors), pages: z.array(z.object({ id: z.uuid(), size: z.enum(pageSizes), template: z.enum(templates), color: z.enum(paperColors), inheritsStyle: z.boolean(), text: z.string().max(100000), image: imageSchema.optional(), strokes: z.array(nativeStroke).max(20000) })).min(1).max(300) }) });

function convertStroke(stroke: z.infer<typeof nativeStroke>) {
  const style = stroke.style ?? (stroke.tool === "pencil" ? { red: 0.38, green: 0.38, blue: 0.42, alpha: 1, width: 1.5, opacity: 0.9 } : stroke.tool === "highlighter" ? { red: 1, green: 1, blue: 0, alpha: 1, width: 14, opacity: 0.35 } : { red: 0, green: 0, blue: 0, alpha: 1, width: 3, opacity: 1 });
  const { red, green, blue, alpha, width, opacity } = style;
  return { id: stroke.id.toLowerCase(), points: stroke.points, tool: stroke.tool, geometry: "polyline" as const, color: `#${[red, green, blue].map(value => Math.round(value * 255).toString(16).padStart(2, "0")).join("")}`, rgba: { red, green, blue, alpha }, width, opacity };
}

export function parseNotebookImport(value: unknown, filename = "Imported drawing"): { document: NotebookDocument; sourceId?: string } {
  const web = documentSchema.safeParse(value);
  if (web.success) return { document: web.data };
  const mac = nativeSchema.safeParse(value);
  if (mac.success) {
    const { id, ...notebook } = mac.data.notebook;
    const document = documentSchema.parse({ schemaVersion: 1, ...notebook, pages: notebook.pages.map(page => ({ ...page, id: page.id.toLowerCase(), strokes: page.strokes.map(convertStroke) })) });
    return { document, sourceId: id.toLowerCase() };
  }
  const drawing = z.array(nativeStroke).min(1).max(20000).safeParse(value);
  if (drawing.success) {
    const document = newDocument(filename.replace(/\.drawing\.json$|\.json$/i, "").slice(0, 120) || "Imported drawing");
    // Deterministic source/page identity makes raw drawing retries safe too.
    document.pages[0].id = drawing.data[0].id.toLowerCase();
    document.pages[0].strokes = drawing.data.map(convertStroke);
    return { document: documentSchema.parse(document), sourceId: document.pages[0].id };
  }
  throw new Error("Choose a MyNotes web JSON backup, a Mac ‘Export for web’ notebook, or a .drawing.json file. Unsupported or damaged content cannot be imported.");
}
