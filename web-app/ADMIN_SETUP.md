# Administrator sign-in setup

## 1. Deploy the authentication update

Use Node.js **24.x** on Vercel. Local development now requires Node.js **22.13+** or **24+**, because the Supabase SDK requires Node.js 22 or later. The repository's `.nvmrc` selects Node.js 24.

Set these variables in the Vercel project's production environment:

```env
APP_URL=https://mynotes.gnyanarushi.tech
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
ADMIN_EMAIL=YOUR_ADMIN_EMAIL
```

Use the same Supabase project and admin email as your local configuration. `APP_URL` must match the exact origin you use in the browser, including the port for local development. Authentication mutations reject requests from other origins.

Redeploy the new code and open `/login`. The production `/admin` route now verifies the session on the server. The previous sample dashboard is at `/preview/admin`.

## 2. Configure Supabase email redirects

In **Authentication → URL Configuration** set:

**Site URL**

```text
https://mynotes.gnyanarushi.tech
```

**Redirect URLs**

```text
https://mynotes.gnyanarushi.tech/auth/callback
https://mynotes.gnyanarushi.tech/auth/callback?next=%2Freset-password
```

For local testing, also add:

```text
http://localhost:3000/auth/callback
http://localhost:3000/auth/callback?next=%2Freset-password
```

Keep the default invitation/recovery email templates using Supabase's confirmation URL. The app supports the standard email fragment flow, OAuth PKCE codes, and token-hash invitation/recovery links.

Confirm your Gmail custom SMTP settings are saved. The Gmail app password belongs in Supabase SMTP settings. The MyNotes account password is chosen by the admin through the email link.

Disable **Allow new users to sign up** for the invite-only application. Server-side admin access is independently restricted to the verified email configured in `ADMIN_EMAIL`.

## 3. Send the initial admin setup email

The local `web-app/.env.local` must contain the Supabase URL, publishable key, secret key, and `ADMIN_EMAIL`.

From the repository root, after deploying the authentication update:

```sh
APP_URL=https://mynotes.gnyanarushi.tech npm --prefix web-app run admin:invite
```

This command:

- Uses the Supabase administrative API to find the configured account.
- Sends an invitation if the account is new or its email is unconfirmed.
- Sends a password-reset email if the verified account already exists.
- Keeps existing account data and lets you choose your own password.
- Prints status messages without exposing credentials or email-link tokens.

To check configuration without sending email:

```sh
APP_URL=https://mynotes.gnyanarushi.tech npm --prefix web-app run admin:invite -- --check
```

If you have not switched your local Node.js to version 24 yet, run the script with a temporary Node.js 24 runtime from the `web-app/` directory:

```sh
APP_URL=https://mynotes.gnyanarushi.tech npm exec --yes --package=node@24 -- node scripts/invite-admin.mjs
```

## 4. Activate and sign in

1. Open the email sent to `ADMIN_EMAIL`.
2. Follow the link and choose a password on `/reset-password`.
3. Continue to the protected admin dashboard.
4. On later visits, use `/login` with the same email and password.

The dashboard includes account information, password changes, logout, and links to the notebook and user-management interface previews. General user invitation management and notebook persistence are subsequent milestones.

## Google sign-in

Google sign-in also works for the configured administrator once the Google provider is enabled in Supabase. Use the Supabase-provided callback in Google Cloud:

```text
https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
```

Supabase then returns to the application's `/auth/callback`. Google sign-in for another email does not grant administrator access. If Google is disabled, the login page explains that email/password should be used.

## Session and authorization behavior

- Session tokens stay in HTTP-only, SameSite=Lax cookies; HTTPS deployments use Secure cookies.
- Supabase `getUser()` verifies identity before each protected page/API operation.
- `ADMIN_EMAIL` is compared against the verified provider email, never editable profile roles or unverified cookie user data.
- The proxy refreshes sessions and forwards the updated cookies to server-rendered pages.
- Authentication responses are private and non-cacheable.
- Logout revokes the current device session when reachable and clears all local auth-cookie chunks.
- The app does not store an administrator password in environment variables.

## Focused verification

After a production build, `npm run test:auth` runs only authentication checks against a local test provider. It covers setup email callbacks, password changes, login/logout, rejected or forged identities, session refresh, Google PKCE, CSRF rejection, and expired links. It does not send real emails or use the live project's credentials.

The complete UI suite remains available through `npm run test:e2e` for broader checks when needed.
