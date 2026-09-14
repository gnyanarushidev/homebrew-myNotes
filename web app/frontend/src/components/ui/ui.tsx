import Link from "next/link";
import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Icon } from "./icon";
import styles from "./ui.module.css";

type Variant = "primary" | "secondary" | "ghost";

export function Button({ variant = "primary", className = "", ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return <button type="button" className={`${styles.button} ${styles[variant]} ${className}`} {...props} />;
}

export function ActionLink({ href, children, variant = "primary" }: { href: string; children: ReactNode; variant?: Variant }) {
  return <Link href={href} className={`${styles.button} ${styles[variant]}`}>{children}</Link>;
}

export function Brand() {
  return (
    <Link href="/" className={styles.brand} aria-label="MyNotes home">
      <span className={styles.brandMark}><Icon name="book" /></span>
      MyNotes<span className={styles.brandDot}>.</span>
    </Link>
  );
}

export function PublicHeader() {
  return (
    <header className={styles.publicHeader}>
      <Brand />
      <nav aria-label="Main navigation" className={styles.headerLinks}>
        <Link href="/notebooks">Explore preview</Link>
        <ActionLink href="/login" variant="secondary">Sign in <Icon name="arrow" /></ActionLink>
      </nav>
    </header>
  );
}

export function PreviewNotice({ children }: { children?: ReactNode }) {
  return (
    <div className={styles.notice}>
      <span className={styles.previewDot} />
      <span><strong>Frontend preview</strong> · {children ?? "Example data. Changes stay in this preview session."}</span>
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children: ReactNode }) {
  return <div className={styles.empty}><Icon name="book" width="32" height="32" /><h2>{title}</h2>{children}</div>;
}
