"use client";

import { useEffect, useRef, useState } from "react";
import { ActionLink } from "@/components/ui/ui";
import { AuthFrame } from "./auth-frame";
import { accountDestination, authRequest } from "./auth-request";
import ui from "@/components/ui/ui.module.css";

async function completeSignIn() {
  const fragment = new URLSearchParams(window.location.hash.slice(1));
  const next = new URLSearchParams(window.location.search).get("next");
  // Remove credentials before any request or navigation. Never persist them in browser storage.
  window.history.replaceState(null, "", window.location.pathname);
  const access_token = fragment.get("access_token");
  const refresh_token = fragment.get("refresh_token");
  if (fragment.has("error") || !access_token || !refresh_token) {
    throw new Error("This link is missing, expired, or already used. Request a fresh password-reset email.");
  }
  const result = await authRequest("complete", { access_token, refresh_token, type: fragment.get("type"), next });
  return accountDestination(result.next);
}

export function AuthComplete() {
  const completion = useRef<Promise<string> | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    completion.current ??= completeSignIn();
    completion.current.then(next => { if (active) window.location.replace(next); })
      .catch(failure => { if (active) setError(failure instanceof Error ? failure.message : "Sign-in could not be completed."); });
    return () => { active = false; };
  }, []);

  return <AuthFrame eyebrow="YOUR MYNOTES ACCOUNT" title="Finishing your sign-in." description="We’re verifying your email link and preparing your account.">
    {error ? <><p role="alert" className={ui.errorMessage}>{error}</p><p><ActionLink href="/forgot-password">Get a new setup link</ActionLink></p><ActionLink href="/login" variant="ghost">Back to sign in</ActionLink></> : <p role="status" className={ui.statusMessage}>Verifying your account…</p>}
  </AuthFrame>;
}
