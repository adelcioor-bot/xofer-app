const LOOPBACK_HOSTNAMES = new Set(["localhost", "127.0.0.1", "[::1]", "::1"]);

function localUrlHostname(value: string | null | undefined): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return url.hostname.toLowerCase();
  } catch {
    return null;
  }
}

function isLoopbackOrigin(value: string | null): boolean {
  const hostname = localUrlHostname(value);
  return hostname !== null && LOOPBACK_HOSTNAMES.has(hostname);
}

export function isLocalDevelopmentUrl(value: string | undefined): boolean {
  if (!value) return false;
  const hostname = localUrlHostname(value);
  if (hostname === null) return false;
  if (LOOPBACK_HOSTNAMES.has(hostname)) return true;
  if (hostname !== "kong") return false;
  return new URL(value).protocol === "http:";
}

function isLocalPaymentMockEnabled(
  enabled: string | undefined,
  supabaseUrl: string | undefined,
  origin: string | null,
): boolean {
  return enabled === "true" && isLocalDevelopmentUrl(supabaseUrl) &&
    isLoopbackOrigin(origin);
}

export function isLocalPaymentMockRequest(request: Request): boolean {
  return isLocalPaymentMockEnabled(
    Deno.env.get("MERCADOPAGO_LOCAL_MOCK"),
    Deno.env.get("SUPABASE_URL"),
    request.headers.get("origin"),
  );
}

export function isLocalMockCardToken(token: string): boolean {
  return /^tok_test_local_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(token);
}
