# Hofkiste

Kisten-Newsletter & Anfrage-Tool für Gemüsekisten-Abo. Statisches Frontend (`index.html`) mit [Supabase](https://supabase.com) als Backend (Datenbank, Auth).

## Stack

- Frontend: reines HTML/CSS/JS, `supabase-js` via CDN (`esm.sh`)
- Backend: Supabase (Postgres, Row Level Security, Anonymous Auth für Kund:innen, E-Mail/Passwort-Auth für Admin)
- Hosting: GitHub Pages, automatisch deployed via GitHub Actions (`.github/workflows/pages.yml`)

## Supabase-Projekt

Projekt: `hofkiste` (`caoqulfbuicqwrrtlfyt.supabase.co`, Region `eu-central-1`).

Schema: [`supabase/schema.sql`](supabase/schema.sql) — bereits auf dem Projekt ausgeführt (Tabellen `customers`, `admins`, `posts`, `requests` + RLS-Policies).

Zugangsdaten liegen in `config.js` (Supabase-URL + **anon key**, öffentlich und sicher, da nur RLS-geschützte Requests möglich sind).

### Einmalige Einrichtung nach dem Deploy

1. **Anonymous Sign-Ins aktivieren** (für die Kund:innen-Registrierung ohne Passwort):
   Supabase Dashboard → Authentication → Sign In / Providers → **Anonymous Sign-Ins** → aktivieren.

2. **Ersten Admin-Account anlegen:**
   - Supabase Dashboard → Authentication → Users → **Add user** (E-Mail + Passwort festlegen)
   - Danach im SQL Editor:
     ```sql
     insert into public.admins (id, email)
     values ('<user-id-aus-auth-users>', '<email>');
     ```
   - Für **weitere** Admins danach nicht mehr direkt in die Tabelle schreiben, sondern
     als eingeloggter Admin die RPC-Funktion nutzen (serverseitig geprüft, dass nur
     bestehende Admins neue anlegen dürfen):
     ```js
     await supabase.rpc('promote_to_admin', {
       target_user_id: '<uuid-aus-auth.users>',
       target_email: 'neue-person@example.de'
     });
     ```
     Die Person muss vorher wie oben als normaler Nutzer angelegt worden sein.

3. **Empfohlene Auth-Einstellungen im Dashboard** (nicht per Migration setzbar):
   - Authentication → Rate Limits: Limits für Anonymous Sign-ins und Sign-ups sinnvoll begrenzen
     (Standardwerte sind für ein kleines Projekt oft zu großzügig).
   - Authentication → Policies → **Leaked Password Protection** aktivieren (prüft Admin-Passwörter
     gegen bekannte Datenlecks).

## Rechtliches

[`impressum.html`](impressum.html) und [`datenschutz.html`](datenschutz.html) enthalten Platzhalter
für Pflichtangaben (Name/Anschrift, Kontakt, DSGVO-Verantwortlicher). **Vor dem Livegang mit echten
Kund:innen müssen diese durch echte Daten ersetzt werden.**

## GitHub Pages

Deploy läuft automatisch bei jedem Push auf `main` über die GitHub Action.

Einmalig einzurichten: **Settings → Pages → Build and deployment → Source: "GitHub Actions"** auswählen.

Danach ist die Seite live unter `https://<username>.github.io/<repo>/`.

## Lokale Entwicklung

Kein Build-Schritt nötig — `index.html` einfach mit einem lokalen Static-Server öffnen (z. B. `npx serve .`), damit ES-Module (`type="module"`) korrekt geladen werden.

