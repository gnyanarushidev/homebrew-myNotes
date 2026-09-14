import { NextRequest } from "next/server";
import { apiFailure, apiJson, authorized } from "@/server/http";
import { isVerifiedAdmin } from "@/server/auth/client";
export async function GET(request: NextRequest) {
  try { const auth = await authorized(request); return auth.finish(apiJson({ id: auth.user.id, email: auth.user.email, isAdmin: isVerifiedAdmin(auth.user, auth.settings) })); }
  catch (error) { return apiFailure(error, request); }
}
