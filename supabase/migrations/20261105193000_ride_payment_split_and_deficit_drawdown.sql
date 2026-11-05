-- Divisão do pagamento capturado na cotação.
-- Motorista e motoboy recebem somente as parcelas da tarifa base.
-- O surcharge cobrado do cliente não entra nesse repasse: ele é margem
-- extra da plataforma e, ao mesmo tempo, a baixa do fundo de amortização.

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

  v_platform_margin_cents :=
    v_base_cents - v_driver_payout_cents - v_courier_payout_cents;
  v_platform_amount_cents := v_platform_margin_cents + v_surcharge_cents;

  if v_driver_payout_cents > 0 and v_ride.driver_id is null then
    raise exception 'A tarifa do motorista não tem um motorista na corrida.'
      using errcode = '23514';
  end if;

  if v_courier_payout_cents > 0 and v_ride.motoboy_id is null then
    raise exception 'A tarifa do resgatador não tem um motoboy na corrida.'
      using errcode = '23514';
  end if;

  if v_driver_payout_cents > 0 then
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
      v_driver_payout_cents,
      'ride-split:' || p_ride_id::text || ':driver',
      jsonb_build_object(
        'payout_basis', 'base_fare_cents',
        'base_fare_cents', v_base_cents,
        'surcharge_excluded_cents', v_surcharge_cents
      )
    );
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

  -- O spread volta para o fundo e não aumenta o ganho de motorista ou motoboy.
  if v_surcharge_cents > 0 then
    update public.platform_deficit_pool
    set current_balance_cents = greatest(
          0,
          current_balance_cents::bigint - v_surcharge_cents
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
  'Reparte o pagamento da corrida. Prestadores recebem parcelas da tarifa base; o acréscimo do cliente fica com a plataforma e reduz o fundo de amortização.';

create or replace function public.settle_completed_ride_split()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status_corrida::text = 'concluida'
     and old.status_corrida::text is distinct from 'concluida' then
    perform public.rpc_process_ride_split(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists corridas_settle_payment_split on public.corridas;
create trigger corridas_settle_payment_split
after update of status_corrida on public.corridas
for each row
execute function public.settle_completed_ride_split();

revoke all on function public.rpc_process_ride_split(uuid)
  from public, anon, authenticated;
revoke all on function public.settle_completed_ride_split()
  from public, anon, authenticated;

grant execute on function public.rpc_process_ride_split(uuid)
  to service_role;
