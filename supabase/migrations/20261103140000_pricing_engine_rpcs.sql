-- Dynamic quote generation. Quote amounts and pricing snapshots are written
-- only by this SECURITY DEFINER function; clients cannot write the table.

create or replace function public.rpc_generate_ride_quote(
  p_requester_id uuid,
  p_requester_type text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_dest_lat double precision,
  p_dest_lng double precision
)
returns table (
  quote_id uuid,
  amount_cents bigint,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_config public.pricing_configs%rowtype;
  v_hot_zone public.hot_zones%rowtype;
  v_origin extensions.geography(Point, 4326);
  v_destination extensions.geography(Point, 4326);
  v_trip_distance_meters double precision;
  v_provider_distance_meters double precision;
  v_provider_distance_source text;
  v_trip_distance_km numeric;
  v_provider_distance_km numeric;
  v_zone_multiplier numeric := 1;
  v_zone_surcharge_cents bigint := 0;
  v_total_multiplier numeric;
  v_partial_amount_cents numeric;
  v_calculated_amount_cents numeric;
  v_final_amount_cents bigint;
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

  v_origin := extensions.ST_SetSRID(
    extensions.ST_MakePoint(p_origin_lng, p_origin_lat),
    4326
  )::extensions.geography;
  v_destination := extensions.ST_SetSRID(
    extensions.ST_MakePoint(p_dest_lng, p_dest_lat),
    4326
  )::extensions.geography;

  v_trip_distance_meters := extensions.ST_Distance(v_origin, v_destination);
  v_trip_distance_km := v_trip_distance_meters / 1000.0;

  select extensions.ST_Distance(presence.location, v_origin)
  into v_provider_distance_meters
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

  if v_provider_distance_meters is null then
    v_provider_distance_meters := v_config.maximum_search_radius_meters;
    v_provider_distance_source := 'maximum_search_radius_fallback';
  else
    v_provider_distance_source := 'nearest_available_driver';
  end if;

  v_provider_distance_km := v_provider_distance_meters / 1000.0;

  select zone.*
  into v_hot_zone
  from public.hot_zones as zone
  where zone.active = true
    and zone.valid_from <= v_now
    and (zone.valid_until is null or zone.valid_until > v_now)
    and extensions.ST_Intersects(
      zone.area,
      v_destination::extensions.geometry
    )
  order by zone.priority desc, zone.created_at desc, zone.id
  limit 1
  for share;

  if found then
    v_zone_multiplier := v_hot_zone.destination_multiplier;
    v_zone_surcharge_cents := v_hot_zone.destination_surcharge_cents;
  end if;

  v_total_multiplier := v_config.hot_zone_multiplier * v_zone_multiplier;
  v_partial_amount_cents :=
    v_config.base_fare_cents
    + v_trip_distance_km * v_config.trip_cents_per_km
    + v_provider_distance_km * v_config.provider_to_pickup_cents_per_km;
  v_calculated_amount_cents :=
    round(v_partial_amount_cents * v_total_multiplier)
    + v_zone_surcharge_cents;

  v_final_amount_cents := greatest(
    v_config.minimum_fare_cents,
    v_calculated_amount_cents::bigint
  );
  if v_config.maximum_fare_cents is not null then
    v_final_amount_cents := least(
      v_final_amount_cents,
      v_config.maximum_fare_cents
    );
  end if;

  v_quote_id := gen_random_uuid();
  v_expires_at := v_now + interval '5 minutes';
  v_snapshot := jsonb_build_object(
    'pricing_config_id', v_config.id,
    'currency', v_config.currency,
    'base_fare_cents', v_config.base_fare_cents,
    'trip_cents_per_km', v_config.trip_cents_per_km,
    'provider_to_pickup_cents_per_km',
      v_config.provider_to_pickup_cents_per_km,
    'config_hot_zone_multiplier', v_config.hot_zone_multiplier,
    'destination_hot_zone_id', v_hot_zone.id,
    'destination_hot_zone_priority', v_hot_zone.priority,
    'destination_hot_zone_multiplier', v_zone_multiplier,
    'destination_hot_zone_surcharge_cents', v_zone_surcharge_cents,
    'total_multiplier', v_total_multiplier,
    'trip_distance_meters', round(v_trip_distance_meters)::bigint,
    'trip_distance_km', v_trip_distance_km,
    'provider_distance_meters', round(v_provider_distance_meters)::integer,
    'provider_distance_km', v_provider_distance_km,
    'provider_distance_source', v_provider_distance_source,
    'provider_search_radius_meters', v_config.initial_search_radius_meters,
    'provider_fallback_radius_meters', v_config.maximum_search_radius_meters,
    'partial_amount_cents', v_partial_amount_cents,
    'calculated_amount_cents', v_calculated_amount_cents,
    'minimum_fare_cents', v_config.minimum_fare_cents,
    'maximum_fare_cents', v_config.maximum_fare_cents,
    'final_amount_cents', v_final_amount_cents,
    'calculated_at', v_now
  );

  insert into public.ride_quotes (
    id,
    requester_id,
    requester_type,
    pricing_config_id,
    origin,
    destination,
    destination_hot_zone_id,
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
    v_hot_zone.id,
    round(v_provider_distance_meters)::integer,
    round(v_trip_distance_meters)::integer,
    v_final_amount_cents,
    v_config.currency,
    v_snapshot,
    'pending',
    v_expires_at,
    v_now,
    v_now
  );

  return query
  select v_quote_id, v_final_amount_cents, v_expires_at;
end;
$$;

revoke all on function public.rpc_generate_ride_quote(
  uuid,
  text,
  double precision,
  double precision,
  double precision,
  double precision
) from public, anon;

grant execute on function public.rpc_generate_ride_quote(
  uuid,
  text,
  double precision,
  double precision,
  double precision,
  double precision
) to authenticated;
