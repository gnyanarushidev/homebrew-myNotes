"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import { Button } from "@/components/ui/ui";
import { Dialog } from "@/components/ui/dialog";
import { Icon } from "@/components/ui/icon";
import ui from "@/components/ui/ui.module.css";
import styles from "./admin-preview.module.css";

type Person = { id: string; email: string; role: string; status: string; createdAt: string; invitedAt: string | null };

export function People() {
  const [people, setPeople] = useState<Person[]>([]);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState("");
  const [email, setEmail] = useState("");
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [revoke, setRevoke] = useState<Person | null>(null);
  const load = useCallback(() => api<Person[]>("/api/admin/users")
    .then(result => { setPeople(result); setError(""); })
    .catch(error => setError((error as Error).message))
    .finally(() => setLoading(false)), []);
  useEffect(() => { void load(); }, [load]);

  async function change(action: "invite" | "resend" | "revoke", email: string) {
    setBusy(true); setError(""); setMessage("");
    try {
      const result = await api<{ message: string }>("/api/admin/users", { method: "POST", body: JSON.stringify({ action, email }) });
      setMessage(result.message); setOpen(false); setRevoke(null); setEmail(""); await load();
    } catch (error) { setError((error as Error).message); }
    finally { setBusy(false); }
  }
  function invite(event: FormEvent) { event.preventDefault(); void change("invite", email); }
  const visible = people.filter(person => person.email.toLowerCase().includes(query.toLowerCase()));
  return <>
    <div className={styles.heading}><div><p className={ui.eyebrow}>ADMINISTRATION</p><h1>People & invitations</h1><p>Real accounts from your Supabase project.</p></div><Button onClick={() => setOpen(true)}><Icon name="plus" />Invite someone</Button></div>
    <div className={styles.stats}>{[["Total people", people.length], ["Active accounts", people.filter(p => p.status === "Active").length], ["Pending invitations", people.filter(p => p.status === "Invited").length]].map(([label, count]) => <article key={label}><div>{label}</div><strong>{loading ? "…" : count}</strong></article>)}</div>
    {error && <p role="alert" className={ui.errorMessage}>{error} <button type="button" onClick={() => void load()}>Retry</button></p>}
    {message && <p role="status" className={ui.statusMessage}>{message}</p>}
    <section className={styles.people}>
      <div className={styles.peopleHeader}><h2>Your people</h2><label className={styles.search}><Icon name="search" /><input aria-label="Search people" type="search" placeholder="Search by email" value={query} onChange={e => setQuery(e.target.value)} /></label></div>
      <div className={styles.tableScroll}><table><thead><tr><th>Email</th><th>Role</th><th>Status</th><th>Joined</th><th>Actions</th></tr></thead><tbody>
        {visible.map(person => <tr key={person.id}><td>{person.email}</td><td>{person.role}</td><td>{person.status}</td><td>{new Date(person.createdAt).toLocaleDateString()}</td><td>{person.role !== "Admin" && <><Button variant="ghost" disabled={busy} onClick={() => void change("resend", person.email)}>{person.status === "Active" ? "Send setup link" : "Invite / resend"}</Button>{person.status !== "Revoked" && <Button variant="ghost" disabled={busy} onClick={() => setRevoke(person)}>Revoke access</Button>}</>}</td></tr>)}
        {!loading && visible.length === 0 && <tr><td colSpan={5}>No people to display.</td></tr>}
      </tbody></table></div>
    </section>
    <Dialog open={open} title="Invite someone" onClose={() => !busy && setOpen(false)}><form className={styles.inviteForm} onSubmit={invite}><p>An email will be sent with a link to set up their MyNotes account.</p><label className={ui.field}>Email address<input type="email" required className={ui.input} value={email} onChange={e => setEmail(e.target.value)} /></label>{error && <p role="alert" className={ui.errorMessage}>{error}</p>}<Button type="submit" disabled={busy}>{busy ? "Sending…" : "Send invitation"}</Button></form></Dialog>
    <Dialog open={Boolean(revoke)} title="Revoke account access?" onClose={() => !busy && setRevoke(null)}><p>{revoke?.email} will lose application access. Their notebook data will be retained.</p>{error && <p role="alert">{error}</p>}<Button disabled={busy} onClick={() => revoke && void change("revoke", revoke.email)}>Revoke access</Button></Dialog>
  </>;
}
