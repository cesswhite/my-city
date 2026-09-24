# Contributing to My City

My City is an MVP released under the [MIT License](LICENSE). Contributions to original project code, documentation, and assets are made under the same license; retain the separate notices for any third-party material you introduce. Read [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before redistributing bundled fonts or dependencies.

## Prepare a change

1. Set up a local copy with the [README](README.md). Sprites are included and AI is optional.
2. Read [AGENTS.md](AGENTS.md), the [architecture](docs/architecture.md), and the [agent guide](docs/agent-guide.md). Find the existing owner of the responsibility you need to change.
3. Use a focused branch; agents use the `codex/` prefix. Avoid combining chat fixes with unrelated economy or art changes.
4. Preserve save compatibility, knowledge privacy, and deterministic economy rules. Use catalogs for content and modules for behavior.

Ordinary tests do not require provider credentials. Do not share `.env`, `.dev.vars`, real saves, or terminal captures containing sensitive values. Configuration examples have empty credential fields; do not fill them in for a commit.

## Verify

From the root, import resources and run the basic contract with your Godot executable:

```sh
godot --headless --editor --path game --import
godot --headless --path game --script res://tests/smoke.gd
```

From `backend/`, after `bun install --frozen-lockfile`:

```sh
bun run check
bun test
```

Before delivering simulation changes, run the basic smoke test and backend tests, plus regressions for the affected module. The [agent guide's test matrix](docs/agent-guide.md) helps select them. Scene fixtures that load `Main` often require `-- --ui-test`; do not omit that isolation.

For transport changes, `bun run test:godot` connects Godot to a local test Worker with a mocked provider. This launcher currently expects Godot at `/Applications/Godot.app/Contents/MacOS/Godot`. `bun run build` bundles with `--dry-run`; it does not deploy.

For UI and sprites, also inspect the scene with a real renderer, long text, keyboard focus, and different window sizes. Headless checks validate contracts, not visual appearance. Store working captures in `artifacts/`, which is excluded from Git.

Tests named `live` or using `--live-chat` are opt-in, require your own configuration, and may incur charges. Do not run them during ordinary validation or with another contributor's credentials.

Documentation-only changes need checks of links, paths, described commands, and consistency with implementation. They do not require image generation or provider calls. Write documentation in English; keep exact identifiers, NPC names, and quoted in-game labels intact.

## Explain the result

Describe the observable problem, resulting behavior, and checks performed. If persistent data changes, explain migration and how old saves remain usable. For UI, include a capture without private data when helpful. Identify checks you could not run and why.

Review the diff before uploading. Exclude caches, installed dependencies, credentials, saves, and exports containing local configuration. Generation costs, deployment, licensing changes, and visibility changes need a specific project-owner decision rather than being side effects of a contribution.
