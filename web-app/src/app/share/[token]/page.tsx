import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { loadShared } from "@/server/share";
import { SharedPage } from "@/features/share/shared-page";
import styles from "@/features/share/shared.module.css";

export const dynamic = "force-dynamic";
// Links are private by obscurity of the token: keep them out of search results and referrers.
export const metadata: Metadata = { title: "Shared notebook", robots: { index: false, follow: false, nocache: true }, referrer: "no-referrer" };

export default async function SharedNotebook({ params }: { params: Promise<{ token: string }> }) {
  const shared = await loadShared((await params).token);
  if (!shared) notFound();
  if (shared.tooLarge) return <main className={styles.shell}><div className={styles.message}><h1>{shared.title}</h1><p>This notebook is too large to display as a shared link. Ask the owner to send an exported copy instead.</p></div></main>;
  const { document } = shared;
  return <div className={styles.shell}>
    <header className={styles.header}><h1 className={styles.title}>{document.title}</h1><span className={styles.badge}>Shared · read only</span></header>
    <main className={styles.pages}>{document.pages.map((page, index) => <div key={page.id} className={styles.page}><SharedPage page={page} document={document} index={index} /></div>)}</main>
    <footer className={styles.footer}>Shared with MyNotes</footer>
  </div>;
}
