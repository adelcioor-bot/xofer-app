import { createClient } from "npm:@supabase/supabase-js@2";
import {
  admin,
  corsHeaders,
  errorResponse,
  HttpError,
  jsonResponse,
  mpRequest,
  numberField,
  readJson,
  requiredText,
  requireUser,
} from "../_shared/merchant_payments.ts";
import {
  isLocalMockCardToken,
  isLocalPaymentMockRequest,
} from "../_shared/local_payment_mock.ts";

type MpPayment = {
  id: number | string;
  status: string;
  transaction_amount: number;
};

type RidePayment = {
  id: string;
  status: string;
  amount_cents: number;
  wallet_debit_cents: number;
  card_charge_cents: number;
  provider_payment_id: string | null;
  ride_id: string | null;
  metadata: Record<string, unknown>;
};

type Quote = {
  quote_id: string;
  amount_cents: number;
  expires_at: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requestScopedClient(request: Request) {
  const authorization = request.headers.get("authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!token || !supabaseUrl || !anonKey) {
    throw new HttpError(503, "Não foi possível validar a sessão da cotação.");
  }
  return createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

async function getCreatedRide(rideId: string) {
  const { data, error } = await admin
    .from("corridas")
    .select("*")
    .eq("id", rideId)
    .single();
  if (error) throw error;
  return data;
}

async function refundPayment(paymentId: string): Promise<void> {
  await mpRequest(`/v1/payments/${encodeURIComponent(paymentId)}/refunds`, {
    method: "POST",
    headers: { "X-Idempotency-Key": `customer-ride-refund-${paymentId}` },
    body: JSON.stringify({}),
  });
}

async function generateQuote(
  request: Request,
  userId: string,
  originLat: number,
  originLng: number,
  destinationLat: number,
  destinationLng: number,
): Promise<Quote> {
  const { data, error } = await requestScopedClient(request).rpc(
    "rpc_generate_ride_quote",
    {
      p_requester_id: userId,
      p_requester_type: "customer",
      p_origin_lat: originLat,
      p_origin_lng: originLng,
      p_dest_lat: destinationLat,
      p_dest_lng: destinationLng,
    },
  );
  if (error) throw error;
  const quote = Array.isArray(data) ? data[0] : null;
  if (
    !isRecord(quote) || typeof quote.quote_id !== "string" ||
    typeof quote.amount_cents !== "number" ||
    !Number.isSafeInteger(quote.amount_cents) ||
    typeof quote.expires_at !== "string"
  ) {
    throw new HttpError(502, "A cotação retornou dados inválidos.");
  }
  return quote as Quote;
}

async function getQuoteForPayment(
  quoteId: string,
  userId: string,
  amountCents: number,
  requireUnexpired: boolean,
) {
  const { data, error } = await admin
    .from("ride_quotes")
    .select(
      "id, requester_id, requester_type, amount_cents, status, expires_at, pricing_snapshot, ride_id",
    )
    .eq("id", quoteId)
    .maybeSingle();
  if (error) throw error;
  if (
    !data || data.requester_id !== userId ||
    data.requester_type !== "customer" ||
    Number(data.amount_cents) !== amountCents ||
    !isRecord(data.pricing_snapshot)
  ) {
    throw new HttpError(409, "A cotação não corresponde ao pagamento.");
  }
  if (requireUnexpired && new Date(data.expires_at).getTime() <= Date.now()) {
    throw new HttpError(409, "A cotação expirou. Solicite uma nova corrida.");
  }
  const radius = data.pricing_snapshot.provider_search_radius_meters;
  if (
    typeof radius !== "number" || !Number.isSafeInteger(radius) || radius <= 0
  ) {
    throw new HttpError(
      500,
      "A cotação não contém um raio de despacho válido.",
    );
  }
  return { quote: data, searchRadiusMeters: Number(radius) };
}

async function ensureRideDispatch(
  rideId: string,
  quoteId: string,
  userId: string,
  amountCents: number,
) {
  const { quote, searchRadiusMeters } = await getQuoteForPayment(
    quoteId,
    userId,
    amountCents,
    false,
  );
  if (quote.ride_id !== null && quote.ride_id !== rideId) {
    throw new HttpError(409, "A cotação já está associada a outra corrida.");
  }
  if (quote.status !== "pending" && quote.status !== "used") {
    throw new HttpError(409, "A cotação não pode ser associada à corrida.");
  }
  if (quote.ride_id === null) {
    const { error: quoteUpdateError } = await admin
      .from("ride_quotes")
      .update({
        ride_id: rideId,
        status: "used",
        updated_at: new Date().toISOString(),
      })
      .eq("id", quoteId)
      .eq("requester_id", userId)
      .is("ride_id", null);
    if (quoteUpdateError) throw quoteUpdateError;

    const { data: associatedQuote, error: associatedQuoteError } = await admin
      .from("ride_quotes")
      .select("ride_id")
      .eq("id", quoteId)
      .single();
    if (associatedQuoteError) throw associatedQuoteError;
    if (associatedQuote.ride_id !== rideId) {
      throw new HttpError(409, "A cotação foi associada a outra corrida.");
    }
  }

  const { error: dispatchError } = await admin
    .from("mission_dispatches")
    .upsert(
      {
        ride_id: rideId,
        provider_role: "driver",
        status: "pending",
        search_radius_meters: searchRadiusMeters,
      },
      { onConflict: "ride_id,provider_role", ignoreDuplicates: true },
    );
  if (dispatchError) throw dispatchError;
}

async function getExistingPayment(
  userId: string,
  idempotencyKey: string,
): Promise<RidePayment | null> {
  const { data, error } = await admin
    .from("customer_wallet_transactions")
    .select(
      "id, status, amount_cents, wallet_debit_cents, card_charge_cents, provider_payment_id, ride_id, metadata",
    )
    .eq("user_id", userId)
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return data as RidePayment;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Método não permitido." }, 405);
  }

  let transactionId: string | null = null;
  let capturedPaymentId: string | null = null;
  let paymentApproved = false;
  let rideFinalized = false;
  let quoteId: string | null = null;
  let paymentReservationUncertain = false;
  try {
    const user = await requireUser(request);
    const body = await readJson(request);
    const origin = requiredText(body, "origin", 500);
    const destination = requiredText(body, "destination", 500);
    const callId = requiredText(body, "call_id", 100);
    const idempotencyKey = requiredText(body, "idempotency_key", 100);
    const originLat = numberField(body, "origin_lat");
    const originLng = numberField(body, "origin_lng");
    const destinationLat = numberField(body, "destination_lat");
    const destinationLng = numberField(body, "destination_lng");
    if (
      originLat < -90 || originLat > 90 || destinationLat < -90 ||
      destinationLat > 90 || originLng < -180 || originLng > 180 ||
      destinationLng < -180 || destinationLng > 180
    ) {
      throw new HttpError(400, "Coordenadas da corrida fora do intervalo.");
    }
    const cardId = body.card_id == null
      ? null
      : requiredText(body, "card_id", 64);
    const cardToken = body.card_token == null
      ? null
      : requiredText(body, "card_token", 2048);
    const paymentMethodId = body.payment_method_id == null
      ? null
      : requiredText(body, "payment_method_id", 100);
    const identificationType = body.identification_type == null
      ? null
      : requiredText(body, "identification_type", 10);
    const identificationNumber = body.identification_number == null
      ? null
      : requiredText(body, "identification_number", 20);
    const billingEmail = body.billing_email == null
      ? null
      : requiredText(body, "billing_email", 254).toLowerCase();
    const hasOneTimeCard = cardToken !== null;
    if (
      (cardId !== null && hasOneTimeCard) ||
      (hasOneTimeCard &&
        (!paymentMethodId || !identificationType ||
          !identificationNumber || !billingEmail ||
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(billingEmail)))
    ) {
      throw new HttpError(400, "Confira os dados do cartão informado.");
    }

    let payment = await getExistingPayment(user.id, idempotencyKey);
    let amountCents: number;
    if (payment) {
      transactionId = payment.id;
      amountCents = Number(payment.amount_cents);
      if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
        throw new HttpError(500, "O pagamento contém um valor inválido.");
      }
      quoteId = typeof payment.metadata?.quote_id === "string"
        ? payment.metadata.quote_id
        : null;
      if (!quoteId) {
        throw new HttpError(
          409,
          "O pagamento existente não está associado a uma cotação.",
        );
      }
      if (payment.status === "approved" && payment.ride_id) {
        rideFinalized = true;
        await ensureRideDispatch(
          payment.ride_id,
          quoteId,
          user.id,
          amountCents,
        );
        return jsonResponse({ ride: await getCreatedRide(payment.ride_id) });
      }
      if (payment.status !== "pending") {
        throw new HttpError(
          409,
          "A solicitação de pagamento já foi encerrada.",
        );
      }
    } else {
      const quote = await generateQuote(
        request,
        user.id,
        originLat,
        originLng,
        destinationLat,
        destinationLng,
      );
      quoteId = quote.quote_id;
      amountCents = quote.amount_cents;
      await getQuoteForPayment(quoteId, user.id, amountCents, true);
    }

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("full_name, phone")
      .eq("id", user.id)
      .maybeSingle();
    if (profileError) throw profileError;

    const rideData = {
      call_id: callId,
      origin,
      destination,
      origin_lat: originLat,
      origin_lng: originLng,
      dest_lat: destinationLat,
      dest_lng: destinationLng,
      customer_name: profile?.full_name ?? "",
      customer_phone: profile?.phone ?? user.phone ?? "",
      quote_id: quoteId,
    };

    if (!payment) {
      paymentReservationUncertain = true;
      const { data: beginPayment, error: beginError } = await admin.rpc(
        "customer_begin_ride_payment",
        {
          p_user_id: user.id,
          p_idempotency_key: idempotencyKey,
          p_amount_cents: amountCents,
          p_card_id: cardId,
          p_has_card: cardId !== null || hasOneTimeCard,
          p_ride_data: rideData,
        },
      );
      if (beginError) {
        payment = await getExistingPayment(user.id, idempotencyKey);
        if (!payment) {
          paymentReservationUncertain = false;
          if (quoteId) {
            const { error: cancelQuoteError } = await admin
              .from("ride_quotes")
              .update({
                status: "cancelled",
                updated_at: new Date().toISOString(),
              })
              .eq("id", quoteId)
              .eq("requester_id", user.id)
              .is("ride_id", null);
            if (cancelQuoteError) {
              console.error(
                "Could not cancel unused quote:",
                cancelQuoteError,
              );
            }
          }
          if (beginError.message.includes("payment method required")) {
            return jsonResponse(
              {
                error:
                  "Adicione créditos ou selecione um cartão para solicitar a corrida.",
                code: "payment_method_required",
                amount_cents: amountCents,
              },
              402,
            );
          }
          throw beginError;
        }
        transactionId = payment.id;
        paymentReservationUncertain = false;
      } else {
        if (
          typeof beginPayment !== "object" || beginPayment === null ||
          typeof beginPayment.id !== "string"
        ) {
          throw new HttpError(
            502,
            "Não foi possível reservar o pagamento da corrida.",
          );
        }
        transactionId = beginPayment.id;
        paymentReservationUncertain = false;
        const { data: storedPayment, error: storedPaymentError } = await admin
          .from("customer_wallet_transactions")
          .select(
            "id, status, amount_cents, wallet_debit_cents, card_charge_cents, provider_payment_id, ride_id, metadata",
          )
          .eq("id", transactionId)
          .eq("user_id", user.id)
          .single();
        if (storedPaymentError) throw storedPaymentError;
        payment = storedPayment as RidePayment;
      }
      if (
        typeof payment.metadata?.quote_id === "string" &&
        payment.metadata.quote_id !== quoteId
      ) {
        const unclaimedQuoteId = quoteId;
        quoteId = payment.metadata.quote_id;
        const { error: cancelQuoteError } = await admin
          .from("ride_quotes")
          .update({ status: "cancelled", updated_at: new Date().toISOString() })
          .eq("id", unclaimedQuoteId)
          .eq("requester_id", user.id)
          .is("ride_id", null);
        if (cancelQuoteError) throw cancelQuoteError;
      }
      amountCents = Number(payment.amount_cents);
      if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
        throw new HttpError(500, "O pagamento contém um valor inválido.");
      }
      if (payment.status === "approved" && payment.ride_id) {
        rideFinalized = true;
        if (!quoteId) {
          throw new HttpError(409, "O pagamento aprovado não possui cotação.");
        }
        await ensureRideDispatch(
          payment.ride_id,
          quoteId,
          user.id,
          amountCents,
        );
        return jsonResponse({ ride: await getCreatedRide(payment.ride_id) });
      }
    }

    if (!payment || !transactionId || !quoteId) {
      throw new HttpError(
        502,
        "Não foi possível recuperar o pagamento da corrida.",
      );
    }
    if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
      throw new HttpError(500, "O pagamento contém um valor inválido.");
    }
    if (payment.status !== "pending") {
      throw new HttpError(409, "A solicitação de pagamento já foi encerrada.");
    }

    const cardChargeCents = Number(payment.card_charge_cents);
    if (cardChargeCents > 0) {
      let mpPayment: MpPayment;
      let card: { provider_card_id: string; payment_method_id: string } | null =
        null;
      let account: {
        mercadopago_customer_id: string | null;
        billing_email: string | null;
      } | null = null;
      if (cardId) {
        const { data: savedCard, error: cardError } = await admin
          .from("customer_cards")
          .select("provider_card_id, payment_method_id")
          .eq("user_id", user.id)
          .eq("id", cardId)
          .single();
        if (cardError) {
          throw new HttpError(402, "Selecione um cartão válido.");
        }
        card = savedCard;
        const { data: walletAccount, error: accountError } = await admin
          .from("customer_wallet_accounts")
          .select("mercadopago_customer_id, billing_email")
          .eq("user_id", user.id)
          .single();
        if (accountError) throw accountError;
        account = walletAccount;
        if (!account.billing_email) {
          throw new HttpError(
            400,
            "Informe um e-mail para concluir o pagamento.",
          );
        }
        if (!account.mercadopago_customer_id) {
          throw new HttpError(402, "Cadastre novamente o cartão selecionado.");
        }
      } else if (!hasOneTimeCard) {
        throw new HttpError(402, "Selecione um cartão para continuar.");
      }

      const localOneTimeCard = hasOneTimeCard &&
        isLocalPaymentMockRequest(request) &&
        isLocalMockCardToken(cardToken!) && paymentMethodId === "visa";
      const localSavedCard = card !== null &&
        isLocalPaymentMockRequest(request) &&
        card.provider_card_id.startsWith("local-") &&
        card.payment_method_id === "visa";
      if (localOneTimeCard || localSavedCard) {
        mpPayment = {
          id: `local-${transactionId}`,
          status: "approved",
          transaction_amount: cardChargeCents / 100,
        };
      } else if (typeof payment.provider_payment_id === "string") {
        mpPayment = await mpRequest<MpPayment>(
          `/v1/payments/${encodeURIComponent(payment.provider_payment_id)}`,
        );
      } else if (card && account) {
        const cardTokenResponse = await mpRequest<{ id: string }>(
          "/v1/card_tokens",
          {
            method: "POST",
            headers: {
              "X-Idempotency-Key": `customer-ride-card-token-${transactionId}`,
            },
            body: JSON.stringify({
              customer_id: account.mercadopago_customer_id,
              card_id: card.provider_card_id,
            }),
          },
        );
        mpPayment = await mpRequest<MpPayment>("/v1/payments", {
          method: "POST",
          headers: { "X-Idempotency-Key": `customer-ride-${transactionId}` },
          body: JSON.stringify({
            transaction_amount: cardChargeCents / 100,
            token: cardTokenResponse.id,
            description: "Pagamento de corrida Xofer",
            payment_method_id: card.payment_method_id,
            installments: 1,
            payer: {
              id: account.mercadopago_customer_id,
              type: "customer",
              email: account.billing_email,
            },
            external_reference: transactionId,
            notification_url: `${
              Deno.env.get("SUPABASE_URL")
            }/functions/v1/mercadopago-webhook`,
          }),
        });
      } else {
        mpPayment = await mpRequest<MpPayment>("/v1/payments", {
          method: "POST",
          headers: { "X-Idempotency-Key": `customer-ride-${transactionId}` },
          body: JSON.stringify({
            transaction_amount: cardChargeCents / 100,
            token: cardToken,
            description: "Pagamento de corrida Xofer",
            payment_method_id: paymentMethodId,
            installments: 1,
            payer: {
              email: billingEmail,
              identification: {
                type: identificationType,
                number: identificationNumber,
              },
            },
            external_reference: transactionId,
            notification_url: `${
              Deno.env.get("SUPABASE_URL")
            }/functions/v1/mercadopago-webhook`,
          }),
        });
      }

      capturedPaymentId = String(mpPayment.id);
      paymentApproved = mpPayment.status === "approved";
      if (Math.round(mpPayment.transaction_amount * 100) !== cardChargeCents) {
        throw new HttpError(
          502,
          "O valor do cartão não corresponde à cobrança.",
        );
      }
      const { error: updateError } = await admin
        .from("customer_wallet_transactions")
        .update({
          provider_payment_id: capturedPaymentId,
          updated_at: new Date().toISOString(),
        })
        .eq("id", transactionId)
        .eq("status", "pending");
      if (updateError) throw updateError;

      if (mpPayment.status === "rejected" || mpPayment.status === "cancelled") {
        await admin.rpc("customer_fail_ride_payment", {
          p_transaction_id: transactionId,
        });
        throw new HttpError(402, "O cartão recusou o pagamento da corrida.");
      }
      if (mpPayment.status !== "approved") {
        return jsonResponse(
          {
            status: "payment_pending",
            transaction_id: transactionId,
            message: "Aguardando confirmação do pagamento do cartão.",
          },
          202,
        );
      }
    }

    const { data: rideId, error: finalizeError } = await admin.rpc(
      "customer_finalize_ride_payment",
      {
        p_transaction_id: transactionId,
        p_provider_payment_id: capturedPaymentId,
      },
    );
    if (finalizeError) throw finalizeError;
    if (typeof rideId !== "string") {
      throw new HttpError(502, "Não foi possível finalizar a corrida.");
    }
    rideFinalized = true;
    await ensureRideDispatch(rideId, quoteId, user.id, amountCents);
    return jsonResponse({ ride: await getCreatedRide(rideId) });
  } catch (error) {
    let paymentStateVerified = transactionId === null;
    if (transactionId && !rideFinalized) {
      const { data: paymentState, error: paymentStateError } = await admin
        .from("customer_wallet_transactions")
        .select("status, ride_id")
        .eq("id", transactionId)
        .maybeSingle();
      if (paymentStateError) {
        console.error(
          "Could not verify customer ride payment state:",
          transactionId,
          paymentStateError,
        );
      } else {
        paymentStateVerified = true;
        if (paymentState?.status === "approved") {
          if (paymentState.ride_id) {
            rideFinalized = true;
          } else {
            paymentStateVerified = false;
          }
        }
      }
    }
    if (
      quoteId && !rideFinalized && paymentStateVerified &&
      !paymentReservationUncertain
    ) {
      const { error: quoteCancelError } = await admin
        .from("ride_quotes")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("id", quoteId)
        .is("ride_id", null)
        .eq("status", "pending");
      if (quoteCancelError) {
        console.error("Could not cancel unused ride quote:", quoteCancelError);
      }
    }
    if (
      transactionId && !rideFinalized && paymentStateVerified &&
      !paymentReservationUncertain
    ) {
      if (
        paymentApproved && capturedPaymentId &&
        !capturedPaymentId.startsWith("local-")
      ) {
        try {
          await refundPayment(capturedPaymentId);
        } catch (refundError) {
          console.error(
            "Customer ride payment requires manual refund:",
            transactionId,
            capturedPaymentId,
            refundError,
          );
        }
      }
      const { error: releaseError } = await admin.rpc(
        "customer_fail_ride_payment",
        { p_transaction_id: transactionId },
      );
      if (releaseError) {
        console.error(
          "Could not release customer ride reservation:",
          releaseError,
        );
      }
    }
    return errorResponse(error);
  }
});
