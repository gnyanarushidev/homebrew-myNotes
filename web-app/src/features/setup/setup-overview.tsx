import Link from "next/link";
import styles from "./setup-overview.module.css";

const steps = [
  {
    number: "01",
    title: "Application foundation",
    description:
      "One full-stack Next.js application with pages, API routes, and server logic, alongside the native Mac project.",
    status: "Complete",
  },
  {
    number: "02",
    title: "Frontend page previews",
    description:
      "Explore sign-in, invitations, notebooks, editor controls, and the admin dashboard before connecting live data.",
    status: "Complete",
  },
  {
    number: "03",
    title: "Administrator authentication",
    description:
      "Supabase sign-in, protected admin access, password-setup emails, session refresh, and logout.",
    status: "Complete",
  },
  {
    number: "04",
    title: "Desktop-style cloud drawing",
    description:
      "A Mac-style sidebar and continuous canvas, floating drawing tools, cloud saves, PDF export, and import of local Mac drawings.",
    status: "Current step",
  },
  {
    number: "05",
    title: "Desktop sign-in and offline sync",
    description:
      "Supabase sign-in, Keychain sessions, private account stores, local migration, downloads, and synchronization after reconnecting.",
    status: "Planned",
  },
];

export function SetupOverview() {
  return (
    <div className={styles.shell}>
      <header className={styles.header}>
        <Link className={styles.brand} href="/" aria-label="MyNotes home">
          <span className={styles.mark} aria-hidden="true">
            M
          </span>
          MyNotes
        </Link>
        <span className={styles.badge}>Cloud notebook foundation</span>
      </header>

      <main id="main-content">
        <section className={styles.hero} aria-labelledby="page-title">
          <p className={styles.eyebrow}>One workspace. Web and Mac.</p>
          <h1 id="page-title">
            A home for your notes.
            <br />
            Online and off.
          </h1>
          <p className={styles.introduction}>
            Invited accounts and private notebook storage are connected in code.
            Apply the notebook database migration, configure the server secret,
            and redeploy to enable the workspace.
          </p>
          <div className={styles.actions}>
            <Link className={styles.primaryLink} href="/notebooks">
              Explore the workspace
            </Link>
            <a className={styles.secondaryLink} href="/api/v1/health">
              Check API health <span aria-hidden="true">↗</span>
            </a>
          </div>
        </section>

        <section className={styles.roadmap} aria-labelledby="roadmap-title">
          <div className={styles.sectionHeading}>
            <h2 id="roadmap-title">Building your workspace</h2>
            <span>Step by step</span>
          </div>
          <ol className={styles.steps}>
            {steps.map((step, index) => (
              <li className={styles.step} key={step.number}>
                <span className={styles.stepNumber}>{step.number}</span>
                <div>
                  <p className={index === 3 ? styles.currentStatus : styles.status}>
                    {step.status}
                  </p>
                  <h3>{step.title}</h3>
                  <p className={styles.stepDescription}>{step.description}</p>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <section
          id="next-step"
          className={styles.nextStep}
          aria-labelledby="next-step-title"
        >
          <div>
            <p className={styles.eyebrow}>Next integration</p>
            <h2 id="next-step-title">Sign into the same account on Mac</h2>
            <p>
              Add native sign-in and account-specific local storage, then
              download cloud notebooks and synchronize offline changes.
            </p>
          </div>
          <span className={styles.nextLabel}>Mac + web compatibility</span>
        </section>
      </main>

      <footer className={styles.footer}>
        <span>MyNotes · Web foundation</span>
        <span>Next.js + Supabase + Backblaze B2</span>
      </footer>
    </div>
  );
}
