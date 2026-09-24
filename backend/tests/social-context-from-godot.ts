/** Explicit local integration check: real isolated Colony contexts, mocked HTTP. */
import { mkdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath, URL as NodeURL } from "node:url";
import { deepStrictEqual, ok, strictEqual } from "node:assert";
import { handleRequest, JEV_MODEL, OPENAI_MODEL, type HttpFetch } from "../src/index";

const root = fileURLToPath(new NodeURL("../../", import.meta.url));
const output = resolve(root, "artifacts/social-knowledge/core-contexts.json");
mkdirSync(resolve(root, "artifacts/social-knowledge"), { recursive: true });
const godot = process.env.GODOT_BIN || "/Applications/Godot.app/Contents/MacOS/Godot";
const generated = Bun.spawnSync([godot, "--headless", "--path", resolve(root, "game"), "--script",
  resolve(root, "backend/tests/social_context_fixture.gd"), "--", "--ui-test"], {
  cwd: root, stdout: "pipe", stderr: "pipe", timeout: 30_000,
  // The fixture needs neither providers nor an inherited development token.
  env: { PATH: process.env.PATH, HOME: process.env.HOME, LANG: process.env.LANG },
});
if (generated.exitCode !== 0) {
  process.stderr.write(generated.stdout);
  process.stderr.write(generated.stderr);
  throw new Error("Isolated Godot fixture did not finish successfully.");
}
type Row = { name: string; context: Record<string, any>; expected_claim?: string; excluded_text?: string; expected_case?: boolean };
const rows = JSON.parse(readFileSync(output, "utf8")) as Row[];
ok(rows.length >= 4, "The real core supplies public, disclosed, withheld and case contexts.");
const token = "synthetic-social-integration-token-123456";
let checked = 0;
for (const row of rows) {
  const resident = row.context;
  ok([...JSON.stringify(resident)].length <= 12_000, row.name + " stays within the complete context budget");
  ok([...JSON.stringify(resident.social_context)].length <= 2_400, row.name + " stays within the social budget");
  if (row.expected_claim) ok(resident.social_context.claims.some((claim: Record<string, unknown>) => claim.id === row.expected_claim), row.name + " preserves the authorized claim");
  if (row.excluded_text) ok(!JSON.stringify(resident).includes(row.excluded_text), row.name + " does not leak withheld content through another field");
  if (row.expected_case) strictEqual(resident.social_context.case.subject_id, resident.identity.id, row.name + " owns its case");
  for (const route of ["/dialogue", "/dialogue/stream", "/decide"]) {
    let calls = 0;
    const fetcher: HttpFetch = async (url, init) => {
      calls++;
      const sent = JSON.parse(init.body as string);
      const forwarded = route === "/decide" ? sent.state.resident : JSON.parse(sent.input[0].content[0].text).resident;
      deepStrictEqual(forwarded, resident, row.name + " forwards exactly the core-filtered context");
      strictEqual(init.redirect, "manual");
      if (route === "/decide") {
        strictEqual(url, "https://api.typesafe.ai/v1/systemone");
        return Response.json({ model: JEV_MODEL, answers: { action: { type: "choice", choice: "descansar", confidence: 1,
          probabilities: Object.fromEntries(resident.allowed_actions.map((action: string) => [action, action === "descansar" ? 1 : 0])) } } });
      }
      strictEqual(url, "https://api.openai.com/v1/responses");
      const text = "Gracias por decírmelo.";
      const final = { model: OPENAI_MODEL, status: "completed", output: [{ type: "message", role: "assistant", content: [{ type: "output_text", text }] }] };
      if (route === "/dialogue") return Response.json(final);
      const event = (type: string, data: object) => `event: ${type}\ndata: ${JSON.stringify({ type, ...data })}\n\n`;
      return new Response(event("response.output_text.delta", { delta: text }) + event("response.completed", { response: final }), { headers: { "Content-Type": "text/event-stream" } });
    };
    const payload = route === "/decide" ? { resident, allowed_actions: resident.allowed_actions }
      : { resident, utterance: "¿Qué me puedes contar?", speaker: { id: resident.partner_id, name: "Interlocutor de prueba" } };
    const request = new Request("http://127.0.0.1:8787" + route, { method: "POST", headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" }, body: JSON.stringify(payload) });
    const response = await handleRequest(request, { MY_CITY_DEV_TOKEN: token, OPENAI_API_KEY: "fake-key", TYPESAFE_API_KEY: "fake-key" }, fetcher);
    if (response.status !== 200) throw new Error(row.name + " " + route + " rejected: " + await response.text());
    const result = await response.text();
    if (route.endsWith("stream")) ok(result.includes("event: done") && !result.includes("event: error"), "Real core context preserves successful streaming");
    strictEqual(calls, 1);
    checked++;
  }
}
console.log(`CORE → BACKEND SOCIAL: ${checked}/${checked} route checks; ${rows.length} real core contexts; no provider/network calls.`);
