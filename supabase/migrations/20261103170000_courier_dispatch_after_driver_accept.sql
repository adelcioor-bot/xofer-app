create or replace function public.enqueue_courier_dispatch_after_driver_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_search_radius_text text;
  v_search_radius integer;
begin
  if new.status_corrida::text <> 'procurando_motoboy'
     or old.status_corrida::text = 'procurando_motoboy'
     or new.driver_id is null then
    return new;
  end if;

  select quote.pricing_snapshot->>'provider_search_radius_meters'
  into v_search_radius_text
  from public.ride_quotes as quote
  where quote.ride_id = new.id
    and quote.requester_type = 'customer'
  order by quote.created_at desc
  limit 1;

  if v_search_radius_text is null
     or v_search_radius_text !~ '^[1-9][0-9]*$' then
    return new;
  end if;

  v_search_radius := v_search_radius_text::integer;

  insert into public.mission_dispatches (
    ride_id,
    provider_role,
    status,
    search_radius_meters,
    next_attempt_at
  )
  values (
    new.id,
    'courier',
    'pending',
    v_search_radius,
    clock_timestamp()
  )
  on conflict (ride_id, provider_role) do nothing;

  return new;
end;
$$;

drop trigger if exists corridas_enqueue_courier_dispatch
  on public.corridas;

create trigger corridas_enqueue_courier_dispatch
after update of status_corrida on public.corridas
for each row
execute function public.enqueue_courier_dispatch_after_driver_accept();

revoke all on function public.enqueue_courier_dispatch_after_driver_accept()
  from public, anon, authenticated;
