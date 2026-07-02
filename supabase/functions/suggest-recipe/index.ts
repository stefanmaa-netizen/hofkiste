import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Best-effort DE -> EN Übersetzung für die häufigsten Gemüsekisten-Zutaten.
// Spoonacular versteht nur Englisch; unbekannte Wörter werden unübersetzt durchgereicht.
const GERMAN_TO_ENGLISH: Record<string, string> = {
  "zucchini": "zucchini",
  "tomate": "tomato", "tomaten": "tomatoes",
  "kartoffel": "potato", "kartoffeln": "potatoes",
  "gurke": "cucumber", "gurken": "cucumbers",
  "karotte": "carrot", "karotten": "carrots",
  "möhre": "carrot", "möhren": "carrots",
  "zwiebel": "onion", "zwiebeln": "onions",
  "knoblauch": "garlic",
  "paprika": "bell pepper",
  "kohl": "cabbage",
  "rotkohl": "red cabbage",
  "weißkohl": "white cabbage", "weisskohl": "white cabbage",
  "blumenkohl": "cauliflower",
  "brokkoli": "broccoli",
  "spinat": "spinach",
  "salat": "lettuce", "kopfsalat": "lettuce",
  "rucola": "arugula",
  "rote bete": "beetroot", "rote beete": "beetroot", "rote rüben": "beetroot",
  "sellerie": "celery",
  "lauch": "leek", "porree": "leek",
  "fenchel": "fennel",
  "aubergine": "eggplant", "auberginen": "eggplants",
  "mais": "corn",
  "erbsen": "peas",
  "bohnen": "beans",
  "radieschen": "radish",
  "rettich": "radish",
  "spargel": "asparagus",
  "kürbis": "pumpkin",
  "pastinake": "parsnip", "pastinaken": "parsnips",
  "steckrübe": "rutabaga", "steckrüben": "rutabaga",
  "rosenkohl": "brussels sprouts",
  "grünkohl": "kale",
  "mangold": "chard",
  "pilze": "mushrooms", "champignons": "mushrooms",
  "apfel": "apple", "äpfel": "apples",
  "birne": "pear", "birnen": "pears",
  "pflaume": "plum", "pflaumen": "plums",
  "erdbeere": "strawberry", "erdbeeren": "strawberries",
  "himbeere": "raspberry", "himbeeren": "raspberries",
  "kirsche": "cherry", "kirschen": "cherries",
  "zitrone": "lemon", "zitronen": "lemons",
  "petersilie": "parsley",
  "basilikum": "basil",
  "dill": "dill",
  "schnittlauch": "chives",
  "thymian": "thyme",
  "rosmarin": "rosemary",
  "minze": "mint",
  "koriander": "cilantro",
  "kräuterbund": "herbs",
  "kräuter": "herbs",
};

function translateIngredients(raw: string): string[] {
  const segments = raw.split(/[,\n]/).map((s) => s.trim()).filter(Boolean);
  const result: string[] = [];
  for (const seg of segments) {
    const lower = seg.toLowerCase();
    let matched: string | null = null;
    for (const [de, en] of Object.entries(GERMAN_TO_ENGLISH)) {
      if (new RegExp(`\\b${de}\\b`, "i").test(lower)) {
        matched = en;
        break;
      }
    }
    result.push(matched ?? seg);
  }
  return [...new Set(result)].slice(0, 10);
}

function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, "").trim();
}

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
    if (!authHeader) {
      return json({ error: "Nicht angemeldet." }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: userErr } = await supabase.auth.getUser();
    if (userErr || !user) {
      return json({ error: "Nicht angemeldet." }, 401);
    }

    // Nur Admins dürfen die (kontingentierte) Rezept-API nutzen.
    const { data: admin } = await supabase.from("admins").select("id").eq("id", user.id).maybeSingle();
    if (!admin) {
      return json({ error: "Nur für Admins." }, 403);
    }

    const { ingredients } = await req.json();
    if (!ingredients || typeof ingredients !== "string" || !ingredients.trim()) {
      return json({ error: "Keine Zutaten angegeben." }, 400);
    }

    const apiKey = Deno.env.get("SPOONACULAR_API_KEY");
    if (!apiKey) {
      return json({ error: "Rezept-API ist noch nicht konfiguriert (SPOONACULAR_API_KEY fehlt)." }, 500);
    }

    const englishIngredients = translateIngredients(ingredients);
    if (!englishIngredients.length) {
      return json({ error: "Konnte keine Zutaten erkennen." }, 400);
    }

    const findUrl = `https://api.spoonacular.com/recipes/findByIngredients?ingredients=${
      encodeURIComponent(englishIngredients.join(","))
    }&number=1&ranking=2&ignorePantry=true&apiKey=${apiKey}`;
    const findRes = await fetch(findUrl);
    if (!findRes.ok) {
      const errText = await findRes.text();
      return json({ error: `Spoonacular-Fehler: ${findRes.status} ${errText}` }, 502);
    }
    const matches = await findRes.json();
    if (!Array.isArray(matches) || matches.length === 0) {
      return json({ error: "Kein passendes Rezept gefunden." }, 404);
    }

    const recipeId = matches[0].id;
    const infoUrl = `https://api.spoonacular.com/recipes/${recipeId}/information?apiKey=${apiKey}`;
    const infoRes = await fetch(infoUrl);
    if (!infoRes.ok) {
      const errText = await infoRes.text();
      return json({ error: `Spoonacular-Fehler: ${infoRes.status} ${errText}` }, 502);
    }
    const info = await infoRes.json();

    const title = info.title as string;
    const summary = stripHtml((info.summary as string) || "").split(". ").slice(0, 3).join(". ");
    const instructions = stripHtml((info.instructions as string) || "");
    const text = [summary, instructions].filter(Boolean).join("\n\n");

    return json({
      title,
      text: text || "Keine Beschreibung verfügbar.",
      sourceUrl: info.sourceUrl || null,
      usedIngredientsEnglish: englishIngredients,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
