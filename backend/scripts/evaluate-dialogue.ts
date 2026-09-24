/** Bounded manual evaluation: eight fictional SSE requests, no save access.
 * Run --health first; --live explicitly enables the eight paid provider calls.
 * Artifacts contain only fixtures, generated dialogue and timing, never config.
 */
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
// @ts-expect-error The shared local config helper runs directly in Node/Bun.
import { readConfig } from "./local-config.mjs";

const root = resolve(import.meta.dir, "../..");
const scene = {
  activity_before_chat: "Ordenando herramientas", routine: "Compartir el oficio",
  place: "taller", place_label: "el taller", intent: "", ongoing_action: "sort_tools",
  phase: "working", next_plan: "Dar una vuelta por el huerto (el huerto)", paused_for_chat: true,
};
const memory = (question: string, answer: string) => ({
  participants: ["player", "mateo"], content: `Alex: ${question} Mateo: ${answer}`,
  heard_from: "player", heard_text: question, source: "conversacion_directa", time: "día 1 a las 10:00",
});
export const QUALITY_CASES = [
  { id: "saludo", utterance: "Hola, Mateo. ¿Cómo estás?", scene, recent: [], criterion: "Devuelve un saludo natural; no desvía hacia biografía, aceite o una misión." },
  { id: "actividad_hoy_historial_defectuoso", utterance: "¿Qué estás haciendo hoy?", scene,
    recent: [memory("¿Qué estás haciendo hoy?", "Hoy estoy conversando contigo; normalmente me gusta arreglar bicicletas y compartir mi oficio.")],
    criterion: "Usa ordenar herramientas antes de la pausa; no repite charla/hobby ni imita el historial defectuoso." },
  { id: "descanso_no_reparacion", utterance: "¿En qué andabas antes de que llegara?", scene: { ...scene, activity_before_chat: "Tomando un descanso en la plaza", routine: "Pasear por la colonia", place: "plaza", place_label: "la plaza", ongoing_action: "take_break", phase: "leisure", next_plan: "" }, recent: [],
    criterion: "Describe el descanso; no inventa que reparaba una bici por su oficio." },
  { id: "camino_no_llegada", utterance: "¿A dónde ibas?", scene: { ...scene, activity_before_chat: "Caminando al café", routine: "Tomar un descanso", place: "calle", place_label: "la calle", intent: "cafe", ongoing_action: "walk", phase: "walking", next_plan: "Tomar un descanso (el café)" }, recent: [],
    criterion: "Iba hacia el café; no afirma que ya llegó o tomó algo." },
  { id: "plan_no_hecho", utterance: "¿Y qué piensas hacer después?", scene, recent: [],
    criterion: "Presenta la visita al huerto como plan, no como hecho pasado ni obligación del jugador." },
  { id: "seguimiento_resuelto", utterance: "Ah, ya entendí. ¿Y luego?", scene,
    recent: [memory("¿Qué estabas haciendo?", "Estaba ordenando mis herramientas."), memory("¿Dónde las guardas?", "Las guardo en el cajón del banco.")],
    criterion: "Continúa con el siguiente plan, sin volver a explicar dónde guarda herramientas ni repetir preguntas resueltas." },
  { id: "actividad_desconocida", utterance: "¿Qué hiciste esta mañana?", scene: { ...scene, activity_before_chat: "", routine: "", place: "plaza", place_label: "la plaza", ongoing_action: "", phase: "idle", next_plan: "" }, recent: [],
    criterion: "No inventa un pasado a partir del oficio, el lugar actual o una actividad ausente." },
  { id: "reparacion_sin_resultado", utterance: "¿Ya terminaste de arreglar la bicicleta?", scene: { ...scene, activity_before_chat: "Revisando la rueda de una bicicleta", ongoing_action: "repair", next_plan: "" }, recent: [],
    criterion: "Sigue revisando o no confirma el resultado; no afirma una reparación terminada ni concede una habilidad." },
];

export function qualityPayload(entry: typeof QUALITY_CASES[number]) {
  return {
    resident: {
      identity: { id: "mateo", name: "Mateo", role: "Mecánico del taller", goal: "Quiero arreglar la bicicleta de César y compartir lo que sé." }, biography: "Aprendió el oficio observando a su abuelo.",
      personality: { sociability: "tranquilo y atento" }, activity: "Conversando con Alex",
      conversation_scene: entry.scene, pair_id: "mateo:player", partner_id: "player",
      recent_conversation: entry.recent, memories: [],
    },
    speaker: { id: "player", name: "Alex" }, utterance: entry.utterance,
    suggest_replies: true, reply_facts: ["Aún no tengo aceite.", "Aún no tengo semillas."],
  };
}

function parseEvents(raw: string) {
  return raw.trim().split(/\r?\n\r?\n/).map((frame) => {
    const type = frame.match(/^event: (.+)$/m)?.[1];
    const data = frame.split(/\r?\n/).filter((line) => line.startsWith("data: ")).map((line) => line.slice(6)).join("\n");
    return { type, data: JSON.parse(data) as Record<string, unknown> };
  });
}
async function main() {
  if (!Bun.argv.includes("--live") && !Bun.argv.includes("--health")) {
    console.log("Use --health for local status; --live explicitly runs exactly eight fictional conversations.");
    return;
  }
  const selectedArgument = Bun.argv.find((argument) => argument.startsWith("--cases="));
  const selectedIds = selectedArgument?.slice("--cases=".length).split(",");
  if (selectedIds && (!selectedIds.length || new Set(selectedIds).size !== selectedIds.length || selectedIds.some((id) => !QUALITY_CASES.some((entry) => entry.id === id))))
    throw new Error("Unknown or repeated evaluation scenario.");
  const selectedCases = selectedIds ? QUALITY_CASES.filter((entry) => selectedIds.includes(entry.id)) : QUALITY_CASES;
  const { client } = readConfig(resolve(root, ".env"));
  if (client.MY_CITY_API_URL !== "http://127.0.0.1:8787") throw new Error("Evaluation requires the existing local endpoint.");
  const headers = { Authorization: "Bearer " + client.MY_CITY_DEV_TOKEN, "Content-Type": "application/json" };
  const health = await fetch(client.MY_CITY_API_URL + "/health", { headers, signal: AbortSignal.timeout(3000) });
  const healthData = await health.json() as Record<string, unknown>;
  console.log(JSON.stringify({ health: health.status, model: healthData.dialogue_model, configured: healthData.openai_configured }));
  if (!Bun.argv.includes("--live")) return;
  if (!health.ok || !healthData.openai_configured || healthData.dialogue_model !== "gpt-6-luna") throw new Error("Local model configuration is not ready.");
  const artifacts = resolve(root, "artifacts/natural-chat");
  await mkdir(artifacts, { recursive: true });
  const results: Record<string, unknown>[] = [];
  // Sequential by design: never retry or silently expand a targeted call budget.
  for (const entry of selectedCases) {
    const payload = qualityPayload(entry);
    try {
      const response = await fetch(client.MY_CITY_API_URL + "/dialogue/stream", { method: "POST", headers, body: JSON.stringify(payload), signal: AbortSignal.timeout(15000) });
      if (!response.ok) {
        results.push({ id: entry.id, question: entry.utterance, http: response.status, error: "HTTP failure; provider body omitted" });
        continue;
      }
      const events = parseEvents(await response.text());
      const done = events.find((event) => event.type === "done")?.data;
      if (!done) {
        results.push({ id: entry.id, question: entry.utterance, http: response.status, error: "No completed dialogue; partial output omitted" });
        continue;
      }
      const text = String(done.text);
      const visible = events.filter((event) => event.type === "delta").map((event) => String(event.data.text)).join("");
      const row = { id: entry.id, question: entry.utterance, scene: entry.scene, recent: entry.recent, criterion: entry.criterion,
        text, suggestions: done.suggestions, ttft_ms: done.ttft_ms, total_ms: done.total_ms,
        checks: { exact_stream: text === visible, brief: [...text].length <= 180 && text.trim().split(/\s+/u).length <= 30,
          compact: !/[\r\n—]|\s{2}/u.test(text), no_chat_state_recital: !/(?:conversando|hablando) contigo/iu.test(text) } };
      results.push(row);
      console.log(JSON.stringify(row));
    } catch {
      results.push({ id: entry.id, question: entry.utterance, error: "Evaluation transport failed; no automatic retry" });
    }
  }
  const artifact = selectedIds ? "evaluation-targeted.json" : "evaluation.json";
  await writeFile(resolve(artifacts, artifact), JSON.stringify({ date: new Date().toISOString(), model: "gpt-6-luna", calls: results.length, synthetic_context_only: true, results }, null, 2) + "\n");
  if (results.some((result) => Object.hasOwn(result, "error"))) process.exitCode = 1;
}

if (import.meta.main) main().catch(() => { console.error("Evaluation stopped; configuration and exception details omitted."); process.exitCode = 1; });
