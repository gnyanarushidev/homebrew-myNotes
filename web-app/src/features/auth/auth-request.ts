export async function authRequest(action: string, body: object): Promise<{ next?: string; message?: string }> {
  const response = await fetch(`/api/auth/${action}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "same-origin",
    cache: "no-store",
    body: JSON.stringify(body),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || "The request could not be completed. Please try again.");
  return result;
}

export function accountDestination(next?: string) {
  return next === "/reset-password" ? "/reset-password" : next === "/notebooks" ? "/notebooks" : "/admin";
}
