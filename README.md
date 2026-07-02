# Hofkiste

Kisten-Newsletter & Anfrage-Tool für Gemüsekisten-Abo. Statisches Frontend (`index.html`) mit [Supabase](https://supabase.com) als Backend (Datenbank, Auth).

## Stack

- Frontend: reines HTML/CSS/JS, `supabase-js` via CDN (`esm.sh`)
- Backend: Supabase (Postgres, Row Level Security, E-Mail/Passwort-Auth für Kund:innen und Admin)
- Hosting: GitHub Pages, automatisch deployed via GitHub Actions (`.github/workflows/pages.yml`)

## Supabase-Projekt

Projekt: `hofkiste` (`caoqulfbuicqwrrtlfyt.supabase.co`, Region `eu-central-1`).

Schema: [`supabase/schema.sql`](supabase/schema.sql) — bereits auf dem Projekt ausgeführt (Tabellen `customers`, `admins`, `posts`, `requests` + RLS-Policies).

Zugangsdaten liegen in `config.js` (Supabase-URL + **anon key**, öffentlich und sicher, da nur RLS-geschützte Requests möglich sind).

### Einmalige Einrichtung nach dem Deploy

1. **Site URL konfigurieren** (wichtig, sonst zeigen Einladungs-/Passwort-Links ins Leere):
   Supabase Dashboard → Authentication → URL Configuration → **Site URL** auf die GitHub-Pages-URL
   setzen (`https://<username>.github.io/hofkiste/`) und dieselbe URL auch bei
   **Redirect URLs** eintragen.

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
   - Authentication → Rate Limits: Limits für Sign-ups/Sign-ins sinnvoll begrenzen
     (Standardwerte sind für ein kleines Projekt oft zu großzügig).
   - Authentication → Policies → **Leaked Password Protection** aktivieren (prüft Passwörter
     gegen bekannte Datenlecks).
   - Authentication → Providers → **Anonymous Sign-Ins** kann deaktiviert bleiben/werden — die App
     nutzt das nicht mehr (siehe unten).

## Kund:innen anlegen (Alternativtermin-Zugang)

Kund:innen registrieren sich **nicht mehr selbst**. Stattdessen legst du als Kistenverwaltung die
Konten in Supabase an, die Person wählt beim ersten Login selbst ein Passwort.

1. Supabase Dashboard → Authentication → Users → **Invite user** → E-Mail-Adresse eingeben.
2. Supabase verschickt automatisch eine Einladungs-Mail mit einem Link.
3. Klickt die Person auf den Link, landet sie auf der Hofkiste-Seite und wird direkt zu einer
   "Passwort festlegen"-Maske geleitet (Name + selbstgewähltes Passwort, mind. 8 Zeichen).
   Danach ist sie eingeloggt und kann Alternativtermine anfragen.
4. Bei künftigen Besuchen loggt sich die Person unter "Mein Konto" mit E-Mail + Passwort ein.
   Passwort vergessen → Link auf der Login-Maske nutzt denselben E-Mail-Flow.

**Hinweis zum E-Mail-Versand:** Supabase verschickt Einladungs-/Reset-Mails standardmäßig über einen
eigenen, stark rate-limitierten Mailserver (nur wenige E-Mails/Stunde, ohne Zusagen zur Zustellbarkeit —
landet leicht im Spam). Für zuverlässigen Versand bei mehr als ein paar Kund:innen: eigenen SMTP-Server
hinterlegen unter Authentication → Emails → SMTP Settings (z. B. über SendGrid, Postmark, AWS SES).

Alte, vor diesem Umbau per anonymer Selbstregistrierung angelegte Test-Konten können nicht mehr
einloggen (kein Passwort) und sollten bei Gelegenheit im Dashboard aufgeräumt werden.

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

