do $$
begin
  if not exists (
    select 1
    from public.pricing_configs
    where active = true
  ) then
    insert into public.pricing_configs (
      name,
      currency,
      base_fare_cents,
      trip_cents_per_km,
      provider_to_pickup_cents_per_km,
      hot_zone_multiplier,
      minimum_fare_cents,
      maximum_fare_cents,
      initial_search_radius_meters,
      maximum_search_radius_meters,
      active,
      valid_from
    )
    values (
      'Configuracao inicial Xofer App',
      'BRL',
      690,
      120,
      60,
      1.2,
      1100,
      30000,
      100,
      12000,
      true,
      now()
    );
  end if;
end;
$$;
