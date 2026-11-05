-- Parâmetros da precificação por tempo (motorista), por km+tempo (motoboy)
-- e a taxa fixa de vistoria. Uma única linha ativa.
--
-- O documento de precificação não fecha os valores comerciais por minuto.
-- O seed abaixo só destrava a leitura: a taxa fixa e o km do resgate repetem
-- a configuração já usada em pricing_configs (R$ 6,90 e R$ 0,60/km).
-- As taxas por minuto ficam em zero até a definição comercial.

create table public.pricing_settings (
  id uuid primary key default gen_random_uuid(),
  driver_rate_per_minute_cents integer not null,
  courier_rate_per_km_cents integer not null,
  courier_rate_per_minute_cents integer not null,
  fixed_onboarding_cents integer not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pricing_settings_amounts_nonnegative check (
    driver_rate_per_minute_cents >= 0
    and courier_rate_per_km_cents >= 0
    and courier_rate_per_minute_cents >= 0
    and fixed_onboarding_cents >= 0
  )
);

create unique index pricing_settings_one_active_idx
  on public.pricing_settings (active)
  where active;

-- Janela de ociosidade do motorista. O saldo só existe enquanto a sessão
-- está active. Recusa ou expiração do despacho grava reset_by_refusal.
-- A conversão para a carteira, depois da próxima missão aceita, encerra
-- a janela como completed.

create table public.idle_sessions (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'active',
  pending_idle_cents integer not null default 0,
  started_at timestamptz not null default clock_timestamp(),
  ended_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint idle_sessions_status_check check (
    status in ('active', 'completed', 'reset_by_refusal')
  ),
  constraint idle_sessions_pending_nonnegative check (pending_idle_cents >= 0),
  constraint idle_sessions_end_matches_status check (
    (status = 'active' and ended_at is null)
    or (status <> 'active' and ended_at is not null)
  )
);

create unique index idle_sessions_one_active_per_driver_idx
  on public.idle_sessions (driver_id)
  where status = 'active';

create index idle_sessions_driver_started_idx
  on public.idle_sessions (driver_id, started_at desc);

-- Fundo global de recomposição. O acréscimo na cotação futura fica limitado
-- a 5% da tarifa base e a R$ 3,00 por corrida.

create table public.platform_deficit_pool (
  id boolean primary key default true,
  current_balance_cents integer not null default 0,
  max_surcharge_percent numeric(4, 2) not null default 0.05,
  max_surcharge_cents integer not null default 300,
  updated_at timestamptz not null default clock_timestamp(),
  constraint platform_deficit_pool_singleton check (id),
  constraint platform_deficit_pool_balance_nonnegative check (
    current_balance_cents >= 0
  ),
  constraint platform_deficit_pool_surcharge_percent_range check (
    max_surcharge_percent >= 0
    and max_surcharge_percent <= 1
  ),
  constraint platform_deficit_pool_surcharge_cap_nonnegative check (
    max_surcharge_cents >= 0
  )
);

insert into public.pricing_settings (
  driver_rate_per_minute_cents,
  courier_rate_per_km_cents,
  courier_rate_per_minute_cents,
  fixed_onboarding_cents
)
values (0, 60, 0, 690);

insert into public.platform_deficit_pool (
  current_balance_cents,
  max_surcharge_percent,
  max_surcharge_cents
)
values (0, 0.05, 300);

alter table public.pricing_settings enable row level security;
alter table public.idle_sessions enable row level security;
alter table public.platform_deficit_pool enable row level security;

revoke all on table
  public.pricing_settings,
  public.idle_sessions,
  public.platform_deficit_pool
from public, anon, authenticated;

grant all on table
  public.pricing_settings,
  public.idle_sessions,
  public.platform_deficit_pool
to service_role;
