create table public.merchant_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  business_name text not null,
  document text not null,
  phone text not null,
  address text not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint merchant_profiles_business_name_check
    check (length(btrim(business_name)) >= 3),
  constraint merchant_profiles_document_check
    check (document ~ '^[0-9]{14}$'),
  constraint merchant_profiles_phone_check
    check (length(btrim(phone)) >= 8),
  constraint merchant_profiles_address_check
    check (length(btrim(address)) >= 5),
  constraint merchant_profiles_status_check
    check (status in ('active', 'suspended'))
);

create unique index merchant_profiles_document_key
  on public.merchant_profiles (document);

alter table public.merchant_profiles enable row level security;

create policy merchant_profiles_select_own
  on public.merchant_profiles
  for select
  to authenticated
  using (user_id = auth.uid());

revoke all on public.merchant_profiles from anon, authenticated;
grant select on public.merchant_profiles to authenticated;

alter table public.corridas
  add column requester_type text not null default 'customer',
  add column service_type text not null default 'rescue',
  add column payment_status text;

alter table public.corridas
  add constraint corridas_requester_type_check
    check (requester_type in ('customer', 'merchant')),
  add constraint corridas_service_type_check
    check (service_type in ('rescue', 'delivery')),
  add constraint corridas_payment_status_check
    check (
      payment_status is null
      or payment_status in (
        'not_configured',
        'pending',
        'authorized',
        'paid',
        'failed',
        'refunded'
      )
    );

drop policy if exists "corridas_select_authenticated" on public.corridas;
create policy corridas_select_participants
  on public.corridas
  for select
  to authenticated
  using (
    requested_by = auth.uid()
    or driver_id = auth.uid()
    or motoboy_id = auth.uid()
    or accepted_by = auth.uid()
  );

drop policy if exists "corridas_update_authenticated" on public.corridas;
create policy corridas_update_participants
  on public.corridas
  for update
  to authenticated
  using (
    (requested_by = auth.uid() and requester_type = 'customer')
    or driver_id = auth.uid()
    or motoboy_id = auth.uid()
    or accepted_by = auth.uid()
  )
  with check (
    (requested_by = auth.uid() and requester_type = 'customer')
    or driver_id = auth.uid()
    or motoboy_id = auth.uid()
    or accepted_by = auth.uid()
  );

drop policy if exists "corridas_insert_own" on public.corridas;
create policy corridas_insert_provider_owned
  on public.corridas
  for insert
  to authenticated
  with check (
    requested_by is null
    and accepted_by = auth.uid()
    and accepted_role in ('driver', 'courier')
    and exists (
      select 1
      from public.providers as provider
      where provider.id = auth.uid()
        and provider.role = accepted_role
        and provider.status_sistema = 'ativo'
    )
  );

create or replace function public.rpc_register_merchant(
  p_business_name text,
  p_document text,
  p_phone text,
  p_address text
)
returns public.merchant_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_merchant public.merchant_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'É necessário iniciar sessão para cadastrar o estabelecimento.'
      using errcode = '42501';
  end if;

  if p_business_name is null or length(btrim(p_business_name)) < 3
     or p_document is null or p_document !~ '^[0-9]{14}$'
     or p_phone is null or length(btrim(p_phone)) < 8
     or p_address is null or length(btrim(p_address)) < 5 then
    raise exception 'Os dados do estabelecimento são inválidos.'
      using errcode = '22023';
  end if;

  insert into public.merchant_profiles (
    user_id,
    business_name,
    document,
    phone,
    address,
    status
  )
  values (
    v_user_id,
    btrim(p_business_name),
    p_document,
    btrim(p_phone),
    btrim(p_address),
    'active'
  )
  on conflict (user_id) do update
    set business_name = excluded.business_name,
        document = excluded.document,
        phone = excluded.phone,
        address = excluded.address,
        updated_at = clock_timestamp()
  returning * into v_merchant;

  return v_merchant;
end;
$$;

revoke all on function public.rpc_register_merchant(text, text, text, text)
  from public, anon;
grant execute on function public.rpc_register_merchant(text, text, text, text)
  to authenticated;

create or replace function public.guard_merchant_ride_quote()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.requester_type = 'merchant'
     and not exists (
       select 1
       from public.merchant_profiles as merchant
       where merchant.user_id = new.requester_id
         and merchant.status = 'active'
     ) then
    raise exception 'O estabelecimento precisa ter cadastro ativo para cotar.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists ride_quotes_merchant_guard on public.ride_quotes;
create trigger ride_quotes_merchant_guard
before insert on public.ride_quotes
for each row
execute function public.guard_merchant_ride_quote();

revoke all on function public.guard_merchant_ride_quote()
  from public, anon, authenticated;

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
    and quote.requester_type in ('customer', 'merchant')
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

create or replace function public.rpc_create_merchant_ride_dispatch(
  p_call_id text,
  p_origin text,
  p_destination text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_dest_lat double precision,
  p_dest_lng double precision,
  p_quote_id uuid,
  p_amount_cents bigint,
  p_service_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_user_id uuid := auth.uid();
  v_quote public.ride_quotes%rowtype;
  v_provider_role text;
  v_initial_status text;
  v_radius integer;
  v_ride public.corridas%rowtype;
  v_dispatch_id uuid;
begin
  if v_user_id is null
     or not exists (
       select 1
       from public.merchant_profiles as merchant
       where merchant.user_id = v_user_id
         and merchant.status = 'active'
     ) then
    raise exception 'É necessário ter um cadastro ativo de estabelecimento.'
      using errcode = '42501';
  end if;

  if p_service_type is null
     or p_service_type not in ('delivery', 'rescue') then
    raise exception 'O tipo de chamado do estabelecimento é inválido.'
      using errcode = '22023';
  end if;

  if p_call_id is null or length(btrim(p_call_id)) = 0
     or length(p_call_id) > 100
     or p_origin is null or length(btrim(p_origin)) = 0
     or p_destination is null or length(btrim(p_destination)) = 0
     or p_origin_lat is null or p_origin_lng is null
     or p_dest_lat is null or p_dest_lng is null
     or p_origin_lat not between -90 and 90
     or p_dest_lat not between -90 and 90
     or p_origin_lng not between -180 and 180
     or p_dest_lng not between -180 and 180 then
    raise exception 'Os dados do chamado são inválidos.'
      using errcode = '22023';
  end if;

  if p_quote_id is null or p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'A cotação do chamado é inválida.'
      using errcode = '22023';
  end if;

  select quote.*
  into v_quote
  from public.ride_quotes as quote
  where quote.id = p_quote_id
    and quote.requester_id = v_user_id
    and quote.requester_type = 'merchant'
    and quote.status = 'pending'
    and quote.ride_id is null
    and quote.expires_at > v_now
    and quote.amount_cents = p_amount_cents
    and quote.pricing_snapshot->>'provider_search_radius_meters'
      ~ '^[1-9][0-9]*$'
    and extensions.ST_DWithin(
      quote.origin,
      extensions.ST_SetSRID(
        extensions.ST_MakePoint(p_origin_lng, p_origin_lat),
        4326
      )::extensions.geography,
      1
    )
    and extensions.ST_DWithin(
      quote.destination,
      extensions.ST_SetSRID(
        extensions.ST_MakePoint(p_dest_lng, p_dest_lat),
        4326
      )::extensions.geography,
      1
    )
  for update of quote;

  if not found then
    raise exception 'A cotação expirou ou não corresponde a este chamado.'
      using errcode = 'P0001';
  end if;

  v_radius :=
    (v_quote.pricing_snapshot->>'provider_search_radius_meters')::integer;
  if v_radius < 1 then
    raise exception 'A cotação não contém um raio de despacho válido.'
      using errcode = '22023';
  end if;

  if p_service_type = 'delivery' then
    v_provider_role := 'courier';
    v_initial_status := 'procurando_motoboy';
  else
    v_provider_role := 'driver';
    v_initial_status := 'buscando_prestadores';
  end if;

  insert into public.corridas (
    call_id,
    status_corrida,
    origin,
    destination,
    origin_lat,
    origin_lng,
    dest_lat,
    dest_lng,
    partner_lat,
    partner_lng,
    valor_total,
    driver_fare,
    requested_by,
    requester_type,
    service_type,
    payment_status,
    accepted_by,
    accepted_role,
    motoboy_id,
    encerrada,
    updated_at
  )
  values (
    btrim(p_call_id),
    v_initial_status::public.status_corrida_enum,
    btrim(p_origin),
    btrim(p_destination),
    p_origin_lat,
    p_origin_lng,
    p_dest_lat,
    p_dest_lng,
    case when p_service_type = 'delivery' then p_origin_lat else null end,
    case when p_service_type = 'delivery' then p_origin_lng else null end,
    p_amount_cents::numeric / 100,
    p_amount_cents::numeric / 100,
    v_user_id,
    'merchant',
    p_service_type,
    'not_configured',
    null,
    null,
    null,
    false,
    v_now
  )
  returning * into v_ride;

  update public.ride_quotes
  set ride_id = v_ride.id,
      status = 'used',
      updated_at = v_now
  where id = v_quote.id
    and ride_id is null
    and status = 'pending';

  if not found then
    raise exception 'A cotação já foi associada a outro chamado.'
      using errcode = 'P0001';
  end if;

  insert into public.mission_dispatches (
    ride_id,
    provider_role,
    status,
    search_radius_meters,
    next_attempt_at
  )
  values (
    v_ride.id,
    v_provider_role,
    'pending',
    v_radius,
    v_now
  )
  returning id into v_dispatch_id;

  return jsonb_build_object(
    'ride', to_jsonb(v_ride),
    'dispatch_id', v_dispatch_id
  );
end;
$$;

revoke all on function public.rpc_create_merchant_ride_dispatch(
  text, text, text, double precision, double precision, double precision,
  double precision, uuid, bigint, text
) from public, anon;
grant execute on function public.rpc_create_merchant_ride_dispatch(
  text, text, text, double precision, double precision, double precision,
  double precision, uuid, bigint, text
) to authenticated;

create or replace function public.rpc_respond_to_mission(
  p_attempt_id uuid,
  p_provider_id uuid,
  p_response text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_authenticated_provider uuid := auth.uid();
  v_dispatch_id uuid;
  v_ride_id uuid;
  v_role text;
  v_dispatch_round integer;
  v_attempt_provider uuid;
  v_attempt_role text;
  v_attempt_round integer;
  v_attempt_status text;
  v_expires_at timestamptz;
  v_now timestamptz;
  v_lat double precision;
  v_lng double precision;
  v_is_merchant_delivery boolean;
  v_updated_ride_id uuid;
begin
  if v_authenticated_provider is null
     or p_provider_id is null
     or v_authenticated_provider <> p_provider_id then
    raise exception 'O parceiro informado não corresponde à sessão autenticada.'
      using errcode = '42501';
  end if;

  if p_response is null or p_response not in ('accepted', 'declined') then
    raise exception 'Resposta inválida para a missão.'
      using errcode = '22023';
  end if;

  select attempt.dispatch_id
  into v_dispatch_id
  from public.dispatch_attempts as attempt
  where attempt.id = p_attempt_id
    and attempt.provider_id = p_provider_id;

  if v_dispatch_id is null then
    raise exception 'Tentativa de missão não encontrada.'
      using errcode = 'P0002';
  end if;

  select
    dispatch.ride_id,
    dispatch.provider_role,
    dispatch.round_no,
    ride.requester_type = 'merchant' and ride.service_type = 'delivery'
  into
    v_ride_id,
    v_role,
    v_dispatch_round,
    v_is_merchant_delivery
  from public.mission_dispatches as dispatch
  join public.corridas as ride on ride.id = dispatch.ride_id
  where dispatch.id = v_dispatch_id
  for update of dispatch;

  if v_ride_id is null then
    raise exception 'Despacho não encontrado.'
      using errcode = 'P0002';
  end if;

  select
    attempt.provider_id,
    attempt.provider_role,
    attempt.round_no,
    attempt.status,
    attempt.expires_at
  into
    v_attempt_provider,
    v_attempt_role,
    v_attempt_round,
    v_attempt_status,
    v_expires_at
  from public.dispatch_attempts as attempt
  where attempt.id = p_attempt_id
    and attempt.dispatch_id = v_dispatch_id
  for update;

  if not found then
    raise exception 'Tentativa de missão não encontrada.'
      using errcode = 'P0002';
  end if;

  v_now := clock_timestamp();
  if v_attempt_provider <> p_provider_id
     or v_attempt_role <> v_role
     or v_attempt_round <> v_dispatch_round
     or v_attempt_status <> 'offered'
     or v_expires_at <= v_now then
    raise exception 'A oferta já expirou ou não está mais disponível.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.providers as provider
    where provider.id = p_provider_id
      and provider.role = v_role
      and provider.status_sistema = 'ativo'
  ) then
    raise exception 'O parceiro não está ativo para aceitar missões.'
      using errcode = '42501';
  end if;

  if p_response = 'declined' then
    update public.dispatch_attempts
    set status = 'declined',
        responded_at = v_now
    where id = p_attempt_id
      and status = 'offered'
      and expires_at > v_now;

    if not found then
      raise exception 'A oferta expirou ou já recebeu uma resposta.'
        using errcode = 'P0001';
    end if;

    update public.mission_dispatches
    set status = 'pending',
        next_attempt_at = v_now,
        updated_at = v_now
    where id = v_dispatch_id
      and status = 'dispatching';

    return jsonb_build_object(
      'status', 'declined',
      'dispatch_id', v_dispatch_id,
      'attempt_id', p_attempt_id
    );
  end if;

  select
    extensions.ST_Y(presence.location::extensions.geometry),
    extensions.ST_X(presence.location::extensions.geometry)
  into v_lat, v_lng
  from public.provider_presence as presence
  where presence.provider_id = p_provider_id
    and presence.provider_role = v_role
  for update;

  if not found or v_lat is null or v_lng is null then
    raise exception 'A localização atual do parceiro não está disponível.'
      using errcode = 'P0001';
  end if;

  update public.dispatch_attempts
  set status = 'accepted',
      responded_at = v_now
  where id = p_attempt_id
    and status = 'offered'
    and expires_at > v_now;

  if not found then
    raise exception 'A oferta expirou ou já recebeu uma resposta.'
      using errcode = 'P0001';
  end if;

  update public.mission_dispatches
  set status = 'accepted',
      accepted_by = p_provider_id,
      accepted_role = v_role,
      accepted_at = v_now,
      next_attempt_at = null,
      updated_at = v_now
  where id = v_dispatch_id
    and status = 'dispatching';

  if not found then
    raise exception 'O despacho não está mais disponível para aceite.'
      using errcode = 'P0001';
  end if;

  if v_role = 'driver' then
    update public.corridas
    set driver_id = p_provider_id,
        partner_lat = v_lat,
        partner_lng = v_lng,
        accepted_by = p_provider_id,
        accepted_role = 'driver',
        status_corrida = 'procurando_motoboy',
        updated_at = v_now
    where id = v_ride_id
      and status_corrida::text = 'buscando_prestadores'
      and accepted_by is null
      and driver_id is null
      and encerrada = false
    returning id into v_updated_ride_id;
  else
    update public.corridas
    set motoboy_id = p_provider_id,
        motoboy_lat = v_lat,
        motoboy_lng = v_lng,
        accepted_by = p_provider_id,
        accepted_role = 'courier',
        status_corrida = 'motoboy_a_caminho',
        updated_at = v_now
    where id = v_ride_id
      and status_corrida::text = 'procurando_motoboy'
      and (
        driver_id is not null
        or v_is_merchant_delivery
      )
      and motoboy_id is null
      and encerrada = false
    returning id into v_updated_ride_id;
  end if;

  if v_updated_ride_id is null then
    raise exception 'O estado da corrida mudou antes do aceite.'
      using errcode = 'P0001';
  end if;

  update public.provider_presence
  set is_available = false,
      updated_at = v_now
  where provider_id = p_provider_id
    and provider_role = v_role;

  return jsonb_build_object(
    'status', 'accepted',
    'dispatch_id', v_dispatch_id,
    'attempt_id', p_attempt_id,
    'ride_id', v_ride_id,
    'provider_role', v_role
  );
end;
$$;

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
  v_is_merchant_delivery boolean;
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

  v_is_merchant_delivery :=
    v_ride.requester_type = 'merchant'
    and v_ride.service_type = 'delivery';

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
       or
       (v_is_merchant_delivery
         and v_ride.status_corrida::text = 'conduzindo_destino'
         and p_next_status = 'concluida')
       or
       (v_is_merchant_delivery
         and v_ride.status_corrida::text = 'a_caminho_do_cliente'
         and p_next_status = 'concluida')
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

revoke all on function public.rpc_respond_to_mission(uuid, uuid, text)
  from public, anon;
grant execute on function public.rpc_respond_to_mission(uuid, uuid, text)
  to authenticated;

revoke all on function public.rpc_advance_ride_status(uuid, text)
  from public, anon;
grant execute on function public.rpc_advance_ride_status(uuid, text)
  to authenticated;
