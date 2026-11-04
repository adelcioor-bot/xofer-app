-- Core schema for dynamic quotes and blind provider dispatch.
-- Dispatch data is intentionally inaccessible through the client API until
-- narrowly scoped RPCs/Edge Functions and their authorization rules are added.

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

create table public.hot_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  area extensions.geometry(MultiPolygon, 4326) not null,
  active boolean not null default true,
  priority integer not null default 0,
  destination_multiplier numeric(8, 4) not null default 1.0,
  destination_surcharge_cents bigint not null default 0,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hot_zones_name_not_blank check (length(btrim(name)) > 0),
  constraint hot_zones_multiplier_positive check (destination_multiplier > 0),
  constraint hot_zones_surcharge_nonnegative check (destination_surcharge_cents >= 0),
  constraint hot_zones_validity_order check (
    valid_until is null or valid_until > valid_from
  ),
  constraint hot_zones_area_nonempty check (not extensions.ST_IsEmpty(area)),
  constraint hot_zones_area_valid check (extensions.ST_IsValid(area))
);

create index hot_zones_area_gix
  on public.hot_zones using gist (area);

create index hot_zones_active_validity_idx
  on public.hot_zones (valid_from, valid_until, priority desc)
  where active;

create table public.pricing_configs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  currency text not null default 'BRL',
  base_fare_cents bigint not null default 0,
  provider_to_pickup_cents_per_km numeric(12, 4) not null default 0,
  trip_cents_per_km numeric(12, 4) not null default 0,
  hot_zone_multiplier numeric(8, 4) not null default 1.0,
  minimum_fare_cents bigint not null default 0,
  maximum_fare_cents bigint,
  initial_search_radius_meters integer not null,
  maximum_search_radius_meters integer not null,
  active boolean not null default false,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pricing_configs_name_not_blank check (length(btrim(name)) > 0),
  constraint pricing_configs_currency_format check (currency ~ '^[A-Z]{3}$'),
  constraint pricing_configs_rates_nonnegative check (
    base_fare_cents >= 0
    and provider_to_pickup_cents_per_km >= 0
    and trip_cents_per_km >= 0
    and minimum_fare_cents >= 0
  ),
  constraint pricing_configs_hot_zone_multiplier_positive check (
    hot_zone_multiplier > 0
  ),
  constraint pricing_configs_fare_range check (
    maximum_fare_cents is null
    or maximum_fare_cents >= minimum_fare_cents
  ),
  constraint pricing_configs_search_radii_valid check (
    initial_search_radius_meters > 0
    and maximum_search_radius_meters >= initial_search_radius_meters
  ),
  constraint pricing_configs_validity_order check (
    valid_until is null or valid_until > valid_from
  )
);

create unique index pricing_configs_one_active_idx
  on public.pricing_configs (active)
  where active;

create index pricing_configs_validity_idx
  on public.pricing_configs (valid_from, valid_until)
  where active;

create table public.provider_presence (
  provider_id uuid not null,
  provider_role text not null,
  location extensions.geography(Point, 4326) not null,
  is_available boolean not null default false,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider_id, provider_role),
  constraint provider_presence_role_check check (
    provider_role in ('driver', 'courier')
  ),
  constraint provider_presence_provider_fkey
    foreign key (provider_id, provider_role)
    references public.providers (id, role)
    on delete cascade
);

create index provider_presence_location_gix
  on public.provider_presence using gist (location);

create index provider_presence_available_idx
  on public.provider_presence (provider_role, last_seen_at desc)
  where is_available;

create table public.ride_quotes (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid unique references public.corridas (id) on delete set null,
  requester_id uuid not null references auth.users (id) on delete restrict,
  requester_type text not null,
  pricing_config_id uuid not null
    references public.pricing_configs (id) on delete restrict,
  origin extensions.geography(Point, 4326) not null,
  destination extensions.geography(Point, 4326) not null,
  destination_hot_zone_id uuid
    references public.hot_zones (id) on delete set null,
  provider_distance_meters integer not null,
  trip_distance_meters integer not null,
  amount_cents bigint not null,
  currency text not null default 'BRL',
  pricing_snapshot jsonb not null,
  status text not null default 'pending',
  expires_at timestamptz not null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ride_quotes_requester_type_check check (
    requester_type in ('customer', 'merchant')
  ),
  constraint ride_quotes_distances_nonnegative check (
    provider_distance_meters >= 0 and trip_distance_meters >= 0
  ),
  constraint ride_quotes_amount_nonnegative check (amount_cents >= 0),
  constraint ride_quotes_currency_format check (currency ~ '^[A-Z]{3}$'),
  constraint ride_quotes_snapshot_object check (
    jsonb_typeof(pricing_snapshot) = 'object'
  ),
  constraint ride_quotes_status_check check (
    status in ('pending', 'accepted', 'expired', 'cancelled', 'used')
  ),
  constraint ride_quotes_expiry_after_creation check (expires_at > created_at)
);

create index ride_quotes_requester_created_idx
  on public.ride_quotes (requester_id, created_at desc);

create index ride_quotes_pending_expiry_idx
  on public.ride_quotes (expires_at)
  where status = 'pending';

create table public.mission_dispatches (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.corridas (id) on delete cascade,
  provider_role text not null,
  status text not null default 'pending',
  round_no integer not null default 1,
  search_radius_meters integer not null,
  next_attempt_at timestamptz,
  accepted_by uuid,
  accepted_role text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  constraint mission_dispatches_ride_role_key unique (ride_id, provider_role),
  constraint mission_dispatches_id_role_key unique (id, provider_role),
  constraint mission_dispatches_provider_role_check check (
    provider_role in ('driver', 'courier')
  ),
  constraint mission_dispatches_status_check check (
    status in ('pending', 'dispatching', 'accepted', 'exhausted', 'cancelled')
  ),
  constraint mission_dispatches_round_positive check (round_no > 0),
  constraint mission_dispatches_radius_positive check (search_radius_meters > 0),
  constraint mission_dispatches_accepted_role_check check (
    accepted_role is null or accepted_role = provider_role
  ),
  constraint mission_dispatches_accepted_by_fkey
    foreign key (accepted_by, accepted_role)
    references public.providers (id, role)
    on delete set null
);

create index mission_dispatches_pending_idx
  on public.mission_dispatches (next_attempt_at, created_at)
  where status in ('pending', 'dispatching');

create index mission_dispatches_ride_idx
  on public.mission_dispatches (ride_id);

create table public.dispatch_attempts (
  id uuid primary key default gen_random_uuid(),
  dispatch_id uuid not null,
  provider_id uuid not null,
  provider_role text not null,
  round_no integer not null,
  sequence_no integer not null,
  status text not null default 'offered',
  offered_at timestamptz not null default now(),
  expires_at timestamptz not null,
  responded_at timestamptz,
  distance_meters integer,
  created_at timestamptz not null default now(),
  constraint dispatch_attempts_provider_fkey
    foreign key (provider_id, provider_role)
    references public.providers (id, role)
    on delete cascade,
  constraint dispatch_attempts_dispatch_role_fkey
    foreign key (dispatch_id, provider_role)
    references public.mission_dispatches (id, provider_role)
    on delete cascade,
  constraint dispatch_attempts_dispatch_round_provider_key
    unique (dispatch_id, round_no, provider_id),
  constraint dispatch_attempts_dispatch_sequence_key
    unique (dispatch_id, round_no, sequence_no),
  constraint dispatch_attempts_role_check check (
    provider_role in ('driver', 'courier')
  ),
  constraint dispatch_attempts_round_positive check (round_no > 0),
  constraint dispatch_attempts_sequence_positive check (sequence_no > 0),
  constraint dispatch_attempts_status_check check (
    status in ('offered', 'accepted', 'declined', 'expired', 'superseded')
  ),
  constraint dispatch_attempts_expiry_after_offer check (expires_at > offered_at),
  constraint dispatch_attempts_distance_nonnegative check (
    distance_meters is null or distance_meters >= 0
  )
);

create unique index dispatch_attempts_one_open_per_dispatch_idx
  on public.dispatch_attempts (dispatch_id)
  where status = 'offered';

create unique index dispatch_attempts_one_open_per_provider_idx
  on public.dispatch_attempts (provider_id, provider_role)
  where status = 'offered';

create index dispatch_attempts_expiry_idx
  on public.dispatch_attempts (expires_at)
  where status = 'offered';

create index dispatch_attempts_history_idx
  on public.dispatch_attempts (dispatch_id, round_no, sequence_no);

alter table public.hot_zones enable row level security;
alter table public.pricing_configs enable row level security;
alter table public.provider_presence enable row level security;
alter table public.ride_quotes enable row level security;
alter table public.mission_dispatches enable row level security;
alter table public.dispatch_attempts enable row level security;

revoke all on table
  public.hot_zones,
  public.pricing_configs,
  public.provider_presence,
  public.ride_quotes,
  public.mission_dispatches,
  public.dispatch_attempts
from public, anon, authenticated;

grant all on table
  public.hot_zones,
  public.pricing_configs,
  public.provider_presence,
  public.ride_quotes,
  public.mission_dispatches,
  public.dispatch_attempts
to service_role;
