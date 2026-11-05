-- Cotação pelo tempo de trânsito. A tarifa base sai de pricing_settings.
-- O acréscimo do fundo é só leitura: a baixa do saldo fica para o
-- pagamento confirmado, para uma cotação abandonada não consumir o déficit.
-- amount_cents continua sendo o total cobrado do cliente.

drop function if exists public.rpc_generate_ride_quote(
  uuid,
  text,
  double precision,
  double precision,
  double precision,
  double precision
);

create function public.rpc_generate_ride_quote(
  p_requester_id uuid,
  p_requester_type text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_dest_lat double precision,
  p_dest_lng double precision,
  p_driver_duration_in_traffic_seconds integer default null,
  p_driver_duration_seconds integer default null,
  p_courier_duration_in_traffic_seconds integer default null,
  p_courier_duration_seconds integer default null,
  p_courier_distance_meters integer default null
)
returns table (
  quote_id uuid,
  amount_cents bigint,
  expires_at timestamptz,
  total_fare_cents bigint,
  base_fare_cents bigint,
  surcharge_cents bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_settings public.pricing_settings%rowtype;
  v_config public.pricing_configs%rowtype;
  v_pool public.platform_deficit_pool%rowtype;
  v_origin extensions.geography(Point, 4326);
  v_destination extensions.geography(Point, 4326);
  v_trip_distance_meters double precision;
  v_courier_distance_meters double precision;
  v_courier_distance_source text;
  v_driver_seconds integer;
  v_driver_duration_source text;
  v_courier_seconds integer;
  v_courier_duration_source text;
  v_onboarding_cents bigint;
  v_driver_cents bigint;
  v_courier_distance_cents bigint;
  v_courier_time_cents bigint;
  v_base_cents bigint;
  v_surcharge_cents bigint;
  v_total_cents bigint;
  v_quote_id uuid;
  v_expires_at timestamptz;
  v_snapshot jsonb;
begin
  if auth.uid() is null or p_requester_id is distinct from auth.uid() then
    raise exception 'O solicitante deve corresponder à sessão autenticada.'
      using errcode = '42501';
  end if;

  if p_requester_type is null
     or p_requester_type not in ('customer', 'merchant') then
    raise exception 'Tipo de solicitante inválido.'
      using errcode = '22023';
  end if;

  if p_origin_lat is null or p_origin_lng is null
     or p_dest_lat is null or p_dest_lng is null
     or p_origin_lat not between -90 and 90
     or p_dest_lat not between -90 and 90
     or p_origin_lng not between -180 and 180
     or p_dest_lng not between -180 and 180 then
    raise exception 'As coordenadas da cotação são inválidas.'
      using errcode = '22023';
  end if;

  if not public.quote_duration_seconds_ok(p_driver_duration_in_traffic_seconds)
     or not public.quote_duration_seconds_ok(p_driver_duration_seconds)
     or not public.quote_duration_seconds_ok(p_courier_duration_in_traffic_seconds)
     or not public.quote_duration_seconds_ok(p_courier_duration_seconds)
     or (
       p_courier_distance_meters is not null
       and (
         p_courier_distance_meters < 0
         or p_courier_distance_meters > 500000
       )
     ) then
    raise exception 'A duração ou a distância informada para a cotação é inválida.'
      using errcode = '22023';
  end if;

  select settings.*
  into v_settings
  from public.pricing_settings as settings
  where settings.active = true
  order by settings.updated_at desc, settings.created_at desc, settings.id
  limit 1
  for share;

  if not found then
    raise exception 'Não há parâmetros de precificação ativos.'
      using errcode = 'P0001';
  end if;

  select config.*
  into v_config
  from public.pricing_configs as config
  where config.active = true
    and config.valid_from <= v_now
    and (config.valid_until is null or config.valid_until > v_now)
  order by config.valid_from desc, config.created_at desc, config.id
  limit 1
  for share;

  if not found then
    raise exception 'Não há configuração de preços ativa e válida.'
      using errcode = 'P0001';
  end if;

  select pool.*
  into v_pool
  from public.platform_deficit_pool as pool
  limit 1
  for share;

  if not found then
    raise exception 'O fundo de recomposição não está inicializado.'
      using errcode = 'P0001';
  end if;

  v_origin := extensions.ST_SetSRID(
    extensions.ST_MakePoint(p_origin_lng, p_origin_lat),
    4326
  )::extensions.geography;
  v_destination := extensions.ST_SetSRID(
    extensions.ST_MakePoint(p_dest_lng, p_dest_lat),
    4326
  )::extensions.geography;
  v_trip_distance_meters := extensions.ST_Distance(v_origin, v_destination);

  if p_courier_distance_meters is not null then
    v_courier_distance_meters := p_courier_distance_meters;
    v_courier_distance_source := 'informed_route';
  else
    select extensions.ST_Distance(presence.location, v_origin)
    into v_courier_distance_meters
    from public.provider_presence as presence
    join public.providers as provider
      on provider.id = presence.provider_id
     and provider.role = presence.provider_role
    where presence.provider_role = 'driver'
      and presence.is_available = true
      and provider.status_sistema = 'ativo'
      and extensions.ST_DWithin(
        presence.location,
        v_origin,
        v_config.initial_search_radius_meters
      )
    order by extensions.ST_Distance(presence.location, v_origin),
             presence.last_seen_at desc,
             presence.provider_id
    limit 1;

    if v_courier_distance_meters is null then
      v_courier_distance_meters := v_config.maximum_search_radius_meters;
      v_courier_distance_source := 'maximum_search_radius_fallback';
    else
      v_courier_distance_source := 'nearest_available_driver';
    end if;
  end if;

  v_driver_seconds := public.quote_billable_seconds(
    p_driver_duration_in_traffic_seconds,
    p_driver_duration_seconds,
    v_trip_distance_meters
  );
  v_driver_duration_source := public.quote_duration_source(
    p_driver_duration_in_traffic_seconds,
    p_driver_duration_seconds
  );
  v_courier_seconds := public.quote_billable_seconds(
    p_courier_duration_in_traffic_seconds,
    p_courier_duration_seconds,
    v_courier_distance_meters
  );
  v_courier_duration_source := public.quote_duration_source(
    p_courier_duration_in_traffic_seconds,
    p_courier_duration_seconds
  );

  v_onboarding_cents := v_settings.fixed_onboarding_cents;
  v_driver_cents := round(
    (v_driver_seconds / 60.0) * v_settings.driver_rate_per_minute_cents
  )::bigint;
  v_courier_distance_cents := round(
    (v_courier_distance_meters / 1000.0) * v_settings.courier_rate_per_km_cents
  )::bigint;
  v_courier_time_cents := round(
    (v_courier_seconds / 60.0) * v_settings.courier_rate_per_minute_cents
  )::bigint;
  v_base_cents :=
    v_onboarding_cents
    + v_driver_cents
    + v_courier_distance_cents
    + v_courier_time_cents;

  if v_pool.current_balance_cents > 0 then
    v_surcharge_cents := least(
      v_pool.current_balance_cents::bigint,
      least(
        floor(v_base_cents * v_pool.max_surcharge_percent)::bigint,
        v_pool.max_surcharge_cents::bigint
      )
    );
  else
    v_surcharge_cents := 0;
  end if;

  v_total_cents := v_base_cents + v_surcharge_cents;
  v_quote_id := gen_random_uuid();
  v_expires_at := v_now + interval '5 minutes';
  v_snapshot := jsonb_build_object(
    'pricing_model', 'time_and_deficit',
    'pricing_settings_id', v_settings.id,
    'pricing_config_id', v_config.id,
    'currency', v_config.currency,
    'fixed_onboarding_cents', v_onboarding_cents,
    'driver_rate_per_minute_cents', v_settings.driver_rate_per_minute_cents,
    'driver_seconds', v_driver_seconds,
    'driver_duration_source', v_driver_duration_source,
    'driver_amount_cents', v_driver_cents,
    'courier_rate_per_km_cents', v_settings.courier_rate_per_km_cents,
    'courier_distance_meters', round(v_courier_distance_meters)::integer,
    'courier_distance_source', v_courier_distance_source,
    'courier_distance_amount_cents', v_courier_distance_cents,
    'courier_rate_per_minute_cents', v_settings.courier_rate_per_minute_cents,
    'courier_seconds', v_courier_seconds,
    'courier_duration_source', v_courier_duration_source,
    'courier_time_amount_cents', v_courier_time_cents,
    'trip_distance_meters', round(v_trip_distance_meters)::bigint,
    'base_fare_cents', v_base_cents,
    'deficit_balance_cents', v_pool.current_balance_cents,
    'max_surcharge_percent', v_pool.max_surcharge_percent,
    'max_surcharge_cents', v_pool.max_surcharge_cents,
    'surcharge_cents', v_surcharge_cents,
    'total_fare_cents', v_total_cents,
    'provider_search_radius_meters', v_config.initial_search_radius_meters,
    'provider_fallback_radius_meters', v_config.maximum_search_radius_meters,
    'calculated_at', v_now
  );

  insert into public.ride_quotes (
    id,
    requester_id,
    requester_type,
    pricing_config_id,
    origin,
    destination,
    provider_distance_meters,
    trip_distance_meters,
    amount_cents,
    currency,
    pricing_snapshot,
    status,
    expires_at,
    created_at,
    updated_at
  )
  values (
    v_quote_id,
    p_requester_id,
    p_requester_type,
    v_config.id,
    v_origin,
    v_destination,
    round(v_courier_distance_meters)::integer,
    round(v_trip_distance_meters)::integer,
    v_total_cents,
    v_config.currency,
    v_snapshot,
    'pending',
    v_expires_at,
    v_now,
    v_now
  );

  return query
  select
    v_quote_id,
    v_total_cents,
    v_expires_at,
    v_total_cents,
    v_base_cents,
    v_surcharge_cents;
end;
$$;

create or replace function public.quote_duration_seconds_ok(p_seconds integer)
returns boolean
language sql
immutable
as $$
  select p_seconds is null or (p_seconds >= 0 and p_seconds <= 86400);
$$;

create or replace function public.quote_duration_source(
  p_duration_in_traffic_seconds integer,
  p_duration_seconds integer
)
returns text
language sql
immutable
as $$
  select case
    when p_duration_in_traffic_seconds is not null then 'duration_in_traffic'
    when p_duration_seconds is not null then 'duration'
    else 'estimated_from_distance'
  end;
$$;

-- 30 km/h, o mesmo ritmo já usado na previsão do app, só quando
-- a rota não trouxe duração.
create or replace function public.quote_billable_seconds(
  p_duration_in_traffic_seconds integer,
  p_duration_seconds integer,
  p_distance_meters double precision
)
returns integer
language sql
immutable
as $$
  select case
    when p_duration_in_traffic_seconds is not null then
      p_duration_in_traffic_seconds
    when p_duration_seconds is not null then
      p_duration_seconds
    else
      least(
        86400,
        greatest(
          0,
          round(coalesce(p_distance_meters, 0) * 3600.0 / 30000.0)::integer
        )
      )
  end;
$$;

revoke all on function public.quote_duration_seconds_ok(integer) from public;
revoke all on function public.quote_duration_source(integer, integer) from public;
revoke all on function public.quote_billable_seconds(integer, integer, double precision)
  from public;

revoke all on function public.rpc_generate_ride_quote(
  uuid,
  text,
  double precision,
  double precision,
  double precision,
  double precision,
  integer,
  integer,
  integer,
  integer,
  integer
) from public, anon;

grant execute on function public.rpc_generate_ride_quote(
  uuid,
  text,
  double precision,
  double precision,
  double precision,
  double precision,
  integer,
  integer,
  integer,
  integer,
  integer
) to authenticated;
