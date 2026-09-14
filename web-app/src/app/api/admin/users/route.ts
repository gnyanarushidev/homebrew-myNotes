import { NextRequest } from "next/server";
import { z } from "zod";
import { authorized, apiJson, apiFailure, HttpError, readJson } from "@/server/http";
import { accountSummary, listAccounts, serviceClient } from "@/server/service";
import { callbackUrl } from "@/server/auth/settings";
import { createEmailAuth } from "@/server/auth/client";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const auth = await authorized(request, true);
    return auth.finish(apiJson((await listAccounts()).map(accountSummary)));
  } catch (error) { return apiFailure(error); }
}

export async function POST(request: NextRequest) {
  try {
    const auth = await authorized(request, true);
    const parsed = z.object({ email: z.string().trim().toLowerCase().pipe(z.email().max(254)), action: z.enum(["invite", "resend", "revoke"]).default("invite") }).safeParse(await readJson(request, 4096));
    if (!parsed.success) throw new HttpError(400, "Enter a valid email address.");
    const email = parsed.data.email.trim().toLowerCase();
    if (email === auth.settings.adminEmail) throw new HttpError(400, "Manage your own account from the password settings.");
    const service = serviceClient();
    let user = (await listAccounts()).find(user => user.email?.toLowerCase() === email);
    if (parsed.data.action === "revoke") {
      if (!user) throw new HttpError(404, "User not found.");
      const { error } = await service.auth.admin.updateUserById(user.id, { app_metadata: { ...user.app_metadata, mynotes_access: "revoked" } });
      if (error) throw new HttpError(503, "Unable to revoke access. Please retry.");
      return auth.finish(apiJson({ message: "Access revoked. Notebook data has been retained." }));
    }
    if (parsed.data.action === "invite" && user?.app_metadata?.mynotes_access === "active") throw new HttpError(409, "This account already has access or a pending invitation. Use Send setup link or Invite / resend.");
    if (parsed.data.action === "resend" && !user) throw new HttpError(404, "User not found.");
    if (!user) {
      const { data, error } = await service.auth.admin.inviteUserByEmail(email, { redirectTo: callbackUrl(auth.settings, true) });
      if (error || !data.user) throw new HttpError(503, "The invitation could not be sent. Check SMTP settings and email rate limits.");
      user = data.user;
      const { error: grantError } = await service.auth.admin.updateUserById(user.id, { app_metadata: { ...user.app_metadata, mynotes_access: "active" } });
      if (grantError) throw new HttpError(503, "The account was created, but access could not be granted. Use Invite again to finish setup.");
    } else {
      const { error } = await service.auth.admin.updateUserById(user.id, { app_metadata: { ...user.app_metadata, mynotes_access: "active" } });
      if (error) throw new HttpError(503, "Unable to grant access.");
      const { error: mailError } = user.email_confirmed_at
        ? await createEmailAuth(auth.settings).auth.resetPasswordForEmail(email, { redirectTo: callbackUrl(auth.settings, true) })
        : await service.auth.admin.inviteUserByEmail(email, { redirectTo: callbackUrl(auth.settings, true) });
      if (mailError) throw new HttpError(503, "Access was granted, but the setup email failed. Use Invite again to resend it.");
    }
    return auth.finish(apiJson({ message: "Invitation sent. The user can verify their email and set a password or use Google with the same address." }));
  } catch (error) { return apiFailure(error); }
}
