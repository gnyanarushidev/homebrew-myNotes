import "server-only";
import { NextRequest, NextResponse } from "next/server";
import { createEmailAuth, createRequestAuth, isAllowedAccount, isVerifiedAdmin, PRIVATE_HEADERS } from "./auth/client";
import { getAuthSettings } from "./auth/settings";

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export const apiJson = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: PRIVATE_HEADERS });
const responseFinish = new WeakMap<NextRequest, (response: NextResponse) => NextResponse>();

export async function authorized(request: NextRequest, adminOnly = false) {
  const settings = getAuthSettings();
  const authorization = request.headers.get("authorization");
  if (authorization !== null) {
    const match = /^Bearer ([^\s]+)$/.exec(authorization);
    if (!match || match[1].length > 8192) throw new HttpError(401, "Invalid bearer credentials.");
    const client = createEmailAuth(settings);
    const { data, error } = await client.auth.getUser(match[1]);
    if (error || !data.user) throw new HttpError(401, "Sign in to continue.");
    if (request.headers.has("x-mynotes-account") && request.headers.get("x-mynotes-account") !== data.user.id) throw new HttpError(403, "The active account changed. Reopen the notebook.");
    if (!isAllowedAccount(data.user, settings) || (adminOnly && !isVerifiedAdmin(data.user, settings))) throw new HttpError(403, "This account does not have access.");
    nativeRequests.add(request);
    return { client, user: data.user, settings, finish: (response: NextResponse) => response };
  }
  const auth = createRequestAuth(request, settings);
  responseFinish.set(request, auth.finish);
  const { data, error } = await auth.client.auth.getUser();
  if (error || !data.user) throw new HttpError(401, "Sign in to continue.");
  if (request.headers.has("x-mynotes-account") && request.headers.get("x-mynotes-account") !== data.user.id) throw new HttpError(403, "The active account changed. Reopen the notebook.");
  if (!isAllowedAccount(data.user, settings) || (adminOnly && !isVerifiedAdmin(data.user, settings))) throw new HttpError(403, "This account does not have access.");
  return { ...auth, user: data.user, settings };
}

// Only successfully verified bearer requests can bypass browser Origin checks.
const nativeRequests = new WeakSet<NextRequest>();

export async function readJson(request: NextRequest, maxBytes = 3_000_000): Promise<unknown> {
  if (!nativeRequests.has(request) && request.headers.get("origin") !== getAuthSettings().appOrigin) throw new HttpError(403, "Request origin is not allowed.");
  if (!request.headers.get("content-type")?.startsWith("application/json")) throw new HttpError(415, "Expected JSON.");
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, "A request body is required.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) { await reader.cancel(); throw new HttpError(413, "The request is too large. Use the page-file upload workflow for large notebooks."); }
    chunks.push(value);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new HttpError(400, "Invalid JSON."); }
}

export function apiFailure(error: unknown, request?: NextRequest) {
  const response = apiJson({ error: error instanceof Error ? error.message : "The request failed." }, error instanceof HttpError ? error.status : 503);
  return (request && responseFinish.get(request))?.(response) ?? response;
}
