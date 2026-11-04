import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing required Supabase function environment variables.");
}

export const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

export function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

export async function requireUser(request: Request) {
  const authorization = request.headers.get("authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new HttpError(401, "Sessão autenticada obrigatória.");

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user || data.user.is_anonymous) {
    throw new HttpError(401, "Sessão inválida ou expirada.");
  }
  return data.user;
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
  ) {
    super(message);
  }
}

export async function readJson(
  request: Request,
): Promise<Record<string, unknown>> {
  try {
    const body: unknown = await request.json();
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new Error("JSON object expected.");
    }
    return body as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "Corpo JSON inválido.");
  }
}

export function requiredText(
  body: Record<string, unknown>,
  key: string,
  maxLength = 500,
): string {
  const value = body[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, `Campo obrigatório: ${key}.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw new HttpError(400, `Campo inválido: ${key}.`);
  }
  return trimmed;
}

export function numberField(
  body: Record<string, unknown>,
  key: string,
): number {
  const value = body[key];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpError(400, `Coordenada inválida: ${key}.`);
  }
  return value;
}

export function mercadopagoToken(): string {
  const token = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN");
  if (!token) throw new HttpError(503, "Mercado Pago não está configurado.");
  return token;
}

export async function mpRequest<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${mercadopagoToken()}`);
  headers.set("Content-Type", "application/json");
  const response = await fetch(`https://api.mercadopago.com${path}`, {
    ...init,
    headers,
  });
  const responseBody: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const message = typeof responseBody === "object" &&
        responseBody !== null &&
        "message" in responseBody &&
        typeof responseBody.message === "string"
      ? responseBody.message
      : `Mercado Pago respondeu com HTTP ${response.status}.`;
    throw new HttpError(502, message, "mercadopago_error");
  }
  return responseBody as T;
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse(
      { error: error.message, code: error.code },
      error.status,
    );
  }
  console.error("Merchant payment function failed:", error);
  return jsonResponse(
    { error: "Não foi possível concluir a operação de pagamento." },
    500,
  );
}
