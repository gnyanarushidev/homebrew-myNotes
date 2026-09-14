import { getHealthStatus } from "@/server/health";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json(getHealthStatus(), {
    headers: { "Cache-Control": "no-store" },
  });
}
