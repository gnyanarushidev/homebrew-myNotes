import styles from "@/features/share/shared.module.css";

export default function SharedNotFound() {
  return <main className={styles.shell}><div className={styles.message}><h1>This link isn’t available</h1><p>The notebook may have been deleted, or its owner stopped sharing it.</p></div></main>;
}
