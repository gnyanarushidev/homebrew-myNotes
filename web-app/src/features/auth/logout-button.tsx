"use client";

import { useState } from "react";
import { Button } from "@/components/ui/ui";
import { authRequest } from "./auth-request";
import ui from "@/components/ui/ui.module.css";

export function LogoutButton() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  return <div>
    <Button variant="secondary" disabled={busy} onClick={async () => {
      setBusy(true);
      setError("");
      try { await authRequest("logout", {}); window.location.replace("/login"); }
      catch { setError("Unable to sign out. Please try again."); setBusy(false); }
    }}>{busy ? "Signing out…" : "Sign out"}</Button>
    {error && <p role="alert" className={ui.errorMessage}>{error}</p>}
  </div>;
}
