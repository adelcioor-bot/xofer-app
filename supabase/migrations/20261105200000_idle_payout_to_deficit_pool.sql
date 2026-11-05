-- A bolsa de espera paga o motorista, mas não reduz a margem desta corrida.
-- O custo de retê-lo entra no fundo global e é diluído nas corridas seguintes.

create or replace function public.rpc_process_ride_split(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_ride public.corridas%rowtype;
  v_quote public.ride_quotes%rowtype;
  v_snapshot jsonb;
  v_base_cents bigint;
  v_surcharge_cents bigint;
  v_driver_payout_cents bigint;
  v_courier_payout_cents bigint;
  v_idle_cents bigint := 0;
  v_idle_id uuid;
  v_driver_credit_cents bigint;
  v_platform_margin_cents bigint;
  v_platform_amount_cents bigint;
  v_balance_cents integer;
  v_split jsonb;
begin
  if p_ride_id is null then
    raise exception 'A corrida da divisão é inválida.'
      using errcode = '22023';
  end if;

  select ride.*
  into v_ride
  from public.corridas as ride
  where ride.id = p_ride_id
  for update;

  if not found
     or v_ride.encerrada is not true
     or v_ride.status_corrida::text <> 'concluida' then
    raise exception 'A corrida precisa estar concluída para dividir o pagamento.'
      using errcode = 'P0001';
  end if;

  select quote.*
  into v_quote
  from public.ride_quotes as quote
  where quote.ride_id = p_ride_id
  for update;

  if not found
     or v_quote.pricing_snapshot->>'pricing_model' is distinct from 'time_and_deficit' then
    return jsonb_build_object('status', 'skipped', 'ride_id', p_ride_id);
  end if;

  v_snapshot := v_quote.pricing_snapshot;
  if v_snapshot ? 'payment_split' then
    return jsonb_build_object(
      'status', 'already_settled',
      'ride_id', p_ride_id
    ) || (v_snapshot->'payment_split');
  end if;

  if v_snapshot->>'base_fare_cents' !~ '^[0-9]+$'
     or v_snapshot->>'surcharge_cents' !~ '^[0-9]+$'
     or v_snapshot->>'driver_amount_cents' !~ '^[0-9]+$'
     or v_snapshot->>'courier_distance_amount_cents' !~ '^[0-9]+$'
     or v_snapshot->>'courier_time_amount_cents' !~ '^[0-9]+$' then
    raise exception 'A cotação não contém a divisão da tarifa base.'
      using errcode = '22023';
  end if;

  v_base_cents := (v_snapshot->>'base_fare_cents')::bigint;
  v_surcharge_cents := (v_snapshot->>'surcharge_cents')::bigint;
  v_driver_payout_cents := (v_snapshot->>'driver_amount_cents')::bigint;
  v_courier_payout_cents :=
    (v_snapshot->>'courier_distance_amount_cents')::bigint
    + (v_snapshot->>'courier_time_amount_cents')::bigint;

  -- Repasse isolado do spread: a base paga os prestadores e a margem
  -- operacional. O surcharge_cents fica fora dessa conta.
  if v_driver_payout_cents + v_courier_payout_cents > v_base_cents then
    raise exception 'O repasse aos prestadores excede a tarifa base.'
      using errcode = '23514';
  end if;

  if v_quote.amount_cents <> v_base_cents + v_surcharge_cents then
    raise exception 'O valor pago não corresponde à base mais o acréscimo.'
      using errcode = '23514';
  end if;

  -- A margem desta corrida ignora a bolsa de espera. Esse custo não
  -- pertence ao rateio da tarifa e vai para o fundo global.
  v_platform_margin_cents :=
    v_base_cents - v_driver_payout_cents - v_courier_payout_cents;
  v_platform_amount_cents := v_platform_margin_cents + v_surcharge_cents;

  if v_ride.driver_id is not null then
    select session.id, session.pending_idle_cents
    into v_idle_id, v_idle_cents
    from public.idle_sessions as session
    where session.driver_id = v_ride.driver_id
      and session.status = 'active'
    for update;

    if not found then
      v_idle_cents := 0;
    end if;
  end if;

  if v_driver_payout_cents > 0 and v_ride.driver_id is null then
    raise exception 'A tarifa do motorista não tem um motorista na corrida.'
      using errcode = '23514';
  end if;

  if v_courier_payout_cents > 0 and v_ride.motoboy_id is null then
    raise exception 'A tarifa do resgatador não tem um motoboy na corrida.'
      using errcode = '23514';
  end if;

  v_driver_credit_cents := v_driver_payout_cents + v_idle_cents;

  if v_driver_credit_cents > 0 then
    insert into public.provider_wallet_accounts (provider_id, provider_role)
    values (v_ride.driver_id, 'driver')
    on conflict (provider_id, provider_role) do nothing;

    insert into public.provider_wallet_ledger (
      provider_id,
      provider_role,
      ride_id,
      type,
      amount_cents,
      idempotency_key,
      metadata
    )
    values (
      v_ride.driver_id,
      'driver',
      p_ride_id,
      'mission_credit',
      v_driver_credit_cents,
      'ride-split:' || p_ride_id::text || ':driver',
      jsonb_build_object(
        'payout_basis', 'base_fare_cents',
        'base_fare_cents', v_base_cents,
        'driver_ride_payout_cents', v_driver_payout_cents,
        'idle_payout_cents', v_idle_cents,
        'surcharge_excluded_cents', v_surcharge_cents
      )
    );
  end if;

  if v_idle_cents > 0 then
    update public.idle_sessions
    set status = 'completed',
        ended_at = v_now,
        updated_at = v_now
    where id = v_idle_id
      and status = 'active';
  end if;

  if v_courier_payout_cents > 0 then
    insert into public.provider_wallet_accounts (provider_id, provider_role)
    values (v_ride.motoboy_id, 'courier')
    on conflict (provider_id, provider_role) do nothing;

    insert into public.provider_wallet_ledger (
      provider_id,
      provider_role,
      ride_id,
      type,
      amount_cents,
      idempotency_key,
      metadata
    )
    values (
      v_ride.motoboy_id,
      'courier',
      p_ride_id,
      'mission_credit',
      v_courier_payout_cents,
      'ride-split:' || p_ride_id::text || ':courier',
      jsonb_build_object(
        'payout_basis', 'base_fare_cents',
        'base_fare_cents', v_base_cents,
        'surcharge_excluded_cents', v_surcharge_cents
      )
    );
  end if;

  -- O acréscimo do cliente reduz o fundo. A bolsa de espera entra depois,
  -- inteira, porque é um custo novo da plataforma e não desta corrida.
  if v_surcharge_cents > 0 or v_idle_cents > 0 then
    update public.platform_deficit_pool
    set current_balance_cents = (
          greatest(0, current_balance_cents::bigint - v_surcharge_cents)
          + v_idle_cents
        )::integer,
        updated_at = v_now
    where id
    returning current_balance_cents into v_balance_cents;

    if not found then
      raise exception 'O fundo de recomposição não está inicializado.'
        using errcode = 'P0001';
    end if;
  else
    select pool.current_balance_cents
    into v_balance_cents
    from public.platform_deficit_pool as pool;
  end if;

  v_split := jsonb_build_object(
    'base_fare_cents', v_base_cents,
    'surcharge_cents', v_surcharge_cents,
    'driver_payout_cents', v_driver_payout_cents,
    'idle_payout_cents', v_idle_cents,
    'driver_wallet_credit_cents', v_driver_credit_cents,
    'courier_payout_cents', v_courier_payout_cents,
    'platform_margin_cents', v_platform_margin_cents,
    'platform_amount_cents', v_platform_amount_cents,
    'deficit_balance_cents', v_balance_cents,
    'settled_at', v_now
  );

  update public.ride_quotes
  set pricing_snapshot = pricing_snapshot || jsonb_build_object('payment_split', v_split),
      updated_at = v_now
  where id = v_quote.id;

  return jsonb_build_object('status', 'settled', 'ride_id', p_ride_id) || v_split;
end;
$$;

comment on function public.rpc_process_ride_split(uuid) is
  'Reparte o pagamento da corrida pela tarifa base. A bolsa de espera entra na carteira do motorista e no fundo global, sem reduzir a margem desta corrida.';
