create table public.merchant_login_identifiers (
  user_id uuid primary key references auth.users (id) on delete cascade,
  document text not null unique,
  email text not null,
  created_at timestamptz not null default now(),
  constraint merchant_login_identifiers_document_check
    check (document ~ '^[0-9]{14}$'),
  constraint merchant_login_identifiers_email_check
    check (position('@' in email) > 1)
);

alter table public.merchant_login_identifiers enable row level security;
revoke all on public.merchant_login_identifiers from public, anon, authenticated;
grant select on public.merchant_login_identifiers to service_role;

insert into public.merchant_login_identifiers (user_id, document, email)
select
  merchant.user_id,
  merchant.document,
  lower(btrim(merchant.email))
from public.merchant_profiles as merchant
where merchant.email is not null
  and btrim(merchant.email) <> ''
on conflict (document) do nothing;

create or replace function public.capture_merchant_signup_identifier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_document text := regexp_replace(
    coalesce(new.raw_user_meta_data ->> 'merchant_document', ''),
    '\D',
    '',
    'g'
  );
  v_email text := lower(btrim(coalesce(new.email, '')));
begin
  if v_document = '' then
    return new;
  end if;

  if v_document !~ '^[0-9]{14}$'
     or v_email = ''
     or position('@' in v_email) < 2 then
    raise exception 'Dados de acesso do estabelecimento inválidos.'
      using errcode = '22023';
  end if;

  insert into public.merchant_login_identifiers (user_id, document, email)
  values (new.id, v_document, v_email);

  return new;
end;
$$;

create trigger auth_user_capture_merchant_identifier
after insert on auth.users
for each row
execute function public.capture_merchant_signup_identifier();

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
     or p_document is null or p_document !~ '^[0-9]{14}$'
     or p_phone is null or length(btrim(p_phone)) < 8
     or p_address is null or length(btrim(p_address)) < 5 then
    raise exception 'Os dados do estabelecimento são inválidos.'
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
