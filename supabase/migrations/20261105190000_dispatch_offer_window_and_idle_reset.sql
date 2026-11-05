-- A oferta do despacho cego fica 45s no ar: 30s de decisão e 15s de
-- tolerância de rede. Recusa explícita e expiração sem resposta zeram
-- a bolsa de espera do motorista. ended_at acompanha o status porque
-- a sessão ativa não pode terminar com essa coluna vazia.

create or replace function public.reset_driver_idle_on_refusal(p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
begin
  if p_driver_id is null then
    return;
  end if;

  update public.idle_sessions
  set pending_idle_cents = 0,
      status = 'reset_by_refusal',
      ended_at = v_now,
      updated_at = v_now
  where driver_id = p_driver_id
    and status = 'active';
end;
$$;

revoke all on function public.reset_driver_idle_on_refusal(uuid)
  from public, anon, authenticated;

create or replace function public.rpc_process_next_dispatch_attempt()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now timestamptz;
  v_dispatch_id uuid;
  v_ride_id uuid;
  v_role text;
  v_round integer;
  v_radius integer;
  v_max_radius integer;
  v_origin_lat double precision;
  v_origin_lng double precision;
  v_partner_lat double precision;
  v_partner_lng double precision;
  v_target extensions.geography(Point, 4326);
  v_provider_id uuid;
  v_sequence integer;
  v_attempt_id uuid;
  v_expires_at timestamptz;
  v_next_round integer;
  v_next_radius integer;
  v_retry_seconds integer;
  v_expired record;
begin
  v_now := clock_timestamp();

  select
    md.id,
    md.ride_id,
    md.provider_role,
    md.round_no,
    md.search_radius_meters,
    r.origin_lat,
    r.origin_lng,
    r.partner_lat,
    r.partner_lng
  into
    v_dispatch_id,
    v_ride_id,
    v_role,
    v_round,
    v_radius,
    v_origin_lat,
    v_origin_lng,
    v_partner_lat,
    v_partner_lng
  from public.mission_dispatches as md
  join public.corridas as r
    on r.id = md.ride_id
  where md.status in ('pending', 'dispatching')
    and (md.next_attempt_at is null or md.next_attempt_at <= v_now)
    and r.encerrada = false
    and (
      (md.provider_role = 'driver'
        and r.status_corrida::text = 'buscando_prestadores')
      or
      (md.provider_role = 'courier'
        and r.status_corrida::text = 'procurando_motoboy')
    )
    and not exists (
      select 1
      from public.dispatch_attempts as active_attempt
      where active_attempt.dispatch_id = md.id
        and active_attempt.status = 'offered'
        and active_attempt.expires_at > v_now
    )
  order by coalesce(md.next_attempt_at, md.created_at), md.created_at
  limit 1
  for update of md skip locked;

  if v_dispatch_id is null then
    return null;
  end if;

  v_now := clock_timestamp();

  select pc.maximum_search_radius_meters
  into v_max_radius
  from public.pricing_configs as pc
  where pc.active = true
    and pc.valid_from <= v_now
    and (pc.valid_until is null or pc.valid_until > v_now)
  order by pc.valid_from desc
  limit 1;

  if v_max_radius is null then
    raise exception 'Não há configuração de preço ativa para o despacho.'
      using errcode = 'P0001';
  end if;

  for v_expired in
    update public.dispatch_attempts as attempt
    set status = 'expired',
        responded_at = v_now
    where attempt.dispatch_id = v_dispatch_id
      and attempt.status = 'offered'
      and attempt.expires_at <= v_now
    returning attempt.provider_id, attempt.provider_role
  loop
    if v_expired.provider_role = 'driver' then
      perform public.reset_driver_idle_on_refusal(v_expired.provider_id);
    end if;
  end loop;

  if v_role = 'driver'
     and v_origin_lat is not null
     and v_origin_lng is not null then
    v_target := extensions.ST_SetSRID(
      extensions.ST_MakePoint(v_origin_lng, v_origin_lat),
      4326
    )::extensions.geography;
  elsif v_role = 'courier'
        and v_partner_lat is not null
        and v_partner_lng is not null then
    v_target := extensions.ST_SetSRID(
      extensions.ST_MakePoint(v_partner_lng, v_partner_lat),
      4326
    )::extensions.geography;
  else
    update public.mission_dispatches
    set status = 'pending',
        next_attempt_at = v_now + interval '30 seconds',
        updated_at = v_now
    where id = v_dispatch_id;

    return jsonb_build_object(
      'status', 'waiting_for_ride_location',
      'dispatch_id', v_dispatch_id,
      'retry_at', v_now + interval '30 seconds'
    );
  end if;

  v_radius := least(v_radius, v_max_radius);

  select pp.provider_id
  into v_provider_id
  from public.provider_presence as pp
  join public.providers as provider
    on provider.id = pp.provider_id
   and provider.role = pp.provider_role
  where pp.provider_role = v_role
    and pp.is_available = true
    and provider.status_sistema = 'ativo'
    and extensions.ST_DWithin(pp.location, v_target, v_radius)
    and not exists (
      select 1
      from public.dispatch_attempts as previous_attempt
      where previous_attempt.dispatch_id = v_dispatch_id
        and previous_attempt.round_no = v_round
        and previous_attempt.provider_id = pp.provider_id
    )
    and not exists (
      select 1
      from public.dispatch_attempts as open_attempt
      where open_attempt.provider_id = pp.provider_id
        and open_attempt.provider_role = pp.provider_role
        and open_attempt.status = 'offered'
    )
  order by pp.location <-> v_target, pp.last_seen_at desc, pp.provider_id
  limit 1
  for update of pp, provider skip locked;

  if v_provider_id is not null then
    select coalesce(max(attempt.sequence_no), 0) + 1
    into v_sequence
    from public.dispatch_attempts as attempt
    where attempt.dispatch_id = v_dispatch_id
      and attempt.round_no = v_round;

    v_attempt_id := gen_random_uuid();
    v_expires_at := clock_timestamp() + interval '45 seconds';

    insert into public.dispatch_attempts (
      id,
      dispatch_id,
      provider_id,
      provider_role,
      round_no,
      sequence_no,
      status,
      offered_at,
      expires_at,
      distance_meters
    )
    select
      v_attempt_id,
      v_dispatch_id,
      v_provider_id,
      v_role,
      v_round,
      v_sequence,
      'offered',
      v_now,
      v_expires_at,
      round(extensions.ST_Distance(pp.location, v_target))::integer
    from public.provider_presence as pp
    where pp.provider_id = v_provider_id
      and pp.provider_role = v_role;

    update public.mission_dispatches
    set status = 'dispatching',
        search_radius_meters = v_radius,
        next_attempt_at = v_expires_at,
        updated_at = v_now
    where id = v_dispatch_id;

    return jsonb_build_object(
      'status', 'offered',
      'dispatch_id', v_dispatch_id,
      'attempt_id', v_attempt_id,
      'provider_id', v_provider_id,
      'provider_role', v_role,
      'expires_at', v_expires_at
    );
  end if;

  v_next_round := v_round + 1;
  v_next_radius := least(
    v_max_radius::bigint,
    greatest(v_radius::bigint + 1, v_radius::bigint * 2)
  )::integer;
  v_retry_seconds := least(
    300,
    5 * power(2, least(v_round - 1, 6))::integer
  );

  update public.mission_dispatches
  set status = 'pending',
      round_no = v_next_round,
      search_radius_meters = v_next_radius,
      next_attempt_at = v_now + make_interval(secs => v_retry_seconds),
      updated_at = v_now
  where id = v_dispatch_id;

  return jsonb_build_object(
    'status', 'waiting_for_provider',
    'dispatch_id', v_dispatch_id,
    'round_no', v_next_round,
    'search_radius_meters', v_next_radius,
    'retry_at', v_now + make_interval(secs => v_retry_seconds)
  );
end;
$$;

create or replace function public.rpc_expire_stale_attempts(
  p_batch_size integer default 100
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz;
  v_dispatch_id uuid;
  v_expired record;
  v_expired_count integer;
  v_total_expired integer := 0;
begin
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 1000 then
    raise exception 'O tamanho do lote deve estar entre 1 e 1000.'
      using errcode = '22023';
  end if;

  for v_dispatch_id in
    select dispatch.id
    from public.mission_dispatches as dispatch
    where dispatch.status = 'dispatching'
      and exists (
        select 1
        from public.dispatch_attempts as attempt
        where attempt.dispatch_id = dispatch.id
          and attempt.status = 'offered'
          and attempt.expires_at <= clock_timestamp()
      )
    order by dispatch.next_attempt_at nulls first, dispatch.created_at
    limit p_batch_size
    for update of dispatch skip locked
  loop
    v_now := clock_timestamp();
    v_expired_count := 0;

    for v_expired in
      update public.dispatch_attempts as attempt
      set status = 'expired',
          responded_at = v_now
      where attempt.dispatch_id = v_dispatch_id
        and attempt.status = 'offered'
        and attempt.expires_at <= v_now
      returning attempt.provider_id, attempt.provider_role
    loop
      v_expired_count := v_expired_count + 1;
      if v_expired.provider_role = 'driver' then
        perform public.reset_driver_idle_on_refusal(v_expired.provider_id);
      end if;
    end loop;

    v_total_expired := v_total_expired + v_expired_count;

    if v_expired_count > 0 then
      update public.mission_dispatches
      set status = 'pending',
          next_attempt_at = v_now,
          updated_at = v_now
      where id = v_dispatch_id
        and status = 'dispatching'
        and not exists (
          select 1
          from public.dispatch_attempts as active_attempt
          where active_attempt.dispatch_id = v_dispatch_id
            and active_attempt.status = 'offered'
            and active_attempt.expires_at > v_now
        );
    end if;
  end loop;

  return v_total_expired;
end;
$$;

create or replace function public.rpc_respond_to_mission(
  p_attempt_id uuid,
  p_provider_id uuid,
  p_response text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_authenticated_provider uuid := auth.uid();
  v_dispatch_id uuid;
  v_ride_id uuid;
  v_role text;
  v_dispatch_round integer;
  v_attempt_provider uuid;
  v_attempt_role text;
  v_attempt_round integer;
  v_attempt_status text;
  v_expires_at timestamptz;
  v_now timestamptz;
  v_lat double precision;
  v_lng double precision;
  v_is_merchant_delivery boolean;
  v_updated_ride_id uuid;
begin
  if v_authenticated_provider is null
     or p_provider_id is null
     or v_authenticated_provider <> p_provider_id then
    raise exception 'O parceiro informado não corresponde à sessão autenticada.'
      using errcode = '42501';
  end if;

  if p_response is null or p_response not in ('accepted', 'declined') then
    raise exception 'Resposta inválida para a missão.'
      using errcode = '22023';
  end if;

  select attempt.dispatch_id
  into v_dispatch_id
  from public.dispatch_attempts as attempt
  where attempt.id = p_attempt_id
    and attempt.provider_id = p_provider_id;

  if v_dispatch_id is null then
    raise exception 'Tentativa de missão não encontrada.'
      using errcode = 'P0002';
  end if;

  select
    dispatch.ride_id,
    dispatch.provider_role,
    dispatch.round_no,
    ride.requester_type = 'merchant' and ride.service_type = 'delivery'
  into
    v_ride_id,
    v_role,
    v_dispatch_round,
    v_is_merchant_delivery
  from public.mission_dispatches as dispatch
  join public.corridas as ride on ride.id = dispatch.ride_id
  where dispatch.id = v_dispatch_id
  for update of dispatch;

  if v_ride_id is null then
    raise exception 'Despacho não encontrado.'
      using errcode = 'P0002';
  end if;

  select
    attempt.provider_id,
    attempt.provider_role,
    attempt.round_no,
    attempt.status,
    attempt.expires_at
  into
    v_attempt_provider,
    v_attempt_role,
    v_attempt_round,
    v_attempt_status,
    v_expires_at
  from public.dispatch_attempts as attempt
  where attempt.id = p_attempt_id
    and attempt.dispatch_id = v_dispatch_id
  for update;

  if not found then
    raise exception 'Tentativa de missão não encontrada.'
      using errcode = 'P0002';
  end if;

  v_now := clock_timestamp();
  if v_attempt_status = 'expired'
     or (v_attempt_status = 'offered' and v_expires_at <= v_now) then
    if v_attempt_status = 'offered' then
      update public.dispatch_attempts
      set status = 'expired',
          responded_at = v_now
      where id = p_attempt_id
        and status = 'offered'
        and expires_at <= v_now;

      update public.mission_dispatches
      set status = 'pending',
          next_attempt_at = v_now,
          updated_at = v_now
      where id = v_dispatch_id
        and status = 'dispatching'
        and not exists (
          select 1
          from public.dispatch_attempts as active_attempt
          where active_attempt.dispatch_id = v_dispatch_id
            and active_attempt.status = 'offered'
            and active_attempt.expires_at > v_now
        );
    end if;

    if v_role = 'driver' then
      perform public.reset_driver_idle_on_refusal(p_provider_id);
    end if;

    return jsonb_build_object(
      'status', 'expired',
      'dispatch_id', v_dispatch_id,
      'attempt_id', p_attempt_id
    );
  end if;

  if v_attempt_provider <> p_provider_id
     or v_attempt_role <> v_role
     or v_attempt_round <> v_dispatch_round
     or v_attempt_status <> 'offered'
     or v_expires_at <= v_now then
    raise exception 'A oferta já expirou ou não está mais disponível.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.providers as provider
    where provider.id = p_provider_id
      and provider.role = v_role
      and provider.status_sistema = 'ativo'
  ) then
    raise exception 'O parceiro não está ativo para aceitar missões.'
      using errcode = '42501';
  end if;

  if p_response = 'declined' then
    update public.dispatch_attempts
    set status = 'declined',
        responded_at = v_now
    where id = p_attempt_id
      and status = 'offered'
      and expires_at > v_now;

    if not found then
      raise exception 'A oferta expirou ou já recebeu uma resposta.'
        using errcode = 'P0001';
    end if;

    update public.mission_dispatches
    set status = 'pending',
        next_attempt_at = v_now,
        updated_at = v_now
    where id = v_dispatch_id
      and status = 'dispatching';

    if v_role = 'driver' then
      perform public.reset_driver_idle_on_refusal(p_provider_id);
    end if;

    return jsonb_build_object(
      'status', 'declined',
      'dispatch_id', v_dispatch_id,
      'attempt_id', p_attempt_id
    );
  end if;

  select
    extensions.ST_Y(presence.location::extensions.geometry),
    extensions.ST_X(presence.location::extensions.geometry)
  into v_lat, v_lng
  from public.provider_presence as presence
  where presence.provider_id = p_provider_id
    and presence.provider_role = v_role
  for update;

  if not found or v_lat is null or v_lng is null then
    raise exception 'A localização atual do parceiro não está disponível.'
      using errcode = 'P0001';
  end if;

  update public.dispatch_attempts
  set status = 'accepted',
      responded_at = v_now
  where id = p_attempt_id
    and status = 'offered'
    and expires_at > v_now;

  if not found then
    raise exception 'A oferta expirou ou já recebeu uma resposta.'
      using errcode = 'P0001';
  end if;

  update public.mission_dispatches
  set status = 'accepted',
      accepted_by = p_provider_id,
      accepted_role = v_role,
      accepted_at = v_now,
      next_attempt_at = null,
      updated_at = v_now
  where id = v_dispatch_id
    and status = 'dispatching';

  if not found then
    raise exception 'O despacho não está mais disponível para aceite.'
      using errcode = 'P0001';
  end if;

  if v_role = 'driver' then
    update public.corridas
    set driver_id = p_provider_id,
        partner_lat = v_lat,
        partner_lng = v_lng,
        accepted_by = p_provider_id,
        accepted_role = 'driver',
        status_corrida = 'procurando_motoboy',
        updated_at = v_now
    where id = v_ride_id
      and status_corrida::text = 'buscando_prestadores'
      and accepted_by is null
      and driver_id is null
      and encerrada = false
    returning id into v_updated_ride_id;
  else
    update public.corridas
    set motoboy_id = p_provider_id,
        motoboy_lat = v_lat,
        motoboy_lng = v_lng,
        accepted_by = p_provider_id,
        accepted_role = 'courier',
        status_corrida = 'motoboy_a_caminho',
        updated_at = v_now
    where id = v_ride_id
      and status_corrida::text = 'procurando_motoboy'
      and (
        driver_id is not null
        or v_is_merchant_delivery
      )
      and motoboy_id is null
      and encerrada = false
    returning id into v_updated_ride_id;
  end if;

  if v_updated_ride_id is null then
    raise exception 'O estado da corrida mudou antes do aceite.'
      using errcode = 'P0001';
  end if;

  update public.provider_presence
  set is_available = false,
      updated_at = v_now
  where provider_id = p_provider_id
    and provider_role = v_role;

  return jsonb_build_object(
    'status', 'accepted',
    'dispatch_id', v_dispatch_id,
    'attempt_id', p_attempt_id,
    'ride_id', v_ride_id,
    'provider_role', v_role
  );
end;
$$;
