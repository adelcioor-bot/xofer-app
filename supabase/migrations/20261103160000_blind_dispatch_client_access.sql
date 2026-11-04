-- Authenticated partners may receive only their own dispatch-attempt events.
drop policy if exists dispatch_attempts_select_own
  on public.dispatch_attempts;

create policy dispatch_attempts_select_own
  on public.dispatch_attempts
  for select
  to authenticated
  using (provider_id = (select auth.uid()));

grant select on table public.dispatch_attempts to authenticated;

do $$
begin
  alter publication supabase_realtime
    add table public.dispatch_attempts;
exception
  when duplicate_object then null;
end
$$;

create or replace function public.rpc_update_provider_presence(
  p_provider_role text,
  p_lat double precision,
  p_lng double precision,
  p_is_available boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider_id uuid := auth.uid();
begin
  if v_provider_id is null then
    raise exception 'Sessão autenticada obrigatória.'
      using errcode = '42501';
  end if;

  if p_provider_role is null
     or p_provider_role not in ('driver', 'courier')
     or p_is_available is null then
    raise exception 'Dados de localização ou disponibilidade inválidos.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.providers as provider
    where provider.id = v_provider_id
      and provider.role = p_provider_role
  ) then
    raise exception 'Cadastro de parceiro não encontrado.'
      using errcode = '42501';
  end if;

  if not p_is_available then
    update public.provider_presence
    set is_available = false,
        last_seen_at = clock_timestamp(),
        updated_at = clock_timestamp()
    where provider_id = v_provider_id
      and provider_role = p_provider_role;
    return;
  end if;

  if p_lat is null
     or p_lng is null
     or p_lat not between -90 and 90
     or p_lng not between -180 and 180 then
    raise exception 'Coordenadas de localização inválidas.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.providers as provider
    where provider.id = v_provider_id
      and provider.role = p_provider_role
      and provider.status_sistema = 'ativo'
  ) then
    raise exception 'Parceiro não está ativo para receber missões.'
      using errcode = '42501';
  end if;

  insert into public.provider_presence (
    provider_id,
    provider_role,
    location,
    is_available,
    last_seen_at,
    updated_at
  )
  values (
    v_provider_id,
    p_provider_role,
    extensions.ST_SetSRID(
      extensions.ST_MakePoint(p_lng, p_lat),
      4326
    )::extensions.geography,
    p_is_available,
    clock_timestamp(),
    clock_timestamp()
  )
  on conflict (provider_id, provider_role)
  do update set
    location = excluded.location,
    is_available = excluded.is_available,
    last_seen_at = excluded.last_seen_at,
    updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.rpc_update_provider_presence(
  text,
  double precision,
  double precision,
  boolean
) from public, anon;

grant execute on function public.rpc_update_provider_presence(
  text,
  double precision,
  double precision,
  boolean
) to authenticated;
