alter table public.corridas
  add column if not exists codigo_reserva text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'corridas_codigo_reserva_format_check'
      and conrelid = 'public.corridas'::regclass
  ) then
    alter table public.corridas
      add constraint corridas_codigo_reserva_format_check
      check (codigo_reserva is null or codigo_reserva ~ '^[0-9]{4}$');
  end if;
end $$;
