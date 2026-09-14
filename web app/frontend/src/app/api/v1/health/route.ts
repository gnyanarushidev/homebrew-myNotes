import { getHealthStatus } from "@mynotes/backend/health";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json(getHealthStatus(), {
    headers: { "Cache-Control": "no-store" },
  });
}
