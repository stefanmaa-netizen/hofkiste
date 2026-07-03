-- Hofkiste — Supabase schema
-- Datenmodell: customers (per Supabase-Einladung angelegte Kund:innen-Konten), posts
-- (Wochenbeiträge), requests (Alternativtermin-Anfragen), admins (Admin-Whitelist).
--
-- Kund:innen-Konten werden per Supabase Dashboard → Authentication → Users → "Invite user"
-- angelegt (E-Mail/Passwort-Auth, Passwort wählt die Person beim ersten Login selbst,
-- siehe Migration 5 unten sowie README.md).

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
--
-- Für jeden weiteren Admin danach die Funktion promote_to_admin() nutzen
-- (siehe Abschnitt "Folge-Migrationen" unten) statt direkt in die Tabelle zu schreiben.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Folge-Migrationen (nach dem initialen Launch, per Supabase-MCP angewendet)
-- Diese Statements sind bereits auf dem Live-Projekt ausgeführt worden.
-- Reihenfolge und Migration-Namen: siehe `supabase migrations list` /
-- list_migrations. Hier nur zur Dokumentation im Repo.
-- ---------------------------------------------------------------------------

-- 1) add_validation_constraints
-- Serverseitige Validierung (ergänzt clientseitige Checks, die man umgehen kann).
-- NOT VALID: gilt für neue/zukünftige INSERT/UPDATE, bestehende Zeilen (Testdaten
-- aus der Entwicklungsphase) werden nicht rückwirkend geprüft.
alter table public.customers
  add constraint customers_name_length check (char_length(trim(name)) between 1 and 200) not valid,
  add constraint customers_email_format check (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') not valid,
  add constraint customers_email_length check (char_length(email) <= 320) not valid;

alter table public.admins
  add constraint admins_email_format check (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') not valid;

alter table public.posts
  add constraint posts_title_length check (char_length(trim(title)) between 1 and 200) not valid,
  add constraint posts_week_length check (char_length(trim(week)) between 1 and 200) not valid,
  add constraint posts_content_length check (char_length(content) between 1 and 5000) not valid,
  add constraint posts_recipe_title_length check (recipe_title is null or char_length(recipe_title) <= 200) not valid,
  add constraint posts_recipe_text_length check (recipe_text is null or char_length(recipe_text) <= 5000) not valid;

alter table public.requests
  add constraint requests_note_length check (note is null or char_length(note) <= 500) not valid;

-- 2) add_admin_delete_policies
-- Admins konnten posts/requests bisher nicht löschen (nur select/insert/update-Policies existierten).
create policy "posts admin delete" on public.posts
  for delete using (public.is_admin());

create policy "requests admin delete" on public.requests
  for delete using (public.is_admin());

-- 3) harden_is_admin_function_exposure
-- Security-Advisor-Warnung: is_admin() war als SECURITY DEFINER Funktion im
-- "public"-Schema öffentlich per REST-RPC aufrufbar (/rest/v1/rpc/is_admin).
-- Durch Verschieben in ein nicht per API exponiertes Schema bleibt sie für
-- RLS-Policies nutzbar (Postgres referenziert Funktionen intern per OID,
-- nicht per Schemaname), ist aber nicht mehr direkt aufrufbar.
create schema if not exists internal;
alter function public.is_admin() set schema internal;
-- Ab hier heißt die Funktion also internal.is_admin() — bestehende Policies
-- funktionieren unverändert weiter.

-- 4) add_promote_to_admin_rpc
-- Sichereres Admin-Onboarding: statt direktem INSERT im SQL-Editor kann ein
-- bestehender Admin neue Admins per RPC anlegen (serverseitig geprüft).
create or replace function public.promote_to_admin(target_user_id uuid, target_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not internal.is_admin() then
    raise exception 'Nur bestehende Admins dürfen neue Admins anlegen.';
  end if;
  insert into public.admins (id, email) values (target_user_id, target_email)
  on conflict (id) do nothing;
end;
$$;

revoke all on function public.promote_to_admin(uuid, text) from public;
grant execute on function public.promote_to_admin(uuid, text) to authenticated;

-- Nutzung (als eingeloggter Admin, z.B. über den Supabase JS-Client in der Konsole):
--   await supabase.rpc('promote_to_admin', {
--     target_user_id: '<uuid-aus-auth.users>',
--     target_email: 'neue-person@example.de'
--   });
-- Der/die neue Admin muss vorher als normaler Nutzer (E-Mail/Passwort) im
-- Supabase Dashboard unter Authentication → Users angelegt worden sein.

-- 5) add_customers_update_self_policy
-- Nötig, damit der Upsert beim Passwort-Setzen (Invite-Flow) auch dann klappt,
-- wenn die customers-Zeile schon existiert (z.B. erneuter Invite-Link-Klick).
create policy "customers update self" on public.customers
  for update using (id = auth.uid()) with check (id = auth.uid());

-- 6) restrict_promote_to_admin_exposure
-- Security-Advisor-WARN: promote_to_admin war trotz "revoke from public" noch für
-- anon per REST-RPC aufrufbar. Explizit entziehen; der eigentliche Schutz bleibt
-- der is_admin()-Check in der Funktion selbst.
revoke execute on function public.promote_to_admin(uuid, text) from anon;

-- 5) add_customers_update_self_policy
-- Kund:innen-Konten werden jetzt per Supabase-Einladung (Authentication → Users → Invite user)
-- angelegt statt per anonymer Selbstregistrierung. Beim ersten Login setzt die Person ihr
-- Passwort + Namen selbst (siehe index.html: setPasswordAndName/renderSetPassword) und die App
-- schreibt per upsert in customers. Dafür fehlte bisher eine UPDATE-Policy (nur INSERT/SELECT
-- existierten) für den Fall, dass die Zeile schon existiert (z.B. erneuter Klick auf den Link).
create policy "customers update self" on public.customers
  for update using (id = auth.uid()) with check (id = auth.uid());
