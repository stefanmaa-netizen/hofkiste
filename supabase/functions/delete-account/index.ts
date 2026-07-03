import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// DSGVO-Selbstlöschung: Kund:innen können ihr eigenes Konto entfernen.
// Löscht den auth.users-Eintrag; customers und requests hängen per
// ON DELETE CASCADE daran und werden mitgelöscht.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Nicht angemeldet." }, 401);

    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) return json({ error: "Nicht angemeldet." }, 401);

    // Admins dürfen sich nicht selbst über diesen Weg löschen — sonst könnte
    // versehentlich das letzte Admin-Konto verschwinden. Admin-Verwaltung
    // läuft über das Supabase Dashboard.
    const { data: admin } = await userClient.from("admins").select("id").eq("id", user.id).maybeSingle();
    if (admin) return json({ error: "Admin-Konten können nur im Supabase Dashboard gelöscht werden." }, 403);

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { error: delErr } = await adminClient.auth.admin.deleteUser(user.id);
    if (delErr) return json({ error: "Löschen fehlgeschlagen: " + delErr.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
