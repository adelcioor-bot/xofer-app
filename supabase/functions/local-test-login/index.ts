import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

import { isLocalDevelopmentUrl } from "../_shared/local_payment_mock.ts";

const LOCAL_TEST_OTP = "123456";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

function digits(phone: string): string {
  return phone.replace(/\D/g, "");
}

function localEmail(phoneDigits: string): string {
  return `local-${phoneDigits}@local.xofer.test`;
}

async function findUserByPhone(
  admin: SupabaseClient,
  phoneDigits: string,
): Promise<User | null> {
  for (let page = 1; page <= 10; page++) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 200,
    });
    if (error) throw error;
    const found = data.users.find((user) => digits(user.phone ?? "") === phoneDigits);
    if (found) return found;
    if (data.users.length < 200) return null;
  }
  return null;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Método não permitido." }, 405);
  }
  if (!isLocalDevelopmentUrl(Deno.env.get("SUPABASE_URL"))) {
    return json({ error: "Login de teste disponível apenas no localhost." }, 403);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Auth local não está configurado." }, 503);
  }

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = await request.json();
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return json({ error: "Corpo JSON inválido." }, 400);
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return json({ error: "Corpo JSON inválido." }, 400);
  }

  const phone = typeof body.phone === "string" ? body.phone.trim() : "";
  const code = typeof body.code === "string" ? body.code.trim() : "";
  const phoneDigits = digits(phone);
  if (phoneDigits.length < 10 || code !== LOCAL_TEST_OTP) {
    return json({ error: "Código inválido." }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const e164 = `+${phoneDigits}`;

  try {
    const existing = await findUserByPhone(admin, phoneDigits);
    const currentEmail = existing?.email?.trim() ?? "";
    const email = currentEmail.includes("@")
      ? currentEmail
      : localEmail(phoneDigits);
    if (existing) {
      const { error } = await admin.auth.admin.updateUserById(existing.id, {
        email,
        email_confirm: true,
        phone: e164,
        phone_confirm: true,
      });
      if (error) throw error;
    } else {
      const { error } = await admin.auth.admin.createUser({
        email,
        phone: e164,
        email_confirm: true,
        phone_confirm: true,
      });
      if (error) throw error;
    }

    const { data: link, error: linkError } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkError) throw linkError;
    const tokenHash = link?.properties?.hashed_token;
    if (!tokenHash) {
      return json({ error: "Não foi possível abrir a sessão de teste." }, 502);
    }
    return json({ token_hash: tokenHash, email });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha no login de teste.";
    console.error("local-test-login failed:", error);
    return json({ error: message }, 500);
  }
});
