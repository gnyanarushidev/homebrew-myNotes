import "server-only";
import { NextRequest, NextResponse } from "next/server";
import { createRequestAuth, isAllowedAccount, isVerifiedAdmin, PRIVATE_HEADERS } from "./auth/client";
import { getAuthSettings } from "./auth/settings";

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export const apiJson = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: PRIVATE_HEADERS });

export async function authorized(request: NextRequest, adminOnly = false) {
  const settings = getAuthSettings();
  const auth = createRequestAuth(request, settings);
  const { data, error } = await auth.client.auth.getUser();
  if (error || !data.user) throw new HttpError(401, "Sign in to continue.");
  if (!isAllowedAccount(data.user, settings) || (adminOnly && !isVerifiedAdmin(data.user, settings))) throw new HttpError(403, "This account does not have access.");
  return { ...auth, user: data.user, settings };
}

export async function readJson(request: NextRequest, maxBytes = 3_000_000): Promise<unknown> {
  if (request.headers.get("origin") !== getAuthSettings().appOrigin) throw new HttpError(403, "Request origin is not allowed.");
  if (!request.headers.get("content-type")?.startsWith("application/json")) throw new HttpError(415, "Expected JSON.");
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, "A request body is required.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) { await reader.cancel(); throw new HttpError(413, "This notebook exceeds the 3 MB cloud-save limit. Export a backup and split it into smaller notebooks."); }
    chunks.push(value);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new HttpError(400, "Invalid JSON."); }
}

export function apiFailure(error: unknown) {
  return apiJson({ error: error instanceof Error ? error.message : "The request failed." }, error instanceof HttpError ? error.status : 503);
}
