import { NextRequest, NextResponse } from "next/server";
import { createRequestAuth, isVerifiedAdmin, PRIVATE_HEADERS } from "@/server/auth/client";
import { authDestination, getAuthSettings } from "@/server/auth/settings";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const settings = getAuthSettings();
    const auth = createRequestAuth(request, settings);
    const params = request.nextUrl.searchParams;
    const fail = () => auth.finish(NextResponse.redirect(new URL("/login?reason=link-invalid", settings.appOrigin)));
    if (params.has("error") || params.has("error_description")) return fail();
    const code = params.get("code");
    const tokenHash = params.get("token_hash");
    const type = params.get("type");

    if (!code && !tokenHash) {
      // Default invitation/recovery emails return tokens in the URL fragment.
      // Browsers preserve that fragment across this redirect to the completion page.
      const destination = new URL("/auth/complete", settings.appOrigin);
      destination.searchParams.set("next", authDestination(params.get("next")));
      return auth.finish(NextResponse.redirect(destination));
    }

    const result = code
      ? await auth.client.auth.exchangeCodeForSession(code)
      : (type === "invite" || type === "recovery" || type === "email") && tokenHash
        ? await auth.client.auth.verifyOtp({ token_hash: tokenHash, type })
        : null;
    const { data } = result && !result.error ? await auth.client.auth.getUser() : { data: { user: null } };
    if (!result || result.error || !isVerifiedAdmin(data.user, settings)) {
      auth.clearSession();
      return fail();
    }
    const next = type === "invite" || type === "recovery" ? "/reset-password" : authDestination(params.get("next"));
    return auth.finish(NextResponse.redirect(new URL(next, settings.appOrigin)));
  } catch {
    return NextResponse.json({ error: "Authentication is unavailable. Check the deployment configuration." }, { status: 503, headers: PRIVATE_HEADERS });
  }
}
