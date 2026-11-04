-- Provider wallet, immutable ledger, Pix payout methods, and withdrawals.
-- balance_cents is the sum of ledger amounts. A withdrawal_hold is a negative
-- ledger entry, so it already reduces balance_cents; held_cents tracks the
-- pending portion for reconciliation and must not be subtracted a second time
-- when calculating spendable balance.

do $$
begin
  create type public.provider_wallet_entry_type as enum (
    'mission_credit',
    'refusal_penalty',
    'withdrawal_hold',
    'withdrawal_release',
    'withdrawal_paid',
    'adjustment'
  );
exception
  when duplicate_object then
    null;
end
$$;

create table public.provider_wallet_accounts (
  provider_id uuid not null,
  provider_role text not null,
  balance_cents bigint not null default 0,
  held_cents bigint not null default 0,
  minimum_retained_cents bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider_id, provider_role),
  constraint provider_wallet_accounts_provider_role_check check (
    provider_role in ('driver', 'courier')
  ),
  constraint provider_wallet_accounts_provider_fkey
    foreign key (provider_id, provider_role)
    references public.providers (id, role)
    on delete restrict,
  constraint provider_wallet_accounts_held_nonnegative check (held_cents >= 0),
  constraint provider_wallet_accounts_minimum_nonnegative check (
    minimum_retained_cents >= 0
  )
);

create table public.provider_payout_methods (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null,
  provider_role text not null,
  pix_key_type text not null,
  pix_key_reference text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_payout_methods_provider_role_check check (
    provider_role in ('driver', 'courier')
  ),
  constraint provider_payout_methods_provider_fkey
    foreign key (provider_id, provider_role)
    references public.providers (id, role)
    on delete restrict,
  constraint provider_payout_methods_key_type_check check (
    pix_key_type in ('cpf', 'cnpj', 'email', 'phone', 'random')
  ),
  constraint provider_payout_methods_reference_not_blank check (
    length(btrim(pix_key_reference)) > 0
  ),
  constraint provider_payout_methods_status_check check (
    status in ('pending', 'active', 'revoked')
  ),
  constraint provider_payout_methods_id_owner_key
    unique (id, provider_id, provider_role)
);

create unique index provider_payout_methods_one_active_idx
  on public.provider_payout_methods (provider_id, provider_role)
  where status = 'active';

comment on column public.provider_payout_methods.pix_key_reference is
  'Encrypted Pix key or token from the payout provider; never store the raw key or a non-reversible hash when payout execution requires retrieval.';

create table public.provider_withdrawals (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null,
  provider_role text not null,
  payout_method_id uuid not null,
  amount_cents bigint not null,
  status text not null default 'pending',
  idempotency_key text not null unique,
  provider_transfer_reference text,
  failure_reason text,
  requested_at timestamptz not null default now(),
  processing_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint provider_withdrawals_provider_role_check check (
    provider_role in ('driver', 'courier')
  ),
  constraint provider_withdrawals_provider_fkey
    foreign key (provider_id, provider_role)
    references public.providers (id, role)
    on delete restrict,
  constraint provider_withdrawals_payout_method_fkey
    foreign key (payout_method_id, provider_id, provider_role)
    references public.provider_payout_methods (id, provider_id, provider_role)
    on delete restrict,
  constraint provider_withdrawals_amount_positive check (amount_cents > 0),
  constraint provider_withdrawals_status_check check (
    status in ('pending', 'processing', 'completed', 'failed')
  ),
  constraint provider_withdrawals_idempotency_not_blank check (
    length(btrim(idempotency_key)) > 0
  )
);

create index provider_withdrawals_provider_history_idx
  on public.provider_withdrawals (provider_id, provider_role, requested_at desc);

create index provider_withdrawals_pending_idx
  on public.provider_withdrawals (requested_at)
  where status in ('pending', 'processing');

create table public.provider_wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null,
  provider_role text not null,
  ride_id uuid,
  dispatch_attempt_id uuid,
  withdrawal_id uuid,
  type public.provider_wallet_entry_type not null,
  amount_cents bigint not null,
  idempotency_key text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint provider_wallet_ledger_provider_fkey
    foreign key (provider_id, provider_role)
    references public.providers (id, role)
    on delete restrict,
  constraint provider_wallet_ledger_ride_fkey
    foreign key (ride_id) references public.corridas (id)
    on delete restrict,
  constraint provider_wallet_ledger_attempt_fkey
    foreign key (dispatch_attempt_id) references public.dispatch_attempts (id)
    on delete restrict,
  constraint provider_wallet_ledger_withdrawal_fkey
    foreign key (withdrawal_id) references public.provider_withdrawals (id)
    on delete restrict,
  constraint provider_wallet_ledger_role_check check (
    provider_role in ('driver', 'courier')
  ),
  constraint provider_wallet_ledger_amount_sign_check check (
    (type in ('mission_credit', 'withdrawal_release') and amount_cents > 0)
    or (type in ('refusal_penalty', 'withdrawal_hold') and amount_cents < 0)
    or (type = 'withdrawal_paid' and amount_cents = 0)
    or (type = 'adjustment' and amount_cents <> 0)
  ),
  constraint provider_wallet_ledger_reference_check check (
    (type = 'mission_credit' and ride_id is not null
      and dispatch_attempt_id is null and withdrawal_id is null)
    or (type = 'refusal_penalty' and ride_id is null
      and dispatch_attempt_id is not null and withdrawal_id is null)
    or (type in ('withdrawal_hold', 'withdrawal_release', 'withdrawal_paid')
      and ride_id is null and dispatch_attempt_id is null
      and withdrawal_id is not null)
    or (type = 'adjustment' and ride_id is null
      and dispatch_attempt_id is null and withdrawal_id is null)
  ),
  constraint provider_wallet_ledger_idempotency_not_blank check (
    length(btrim(idempotency_key)) > 0
  ),
  constraint provider_wallet_ledger_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create unique index provider_wallet_ledger_refusal_attempt_key
  on public.provider_wallet_ledger (dispatch_attempt_id, provider_id)
  where type = 'refusal_penalty';

create unique index provider_wallet_ledger_withdrawal_event_key
  on public.provider_wallet_ledger (withdrawal_id, type)
  where type in ('withdrawal_hold', 'withdrawal_release', 'withdrawal_paid');

create index provider_wallet_ledger_provider_history_idx
  on public.provider_wallet_ledger (provider_id, provider_role, created_at desc);

create index provider_wallet_ledger_ride_idx
  on public.provider_wallet_ledger (ride_id)
  where ride_id is not null;

create index provider_wallet_ledger_attempt_idx
  on public.provider_wallet_ledger (dispatch_attempt_id)
  where dispatch_attempt_id is not null;

create or replace function public.ensure_provider_wallet_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.provider_wallet_accounts (provider_id, provider_role)
  values (new.id, new.role)
  on conflict (provider_id, provider_role) do nothing;
  return new;
end;
$$;

drop trigger if exists providers_create_wallet_account on public.providers;
create trigger providers_create_wallet_account
  after insert on public.providers
  for each row execute function public.ensure_provider_wallet_account();

insert into public.provider_wallet_accounts (provider_id, provider_role)
select provider.id, provider.role
from public.providers as provider
on conflict (provider_id, provider_role) do nothing;

create or replace function public.apply_provider_wallet_ledger_entry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.provider_wallet_accounts%rowtype;
  v_withdrawal public.provider_withdrawals%rowtype;
  v_held_delta bigint := 0;
begin
  select account.*
  into v_account
  from public.provider_wallet_accounts as account
  where account.provider_id = new.provider_id
    and account.provider_role = new.provider_role
  for update;

  if not found then
    raise exception 'A carteira do parceiro não existe.'
      using errcode = 'P0002';
  end if;

  if new.type = 'mission_credit' then
    if not exists (
      select 1
      from public.corridas as ride
      where ride.id = new.ride_id
        and ride.encerrada = true
        and ride.status_corrida::text = 'concluida'
        and (
          (new.provider_role = 'driver' and ride.driver_id = new.provider_id)
          or
          (new.provider_role = 'courier' and ride.motoboy_id = new.provider_id)
        )
    ) then
      raise exception 'O parceiro não está associado a uma corrida concluída.'
        using errcode = '23514';
    end if;
  elsif new.type = 'refusal_penalty' then
    if not exists (
      select 1
      from public.dispatch_attempts as attempt
      where attempt.id = new.dispatch_attempt_id
        and attempt.provider_id = new.provider_id
        and attempt.provider_role = new.provider_role
        and attempt.status = 'declined'
    ) then
      raise exception 'A tentativa não representa uma recusa deste parceiro.'
        using errcode = '23514';
    end if;
  elsif new.type in (
    'withdrawal_hold',
    'withdrawal_release',
    'withdrawal_paid'
  ) then
    select withdrawal.*
    into v_withdrawal
    from public.provider_withdrawals as withdrawal
    where withdrawal.id = new.withdrawal_id
      and withdrawal.provider_id = new.provider_id
      and withdrawal.provider_role = new.provider_role
    for update;

    if not found then
      raise exception 'O saque associado ao lançamento não existe.'
        using errcode = '23503';
    end if;

    if new.type = 'withdrawal_hold' then
      if v_withdrawal.status <> 'pending'
         or new.amount_cents <> -v_withdrawal.amount_cents then
        raise exception 'O lançamento de reserva não corresponde ao saque.'
          using errcode = '23514';
      end if;
      v_held_delta := v_withdrawal.amount_cents;
    elsif new.type = 'withdrawal_release' then
      if v_withdrawal.status <> 'failed'
         or new.amount_cents <> v_withdrawal.amount_cents then
        raise exception 'O lançamento de liberação não corresponde ao saque.'
          using errcode = '23514';
      end if;
      v_held_delta := -v_withdrawal.amount_cents;
    else
      if v_withdrawal.status <> 'processing'
         or new.amount_cents <> 0 then
        raise exception 'O lançamento de pagamento não corresponde ao saque.'
          using errcode = '23514';
      end if;
      v_held_delta := -v_withdrawal.amount_cents;
    end if;
  end if;

  if v_account.held_cents + v_held_delta < 0 then
    raise exception 'O saldo reservado da carteira ficaria negativo.'
      using errcode = '23514';
  end if;

  update public.provider_wallet_accounts
  set balance_cents = balance_cents + new.amount_cents,
      held_cents = held_cents + v_held_delta,
      updated_at = clock_timestamp()
  where provider_id = new.provider_id
    and provider_role = new.provider_role;

  return new;
end;
$$;

create trigger provider_wallet_ledger_apply_insert
  after insert on public.provider_wallet_ledger
  for each row execute function public.apply_provider_wallet_ledger_entry();

create or replace function public.prevent_provider_wallet_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'O livro-razão é imutável; registre um lançamento compensatório.'
    using errcode = '55000';
end;
$$;

create trigger provider_wallet_ledger_immutable
  before update or delete on public.provider_wallet_ledger
  for each row execute function public.prevent_provider_wallet_ledger_mutation();

create or replace function public.rpc_credit_mission_payout(
  p_provider_id uuid,
  p_provider_role text,
  p_ride_id uuid,
  p_amount_cents bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.provider_wallet_ledger%rowtype;
  v_inserted_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Operação restrita ao backend.'
      using errcode = '42501';
  end if;

  if p_provider_id is null
     or p_provider_role is null
     or p_provider_role not in ('driver', 'courier')
     or p_ride_id is null
     or p_amount_cents is null
     or p_amount_cents <= 0
     or p_idempotency_key is null
     or length(btrim(p_idempotency_key)) = 0 then
    raise exception 'Parâmetros inválidos para creditar a missão.'
      using errcode = '22023';
  end if;

  insert into public.provider_wallet_accounts (provider_id, provider_role)
  values (p_provider_id, p_provider_role)
  on conflict (provider_id, provider_role) do nothing;

  insert into public.provider_wallet_ledger (
    provider_id,
    provider_role,
    ride_id,
    type,
    amount_cents,
    idempotency_key
  )
  values (
    p_provider_id,
    p_provider_role,
    p_ride_id,
    'mission_credit',
    p_amount_cents,
    p_idempotency_key
  )
  on conflict (idempotency_key) do nothing
  returning id into v_inserted_id;

  if v_inserted_id is null then
    select ledger.*
    into v_existing
    from public.provider_wallet_ledger as ledger
    where ledger.idempotency_key = p_idempotency_key;

    if not found
       or v_existing.provider_id <> p_provider_id
       or v_existing.provider_role <> p_provider_role
       or v_existing.ride_id <> p_ride_id
       or v_existing.type <> 'mission_credit'
       or v_existing.amount_cents <> p_amount_cents then
      raise exception 'A chave idempotente já foi usada em outra operação.'
        using errcode = '23505';
    end if;

    return jsonb_build_object('status', 'already_applied', 'ledger_id', v_existing.id);
  end if;

  return jsonb_build_object('status', 'credited', 'ledger_id', v_inserted_id);
end;
$$;

create or replace function public.rpc_apply_refusal_penalty(
  p_provider_id uuid,
  p_dispatch_attempt_id uuid,
  p_penalty_cents bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempt public.dispatch_attempts%rowtype;
  v_existing public.provider_wallet_ledger%rowtype;
  v_idempotency_key text;
  v_inserted_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Operação restrita ao backend.'
      using errcode = '42501';
  end if;

  if p_provider_id is null
     or p_dispatch_attempt_id is null
     or p_penalty_cents is null
     or p_penalty_cents <= 0 then
    raise exception 'Parâmetros inválidos para aplicar penalidade.'
      using errcode = '22023';
  end if;

  select attempt.*
  into v_attempt
  from public.dispatch_attempts as attempt
  where attempt.id = p_dispatch_attempt_id
    and attempt.provider_id = p_provider_id
  for share;

  if not found
     or v_attempt.status <> 'declined' then
    raise exception 'A tentativa não foi recusada por este parceiro.'
      using errcode = '23514';
  end if;

  v_idempotency_key := 'refusal-penalty:' || p_dispatch_attempt_id::text;

  insert into public.provider_wallet_accounts (provider_id, provider_role)
  values (p_provider_id, v_attempt.provider_role)
  on conflict (provider_id, provider_role) do nothing;

  insert into public.provider_wallet_ledger (
    provider_id,
    provider_role,
    dispatch_attempt_id,
    type,
    amount_cents,
    idempotency_key
  )
  values (
    p_provider_id,
    v_attempt.provider_role,
    p_dispatch_attempt_id,
    'refusal_penalty',
    -p_penalty_cents,
    v_idempotency_key
  )
  on conflict (dispatch_attempt_id, provider_id)
    where type = 'refusal_penalty'
  do nothing
  returning id into v_inserted_id;

  if v_inserted_id is null then
    select ledger.*
    into v_existing
    from public.provider_wallet_ledger as ledger
    where ledger.dispatch_attempt_id = p_dispatch_attempt_id
      and ledger.provider_id = p_provider_id
      and ledger.type = 'refusal_penalty';

    if not found or v_existing.amount_cents <> -p_penalty_cents then
      raise exception 'A tentativa já foi penalizada com valor diferente.'
        using errcode = '23505';
    end if;

    return jsonb_build_object('status', 'already_applied', 'ledger_id', v_existing.id);
  end if;

  return jsonb_build_object('status', 'penalty_applied', 'ledger_id', v_inserted_id);
end;
$$;

create or replace function public.rpc_request_withdrawal(
  p_provider_role text,
  p_amount_cents bigint,
  p_payout_method_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider_id uuid := auth.uid();
  v_account public.provider_wallet_accounts%rowtype;
  v_existing public.provider_withdrawals%rowtype;
  v_withdrawal_id uuid;
  v_inserted_id uuid;
begin
  if v_provider_id is null then
    raise exception 'Autenticação obrigatória.'
      using errcode = '42501';
  end if;

  if p_provider_role is null
     or p_provider_role not in ('driver', 'courier')
     or p_amount_cents is null
     or p_amount_cents <= 0
     or p_payout_method_id is null
     or p_idempotency_key is null
     or length(btrim(p_idempotency_key)) = 0 then
    raise exception 'Parâmetros inválidos para solicitar saque.'
      using errcode = '22023';
  end if;

  perform 1
  from public.providers as provider
  where provider.id = v_provider_id
    and provider.role = p_provider_role
    and provider.status_sistema = 'ativo';

  if not found then
    raise exception 'Parceiro ativo não encontrado para o papel informado.'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.provider_payout_methods as method
    where method.id = p_payout_method_id
      and method.provider_id = v_provider_id
      and method.provider_role = p_provider_role
      and method.status = 'active'
  ) then
    raise exception 'Não há uma chave Pix ativa para este parceiro.'
      using errcode = '42501';
  end if;

  insert into public.provider_wallet_accounts (provider_id, provider_role)
  values (v_provider_id, p_provider_role)
  on conflict (provider_id, provider_role) do nothing;

  select account.*
  into v_account
  from public.provider_wallet_accounts as account
  where account.provider_id = v_provider_id
    and account.provider_role = p_provider_role
  for update;

  if exists (
    select 1
    from public.provider_withdrawals as withdrawal
    where withdrawal.idempotency_key = p_idempotency_key
  ) then
    select withdrawal.*
    into v_existing
    from public.provider_withdrawals as withdrawal
    where withdrawal.idempotency_key = p_idempotency_key;

    if v_existing.provider_id <> v_provider_id
       or v_existing.provider_role <> p_provider_role
       or v_existing.amount_cents <> p_amount_cents
       or v_existing.payout_method_id <> p_payout_method_id then
      raise exception 'A chave idempotente já foi usada em outra operação.'
        using errcode = '23505';
    end if;

    return jsonb_build_object(
      'status', 'already_requested',
      'withdrawal_id', v_existing.id,
      'withdrawal_status', v_existing.status,
      'amount_cents', v_existing.amount_cents
    );
  end if;

  if v_account.balance_cents - v_account.minimum_retained_cents
       < p_amount_cents then
    raise exception 'Saldo disponível insuficiente após o mínimo retido.'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.provider_withdrawals as withdrawal
    where withdrawal.provider_id = v_provider_id
      and withdrawal.provider_role = p_provider_role
      and withdrawal.status in ('pending', 'processing')
  ) then
    raise exception 'Já existe um saque pendente para esta carteira.'
      using errcode = 'P0001';
  end if;

  v_withdrawal_id := gen_random_uuid();

  insert into public.provider_withdrawals (
    id,
    provider_id,
    provider_role,
    payout_method_id,
    amount_cents,
    status,
    idempotency_key
  )
  values (
    v_withdrawal_id,
    v_provider_id,
    p_provider_role,
    p_payout_method_id,
    p_amount_cents,
    'pending',
    p_idempotency_key
  )
  on conflict (idempotency_key) do nothing
  returning id into v_withdrawal_id;

  if v_withdrawal_id is null then
    select withdrawal.*
    into v_existing
    from public.provider_withdrawals as withdrawal
    where withdrawal.idempotency_key = p_idempotency_key;

    if not found
       or v_existing.provider_id <> v_provider_id
       or v_existing.provider_role <> p_provider_role
       or v_existing.amount_cents <> p_amount_cents
       or v_existing.payout_method_id <> p_payout_method_id then
      raise exception 'A chave idempotente já foi usada em outra operação.'
        using errcode = '23505';
    end if;

    return jsonb_build_object(
      'status', 'already_requested',
      'withdrawal_id', v_existing.id,
      'withdrawal_status', v_existing.status,
      'amount_cents', v_existing.amount_cents
    );
  end if;

  insert into public.provider_wallet_ledger (
    provider_id,
    provider_role,
    withdrawal_id,
    type,
    amount_cents,
    idempotency_key
  )
  values (
    v_provider_id,
    p_provider_role,
    v_withdrawal_id,
    'withdrawal_hold',
    -p_amount_cents,
    'withdrawal-hold:' || v_withdrawal_id::text
  )
  returning id into v_inserted_id;

  return jsonb_build_object(
    'status', 'pending',
    'withdrawal_id', v_withdrawal_id,
    'ledger_id', v_inserted_id,
    'amount_cents', p_amount_cents
  );
end;
$$;

create or replace function public.rpc_set_provider_wallet_minimum(
  p_provider_id uuid,
  p_provider_role text,
  p_minimum_retained_cents bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Operação restrita ao backend.'
      using errcode = '42501';
  end if;

  if p_provider_id is null
     or p_provider_role is null
     or p_provider_role is null
     or p_provider_role not in ('driver', 'courier')
     or p_minimum_retained_cents is null
     or p_minimum_retained_cents < 0 then
    raise exception 'Parâmetros inválidos para o mínimo retido.'
      using errcode = '22023';
  end if;

  insert into public.provider_wallet_accounts (
    provider_id,
    provider_role,
    minimum_retained_cents
  )
  values (
    p_provider_id,
    p_provider_role,
    p_minimum_retained_cents
  )
  on conflict (provider_id, provider_role)
  do update
  set minimum_retained_cents = excluded.minimum_retained_cents,
      updated_at = clock_timestamp();
end;
$$;

create or replace function public.rpc_complete_withdrawal(
  p_withdrawal_id uuid,
  p_provider_transfer_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_withdrawal public.provider_withdrawals%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Operação restrita ao backend.'
      using errcode = '42501';
  end if;

  select withdrawal.*
  into v_withdrawal
  from public.provider_withdrawals as withdrawal
  where withdrawal.id = p_withdrawal_id
  for update;

  if not found then
    raise exception 'Pedido de saque não encontrado.'
      using errcode = 'P0002';
  end if;

  if v_withdrawal.status = 'completed' then
    return jsonb_build_object(
      'status', 'already_completed',
      'withdrawal_id', v_withdrawal.id
    );
  end if;

  if v_withdrawal.status not in ('pending', 'processing') then
    raise exception 'O saque não pode ser concluído neste estado.'
      using errcode = 'P0001';
  end if;

  if p_provider_transfer_reference is null
     or length(btrim(p_provider_transfer_reference)) = 0 then
    raise exception 'A referência de transferência é obrigatória.'
      using errcode = '22023';
  end if;

  update public.provider_withdrawals
  set status = 'processing',
      processing_at = coalesce(processing_at, clock_timestamp()),
      provider_transfer_reference = p_provider_transfer_reference,
      updated_at = clock_timestamp()
  where id = p_withdrawal_id;

  insert into public.provider_wallet_ledger (
    provider_id,
    provider_role,
    withdrawal_id,
    type,
    amount_cents,
    idempotency_key
  )
  values (
    v_withdrawal.provider_id,
    v_withdrawal.provider_role,
    v_withdrawal.id,
    'withdrawal_paid',
    0,
    'withdrawal-paid:' || v_withdrawal.id::text
  )
  on conflict (withdrawal_id, type)
    where type in ('withdrawal_hold', 'withdrawal_release', 'withdrawal_paid')
  do nothing;

  update public.provider_withdrawals
  set status = 'completed',
      completed_at = coalesce(completed_at, clock_timestamp()),
      updated_at = clock_timestamp()
  where id = p_withdrawal_id;

  return jsonb_build_object(
    'status', 'completed',
    'withdrawal_id', p_withdrawal_id
  );
end;
$$;

create or replace function public.rpc_fail_withdrawal(
  p_withdrawal_id uuid,
  p_failure_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_withdrawal public.provider_withdrawals%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Operação restrita ao backend.'
      using errcode = '42501';
  end if;

  select withdrawal.*
  into v_withdrawal
  from public.provider_withdrawals as withdrawal
  where withdrawal.id = p_withdrawal_id
  for update;

  if not found then
    raise exception 'Pedido de saque não encontrado.'
      using errcode = 'P0002';
  end if;

  if v_withdrawal.status = 'failed' then
    return jsonb_build_object(
      'status', 'already_failed',
      'withdrawal_id', v_withdrawal.id
    );
  end if;

  if v_withdrawal.status not in ('pending', 'processing') then
    raise exception 'O saque não pode falhar neste estado.'
      using errcode = 'P0001';
  end if;

  update public.provider_withdrawals
  set status = 'failed',
      failed_at = clock_timestamp(),
      failure_reason = left(coalesce(p_failure_reason, 'Falha no processamento'), 500),
      updated_at = clock_timestamp()
  where id = p_withdrawal_id;

  insert into public.provider_wallet_ledger (
    provider_id,
    provider_role,
    withdrawal_id,
    type,
    amount_cents,
    idempotency_key
  )
  values (
    v_withdrawal.provider_id,
    v_withdrawal.provider_role,
    v_withdrawal.id,
    'withdrawal_release',
    v_withdrawal.amount_cents,
    'withdrawal-release:' || v_withdrawal.id::text
  )
  on conflict (withdrawal_id, type)
    where type in ('withdrawal_hold', 'withdrawal_release', 'withdrawal_paid')
  do nothing;

  return jsonb_build_object(
    'status', 'failed',
    'withdrawal_id', p_withdrawal_id
  );
end;
$$;

alter table public.provider_wallet_accounts enable row level security;
alter table public.provider_payout_methods enable row level security;
alter table public.provider_withdrawals enable row level security;
alter table public.provider_wallet_ledger enable row level security;

drop policy if exists provider_wallet_accounts_select_own
  on public.provider_wallet_accounts;
create policy provider_wallet_accounts_select_own
  on public.provider_wallet_accounts
  for select
  to authenticated
  using (auth.uid() = provider_id);

drop policy if exists provider_payout_methods_select_own
  on public.provider_payout_methods;
create policy provider_payout_methods_select_own
  on public.provider_payout_methods
  for select
  to authenticated
  using (auth.uid() = provider_id);

drop policy if exists provider_withdrawals_select_own
  on public.provider_withdrawals;
create policy provider_withdrawals_select_own
  on public.provider_withdrawals
  for select
  to authenticated
  using (auth.uid() = provider_id);

drop policy if exists provider_wallet_ledger_select_own
  on public.provider_wallet_ledger;
create policy provider_wallet_ledger_select_own
  on public.provider_wallet_ledger
  for select
  to authenticated
  using (auth.uid() = provider_id);

revoke all on table
  public.provider_wallet_accounts,
  public.provider_payout_methods,
  public.provider_withdrawals,
  public.provider_wallet_ledger
from public, anon, authenticated;

grant select on table
  public.provider_wallet_accounts,
  public.provider_payout_methods,
  public.provider_withdrawals,
  public.provider_wallet_ledger
to authenticated;

grant all on table
  public.provider_payout_methods
to service_role;

grant select on table
  public.provider_wallet_accounts,
  public.provider_wallet_ledger,
  public.provider_withdrawals
to service_role;

revoke all on function public.rpc_credit_mission_payout(
  uuid, text, uuid, bigint, text
) from public, anon, authenticated;
revoke all on function public.rpc_apply_refusal_penalty(
  uuid, uuid, bigint
) from public, anon, authenticated;
revoke all on function public.rpc_request_withdrawal(
  text, bigint, uuid, text
) from public, anon;
revoke all on function public.rpc_complete_withdrawal(
  uuid, text
) from public, anon, authenticated;
revoke all on function public.rpc_fail_withdrawal(
  uuid, text
) from public, anon, authenticated;
revoke all on function public.rpc_set_provider_wallet_minimum(
  uuid, text, bigint
) from public, anon, authenticated;
revoke all on function public.ensure_provider_wallet_account()
  from public, anon, authenticated;
revoke all on function public.apply_provider_wallet_ledger_entry()
  from public, anon, authenticated;
revoke all on function public.prevent_provider_wallet_ledger_mutation()
  from public, anon, authenticated;

grant execute on function public.rpc_credit_mission_payout(
  uuid, text, uuid, bigint, text
) to service_role;
grant execute on function public.rpc_apply_refusal_penalty(
  uuid, uuid, bigint
) to service_role;
grant execute on function public.rpc_request_withdrawal(
  text, bigint, uuid, text
) to authenticated;
grant execute on function public.rpc_complete_withdrawal(
  uuid, text
) to service_role;
grant execute on function public.rpc_fail_withdrawal(
  uuid, text
) to service_role;
grant execute on function public.rpc_set_provider_wallet_minimum(
  uuid, text, bigint
) to service_role;
