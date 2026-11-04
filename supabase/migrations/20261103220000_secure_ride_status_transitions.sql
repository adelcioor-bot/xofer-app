create or replace function public.rpc_advance_ride_status(
  p_ride_id uuid,
  p_next_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider_id uuid := auth.uid();
  v_ride public.corridas%rowtype;
begin
  if v_provider_id is null then
    raise exception 'É necessário iniciar sessão para avançar a corrida.'
      using errcode = '42501';
  end if;

  if p_ride_id is null or p_next_status is null then
    raise exception 'A próxima etapa da corrida é inválida.'
      using errcode = '22023';
  end if;

  select *
  into v_ride
  from public.corridas
  where id = p_ride_id
  for update;

  if not found or v_ride.encerrada then
    raise exception 'A corrida não está mais ativa.'
      using errcode = 'P0002';
  end if;

  if v_ride.driver_id = v_provider_id
     and (
       (v_ride.status_corrida::text = 'conduzindo_destino'
         and p_next_status = 'em_andamento')
       or
       (v_ride.status_corrida::text = 'em_andamento'
         and p_next_status = 'concluida')
     ) then
    null;
  elsif v_ride.motoboy_id = v_provider_id
     and (
       (v_ride.status_corrida::text = 'motoboy_a_caminho'
         and p_next_status = 'a_caminho_do_cliente')
       or
       (v_ride.status_corrida::text = 'a_caminho_do_cliente'
         and p_next_status = 'conduzindo_destino')
     ) then
    null;
  else
    raise exception 'A transição não é permitida para este parceiro ou etapa.'
      using errcode = '42501';
  end if;

  update public.corridas
  set status_corrida = p_next_status,
      encerrada = p_next_status = 'concluida',
      updated_at = clock_timestamp()
  where id = p_ride_id
  returning * into v_ride;

  return to_jsonb(v_ride);
end;
$$;

revoke all on function public.rpc_advance_ride_status(uuid, text)
  from public, anon;
grant execute on function public.rpc_advance_ride_status(uuid, text)
  to authenticated;
