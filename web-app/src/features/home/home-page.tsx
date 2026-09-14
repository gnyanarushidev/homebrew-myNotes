import Link from "next/link";
import { Icon, type IconName } from "@/components/ui/icon";
import { ActionLink, Brand, PublicHeader } from "@/components/ui/ui";
import styles from "./home-page.module.css";

const features: { icon: IconName; title: string; text: string; label: string }[] = [
  { icon: "pen", title: "Room to think", text: "Paper that fits your ideas. A familiar notebook space for writing, sketching, and connecting the dots.", label: "Editor layout available" },
  { icon: "lock", title: "A space of your own", text: "A personal workspace, with invited accounts and a private notebook library.", label: "Invited-user sign-in available" },
  { icon: "monitor", title: "At your desk. On the go.", text: "The plan: one library on the web and Mac, with offline editing that catches up when you reconnect.", label: "Desktop sync planned" },
];

export function HomePage() {
  return (
    <>
      <PublicHeader />
      <main id="main-content" className={styles.main}>
        <section className={styles.hero}>
          <div className={styles.heroCopy}>
            <span className={styles.release}><span /> A new chapter for MyNotes</span>
            <h1>A little space<br />for <em>big ideas.</em></h1>
            <p>Your thoughts deserve more than another open tab. Make room for notes, sketches, and the things you want to remember.</p>
            <div className={styles.actions}>
              <ActionLink href="/notebooks">Explore the workspace <Icon name="arrow" /></ActionLink>
              <ActionLink href="/login" variant="ghost">Already invited? Sign in</ActionLink>
            </div>
            <p className={styles.previewNote}>Private notebooks · Cloud saves · Invitation required</p>
          </div>
          <div className={styles.illustration} aria-label="Illustration of a cream notebook and handwritten ideas" role="img">
            <div className={styles.backCover} />
            <div className={styles.paper}>
              <span className={styles.paperLabel}>A FRESH PAGE</span>
              <p className={styles.handwriting}>Good things<br />start with<br /><span>a little space.</span></p>
              <svg viewBox="0 0 260 80" fill="none" aria-hidden="true"><path d="M16 39c29-31 45 38 72 4s34-40 58-9 44-3 83-5m-23-9 24 9-17 15" stroke="#315e4b" strokeWidth="2.5" strokeLinecap="round" /></svg>
              <span className={styles.paperNumber}>01 / ENDLESS POSSIBILITIES</span>
            </div>
            <span className={styles.annotation}>A place to begin.</span>
          </div>
        </section>

        <section className={styles.features} aria-label="The MyNotes experience">
          {features.map(feature => (
            <article key={feature.title}>
              <span className={styles.featureIcon}><Icon name={feature.icon} /></span>
              <h2>{feature.title}</h2>
              <p>{feature.text}</p>
              <span className={styles.featureLabel}>{feature.label}</span>
            </article>
          ))}
        </section>

        <section className={styles.invitation}>
          <div><p className={styles.eyebrow}>MADE FOR A SMALLER CIRCLE</p><h2>A personal workspace.<br />An open-ended canvas.</h2></div>
          <div><p>MyNotes is taking shape, one thoughtful step at a time. Sign in to your notebook library, or activate your invited account using your setup email.</p><ActionLink href="/invite" variant="secondary">Account setup <Icon name="mail" /></ActionLink></div>
        </section>
      </main>
      <footer className={styles.footer}><Brand /><span>A home for your notes.</span><Link href="/setup">Build status</Link></footer>
    </>
  );
}
