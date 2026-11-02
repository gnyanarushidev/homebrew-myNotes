"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { Button } from "@/components/ui/ui";
import ui from "@/components/ui/ui.module.css";

type ShareState = { shared: boolean; url: string | null };

/** Content of the share dialog. Mount it only while the dialog is open so every opening reloads the status. */
export function ShareContent({ notebookId }: { notebookId: string }) {
  const [state, setState] = useState<ShareState | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const path = `/api/v1/share/${notebookId}`;

  useEffect(() => {
    let active = true;
    api<ShareState>(path).then(result => { if (active) setState(result); }).catch(failure => { if (active) setError(failure.message); });
    return () => { active = false; };
  }, [path]);

  async function change(method: "POST" | "DELETE") {
    setBusy(true); setError(""); setCopied(false);
    try { setState(await api<ShareState>(path, { method, body: "{}" })); }
    catch (failure) { setError((failure as Error).message); }
    finally { setBusy(false); }
  }
  async function copy() {
    if (!state?.url) return;
    try { await navigator.clipboard.writeText(state.url); setCopied(true); }
    catch { setError("Copy failed. Select the link and copy it manually."); }
  }

  return <div style={{ display: "grid", gap: 12 }}>
    {!state && !error && <p role="status">Loading…</p>}
    {state && !state.shared && <>
      <p>Anyone with the link can view this notebook, but not edit it. You can stop sharing at any time.</p>
      <Button disabled={busy} onClick={() => void change("POST")}>{busy ? "Creating…" : "Create share link"}</Button>
    </>}
    {state?.shared && state.url && <>
      <p>Anyone with this link can view the notebook, including future changes you save.</p>
      <input className={ui.input} readOnly aria-label="Share link" value={state.url} onFocus={event => event.currentTarget.select()} />
      <Button onClick={() => void copy()}>{copied ? "Copied" : "Copy link"}</Button>
      <Button variant="ghost" disabled={busy} onClick={() => void change("DELETE")}>{busy ? "Stopping…" : "Stop sharing"}</Button>
    </>}
    {error && <p role="alert" className={ui.errorMessage}>{error}</p>}
  </div>;
}
