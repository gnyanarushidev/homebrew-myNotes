import { NextRequest } from "next/server";
import { z } from "zod";
import { apiFailure, apiJson, authorized, HttpError, readJson } from "@/server/http";
import { createShare, getShare, revokeShare, sharePath } from "@/server/share";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ id: string }> };

async function notebookId(context: Context) {
  const { id } = await context.params;
  if (!z.uuid().safeParse(id).success) throw new HttpError(404, "Notebook not found.");
  return id.toLowerCase();
}
const view = (appOrigin: string, token: string | null) => ({ shared: Boolean(token), url: token ? new URL(sharePath(token), appOrigin).toString() : null });

// The owner's share status. Browser and native clients authenticate the same way as the sync API.
export async function GET(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request), id = await notebookId(context);
    return auth.finish(apiJson(view(auth.settings.appOrigin, await getShare(auth.user.id, id))));
  } catch (error) { return apiFailure(error, request); }
}
// Creates the read-only link, or returns the existing one.
export async function POST(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request), id = await notebookId(context);
    await readJson(request, 1024);
    return auth.finish(apiJson(view(auth.settings.appOrigin, await createShare(auth.user.id, id))));
  } catch (error) { return apiFailure(error, request); }
}
// Stops sharing; the old URL stops working immediately.
export async function DELETE(request: NextRequest, context: Context) {
  try {
    const auth = await authorized(request), id = await notebookId(context);
    await readJson(request, 1024);
    await revokeShare(auth.user.id, id);
    return auth.finish(apiJson(view(auth.settings.appOrigin, null)));
  } catch (error) { return apiFailure(error, request); }
}
