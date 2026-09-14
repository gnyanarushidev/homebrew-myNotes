import { test, expect } from "@playwright/test";
import { newDocument, documentSchema, type Stroke } from "../src/lib/notebook";
import { mergeDocuments } from "../src/lib/merge";
import { installSession, mutationHeaders, provider } from "./support/session";

const ink = (x: number): Stroke => ({ id: crypto.randomUUID(), tool: "pen", geometry: "polyline", points: [{ x, y: 100 }, { x: x + 20, y: 130 }], color: "#000000", width: 3, opacity: 1 });

test("three-way merge preserves independent ink and metadata, but rejects overlapping edits", () => {
  const base = newDocument("Base"); base.pages[0].strokes = [ink(100)];
  const local = structuredClone(base), remote = structuredClone(base);
  local.title = "Renamed"; local.pages[0].strokes.push(ink(200));
  remote.color = "cream"; remote.pages[0].strokes.push(ink(300));
  const merged = mergeDocuments(base, local, remote)!;
  expect(merged.title).toBe("Renamed"); expect(merged.color).toBe("cream");
  expect(merged.pages[0].strokes).toHaveLength(3);
  local.pages[0].strokes[0].points[0].x = 110;
  remote.pages[0].strokes[0].points[0].x = 120;
  expect(mergeDocuments(base, local, remote)).toBeNull();
  local.pages[0].strokes = [];
  expect(mergeDocuments(base, local, remote)).toBeNull();
});

test("legacy finite off-page coordinates remain exact through document validation", () => {
  const document = newDocument(); const stroke = ink(12500.125); stroke.points[1].y = -24000.5; document.pages[0].strokes = [stroke];
  expect(documentSchema.parse(document).pages[0].strokes[0].points).toEqual(stroke.points);
  document.pages[0].strokes[0].points[0].x = Infinity;
  expect(documentSchema.safeParse(document).success).toBe(false);
});

test("a web stroke merges with a concurrent device stroke without creating another notebook", async ({ page, context, request }) => {
  await request.post(`${provider}/__test__/reset`);
  await installSession(context, request, "?user=invited");
  const id = crypto.randomUUID(), base = newDocument("Shared edit"); base.pages[0].strokes = [ink(100)];
  await context.request.post("/api/notebooks", { headers: mutationHeaders, data: { id, document: base, mutationId: crypto.randomUUID() } });
  await page.goto(`/notebooks/${id}`);
  const surface = page.getByRole("application", { name: "Drawing page 1" });
  await expect(surface.locator("canvas").first()).toBeVisible();
  const remote = structuredClone(base); const other = ink(300); remote.pages[0].strokes.push(other);
  expect((await context.request.put(`/api/notebooks/${id}`, { headers: mutationHeaders, data: { id, revision: 1, document: remote, mutationId: crypto.randomUUID() } })).status()).toBe(200);
  const box = (await surface.boundingBox())!, scale = box.width / 612;
  await page.mouse.move(box.x + 100 * scale, box.y + 220 * scale); await page.mouse.down();
  await page.mouse.move(box.x + 200 * scale, box.y + 260 * scale, { steps: 5 }); await page.mouse.up();
  await expect(page.getByRole("status").filter({ hasText: "Saved to cloud" })).toBeVisible({ timeout: 10000 });
  const result = await (await context.request.get(`/api/notebooks/${id}`)).json();
  expect(result.document.pages[0].strokes).toHaveLength(3);
  expect(result.document.pages[0].strokes.map((s: Stroke) => s.id)).toContain(other.id);
  expect(await (await context.request.get("/api/notebooks")).json()).toHaveLength(1);
  await expect(page.getByRole("button", { name: "Save conflict copy" })).toHaveCount(0);
});
