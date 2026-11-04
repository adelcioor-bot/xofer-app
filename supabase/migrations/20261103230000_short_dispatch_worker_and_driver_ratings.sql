create or replace function public.rpc_run_dispatch_worker_window()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_processed integer := 0;
begin
  if not pg_try_advisory_lock(811, 34781) then
    return;
  end if;

  begin
    perform public.rpc_expire_stale_attempts(100);

    while v_processed < 25 loop
      v_result := public.rpc_process_next_dispatch_attempt();
      exit when v_result is null;
      v_processed := v_processed + 1;
    end loop;
  exception
    when others then
      perform pg_advisory_unlock(811, 34781);
      raise;
  end;

  perform pg_advisory_unlock(811, 34781);
end;
$$;

create table if not exists public.driver_ride_ratings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null unique
    references public.corridas (id) on delete cascade,
  customer_id uuid not null references auth.users (id) on delete cascade,
  driver_id uuid not null references auth.users (id) on delete restrict,
  stars smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default clock_timestamp()
);

alter table public.driver_ride_ratings enable row level security;

drop policy if exists driver_ride_ratings_select_customer
  on public.driver_ride_ratings;
create policy driver_ride_ratings_select_customer
  on public.driver_ride_ratings
  for select
  to authenticated
  using (customer_id = (select auth.uid()));

revoke all on public.driver_ride_ratings from public, anon, authenticated;
grant select on public.driver_ride_ratings to authenticated;

create or replace function public.rpc_rate_completed_driver(
  p_ride_id uuid,
  p_stars integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid := auth.uid();
  v_driver_id uuid;
  v_rating public.driver_ride_ratings%rowtype;
begin
  if v_customer_id is null then
    raise exception 'É necessário iniciar sessão para avaliar a corrida.'
      using errcode = '42501';
  end if;

  if p_ride_id is null or p_stars is null or p_stars not between 1 and 5 then
    raise exception 'Selecione uma avaliação entre 1 e 5 estrelas.'
      using errcode = '22023';
  end if;

  select ride.driver_id
  into v_driver_id
  from public.corridas as ride
  where ride.id = p_ride_id
    and ride.requested_by = v_customer_id
    and ride.status_corrida::text = 'concluida'
    and ride.encerrada = true
    and ride.driver_id is not null;

  if v_driver_id is null then
    raise exception 'A corrida não foi concluída ou não pertence a este cliente.'
      using errcode = '42501';
  end if;

  insert into public.driver_ride_ratings (
    ride_id,
    customer_id,
    driver_id,
    stars
  )
  values (
    p_ride_id,
    v_customer_id,
    v_driver_id,
    p_stars::smallint
  )
  on conflict (ride_id) do nothing
  returning * into v_rating;

  if not found then
    select *
    into v_rating
    from public.driver_ride_ratings
    where ride_id = p_ride_id
      and customer_id = v_customer_id;

    if not found then
      raise exception 'Esta corrida já recebeu uma avaliação.'
        using errcode = '23505';
    end if;
  end if;

  return jsonb_build_object(
    'ride_id', v_rating.ride_id,
    'stars', v_rating.stars,
    'created_at', v_rating.created_at
  );
end;
$$;

revoke all on function public.rpc_rate_completed_driver(uuid, integer)
  from public, anon;
grant execute on function public.rpc_rate_completed_driver(uuid, integer)
  to authenticated;
