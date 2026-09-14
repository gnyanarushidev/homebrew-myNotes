import { NextRequest, NextResponse } from "next/server";
import { createRequestAuth, PRIVATE_HEADERS } from "@/server/auth/client";
import { getAuthSettings } from "@/server/auth/settings";

export async function proxy(request: NextRequest) {
  try {
    const auth = createRequestAuth(request, getAuthSettings());
    await auth.client.auth.getUser();
    // Forward refreshed cookies to the server-rendered page as well as the browser.
    return auth.finish(NextResponse.next({ request: { headers: request.headers } }));
  } catch {
    return NextResponse.next({ headers: PRIVATE_HEADERS });
  }
}

export const config = {
  matcher: ["/admin/:path*", "/notebooks/:path*", "/login", "/invite", "/reset-password"],
};
