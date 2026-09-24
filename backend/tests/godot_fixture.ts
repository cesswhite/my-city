/** Real loopback transport, fake provider only. Stops the fixture on every exit. */
import { resolve } from "node:path";
import { handleRequest, OPENAI_MODEL, type HttpFetch } from "../src/index";

const token = "my-city-godot-loopback-fixture-token-12345678";
const env = { MY_CITY_DEV_TOKEN: token, OPENAI_API_KEY: "fake-fixture-key-never-sent-to-internet" };
const fragments = [" ¡Hola, César! ", "¿Vamos al huerto? 🌿 "];
let requests = 0;
let providerCalls = 0;
let invalidHeaders = false;
const fakeProvider: HttpFetch = async (url, init) => {
  providerCalls++;
  const sent = JSON.parse(init.body as string);
  if (url !== "https://api.openai.com/v1/responses" || sent.stream !== true
    || new Headers(init.headers).get("Authorization") !== `Bearer ${env.OPENAI_API_KEY}`)
    throw new Error("Provider contract mismatch in fixture");
  if (providerCalls === 2) return new Response("rate limited", { status: 429 });
  const interrupted = providerCalls === 3;
  const encoder = new TextEncoder();
  const timers: ReturnType<typeof setTimeout>[] = [];
  const response = new ReadableStream<Uint8Array>({
    start(controller) {
      const emit = (event: Record<string, unknown>) => {
        const bytes = encoder.encode(`event: ${event.type}\r\ndata: ${JSON.stringify(event)}\r\n\r\n`);
        for (let at = 0; at < bytes.length; at += 7) controller.enqueue(bytes.slice(at, at + 7));
      };
      if (interrupted) {
        timers.push(setTimeout(() => emit({ type: "response.output_text.delta", delta: "Respuesta incompleta" }), 20));
        timers.push(setTimeout(() => {
          emit({ type: "response.failed", response: { status: "failed" } });
          controller.close();
        }, 150));
        return;
      }
      timers.push(setTimeout(() => emit({ type: "response.output_text.delta", delta: fragments[0] }), 20));
      timers.push(setTimeout(() => emit({ type: "response.output_text.delta", delta: fragments[1] }), 250));
      timers.push(setTimeout(() => {
        emit({ type: "response.completed", response: {
          model: OPENAI_MODEL, status: "completed",
          output: [{ type: "message", role: "assistant", content: [{ type: "output_text", text: fragments.join("") }] }],
        } });
        controller.close();
      }, 350));
    },
    cancel() { for (const timer of timers) clearTimeout(timer); },
  });
  return new Response(response, { headers: { "Content-Type": "text/event-stream" } });
};

const server = Bun.serve({
  hostname: "127.0.0.1", port: 18787,
  async fetch(request) {
    requests++;
    if (request.headers.get("Authorization") !== `Bearer ${token}`
      || request.headers.get("Content-Type") !== "application/json") invalidHeaders = true;
    return handleRequest(request, env, fakeProvider);
  },
});

try {
  const game = resolve(import.meta.dir, "../../game");
  const process = Bun.spawn([
    "/Applications/Godot.app/Contents/MacOS/Godot", "--headless", "--path", game, "--script", "res://tests/backend_smoke.gd",
  ], {
    env: {
      ...Bun.env,
      MY_CITY_DEV_TOKEN: token,
      MY_CITY_API_URL: "http://127.0.0.1:18787",
      OPENAI_API_KEY: "",
      TYPESAFE_API_KEY: "",
    },
    stdout: "pipe", stderr: "pipe",
  });
  const deadline = setTimeout(() => process.kill(), 20_000);
  const [exit, stdout, stderr] = await Promise.all([
    process.exited, new Response(process.stdout).text(), new Response(process.stderr).text(),
  ]);
  clearTimeout(deadline);
  console.log(stdout.trim());
  if (stderr.trim()) console.error(stderr.trim());
  if (exit !== 0 || requests !== 3 || providerCalls !== 3 || invalidHeaders)
    throw new Error(`Loopback integration failed: exit=${exit}, requests=${requests}, providerCalls=${providerCalls}, headers=${!invalidHeaders}`);
  console.log("PASS: Godot → Worker → mocked Responses SSE, HTTP 503 and streamed failure; valid Authorization and Content-Type; no external API call.");
} finally {
  await server.stop(true);
}
