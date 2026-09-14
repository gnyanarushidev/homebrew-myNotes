import { NextResponse } from "next/server";
import { getAuthSettings } from "@/server/auth/settings";
export const dynamic = "force-dynamic";
export async function GET() {
  try { const settings = getAuthSettings(); return NextResponse.json({ apiVersion: 1, syncProtocol: 2, supabaseUrl: settings.supabaseUrl, publishableKey: settings.publishableKey }, { headers: { "Cache-Control": "no-store" } }); }
  catch { return NextResponse.json({ error: "Application authentication is not configured." }, { status: 503 }); }
}
