import "server-only";
import { randomBytes } from "node:crypto";
import { HttpError } from "./http";
import { serviceClient } from "./service";
import { assemble, getCloud } from "./cloud";

const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const MISSING_TABLE = "Share links are not set up. Apply 003_share_links.sql.";
// Shared notebooks are rendered on the server, so very large ones are not displayed.
const MAX_SHARED_BYTES = 24_000_000;

function db(error: { code?: string; message?: string } | null) {
  if (!error) return;
  if (error.code === "42P01" || error.code === "PGRST205" || error.message?.includes("cloud_shares")) throw new HttpError(503, MISSING_TABLE);
  throw new HttpError(503, "Share links are temporarily unavailable.");
}

export const sharePath = (token: string) => `/share/${token}`;

export async function getShare(owner: string, notebookId: string): Promise<string | null> {
  await getCloud(owner, notebookId);
  const { data, error } = await serviceClient().from("cloud_shares").select("token").eq("owner_id", owner).eq("notebook_id", notebookId).maybeSingle();
  db(error);
  return data?.token ?? null;
}

/** Returns the notebook's existing link, or creates one. */
export async function createShare(owner: string, notebookId: string): Promise<string> {
  const existing = await getShare(owner, notebookId);
  if (existing) return existing;
  const token = randomBytes(32).toString("base64url");
  const { error } = await serviceClient().from("cloud_shares").insert({ token, owner_id: owner, notebook_id: notebookId });
  if (error?.code === "23505") {
    // A concurrent request created the link first; use that one.
    const winner = await getShare(owner, notebookId);
    if (winner) return winner;
  }
  db(error);
  return token;
}

export async function revokeShare(owner: string, notebookId: string): Promise<void> {
  const { error } = await serviceClient().from("cloud_shares").delete().eq("owner_id", owner).eq("notebook_id", notebookId);
  db(error);
}

/** Resolves a public token to the shared notebook, or null when the link is invalid, revoked, or the notebook was deleted. */
export async function loadShared(token: string) {
  if (!TOKEN.test(token)) return null;
  const { data, error } = await serviceClient().from("cloud_shares").select("owner_id,notebook_id").eq("token", token).maybeSingle();
  db(error);
  if (!data) return null;
  const record = await getCloud(data.owner_id, data.notebook_id).catch(failure => { if (failure instanceof HttpError && failure.status === 404) return null; throw failure; });
  if (!record) return null;
  const bytes = record.manifest.pages.reduce((sum, page) => sum + page.content.bytes + (page.image?.bytes ?? 0), 0);
  if (bytes > MAX_SHARED_BYTES) return { tooLarge: true as const, title: record.manifest.title };
  const { document } = await assemble(data.owner_id, record);
  return { tooLarge: false as const, document, updatedAt: record.updated_at };
}
