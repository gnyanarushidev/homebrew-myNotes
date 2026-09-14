import { z } from "zod";
import { pageSizes, paperColors, strokeSchema, templates } from "./notebook";

export const MAX_PAGE_BYTES = 16_000_000;
export const MAX_ASSET_BYTES = 8_000_000;
export const pageContentSchema = z.object({ version: z.literal(1), text: z.string().max(100000), strokes: z.array(strokeSchema).max(20000) }).superRefine((page, ctx) => {
  if (new Set(page.strokes.map(s => s.id.toLowerCase())).size !== page.strokes.length) ctx.addIssue({ code: "custom", message: "Duplicate stroke IDs" });
});
export const fileSchema = z.object({ key: z.string().max(400), sha256: z.string().regex(/^[a-f0-9]{64}$/), bytes: z.number().int().positive().max(MAX_PAGE_BYTES), kind: z.enum(["page", "image/png", "image/jpeg"]) }).strict();
export const cloudPageSchema = z.object({ id: z.uuid().toLowerCase(), size: z.enum(pageSizes), template: z.enum(templates), color: z.enum(paperColors), inheritsStyle: z.boolean(), content: fileSchema, image: fileSchema.optional() }).strict();
export const manifestSchema = z.object({ version: z.literal(1), title: z.string().trim().min(1).max(120), template: z.enum(templates), color: z.enum(paperColors), pages: z.array(cloudPageSchema).max(300) }).strict().superRefine((manifest, ctx) => {
  if (new Set(manifest.pages.map(p => p.id.toLowerCase())).size !== manifest.pages.length) ctx.addIssue({ code: "custom", message: "Duplicate page IDs" });
  if (manifest.pages.some(p => p.content.kind !== "page" || p.image?.kind === "page")) ctx.addIssue({ code: "custom", message: "Invalid file kind" });
  if (manifest.pages.reduce((bytes, page) => bytes + page.content.bytes + (page.image?.bytes ?? 0), 0) > 128_000_000) ctx.addIssue({ code: "custom", message: "Notebook content exceeds 128 MB" });
});
export type CloudFile = z.infer<typeof fileSchema>;
export type CloudManifest = z.infer<typeof manifestSchema>;
export type CloudRecord = { id: string; manifest: CloudManifest; revision: number; change_seq: number; deleted: boolean; updated_at: string; created_at: string; mutation_id: string };
export type CloudReceipt = { id: string; revision: number; sequence: number; conflict: boolean; deleted: boolean; duplicate?: boolean };
export function filesIn(manifest: CloudManifest) { return manifest.pages.flatMap(page => page.image ? [page.content, page.image] : [page.content]); }
