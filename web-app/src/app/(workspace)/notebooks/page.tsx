import type { Metadata } from "next";
import { Icon } from "@/components/ui/icon";
import styles from "@/features/notebooks/desktop-workspace.module.css";

export const metadata: Metadata = { title: "Your notebooks" };
export default function LibraryPage() {
  return <div className={styles.empty}><Icon name="book" width="60" height="60" /><h1>Your notebooks</h1><h2>Select a Notebook</h2><p>Choose a notebook from the sidebar to open it.</p><p>Import a Mac notebook using <strong>Export for web</strong> in the Mac app,<br />then the import button in your cloud library.</p></div>;
}
