"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, type ReactNode } from "react";
import { Brand, Button, PreviewNotice } from "@/components/ui/ui";
import { Icon } from "@/components/ui/icon";
import { PreviewProvider } from "./preview-provider";
import styles from "./workspace-shell.module.css";

function WorkspaceNavigation() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);
  const isAdmin = pathname.startsWith("/preview/admin");

  return (
    <aside className={styles.sidebar}>
      <div className={styles.brandRow}><Brand /><Button variant="ghost" className={styles.menuButton} aria-label="Toggle workspace navigation" aria-expanded={mobileOpen} aria-controls="workspace-navigation" onClick={() => setMobileOpen(!mobileOpen)}><Icon name={mobileOpen ? "close" : "menu"} /></Button></div>
      <div className={`${styles.sidebarContent} ${mobileOpen ? styles.open : ""}`} id="workspace-navigation">
        <p className={styles.navLabel}>YOUR WORKSPACE</p>
        <nav aria-label="Workspace navigation" className={styles.navigation}>
          <Link href="/notebooks" className={!isAdmin ? styles.activeLink : ""} aria-current={!isAdmin ? "page" : undefined} onClick={() => setMobileOpen(false)}><Icon name="book" />Notebooks</Link>
          <Link href="/preview/admin" className={isAdmin ? styles.activeLink : ""} aria-current={isAdmin ? "page" : undefined} onClick={() => setMobileOpen(false)}><Icon name="users" />Administration preview</Link>
        </nav>
        <div className={styles.sidebarNote}><Icon name="cloud" /><p>Your notes, in good company.</p><span>Cloud and offline synchronization are coming in a later step.</span></div>
        <div className={styles.profile}><span className={styles.avatar}>D</span><div><strong>Demo workspace</strong><span>Sample account</span></div></div>
        <Link className={styles.signIn} href="/admin"><Icon name="arrow" /> Open admin dashboard</Link>
      </div>
    </aside>
  );
}

export function WorkspaceShell({ children }: { children: ReactNode }) {
  return (
    <PreviewProvider>
      <div className={styles.layout}>
        <WorkspaceNavigation />
        <div className={styles.workspace}>
          <header className={styles.topbar}><span>Personal workspace <span className={styles.slash}>/</span> Web preview</span><Link href="/setup">Build status <Icon name="arrow" width="14" height="14" /></Link></header>
          <div className={styles.notice}><PreviewNotice /></div>
          <main id="main-content" className={styles.content}>{children}</main>
        </div>
      </div>
    </PreviewProvider>
  );
}
