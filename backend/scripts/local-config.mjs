import { existsSync, mkdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import { parseEnv } from "node:util";

const DEFAULT_MODEL = "gpt-6-luna";
const DEFAULT_API_URL = "http://127.0.0.1:8787";
const REQUIRED = ["TYPESAFE_API_KEY", "OPENAI_API_KEY", "MY_CITY_DEV_TOKEN"];

function value(env, name) {
  const selected = (env[name] ?? "").trim();
  if (/[\r\n\0']/.test(selected)) throw new Error(`${name}: usa un valor de una sola línea sin comillas simples.`);
  return selected;
}

function alias(env, canonical, alternate) {
  const first = value(env, canonical), second = value(env, alternate);
  if (first && second && first !== second)
    throw new Error(`${canonical} y ${alternate} contienen valores diferentes; elige una única fuente.`);
  return first || second;
}

/**
 * Parse only the explicit root file. Never mutates it or merges process.env.
 * backend holds provider secrets; client contains only the development token and URL.
 */
export function readConfig(rootEnvPath) {
  let env;
  try {
    env = parseEnv(readFileSync(rootEnvPath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") throw new Error("No existe .env en la raíz del proyecto.");
    throw new Error("No se pudo leer la configuración .env del proyecto.");
  }
  const base = value(env, "OPENAI_API_BASE").replace(/\/+$/, "");
  const version = value(env, "OPENAI_API_VERSION");
  if (base && base !== "https://api.openai.com/v1")
    throw new Error("OPENAI_API_BASE: este backend sólo admite https://api.openai.com/v1.");
  if (version && version !== "v1")
    throw new Error("OPENAI_API_VERSION: sólo se admite v1 como parte de la ruta oficial, sin parámetro de versión.");
  const token = value(env, "MY_CITY_DEV_TOKEN");
  if (token && token.length < 32) throw new Error("MY_CITY_DEV_TOKEN debe tener al menos 32 caracteres.");
  const apiUrl = value(env, "MY_CITY_API_URL") || DEFAULT_API_URL;
  let parsedUrl;
  try { parsedUrl = new URL(apiUrl); } catch { throw new Error("MY_CITY_API_URL no es una URL válida."); }
  if (parsedUrl.username || parsedUrl.password || parsedUrl.search || parsedUrl.hash
    || (parsedUrl.protocol !== "https:" && !(parsedUrl.protocol === "http:" && parsedUrl.hostname === "127.0.0.1")))
    throw new Error("MY_CITY_API_URL debe usar HTTPS o HTTP en 127.0.0.1, sin credenciales, consulta ni fragmento.");
  const backend = {
    TYPESAFE_API_KEY: alias(env, "TYPESAFE_API_KEY", "JEV_API_KEY"),
    OPENAI_API_KEY: value(env, "OPENAI_API_KEY"),
    MY_CITY_DEV_TOKEN: token,
    OPENAI_MODEL: alias(env, "OPENAI_MODEL", "OPENAI_API_MODEL") || DEFAULT_MODEL,
  };
  return {
    backend,
    client: { MY_CITY_DEV_TOKEN: token, MY_CITY_API_URL: apiUrl.replace(/\/+$/, "") },
    missing: REQUIRED.filter((name) => !backend[name]),
  };
}

/**
 * Root .env is canonical when present. Regenerate its ignored, 0600 .dev.vars view.
 * If absent, preserve manual .dev.vars byte-for-byte without reading its values.
 */
export function syncBackendConfig(projectRoot) {
  const rootEnvPath = join(projectRoot, ".env");
  const devVarsPath = join(projectRoot, "backend", ".dev.vars");
  if (!existsSync(rootEnvPath)) {
    return {
      source: existsSync(devVarsPath) ? "manual_dev_vars" : "unconfigured",
      written: false,
      backend: null,
      client: null,
      missing: null,
    };
  }
  const config = readConfig(rootEnvPath);
  const lines = ["# Generado desde .env de la raíz. Edita ese archivo; este derivado se regenera al iniciar."];
  for (const [name, setting] of Object.entries(config.backend)) {
    // .dev.vars uses dotenv parsing without expansion: literal $ stays literal.
    if (setting) lines.push(`${name}='${setting}'`);
  }
  const output = lines.join("\n") + "\n";
  mkdirSync(dirname(devVarsPath), { recursive: true });
  let unchanged = false;
  try {
    unchanged = readFileSync(devVarsPath, "utf8") === output && (statSync(devVarsPath).mode & 0o777) === 0o600;
  } catch { /* Missing or unreadable derived file will be replaced atomically. */ }
  if (!unchanged) {
    const temporary = `${devVarsPath}.tmp-${process.pid}-${randomBytes(6).toString("hex")}`;
    try {
      writeFileSync(temporary, output, { encoding: "utf8", mode: 0o600, flag: "wx" });
      renameSync(temporary, devVarsPath);
    } finally {
      try { unlinkSync(temporary); } catch { /* Rename normally removed it. */ }
    }
  }
  return { source: "root_env", written: !unchanged, ...config };
}

function main() {
  const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
  try {
    const config = syncBackendConfig(projectRoot);
    if (config.source === "manual_dev_vars") {
      console.log("Configuración: .env raíz ausente; se conserva .dev.vars manual sin inspeccionar valores.");
    } else if (config.source === "unconfigured") {
      console.log("Configuración: sin .env raíz ni .dev.vars; el backend informará claves ausentes.");
    } else {
      console.log(`Configuración: .dev.vars ${config.written ? "actualizado" : "sin cambios"} desde .env raíz.`);
      for (const [name, setting] of Object.entries(config.backend)) console.log(`${name}: ${setting ? "configurado" : "ausente"}`);
    }
  } catch (error) {
    // All explicit configuration errors contain variable names, never values.
    const safe = error instanceof Error && !Object.hasOwn(error, "code") ? error.message : "No se pudo preparar la configuración local.";
    console.error(safe);
    process.exitCode = 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
