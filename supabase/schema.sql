-- Hofkiste — Supabase schema
-- Datenmodell: customers (anonyme Auth-Identität pro Kund:in), posts (Wochenbeiträge),
-- requests (Alternativtermin-Anfragen), admins (Admin-Whitelist).
--
-- Voraussetzung: Anonymous Sign-ins müssen im Supabase-Projekt aktiviert sein
-- (Dashboard → Authentication → Providers → Anonymous Sign-Ins → Enable).

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

create table if not exists public.customers (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.admins (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  week text not null,
  content text not null,
  recipe_title text,
  recipe_text text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  requested_date date not null,
  note text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'abgelehnt')),
  pin text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Helper: ist der aktuell eingeloggte User ein Admin?
-- ---------------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.admins where id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- RLS aktivieren
-- ---------------------------------------------------------------------------

alter table public.customers enable row level security;
alter table public.admins enable row level security;
alter table public.posts enable row level security;
alter table public.requests enable row level security;

-- customers: jede:r darf sich selbst anlegen (id = eigene auth.uid()),
-- lesen darf man nur sich selbst oder als Admin alle.
create policy "customers insert self" on public.customers
  for insert with check (id = auth.uid());

create policy "customers select self or admin" on public.customers
  for select using (id = auth.uid() or public.is_admin());

-- admins: nur Admins dürfen die Liste sehen (Verwaltung läuft über Dashboard/Service-Role).
create policy "admins select admin only" on public.admins
  for select using (public.is_admin());

-- posts: öffentlich lesbar (auch ohne Login), nur Admins dürfen schreiben.
create policy "posts public read" on public.posts
  for select using (true);

create policy "posts admin insert" on public.posts
  for insert with check (public.is_admin());

create policy "posts admin update" on public.posts
  for update using (public.is_admin());

-- requests: Kund:in darf eigene Anfragen anlegen & lesen, Admin darf alles lesen & bearbeiten.
create policy "requests insert own" on public.requests
  for insert with check (customer_id = auth.uid());

create policy "requests select own or admin" on public.requests
  for select using (customer_id = auth.uid() or public.is_admin());

create policy "requests admin update" on public.requests
  for update using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Ersten Admin anlegen (nach dem Deploy manuell ausführen):
--
-- 1. Im Supabase Dashboard unter Authentication → Users einen Nutzer per
--    E-Mail/Passwort anlegen (das ist der Admin-Login für die Seite).
-- 2. Danach dessen User-ID in die admins-Tabelle eintragen:
--
--    insert into public.admins (id, email) values ('<user-id-aus-auth-users>', '<email>');
-- ---------------------------------------------------------------------------
