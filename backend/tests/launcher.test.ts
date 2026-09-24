import { describe, expect, test } from "bun:test";
// @ts-expect-error The Node launcher is intentionally executable without compilation.
import { gameEnvironment } from "../../scripts/play.mjs";

describe("Godot credential boundary", () => {
  test("forwards client configuration while keeping provider and unrelated credentials out", () => {
    const result = gameEnvironment({
      HOME: "/tmp/example", PATH: "/usr/bin", LANG: "es_MX.UTF-8",
      OPENAI_API_KEY: "fixture-openai", JEV_API_KEY: "fixture-jev",
      TYPESAFE_API_KEY: "fixture-typesafe", CLOUDFLARE_API_TOKEN: "fixture-cloudflare",
      UNRELATED_SECRET: "fixture-unrelated", MY_CITY_DEV_TOKEN: "stale-fixture",
    }, { MY_CITY_DEV_TOKEN: "client-fixture", MY_CITY_API_URL: "http://127.0.0.1:8787", OPENAI_API_KEY: "fixture-extra" });
    expect(result).toEqual({
      HOME: "/tmp/example", PATH: "/usr/bin", LANG: "es_MX.UTF-8",
      MY_CITY_DEV_TOKEN: "client-fixture", MY_CITY_API_URL: "http://127.0.0.1:8787",
    });
  });

  test("offline launch needs no provider credentials and does not modify its source environment", () => {
    const system = { HOME: "/tmp/example", OPENAI_API_KEY: "fixture-openai" };
    expect(gameEnvironment(system)).toEqual({ HOME: "/tmp/example" });
    expect(system.OPENAI_API_KEY).toBe("fixture-openai");
  });
});
