"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { Icon } from "@/components/ui/icon";
import { LogoutButton } from "@/features/auth/logout-button";
import type { Account } from "@/lib/notebook";
import { NotebookLibrary } from "./notebook-library";
import styles from "./desktop-workspace.module.css";

export function WorkspaceShell({ user, children }: { user: Account; children: ReactNode }) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  return <div className={styles.layout} data-collapsed={collapsed} data-mobile-open={mobileOpen}>
    <aside className={styles.sidebar}>
      <header className={styles.brandRow}><Link href="/notebooks">MyNotes</Link><Icon name="cloud" width="18" /></header>
      <NotebookLibrary onNavigate={() => setMobileOpen(false)} />
      <footer className={styles.account}><span title={user.email}>{user.email}</span><nav aria-label="Workspace navigation"><Link href="/notebooks" onClick={() => setMobileOpen(false)}>Notebooks</Link><Link href="/reset-password">Account</Link>{user.isAdmin && <Link href="/admin">People & invitations</Link>}</nav><LogoutButton /></footer>
    </aside>
    {mobileOpen && <button type="button" className={styles.scrim} aria-label="Close notebook navigation" onClick={() => setMobileOpen(false)} />}
    <div className={styles.workspace}><header className={styles.windowBar}><button type="button" className={styles.desktopToggle} aria-label="Toggle notebook sidebar" aria-expanded={!collapsed} onClick={() => setCollapsed(!collapsed)}><Icon name="sidebar" /></button><button type="button" className={styles.mobileToggle} aria-label="Toggle workspace navigation" aria-expanded={mobileOpen} onClick={() => setMobileOpen(!mobileOpen)}><Icon name="sidebar" /></button><span>MyNotes</span><span className={styles.cloudLabel}><Icon name="cloud" width="15" />Private cloud workspace</span></header><main id="main-content" className={styles.content}>{children}</main></div>
  </div>;
}
