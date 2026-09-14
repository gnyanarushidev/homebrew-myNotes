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
    status: "Current step",
  },
  {
    number: "03",
    title: "Your private account",
    description:
      "Connect Supabase, configure the administrator, and add invitations with email or Google sign-in.",
    status: "Up next",
  },
  {
    number: "04",
    title: "Your notebook workspace",
    description:
      "Build the page editor, paper styles, drawing tools, and cloud saves around a shared document format.",
    status: "Planned",
  },
  {
    number: "05",
    title: "Take your notes offline",
    description:
      "Download notebooks to your Mac and synchronize offline edits when you reconnect.",
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
        <span className={styles.badge}>Frontend preview</span>
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
            The frontend page previews are ready to explore and deploy.
            Next, we&apos;ll connect the production domain, Supabase accounts,
            and invitations.
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
                  <p className={index === 1 ? styles.currentStatus : styles.status}>
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
            <h2 id="next-step-title">Connect Supabase authentication</h2>
            <p>
              Deploy the preview and connect mynotes.gnyanarushi.tech. We&apos;ll
              then implement authentication using the configured Supabase project.
            </p>
          </div>
          <span className={styles.nextLabel}>Email + Google sign-in</span>
        </section>
      </main>

      <footer className={styles.footer}>
        <span>MyNotes · Web foundation</span>
        <span>Next.js + Supabase + Backblaze B2</span>
      </footer>
    </div>
  );
}
