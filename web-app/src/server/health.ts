import "server-only";

/** Application liveness only; it does not probe Supabase or B2 (use `npm run cloud:check`). */
export function getHealthStatus() {
  return {
    status: "ok",
    service: "mynotes-api",
    apiVersion: "v1",
    stage: "live",
  } as const;
}
