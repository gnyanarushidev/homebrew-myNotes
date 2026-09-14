import type { APIRequestContext, BrowserContext } from "@playwright/test";

export const origin = "http://127.0.0.1:3101";
export const provider = "http://127.0.0.1:54329";
export const mutationHeaders = { Origin: origin };

export async function installSession(context: BrowserContext, request: APIRequestContext, query = "") {
  const session = await (await request.get(`${provider}/__test__/session${query}`)).json();
  const encoded = `base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`;
  const chunks = encoded.match(/.{1,3000}/g) ?? [];
  await context.addCookies(chunks.map((value, index) => ({ name: chunks.length === 1 ? "mynotes-auth" : `mynotes-auth.${index}`, value, url: origin, httpOnly: true, sameSite: "Lax" as const })));
  return session;
}
