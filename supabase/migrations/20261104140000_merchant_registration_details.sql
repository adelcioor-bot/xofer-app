alter table public.merchant_profiles
  add column legal_name text not null default '',
  add column postal_code text not null default '',
  add column street text not null default '',
  add column building_number text not null default '',
  add column district text not null default '',
  add column city text not null default '',
  add column state text not null default '',
  add column opening_time text,
  add column closing_time text,
  add column operating_days text[] not null default '{}',
  add column social_links text;

update public.merchant_profiles
set legal_name = business_name
where legal_name = '';

create or replace function public.rpc_register_merchant(
  p_business_name text,
  p_document text,
  p_phone text,
  p_address text,
  p_legal_name text,
  p_postal_code text,
  p_street text,
  p_building_number text,
  p_district text,
  p_city text,
  p_state text,
  p_opening_time text,
  p_closing_time text,
  p_operating_days text[],
  p_social_links text
)
returns public.merchant_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_signup_document text;
  v_merchant public.merchant_profiles%rowtype;
  v_rows integer;
begin
  if v_user_id is null then
    raise exception 'É necessário iniciar sessão para cadastrar o estabelecimento.'
      using errcode = '42501';
  end if;

  select
    lower(btrim(auth_user.email)),
    regexp_replace(
      coalesce(auth_user.raw_user_meta_data ->> 'merchant_document', ''),
      '\D',
      '',
      'g'
    )
  into v_email, v_signup_document
  from auth.users as auth_user
  where auth_user.id = v_user_id;

  if v_email is null or position('@' in v_email) < 2 then
    raise exception 'A conta autenticada precisa possuir um e-mail válido.'
      using errcode = '22023';
  end if;

  if p_business_name is null or length(btrim(p_business_name)) < 3
     or p_legal_name is null or length(btrim(p_legal_name)) < 3
     or p_document is null or p_document !~ '^[0-9]{14}$'
     or p_phone is null or length(btrim(p_phone)) < 8
     or p_address is null or length(btrim(p_address)) < 5
     or p_postal_code is null or p_postal_code !~ '^[0-9]{8}$'
     or p_street is null or length(btrim(p_street)) < 2
     or p_building_number is null or length(btrim(p_building_number)) = 0
     or p_district is null or length(btrim(p_district)) < 2
     or p_city is null or length(btrim(p_city)) < 2
     or p_state is null or length(btrim(p_state)) <> 2 then
    raise exception 'Os dados do estabelecimento são inválidos.'
      using errcode = '22023';
  end if;

  if (p_opening_time is null) <> (p_closing_time is null)
     or (p_opening_time is not null and (
       p_opening_time !~ '^([01][0-9]|2[0-3]):00$'
       or p_closing_time !~ '^([01][0-9]|2[0-3]):00$'
     )) then
    raise exception 'O horário de funcionamento é inválido.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_operating_days, '{}'::text[])) as days(day_name)
    where days.day_name not in (
      'segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo'
    )
  ) then
    raise exception 'Os dias de funcionamento são inválidos.'
      using errcode = '22023';
  end if;

  if v_signup_document <> '' and v_signup_document <> p_document then
    raise exception 'O CNPJ não corresponde ao informado na criação da conta.'
      using errcode = '22023';
  end if;

  insert into public.merchant_login_identifiers (user_id, document, email)
  values (v_user_id, p_document, v_email)
  on conflict (document) do update
    set email = excluded.email
    where merchant_login_identifiers.user_id = excluded.user_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'Este CNPJ já está vinculado a outra conta.'
      using errcode = '23505';
  end if;

  insert into public.merchant_profiles (
    user_id,
    business_name,
    document,
    email,
    phone,
    address,
    status,
    legal_name,
    postal_code,
    street,
    building_number,
    district,
    city,
    state,
    opening_time,
    closing_time,
    operating_days,
    social_links
  )
  values (
    v_user_id,
    btrim(p_business_name),
    p_document,
    v_email,
    btrim(p_phone),
    btrim(p_address),
    'active',
    btrim(p_legal_name),
    p_postal_code,
    btrim(p_street),
    btrim(p_building_number),
    btrim(p_district),
    btrim(p_city),
    upper(btrim(p_state)),
    p_opening_time,
    p_closing_time,
    coalesce(p_operating_days, '{}'::text[]),
    nullif(btrim(coalesce(p_social_links, '')), '')
  )
  on conflict (user_id) do update
    set business_name = excluded.business_name,
        document = excluded.document,
        email = excluded.email,
        phone = excluded.phone,
        address = excluded.address,
        legal_name = excluded.legal_name,
        postal_code = excluded.postal_code,
        street = excluded.street,
        building_number = excluded.building_number,
        district = excluded.district,
        city = excluded.city,
        state = excluded.state,
        opening_time = excluded.opening_time,
        closing_time = excluded.closing_time,
        operating_days = excluded.operating_days,
        social_links = excluded.social_links,
        updated_at = clock_timestamp()
  returning * into v_merchant;

  return v_merchant;
end;
$$;

revoke all on function public.rpc_register_merchant(
  text, text, text, text, text, text, text, text, text, text, text, text,
  text, text[], text
) from public, anon;
grant execute on function public.rpc_register_merchant(
  text, text, text, text, text, text, text, text, text, text, text, text,
  text, text[], text
) to authenticated;
