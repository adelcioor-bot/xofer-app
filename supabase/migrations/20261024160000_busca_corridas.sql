alter table public.corridas
  add column if not exists requested_by uuid
  references auth.users (id) on delete set null;

alter table public.corridas
  add column if not exists motoboy_id uuid
  references auth.users (id) on delete set null;

alter table public.corridas
  add column if not exists valor_total numeric;

alter table public.corridas
  add column if not exists distancia_resgate_km numeric;

alter table public.corridas
  alter column valor_total drop not null;

alter table public.corridas
  alter column accepted_by drop not null,
  alter column motoboy_id drop not null;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'corridas'
      and column_name = 'origem_coordenadas'
  ) then
    alter table public.corridas
      alter column origem_coordenadas drop not null;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'corridas'
      and column_name = 'destino_coordenadas'
  ) then
    alter table public.corridas
      alter column destino_coordenadas drop not null;
  end if;
end $$;

create index if not exists corridas_busca_disponiveis_idx
  on public.corridas (created_at desc)
  where status_corrida = 'buscando_prestadores'
    and encerrada = false
    and accepted_by is null
    and motoboy_id is null;

create index if not exists corridas_resgate_disponivel_idx
  on public.corridas (updated_at desc)
  where status_corrida = 'procurando_motoboy'
    and encerrada = false
    and accepted_by is not null
    and motoboy_id is null;

drop policy if exists "corridas_insert_own" on public.corridas;
create policy "corridas_insert_own"
  on public.corridas
  for insert
  to authenticated
  with check (
    auth.uid() = requested_by
    or (accepted_by is not null and auth.uid() = accepted_by)
  );

drop policy if exists "corridas_update_authenticated" on public.corridas;
create policy "corridas_update_authenticated"
  on public.corridas
  for update
  to authenticated
  using (
    auth.uid() = requested_by
    or auth.uid() = accepted_by
    or auth.uid() = motoboy_id
    or (
      status_corrida = 'buscando_prestadores'
      and accepted_by is null
      and motoboy_id is null
    )
    or (
      status_corrida = 'procurando_motoboy'
      and accepted_by is not null
      and motoboy_id is null
    )
  )
  with check (
    auth.uid() = requested_by
    or auth.uid() = accepted_by
    or auth.uid() = motoboy_id
    or (
      status_corrida = 'buscando_prestadores'
      and accepted_by is null
      and motoboy_id is null
    )
    or (
      status_corrida = 'procurando_motoboy'
      and accepted_by is not null
      and motoboy_id is null
    )
  );
