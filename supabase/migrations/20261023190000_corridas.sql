-- Corrida compartilhada entre motoboy e motorista. O app grava status_corrida
-- a cada avanço de fase e escuta a linha pelo Supabase Realtime.
--
-- status_corrida já é o enum status_corrida_enum. Os valores novos entram
-- nesse tipo. Este script não grava esses valores nas linhas existentes:
-- o Postgres só deixa usá-los depois que esta execução for confirmada.

alter type public.status_corrida_enum add value if not exists 'motoboy_a_caminho';
alter type public.status_corrida_enum add value if not exists 'a_caminho_do_cliente';
alter type public.status_corrida_enum add value if not exists 'conduzindo_destino';
alter type public.status_corrida_enum add value if not exists 'concluida';

create table if not exists public.corridas (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

alter table public.corridas add column if not exists call_id text;
alter table public.corridas add column if not exists status_corrida text;
alter table public.corridas add column if not exists origin text;
alter table public.corridas add column if not exists destination text;
alter table public.corridas add column if not exists origin_lat double precision;
alter table public.corridas add column if not exists origin_lng double precision;
alter table public.corridas add column if not exists dest_lat double precision;
alter table public.corridas add column if not exists dest_lng double precision;
alter table public.corridas add column if not exists partner_lat double precision;
alter table public.corridas add column if not exists partner_lng double precision;
alter table public.corridas add column if not exists driver_fare numeric;
alter table public.corridas add column if not exists accepted_by uuid;
alter table public.corridas add column if not exists accepted_role text;
alter table public.corridas add column if not exists created_at timestamptz default now();
alter table public.corridas add column if not exists updated_at timestamptz;
alter table public.corridas add column if not exists encerrada boolean not null default false;

alter table public.corridas alter column created_at set default now();
alter table public.corridas alter column updated_at set default now();

update public.corridas
set updated_at = coalesce(created_at, now())
where updated_at is null;

update public.corridas
set encerrada = true
where status_corrida::text = 'concluida';

do $$
begin
  alter table public.corridas
    add constraint corridas_accepted_role_check
    check (accepted_role is null or accepted_role in ('driver', 'courier'));
exception
  when duplicate_object then
    null;
end $$;

do $$
begin
  alter table public.corridas
    add constraint corridas_accepted_by_fkey
    foreign key (accepted_by) references auth.users (id) on delete set null;
exception
  when duplicate_object then
    null;
end $$;

create unique index if not exists corridas_open_call_key
  on public.corridas (call_id)
  where encerrada = false;

alter table public.corridas replica identity full;

alter table public.corridas enable row level security;

drop policy if exists "corridas_select_authenticated" on public.corridas;
create policy "corridas_select_authenticated"
  on public.corridas
  for select
  to authenticated
  using (true);

drop policy if exists "corridas_insert_own" on public.corridas;
create policy "corridas_insert_own"
  on public.corridas
  for insert
  to authenticated
  with check (auth.uid() = accepted_by);

drop policy if exists "corridas_update_authenticated" on public.corridas;
create policy "corridas_update_authenticated"
  on public.corridas
  for update
  to authenticated
  using (true)
  with check (true);

grant select, insert, update on public.corridas to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.corridas;
exception
  when duplicate_object then
    null;
  when undefined_object then
    null;
end $$;
