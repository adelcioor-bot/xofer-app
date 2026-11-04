import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing required Supabase function environment variables.");
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const MAX_RUNTIME_MS = 50_000;
const CYCLE_INTERVAL_MS = 3_000;
const EXPIRATION_BATCH_SIZE = 100;

function isAuthorized(request: Request): boolean {
  return request.headers.get("authorization") ===
    `Bearer ${serviceRoleKey}`;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed." }, { status: 405 });
  }
  if (!isAuthorized(request)) {
    return Response.json({ error: "Unauthorized." }, { status: 401 });
  }

  const startedAt = Date.now();
  const deadline = startedAt + MAX_RUNTIME_MS;
  let cycles = 0;
  let expiredAttempts = 0;
  let processedDispatches = 0;
  let workerErrors = 0;

  while (Date.now() < deadline) {
    const cycleStartedAt = Date.now();
    cycles += 1;

    try {
      const { data, error } = await supabase.rpc(
        "rpc_expire_stale_attempts",
        { p_batch_size: EXPIRATION_BATCH_SIZE },
      );
      if (error) throw error;
      if (typeof data !== "number" || !Number.isInteger(data) || data < 0) {
        throw new Error("Expiration RPC returned an invalid result.");
      }
      expiredAttempts += data;
    } catch (error) {
      workerErrors += 1;
      console.error(
        "[dispatch-worker] Failed to expire stale attempts:",
        errorMessage(error),
      );
    }

    while (Date.now() < deadline) {
      try {
        const { data, error } = await supabase.rpc(
          "rpc_process_next_dispatch_attempt",
        );
        if (error) throw error;
        if (data === null) break;
        if (typeof data !== "object" || Array.isArray(data)) {
          throw new Error("Dispatch RPC returned an invalid result.");
        }
        processedDispatches += 1;
      } catch (error) {
        workerErrors += 1;
        console.error(
          "[dispatch-worker] Failed to process the next dispatch:",
          errorMessage(error),
        );
        break;
      }
    }

    const waitMs = CYCLE_INTERVAL_MS - (Date.now() - cycleStartedAt);
    if (waitMs > 0) {
      await sleep(Math.min(waitMs, Math.max(0, deadline - Date.now())));
    }
  }

  return Response.json({
    cycles,
    expired_attempts: expiredAttempts,
    processed_dispatches: processedDispatches,
    errors: workerErrors,
    duration_ms: Date.now() - startedAt,
  });
});
