create or replace function public.rpc_create_customer_ride_dispatch(
  p_call_id text,
  p_origin text,
  p_destination text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_dest_lat double precision,
  p_dest_lng double precision,
  p_quote_id uuid,
  p_amount_cents bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_user_id uuid := auth.uid();
  v_quote public.ride_quotes%rowtype;
  v_radius integer;
  v_ride public.corridas%rowtype;
  v_dispatch_id uuid;
begin
  if v_user_id is null then
    raise exception 'É necessário iniciar sessão para solicitar uma corrida.'
      using errcode = '42501';
  end if;

  if p_call_id is null or length(btrim(p_call_id)) = 0
     or length(p_call_id) > 100
     or p_origin is null or length(btrim(p_origin)) = 0
     or p_destination is null or length(btrim(p_destination)) = 0 then
    raise exception 'Os dados da corrida são inválidos.'
      using errcode = '22023';
  end if;

  if p_origin_lat is null or p_origin_lng is null
     or p_dest_lat is null or p_dest_lng is null
     or p_origin_lat not between -90 and 90
     or p_dest_lat not between -90 and 90
     or p_origin_lng not between -180 and 180
     or p_dest_lng not between -180 and 180 then
    raise exception 'As coordenadas da corrida são inválidas.'
      using errcode = '22023';
  end if;

  if p_quote_id is null or p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'A cotação da corrida é inválida.'
      using errcode = '22023';
  end if;

  select quote.*
  into v_quote
  from public.ride_quotes as quote
  join public.pricing_configs as config
    on config.id = quote.pricing_config_id
  where quote.id = p_quote_id
    and quote.requester_id = v_user_id
    and quote.requester_type = 'customer'
    and quote.status = 'pending'
    and quote.ride_id is null
    and quote.expires_at > v_now
    and quote.amount_cents = p_amount_cents
    and quote.pricing_snapshot->>'provider_search_radius_meters'
      ~ '^[1-9][0-9]*$'
    and extensions.ST_DWithin(
      quote.origin,
      extensions.ST_SetSRID(
        extensions.ST_MakePoint(p_origin_lng, p_origin_lat),
        4326
      )::extensions.geography,
      1
    )
    and extensions.ST_DWithin(
      quote.destination,
      extensions.ST_SetSRID(
        extensions.ST_MakePoint(p_dest_lng, p_dest_lat),
        4326
      )::extensions.geography,
      1
    )
  for update of quote;

  if not found then
    raise exception 'A cotação expirou ou não corresponde a esta corrida.'
      using errcode = 'P0001';
  end if;

  v_radius := (v_quote.pricing_snapshot->>'provider_search_radius_meters')::integer;
  if v_radius < 1 then
    raise exception 'A cotação não contém um raio de despacho válido.'
      using errcode = '22023';
  end if;

  insert into public.corridas (
    call_id,
    status_corrida,
    origin,
    destination,
    origin_lat,
    origin_lng,
    dest_lat,
    dest_lng,
    valor_total,
    driver_fare,
    requested_by,
    accepted_by,
    accepted_role,
    motoboy_id,
    encerrada,
    updated_at
  )
  values (
    btrim(p_call_id),
    'buscando_prestadores',
    btrim(p_origin),
    btrim(p_destination),
    p_origin_lat,
    p_origin_lng,
    p_dest_lat,
    p_dest_lng,
    p_amount_cents::numeric / 100,
    p_amount_cents::numeric / 100,
    v_user_id,
    null,
    null,
    null,
    false,
    v_now
  )
  returning * into v_ride;

  update public.ride_quotes
  set ride_id = v_ride.id,
      status = 'used',
      updated_at = v_now
  where id = v_quote.id
    and ride_id is null
    and status = 'pending';

  if not found then
    raise exception 'A cotação já foi associada a outra corrida.'
      using errcode = 'P0001';
  end if;

  insert into public.mission_dispatches (
    ride_id,
    provider_role,
    status,
    search_radius_meters,
    next_attempt_at
  )
  values (
    v_ride.id,
    'driver',
    'pending',
    v_radius,
    v_now
  )
  returning id into v_dispatch_id;

  return jsonb_build_object(
    'ride', to_jsonb(v_ride),
    'dispatch_id', v_dispatch_id
  );
end;
$$;

revoke all on function public.rpc_create_customer_ride_dispatch(
  text,
  text,
  text,
  double precision,
  double precision,
  double precision,
  double precision,
  uuid,
  bigint
) from public, anon;

grant execute on function public.rpc_create_customer_ride_dispatch(
  text,
  text,
  text,
  double precision,
  double precision,
  double precision,
  double precision,
  uuid,
  bigint
) to authenticated;

do $$
declare
  v_candidate record;
  v_radius integer;
begin
  for v_candidate in
    select
      ride.id as ride_id,
      quote.id as quote_id,
      quote.pricing_snapshot->>'provider_search_radius_meters' as radius
    from public.corridas as ride
    join lateral (
      select candidate.*
      from public.ride_quotes as candidate
      where candidate.requester_id = ride.requested_by
        and candidate.requester_type = 'customer'
        and candidate.status = 'pending'
        and candidate.ride_id is null
        and candidate.created_at <= ride.created_at
        and candidate.created_at >= ride.created_at - interval '10 minutes'
        and candidate.expires_at > clock_timestamp()
        and candidate.amount_cents = round(ride.valor_total * 100)::bigint
        and extensions.ST_DWithin(
          candidate.origin,
          extensions.ST_SetSRID(
            extensions.ST_MakePoint(ride.origin_lng, ride.origin_lat),
            4326
          )::extensions.geography,
          1
        )
        and extensions.ST_DWithin(
          candidate.destination,
          extensions.ST_SetSRID(
            extensions.ST_MakePoint(ride.dest_lng, ride.dest_lat),
            4326
          )::extensions.geography,
          1
        )
      order by candidate.created_at desc
      limit 1
    ) as quote on true
    where ride.status_corrida::text = 'buscando_prestadores'
      and ride.encerrada = false
      and ride.driver_id is null
      and ride.requested_by is not null
      and ride.valor_total is not null
      and quote.pricing_snapshot->>'provider_search_radius_meters'
        ~ '^[1-9][0-9]*$'
      and not exists (
        select 1
        from public.mission_dispatches as dispatch
        where dispatch.ride_id = ride.id
          and dispatch.provider_role = 'driver'
      )
  loop
    v_radius := v_candidate.radius::integer;
    if v_radius > 0 then
      update public.ride_quotes
      set ride_id = v_candidate.ride_id,
          status = 'used',
          updated_at = clock_timestamp()
      where id = v_candidate.quote_id
        and ride_id is null
        and status = 'pending';

      if found then
        insert into public.mission_dispatches (
          ride_id,
          provider_role,
          status,
          search_radius_meters,
          next_attempt_at
        )
        values (
          v_candidate.ride_id,
          'driver',
          'pending',
          v_radius,
          clock_timestamp()
        )
        on conflict (ride_id, provider_role) do nothing;
      end if;
    end if;
  end loop;
end;
$$;
