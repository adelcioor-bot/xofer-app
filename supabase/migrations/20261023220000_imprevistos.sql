-- Imprevisto do motoboy. Dentro de 3 minutos a corrida volta à fila.
-- Depois disso o app grava o motivo, a foto e avisa o Make.com.

create table if not exists public.imprevistos (
  id uuid primary key default gen_random_uuid(),
  corrida_id uuid references public.corridas (id) on delete cascade,
  motoboy_id uuid,
  motivo text not null,
  penalizado boolean not null default true,
  foto_path text,
  aceite_em timestamptz not null,
  reportado_em timestamptz not null default now(),
  webhook_enviado boolean not null default false
);

create unique index if not exists imprevistos_corrida_motoboy_key
  on public.imprevistos (corrida_id, motoboy_id);

alter table public.imprevistos enable row level security;

drop policy if exists "imprevistos_select_own" on public.imprevistos;
create policy "imprevistos_select_own"
  on public.imprevistos
  for select
  to authenticated
  using (motoboy_id = auth.uid());

drop policy if exists "imprevistos_insert_own" on public.imprevistos;
create policy "imprevistos_insert_own"
  on public.imprevistos
  for insert
  to authenticated
  with check (motoboy_id = auth.uid());

drop policy if exists "imprevistos_update_own" on public.imprevistos;
create policy "imprevistos_update_own"
  on public.imprevistos
  for update
  to authenticated
  using (motoboy_id = auth.uid())
  with check (motoboy_id = auth.uid());

grant select, insert, update on public.imprevistos to authenticated;

alter table public.corridas add column if not exists aceite_em timestamptz;
