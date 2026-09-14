"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { Icon } from "@/components/ui/icon";
import { ActionLink, Brand, Button, PreviewNotice } from "@/components/ui/ui";
import ui from "@/components/ui/ui.module.css";
import styles from "./auth-preview.module.css";

type AuthMode = "login" | "invite" | "forgot" | "reset" | "callback";

const content: Record<AuthMode, { eyebrow: string; title: string; description: string; submit: string }> = {
  login: { eyebrow: "YOUR PERSONAL WORKSPACE", title: "Welcome back.", description: "A familiar space for your thoughts. Sign in to pick up where you left off.", submit: "Sign in" },
  invite: { eyebrow: "A PLACE IN THE CIRCLE", title: "Make yourself at home.", description: "The invitation experience starts here. Set a password, or use Google with your invited email address.", submit: "Set up my account" },
  forgot: { eyebrow: "LET’S GET YOU BACK IN", title: "Forgot your password?", description: "Enter your account email and we’ll help you get back to your notebooks.", submit: "Send reset link" },
  reset: { eyebrow: "A FRESH START", title: "Choose a new password.", description: "Set a new password for your account and get back to your next idea.", submit: "Update password" },
  callback: { eyebrow: "AUTHENTICATION PREVIEW", title: "Your return to MyNotes.", description: "This is the future sign-in callback page. Authentication will be connected in the next development step.", submit: "" },
};

export function AuthPreview({ mode }: { mode: AuthMode }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const copy = content[mode];
  const hasEmail = mode !== "reset";
  const hasPassword = mode !== "forgot";
  const hasConfirmation = mode === "invite" || mode === "reset";

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");
    if (hasConfirmation && password !== confirmation) {
      setError("Your passwords don’t match. Please try again.");
      return;
    }
    setError("");
    setMessage(mode === "forgot"
      ? "Preview only — no reset email was sent. Email delivery will be connected with authentication."
      : "Preview only — your details were not submitted or saved. Explore the sample workspace below.");
    setPassword("");
    setConfirmation("");
  }

  return (
    <div className={styles.layout}>
      <aside className={styles.story}>
        <Brand />
        <div className={styles.storyContent}><span className={styles.storyNumber}>A NOTE TO YOURSELF</span><h2>Leave a little room<br />for <em>what’s next.</em></h2><p>A sketch. A thought. A plan that’s still taking shape. Give your ideas somewhere to belong.</p><div className={styles.sketch} aria-hidden="true"><span /><span /><span /></div></div>
        <span className={styles.storyFooter}>Your ideas, at your own pace.</span>
      </aside>
      <main id="main-content" className={styles.main}>
        <div className={styles.topbar}><Link href="/"><Icon name="back" /> Back to home</Link><span>WEB PREVIEW</span></div>
        <div className={styles.card}>
          <div className={styles.cardIcon}><Icon name={mode === "invite" ? "mail" : "lock"} /></div>
          <p className={ui.eyebrow}>{copy.eyebrow}</p>
          <h1>{copy.title}</h1>
          <p className={styles.description}>{copy.description}</p>
          <PreviewNotice>{mode === "callback" ? "This page does not process sign-in tokens yet." : "Forms are for layout review. Authentication is not connected."}</PreviewNotice>

          {mode !== "callback" && (
            <>
              {(mode === "login" || mode === "invite") && <><Button variant="secondary" className={styles.fullWidth} onClick={() => { setError(""); setMessage("Google sign-in will be available after the Supabase OAuth integration. No sign-in was attempted."); }}><span className={styles.googleMark} aria-hidden="true">G</span>Continue with Google</Button><div className={styles.divider}><span />or continue with email<span /></div></>}
              <form className={styles.form} onSubmit={submit} aria-label={`${copy.title} form`}>
                {hasEmail && <label className={ui.field} htmlFor="email">{mode === "invite" ? "Invited email address" : "Email address"}<input id="email" type="email" autoComplete="email" required className={ui.input} placeholder="you@example.com" value={email} onChange={event => setEmail(event.target.value)} /></label>}
                {hasPassword && (
                  <div className={ui.field}>
                    <label htmlFor="password">Password</label>
                    <div className={styles.passwordField}>
                      <input
                        id="password"
                        type={showPassword ? "text" : "password"}
                        autoComplete={mode === "login" ? "current-password" : "new-password"}
                        required
                        minLength={mode === "login" ? 1 : 8}
                        className={ui.input}
                        placeholder={mode === "login" ? "Enter your password" : "At least 8 characters"}
                        value={password}
                        onChange={event => setPassword(event.target.value)}
                      />
                      <button
                        type="button"
                        aria-label={showPassword ? "Hide password" : "Show password"}
                        aria-pressed={showPassword}
                        onClick={() => setShowPassword(!showPassword)}
                      >
                        {showPassword ? "Hide" : "Show"}
                      </button>
                    </div>
                  </div>
                )}
                {hasConfirmation && <label className={ui.field} htmlFor="confirmation">Confirm password<input id="confirmation" type={showPassword ? "text" : "password"} autoComplete="new-password" required minLength={8} className={ui.input} value={confirmation} onChange={event => setConfirmation(event.target.value)} placeholder="Enter your password again" aria-invalid={Boolean(error)} aria-describedby={error ? "form-error" : undefined} /></label>}
                {mode === "login" && <Link href="/forgot-password" className={styles.forgot}>Forgot password?</Link>}
                {error && <p id="form-error" role="alert" className={ui.errorMessage}>{error}</p>}
                <Button type="submit" className={styles.fullWidth}>{copy.submit}<Icon name="arrow" /></Button>
              </form>
            </>
          )}
          {message && <p role="status" className={`${ui.statusMessage} ${styles.message}`}>{message}</p>}
          <div className={styles.bottomLinks}>
            <ActionLink href="/notebooks" variant="ghost">Explore the sample workspace <Icon name="arrow" /></ActionLink>
            {mode !== "login" && <Link href="/login">Back to sign in</Link>}
            {mode === "login" && <p>MyNotes is invitation-only. <Link href="/invite">Preview an invitation</Link></p>}
          </div>
        </div>
        <footer className={styles.footer}>A home for your notes. Built one page at a time.</footer>
      </main>
    </div>
  );
}
