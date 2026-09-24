import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { readConfig } from "../backend/scripts/local-config.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export function gameEnvironment(system, client = {}) {
  // Provider keys and unrelated process credentials never reach Godot or exports.
  const allowed = ["HOME", "PATH", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"];
  const environment = {};
  for (const name of allowed) if (system[name]) environment[name] = system[name];
  for (const name of ["MY_CITY_DEV_TOKEN", "MY_CITY_API_URL"]) {
    if (client[name]) environment[name] = client[name];
  }
  return environment;
}

async function main() {
  const envPath = resolve(root, ".env");
  const config = existsSync(envPath) ? await readConfig(envPath) : { client: {
    MY_CITY_DEV_TOKEN: process.env.MY_CITY_DEV_TOKEN,
    MY_CITY_API_URL: process.env.MY_CITY_API_URL,
  } };
  const child = spawn("/Applications/Godot.app/Contents/MacOS/Godot", ["--path", resolve(root, "game")], {
    cwd: root, env: gameEnvironment(process.env, config.client), stdio: "inherit",
  });
  child.on("error", () => { console.error("No se pudo iniciar Godot. Revisa su instalación."); process.exitCode = 1; });
  child.on("exit", code => { process.exitCode = code ?? 1; });
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error("No se pudo leer la configuración local. Ejecuta bun run configure en backend para revisarla."); process.exitCode = 1; });
}
