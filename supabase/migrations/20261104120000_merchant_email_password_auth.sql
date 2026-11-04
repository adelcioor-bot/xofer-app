alter table public.merchant_profiles
  add column email text;

update public.merchant_profiles as merchant
set email = lower(btrim(auth_user.email))
from auth.users as auth_user
where auth_user.id = merchant.user_id
  and auth_user.email is not null
  and btrim(auth_user.email) <> '';

create unique index merchant_profiles_email_key
  on public.merchant_profiles (lower(email))
  where email is not null;

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
  v_email text;
  v_merchant public.merchant_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'É necessário iniciar sessão para cadastrar o estabelecimento.'
      using errcode = '42501';
  end if;

  select lower(btrim(auth_user.email))
  into v_email
  from auth.users as auth_user
  where auth_user.id = v_user_id;

  if v_email is null or position('@' in v_email) < 2 then
    raise exception 'A conta autenticada precisa possuir um e-mail válido.'
      using errcode = '22023';
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
    email,
    phone,
    address,
    status
  )
  values (
    v_user_id,
    btrim(p_business_name),
    p_document,
    v_email,
    btrim(p_phone),
    btrim(p_address),
    'active'
  )
  on conflict (user_id) do update
    set business_name = excluded.business_name,
        document = excluded.document,
        email = excluded.email,
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
