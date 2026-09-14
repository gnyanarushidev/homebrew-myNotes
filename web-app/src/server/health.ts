import "server-only";

/** Application liveness only; external services are added in later steps. */
export function getHealthStatus() {
  return {
    status: "ok",
    service: "mynotes-api",
    apiVersion: "v1",
    stage: "foundation",
  } as const;
}
