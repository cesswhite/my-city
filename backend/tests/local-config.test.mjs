import { afterEach, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { parseEnv } from "node:util";
import { spawnSync } from "node:child_process";
import { readConfig, syncBackendConfig } from "../scripts/local-config.mjs";

const roots = [];
const fixture = "OPENAI_API_KEY=fake-openai-fixture\nJEV_API_KEY=fake-jev-fixture\nMY_CITY_DEV_TOKEN=fake-development-token-123456789012345\n";
function root(content = fixture) {
  const path = mkdtempSync(join(tmpdir(), "my-city-config-test-"));
  roots.push(path);
  mkdirSync(join(path, "backend"));
  if (content !== null) writeFileSync(join(path, ".env"), content, { mode: 0o600 });
  return path;
}
afterEach(() => { for (const path of roots.splice(0)) rmSync(path, { recursive: true, force: true }); });

test("aliases map in memory, root values stay intact, Godot gets only its two variables", () => {
  const content = fixture + "OPENAI_API_MODEL=custom-model\nUNRELATED_SECRET=do-not-forward\nOPENAI_API_BASE=https://api.openai.com/v1/\nOPENAI_API_VERSION=v1\n";
  const path = root(content);
  const config = readConfig(join(path, ".env"));
  expect(config.backend.TYPESAFE_API_KEY).toBe("fake-jev-fixture");
  expect(config.backend.OPENAI_MODEL).toBe("custom-model");
  expect(Object.keys(config.backend).sort()).toEqual(["MY_CITY_DEV_TOKEN", "OPENAI_API_KEY", "OPENAI_MODEL", "TYPESAFE_API_KEY"]);
  expect(Object.keys(config.client).sort()).toEqual(["MY_CITY_API_URL", "MY_CITY_DEV_TOKEN"]);
  expect(config.client.MY_CITY_API_URL).toBe("http://127.0.0.1:8787");
  expect(JSON.stringify(config.client)).not.toContain("fake-openai-fixture");
  expect(JSON.stringify(config.client)).not.toContain("fake-jev-fixture");
  expect(config.missing).toEqual([]);
  expect(readFileSync(join(path, ".env"), "utf8")).toBe(content);
});

test("derived dev vars are restricted, private, idempotent and refresh from the canonical file", () => {
  const path = root(fixture);
  const result = syncBackendConfig(path);
  const target = join(path, "backend", ".dev.vars");
  expect(result.source).toBe("root_env");
  expect(result.written).toBe(true);
  expect(statSync(target).mode & 0o777).toBe(0o600);
  expect(parseEnv(readFileSync(target, "utf8"))).toEqual(result.backend);
  expect(syncBackendConfig(path).written).toBe(false);
  writeFileSync(join(path, ".env"), fixture.replace("fake-jev-fixture", "fake-jev-rotated"));
  expect(syncBackendConfig(path).written).toBe(true);
  expect(parseEnv(readFileSync(target, "utf8")).TYPESAFE_API_KEY).toBe("fake-jev-rotated");
});

test("manual dev vars remain byte-for-byte untouched when root env is absent", () => {
  const path = root(null);
  const target = join(path, "backend", ".dev.vars");
  const content = "# manual fixture\nOPENAI_API_KEY='manual-fake-key'\n";
  writeFileSync(target, content, { mode: 0o640 });
  expect(syncBackendConfig(path)).toEqual({ source: "manual_dev_vars", written: false, backend: null, client: null, missing: null });
  expect(readFileSync(target, "utf8")).toBe(content);
  expect(statSync(target).mode & 0o777).toBe(0o640);
});

test("conflicting populated aliases fail without exposing values or replacing config", () => {
  const path = root(fixture + "TYPESAFE_API_KEY=different-fake-secret\n");
  const target = join(path, "backend", ".dev.vars");
  writeFileSync(target, "EXISTING=keep\n");
  try { syncBackendConfig(path); throw new Error("Expected conflict"); } catch (error) {
    expect(error.message).toContain("TYPESAFE_API_KEY y JEV_API_KEY");
    expect(error.message).not.toContain("different-fake-secret");
    expect(error.message).not.toContain("fake-jev-fixture");
  }
  expect(readFileSync(target, "utf8")).toBe("EXISTING=keep\n");
  const modelPath = root(fixture + "OPENAI_MODEL=model-a\nOPENAI_API_MODEL=model-b\n");
  expect(() => readConfig(join(modelPath, ".env"))).toThrow("OPENAI_MODEL y OPENAI_API_MODEL");
});

test("empty optional settings use defaults and absent keys remain visibly absent", () => {
  const path = root("OPENAI_API_KEY=\nJEV_API_KEY=\nOPENAI_API_MODEL=\nOPENAI_API_BASE=\nOPENAI_API_VERSION=\n");
  const config = syncBackendConfig(path);
  expect(config.backend.OPENAI_MODEL).toBe("gpt-6-luna");
  expect(config.missing).toEqual(["TYPESAFE_API_KEY", "OPENAI_API_KEY", "MY_CITY_DEV_TOKEN"]);
  expect(Object.keys(parseEnv(readFileSync(join(path, "backend", ".dev.vars"), "utf8")))).toEqual(["OPENAI_MODEL"]);
});

test("only official API base and path-version are accepted; client URLs are constrained", () => {
  for (const extra of ["OPENAI_API_BASE=https://wrong.example/v1", "OPENAI_API_VERSION=2026-09-23", "MY_CITY_API_URL=http://remote.example", "MY_CITY_API_URL=https://user:password@example.com", "MY_CITY_DEV_TOKEN=short"]) {
    const path = root(fixture + extra + "\n");
    expect(() => readConfig(join(path, ".env"))).toThrow();
  }
});

test("literal dollar signs survive derivation and no shell interpolation occurs", () => {
  const path = root(fixture.replace("fake-openai-fixture", "'fake-$TOKEN-$(do-not-run)-#literal'"));
  const config = syncBackendConfig(path);
  expect(config.backend.OPENAI_API_KEY).toBe("fake-$TOKEN-$(do-not-run)-#literal");
  expect(parseEnv(readFileSync(join(path, "backend", ".dev.vars"), "utf8")).OPENAI_API_KEY).toBe(config.backend.OPENAI_API_KEY);
});

test("inherited process credentials never fill missing root values", () => {
  const path = root("OPENAI_API_MODEL=gpt-6-luna\n");
  const moduleUrl = new URL("../scripts/local-config.mjs", import.meta.url).href;
  const code = `import { readConfig } from ${JSON.stringify(moduleUrl)}; console.log(readConfig(${JSON.stringify(join(path, ".env"))}).backend.OPENAI_API_KEY === "");`;
  const result = spawnSync(process.execPath, ["--no-env-file", "--eval", code], {
    cwd: tmpdir(), env: { OPENAI_API_KEY: "fake-inherited-key" }, encoding: "utf8",
  });
  expect(result.status).toBe(0);
  expect(result.stdout.trim()).toBe("true");
});
