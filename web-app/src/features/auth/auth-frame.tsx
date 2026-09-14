import Link from "next/link";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/icon";
import { Brand } from "@/components/ui/ui";
import ui from "@/components/ui/ui.module.css";
import styles from "./auth-preview.module.css";

export function AuthFrame({ eyebrow, title, description, children }: { eyebrow: string; title: string; description: string; children: ReactNode }) {
  return (
    <div className={styles.layout}>
      <aside className={styles.story}>
        <Brand />
        <div className={styles.storyContent}>
          <span className={styles.storyNumber}>A NOTE TO YOURSELF</span>
          <h2>Leave a little room<br />for <em>what’s next.</em></h2>
          <p>A sketch. A thought. A plan that’s still taking shape. Give your ideas somewhere to belong.</p>
          <div className={styles.sketch} aria-hidden="true"><span /><span /><span /></div>
        </div>
        <span className={styles.storyFooter}>Your ideas, at your own pace.</span>
      </aside>
      <main id="main-content" className={styles.main}>
        <div className={styles.topbar}><Link href="/"><Icon name="back" /> Back to home</Link><span>MYNOTES ACCOUNT</span></div>
        <div className={styles.card}>
          <div className={styles.cardIcon}><Icon name="lock" /></div>
          <p className={ui.eyebrow}>{eyebrow}</p>
          <h1>{title}</h1>
          <p className={styles.description}>{description}</p>
          {children}
        </div>
        <footer className={styles.footer}>A home for your notes. Built one page at a time.</footer>
      </main>
    </div>
  );
}
