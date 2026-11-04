import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Método não permitido." }, 405);
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

  const document = typeof body.document === "string"
    ? body.document.replace(/\D/g, "")
    : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (document.length !== 14 || password.length < 1 || password.length > 256) {
    return json({ error: "CNPJ ou senha inválidos." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("merchant-cnpj-login is missing Supabase configuration.");
    return json({ error: "Login temporariamente indisponível." }, 503);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data: merchant, error: lookupError } = await admin
      .from("merchant_login_identifiers")
      .select("email")
      .eq("document", document)
      .maybeSingle();
    if (lookupError) throw lookupError;

    const email = typeof merchant?.email === "string"
      ? merchant.email.trim().toLowerCase()
      : "";
    if (!email) return json({ error: "CNPJ ou senha inválidos." }, 401);

    const { data, error } = await authClient.auth.signInWithPassword({
      email,
      password,
    });
    if (error || !data.session) {
      return json({ error: "CNPJ ou senha inválidos." }, 401);
    }

    return json({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    });
  } catch (error) {
    console.error("merchant-cnpj-login failed:", error);
    return json({ error: "Login temporariamente indisponível." }, 503);
  }
});
