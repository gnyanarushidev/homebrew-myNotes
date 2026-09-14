"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { Icon } from "@/components/ui/icon";
import { Button } from "@/components/ui/ui";
import { AuthFrame } from "./auth-frame";
import { accountDestination, authRequest } from "./auth-request";
import ui from "@/components/ui/ui.module.css";
import styles from "./auth-preview.module.css";

const content = {
  login: { eyebrow: "YOUR PERSONAL WORKSPACE", title: "Welcome back.", description: "Sign in with your administrator account to manage MyNotes.", submit: "Sign in", action: "login" },
  forgot: { eyebrow: "LET’S GET YOU BACK IN", title: "Forgot your password?", description: "Enter your administrator email to receive a password-reset link.", submit: "Send reset link", action: "recovery" },
  reset: { eyebrow: "A FRESH START", title: "Choose your password.", description: "Set a password for your verified account, then continue to the admin dashboard.", submit: "Save password", action: "password" },
};

export function AuthForm({ mode, initialError = "", verifiedEmail }: { mode: keyof typeof content; initialError?: string; verifiedEmail?: string }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState(initialError);
  const [busy, setBusy] = useState(false);
  const copy = content[mode];

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setError("");
    setMessage("");
    if (mode === "reset" && password !== confirmation) {
      setError("Your passwords don’t match. Please try again.");
      return;
    }
    setBusy(true);
    try {
      const result = await authRequest(copy.action, mode === "forgot" ? { email } : mode === "reset" ? { password } : { email, password });
      setPassword("");
      setConfirmation("");
      if (mode === "forgot") setMessage(result.message ?? "Check your inbox for the next step.");
      else window.location.replace(accountDestination(result.next));
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Unable to reach MyNotes. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <AuthFrame {...copy}>
      {verifiedEmail && <p className={ui.statusMessage}>Setting a password for {verifiedEmail}</p>}
      {mode === "login" && <>
        <Button variant="secondary" className={styles.fullWidth} disabled={busy} onClick={() => {
          setBusy(true);
          // OAuth starts through an HTTP redirect, not an App Router page transition.
          window.location.assign(new URL("/api/auth/google", window.location.origin).href);
        }}>
          <span className={styles.googleMark} aria-hidden="true">G</span>Continue with Google
        </Button>
        <div className={styles.divider}><span />or continue with email<span /></div>
      </>}
      <form className={styles.form} method="post" action={`/api/auth/${copy.action}`} onSubmit={submit} aria-label={`${copy.title} form`} aria-busy={busy}>
        {mode !== "reset" && <label className={ui.field} htmlFor="email">Email address
          <input id="email" name="email" type="email" autoComplete="email" required maxLength={254} disabled={busy} className={ui.input} placeholder="you@example.com" value={email} onChange={event => setEmail(event.target.value)} />
        </label>}
        {mode !== "forgot" && <div className={ui.field}>
          <label htmlFor="password">Password</label>
          <div className={styles.passwordField}>
            <input id="password" name="password" type={showPassword ? "text" : "password"} autoComplete={mode === "login" ? "current-password" : "new-password"} required minLength={mode === "reset" ? 8 : 1} maxLength={mode === "reset" ? 128 : 1024} disabled={busy} className={ui.input} placeholder={mode === "login" ? "Enter your password" : "At least 8 characters"} value={password} onChange={event => setPassword(event.target.value)} />
            <button type="button" aria-label={showPassword ? "Hide password" : "Show password"} aria-pressed={showPassword} onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Hide" : "Show"}</button>
          </div>
        </div>}
        {mode === "reset" && <label className={ui.field} htmlFor="confirmation">Confirm password
          <input id="confirmation" name="confirmation" type={showPassword ? "text" : "password"} autoComplete="new-password" required minLength={8} maxLength={128} disabled={busy} className={ui.input} value={confirmation} onChange={event => setConfirmation(event.target.value)} placeholder="Enter your password again" aria-invalid={Boolean(error)} aria-describedby={error ? "form-error" : undefined} />
        </label>}
        {mode === "login" && <Link href="/forgot-password" className={styles.forgot}>Forgot password?</Link>}
        {error && <p id="form-error" role="alert" className={ui.errorMessage}>{error}</p>}
        <Button type="submit" disabled={busy} className={styles.fullWidth}>{busy ? "Please wait…" : copy.submit}<Icon name="arrow" /></Button>
      </form>
      {message && <p role="status" className={`${ui.statusMessage} ${styles.message}`}>{message}</p>}
      <div className={styles.bottomLinks}>
        {mode !== "login" && <Link href="/login">Back to sign in</Link>}
        {mode === "login" && <p>First time here? Open your admin setup email to choose a password.</p>}
        <Link href="/notebooks">Explore the sample notebook interface</Link>
      </div>
    </AuthFrame>
  );
}
