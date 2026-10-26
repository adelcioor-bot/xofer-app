-- Oferta de resgate: o motorista abre a corrida sem motoboy.
-- O aceite do motoboy preenche motoboy_id. O valor novo do enum
-- só pode ser gravado numa execução seguinte a esta.

alter type public.status_corrida_enum add value if not exists 'procurando_motoboy';

alter table public.corridas add column if not exists driver_label text;
alter table public.corridas add column if not exists ganho_resgate numeric;
alter table public.corridas add column if not exists motoboy_id uuid;
alter table public.corridas add column if not exists motoboy_nome text;
alter table public.corridas add column if not exists eta_minutos integer;
alter table public.corridas add column if not exists motoboy_lat double precision;
alter table public.corridas add column if not exists motoboy_lng double precision;

do $$
begin
  alter table public.corridas
    add constraint corridas_motoboy_id_fkey
    foreign key (motoboy_id) references auth.users (id) on delete set null;
exception
  when duplicate_object then
    null;
end $$;
