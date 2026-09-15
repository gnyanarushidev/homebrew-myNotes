"use client";

import Link from "next/link";
import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { usePathname } from "next/navigation";
import { Icon } from "@/components/ui/icon";
import { DisclosureMenu } from "@/components/ui/disclosure-menu";
import { LogoutButton } from "@/features/auth/logout-button";
import { api } from "@/lib/api";
import type { Account } from "@/lib/notebook";
import { NotebookLibrary } from "./notebook-library";
import styles from "./desktop-workspace.module.css";

const NavigationContext = createContext<{ collapsed: boolean; mobileOpen: boolean; toggleDesktop: () => void; toggleMobile: () => void } | null>(null);

export function WorkspaceSidebarToggle() {
  const navigation = useContext(NavigationContext);
  if (!navigation) return null;
  return <>
    <button type="button" className={styles.desktopToggle} title="Toggle notebook sidebar" aria-label="Toggle notebook sidebar" aria-expanded={!navigation.collapsed} onClick={navigation.toggleDesktop}><Icon name="sidebar" width="17" height="17" /></button>
    <button type="button" className={styles.mobileToggle} title="Open notebooks" aria-label="Toggle workspace navigation" aria-expanded={navigation.mobileOpen} onClick={navigation.toggleMobile}><Icon name="sidebar" width="17" height="17" /></button>
  </>;
}

export function WorkspaceShell({ user, children }: { user: Account; children: ReactNode }) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const [storageBytes, setStorageBytes] = useState<number | null>(null);
  const isEditor = usePathname().startsWith("/notebooks/");
  const name = user.email.split("@")[0].replace(/[._-]+/g, " ");
  useEffect(() => {
    let cancelled = false;
    const load = () => { void api<{ storedBytes: number }>("/api/v1/sync/usage").then(result => { if (!cancelled) setStorageBytes(result.storedBytes); }).catch(() => undefined); };
    load(); const timer = setInterval(load, 60000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [user.id]);
  return <NavigationContext.Provider value={{ collapsed, mobileOpen, toggleDesktop: () => setCollapsed(value => !value), toggleMobile: () => setMobileOpen(value => !value) }}><div className={styles.layout} data-collapsed={collapsed} data-mobile-open={mobileOpen}>
    <aside className={styles.sidebar}>
      <header className={styles.brandRow}><Link href="/notebooks" onClick={() => setMobileOpen(false)}><span className={styles.brandMark}><Icon name="book" width="19" height="19" /></span>MyNotes</Link><span className={styles.privateMark} title="Private notebook library"><Icon name="lock" width="13" height="13" /></span></header>
      <NotebookLibrary onNavigate={() => setMobileOpen(false)} />
      <footer className={styles.account}>
        <DisclosureMenu name="Account menu" className={styles.accountMenu} panelClassName={styles.accountPanel} closeOnButtons={false} label={<><span className={styles.avatar}>{user.email.charAt(0).toUpperCase()}</span><span className={styles.accountCopy}><strong>{name}</strong><span>Personal workspace</span></span><Icon name="chevrons" width="14" height="14" /></>}>
          <div className={styles.accountIdentity}><strong>{name}</strong><span>{user.email}</span></div>
          <nav className={styles.accountLinks} aria-label="Workspace navigation">
            <Link href="/notebooks" onClick={() => setMobileOpen(false)}><Icon name="book" />Notebooks</Link>
            <Link href="/reset-password" onClick={() => setMobileOpen(false)}><Icon name="settings" />Account settings</Link>
            {user.isAdmin && <Link href="/admin" onClick={() => setMobileOpen(false)}><Icon name="users" />People & invitations</Link>}
          </nav>
          <div className={styles.storageInfo} title="Registered B2 files including previous versions; excludes temporary staging uploads."><Icon name="cloud" /><span>Cloud storage</span><strong>{storageBytes === null ? "—" : storageBytes < 1_000_000 ? `${(storageBytes / 1000).toFixed(1)} KB` : `${(storageBytes / 1_000_000).toFixed(1)} MB`}</strong></div>
          <div className={styles.logoutRow}><Icon name="logout" /><LogoutButton /></div>
        </DisclosureMenu>
      </footer>
    </aside>
    {mobileOpen && <button type="button" className={styles.scrim} aria-label="Close notebook navigation" onClick={() => setMobileOpen(false)} />}
    <div className={styles.workspace}>{!isEditor && <header className={styles.windowBar}><WorkspaceSidebarToggle /><span className={styles.windowTitle}>Notebook library</span><span className={styles.cloudLabel}><Icon name="lock" width="13" height="13" />Only you can see your notes</span></header>}<main id="main-content" className={styles.content}>{children}</main></div>
  </div></NavigationContext.Provider>;
}
