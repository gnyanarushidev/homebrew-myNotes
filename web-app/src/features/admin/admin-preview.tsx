"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { Button } from "@/components/ui/ui";
import { Dialog } from "@/components/ui/dialog";
import { Icon } from "@/components/ui/icon";
import { usePreview } from "@/features/preview/preview-provider";
import ui from "@/components/ui/ui.module.css";
import styles from "./admin-preview.module.css";

export function AdminPreview() {
  const { members, inviteMember, revokeInvitation } = usePreview();
  const [query, setQuery] = useState("");
  const [inviting, setInviting] = useState(false);
  const [email, setEmail] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const visible = members.filter(member => `${member.name} ${member.email}`.toLowerCase().includes(query.trim().toLowerCase()));

  function invite(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!inviteMember(email)) { setError("This email already has a sample account or pending invitation."); return; }
    setInviting(false);
    setEmail("");
    setError("");
    setMessage("Preview invitation added. No email was sent and no real account was created.");
  }

  return (
    <>
      <div className={styles.heading}><div><p className={ui.eyebrow}>KEEP YOUR CIRCLE CLOSE</p><h1>People & invitations</h1><p>A thoughtful little workspace, shared by invitation.</p></div><Button onClick={() => { setError(""); setInviting(true); }}><Icon name="plus" />Invite someone</Button></div>
      <div className={styles.stats}>
        <article><div><span>Total people</span><Icon name="users" /></div><strong>{members.filter(member => member.status !== "Revoked").length}</strong><p>Sample accounts and invitations</p></article>
        <article><div><span>Active accounts</span><Icon name="check" /></div><strong>{members.filter(member => member.status === "Active").length}</strong><p>Onboarded in this preview</p></article>
        <article><div><span>Pending invitations</span><Icon name="mail" /></div><strong>{members.filter(member => member.status === "Invited").length}</strong><p>Waiting for a first hello</p></article>
      </div>
      {message && <p role="status" className={ui.statusMessage}>{message}</p>}
      <section className={styles.people} aria-labelledby="people-title">
        <div className={styles.peopleHeader}><h2 id="people-title">Your people <span>Preview data</span></h2><label className={styles.search}><Icon name="search" width="16" height="16" /><span className="sr-only">Search people</span><input type="search" placeholder="Find a person…" value={query} onChange={event => setQuery(event.target.value)} /></label></div>
        <div className={styles.tableScroll}><table><caption className="sr-only">Fictional users and invitations for the admin interface preview</caption><thead><tr><th scope="col">Person</th><th scope="col">Role</th><th scope="col">Status</th><th scope="col"><span className="sr-only">Actions</span></th></tr></thead><tbody>{visible.map(member => <tr key={member.id}><td><div className={styles.person}><span className={styles.avatar}>{member.status === "Active" ? member.name.charAt(0) : <Icon name="mail" width="15" height="15" />}</span><div><strong>{member.name}</strong><span>{member.email}</span></div></div></td><td><span className={styles.role}>{member.role}</span></td><td><span className={`${styles.memberStatus} ${styles[member.status.toLowerCase()]}`}>{member.status}</span></td><td>{member.status === "Invited" ? <button type="button" className={styles.revoke} aria-label={`Revoke preview invitation for ${member.email}`} onClick={() => { revokeInvitation(member.id); setMessage("Preview invitation revoked. This changed only the sample data."); }}>Revoke</button> : <span className={styles.noAction}>—</span>}</td></tr>)}{visible.length === 0 && <tr><td colSpan={4} className={styles.noResults}>No people match your search.</td></tr>}</tbody></table></div>
        <footer>{visible.length} {visible.length === 1 ? "person" : "people"} shown · All data on this page is fictional</footer>
      </section>
      <div className={styles.inviteInfo}><div className={styles.infoIcon}><Icon name="mail" /></div><div><h2>An invitation makes it personal.</h2><p>Once connected, invitees will receive an email and choose a password or Google sign-in. Explore how their first visit will look.</p><Link href="/invite">Preview the invitation page <Icon name="arrow" width="14" height="14" /></Link></div></div>
      <Dialog open={inviting} title="Invite someone in" onClose={() => setInviting(false)}>
        <form className={styles.inviteForm} onSubmit={invite}><p>Try the invitation interface. This adds a sample row only; no email is sent.</p><label className={ui.field} htmlFor="invite-email">Email address<input id="invite-email" type="email" required className={ui.input} placeholder="friend@example.com" value={email} onChange={event => setEmail(event.target.value)} aria-invalid={Boolean(error)} aria-describedby={error ? "invite-error" : undefined} /></label>{error && <p id="invite-error" role="alert" className={ui.errorMessage}>{error}</p>}<div className={styles.inviteActions}><Button variant="secondary" onClick={() => setInviting(false)}>Cancel</Button><Button type="submit">Add preview invitation<Icon name="arrow" /></Button></div></form>
      </Dialog>
    </>
  );
}
