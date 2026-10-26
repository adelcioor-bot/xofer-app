-- Prestadores do Xofer Prof. O Make.com lê status_sistema = 'analise'.
create table if not exists public.providers (
  id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('driver', 'courier')),
  full_name text not null,
  document text not null,
  phone text not null,
  email text not null,
  status_sistema text not null default 'analise'
    check (status_sistema in ('analise', 'ativo', 'recusado')),
  cnh_path text,
  criminal_record_path text,
  crlv_path text,
  selfie_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (id, role)
);

create unique index if not exists providers_document_role_key
  on public.providers (document, role)
  where document is not null and length(trim(document)) > 0;

alter table public.providers enable row level security;

drop policy if exists "providers_select_own" on public.providers;
create policy "providers_select_own"
  on public.providers
  for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "providers_insert_own" on public.providers;
create policy "providers_insert_own"
  on public.providers
  for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "providers_update_own" on public.providers;
create policy "providers_update_own"
  on public.providers
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

insert into storage.buckets (id, name, public)
values ('provider-documents', 'provider-documents', false)
on conflict (id) do nothing;

drop policy if exists "provider_docs_insert_own" on storage.objects;
create policy "provider_docs_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'provider-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "provider_docs_select_own" on storage.objects;
create policy "provider_docs_select_own"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'provider-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
