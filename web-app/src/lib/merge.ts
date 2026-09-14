import { strokePoints } from "./drawing";
import type { NotebookDocument, NotePage, Stroke } from "./notebook";

class MergeConflict extends Error {}
function canonical(value: unknown): string {
  if (value === undefined) return "undefined";
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.entries(value).filter(([, value]) => value !== undefined).sort(([a], [b]) => a.localeCompare(b)).map(([key, value]) => `${JSON.stringify(key)}:${canonical(value)}`).join(",")}}`;
  return JSON.stringify(value);
}
const equal = (a: unknown, b: unknown) => canonical(a) === canonical(b);
function value<T>(base: T, local: T, remote: T): T {
  if (equal(local, base)) return remote;
  if (equal(remote, base) || equal(local, remote)) return local;
  throw new MergeConflict();
}
function stroke(stroke: Stroke): Stroke {
  const hex = Number.parseInt(stroke.color.slice(1), 16);
  const rgba = stroke.rgba ?? { red: ((hex >> 16) & 255) / 255, green: ((hex >> 8) & 255) / 255, blue: (hex & 255) / 255, alpha: 1 };
  return { ...stroke, id: stroke.id.toLowerCase(), geometry: "polyline", points: strokePoints(stroke), rgba, color: `#${[rgba.red, rgba.green, rgba.blue].map(value => Math.round(value * 255).toString(16).padStart(2, "0")).join("")}` };
}
export function normalizeDocument(document: NotebookDocument): NotebookDocument {
  return { ...document, title: document.title.trim(), pages: document.pages.map(page => ({ ...page, id: page.id.toLowerCase(), strokes: page.strokes.map(stroke) })) };
}
export const documentsEqual = (a: NotebookDocument, b: NotebookDocument) => equal(normalizeDocument(a), normalizeDocument(b));
function items<T extends { id: string }>(base: T[], local: T[], remote: T[], combine: (base: T, local: T, remote: T) => T): T[] {
  const b = new Map(base.map(item => [item.id, item])), l = new Map(local.map(item => [item.id, item])), r = new Map(remote.map(item => [item.id, item]));
  const merged = new Map<string, T | undefined>();
  for (const id of new Set([...b.keys(), ...l.keys(), ...r.keys()])) {
    if (equal(l.get(id), b.get(id))) merged.set(id, r.get(id));
    else if (equal(r.get(id), b.get(id)) || equal(l.get(id), r.get(id))) merged.set(id, l.get(id));
    else if (b.has(id) && l.has(id) && r.has(id)) merged.set(id, combine(b.get(id)!, l.get(id)!, r.get(id)!));
    else throw new MergeConflict();
  }
  const order = (list: T[]) => list.map(item => item.id).filter(id => b.has(id) && l.has(id) && r.has(id));
  const original = order(base), left = order(local), right = order(remote);
  if (!equal(left, original) && !equal(right, original) && !equal(left, right)) throw new MergeConflict();
  const preferred = !equal(left, original) ? [...local, ...remote] : [...remote, ...local];
  const seen = new Set<string>();
  return preferred.flatMap(item => { if (seen.has(item.id)) return []; seen.add(item.id); const value = merged.get(item.id); return value ? [value] : []; });
}
export function mergeDocuments(base: NotebookDocument, local: NotebookDocument, remote: NotebookDocument): NotebookDocument | null {
  const b = normalizeDocument(base), l = normalizeDocument(local), r = normalizeDocument(remote);
  try {
    const pages = items(b.pages, l.pages, r.pages, (b, l, r): NotePage => ({
      id: b.id, size: value(b.size, l.size, r.size), template: value(b.template, l.template, r.template), color: value(b.color, l.color, r.color),
      inheritsStyle: value(b.inheritsStyle, l.inheritsStyle, r.inheritsStyle), text: value(b.text, l.text, r.text), image: value(b.image, l.image, r.image),
      strokes: items(b.strokes, l.strokes, r.strokes, () => { throw new MergeConflict(); }),
    }));
    if (!pages.length || pages.length > 300) return null;
    return { schemaVersion: 1, title: value(b.title, l.title, r.title), template: value(b.template, l.template, r.template), color: value(b.color, l.color, r.color), pages };
  } catch (error) { if (error instanceof MergeConflict) return null; throw error; }
}
