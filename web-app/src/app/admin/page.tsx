import type { Metadata } from "next";
import { Brand, ActionLink } from "@/components/ui/ui";
import { Icon } from "@/components/ui/icon";
import { LogoutButton } from "@/features/auth/logout-button";
import { requireAdmin } from "@/server/auth/access";
import { People } from "@/features/admin/people";
import styles from "./page.module.css";

export const metadata: Metadata = { title: "Admin dashboard" };
export const dynamic = "force-dynamic";

export default async function AdminPage() {
  const user = await requireAdmin();
  return <div className={styles.shell}>
    <header className={styles.header}><Brand /><LogoutButton /></header>
    <main id="main-content">
      <p className={styles.eyebrow}>MYNOTES ADMINISTRATION</p>
      <h1>Welcome, administrator.</h1>
      <p className={styles.intro}>Your account is verified and your admin dashboard is protected.</p>
      <section className={styles.account} aria-label="Administrator account">
        <span className={styles.accountIcon}><Icon name="check" /></span>
        <div><h2>Administrator access enabled</h2><p>{user.email}</p></div>
        <span className={styles.badge}>Verified account</span>
      </section>
      <div className={styles.cards}>
        <section><Icon name="lock" /><h2>Your account</h2><p>Manage the password for your administrator account.</p><ActionLink href="/reset-password" variant="secondary">Change password</ActionLink></section>
        <section><Icon name="book" /><h2>Your notebooks</h2><p>Write notes, organize pages, and export JSON backups.</p><ActionLink href="/notebooks" variant="secondary">Open notebooks</ActionLink></section>
      </div>
      <section style={{ marginTop: 40 }}><People /></section>
    </main>
  </div>;
}
