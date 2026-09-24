# My City · Mi Colonia

A small town that grows with you. Explore connected streets, get to know their inhabitants, gather materials, and build places that create new activities and relationships.

**An open-source, single-player local MVP**, built with Godot 4.7 and GDScript. A new game starts with **8 coins, two open areas, and two neighbors: Lupita and Inés**. César, Mateo, and Alma join as their homes are restored. The current world has six connected areas and saves progress between sessions.

[Getting started](#play-locally) · [Gameplay guide](docs/gameplay.md) · [Documentation](docs/README.md) · [Architecture](docs/architecture.md) · [LLM contributor guide](docs/agent-guide.md)

## What you can do

- Explore, gather, produce, help, trade, build, and open new streets.
- Ask neighbors to help based on their own interests, energy, routines, and willingness; they physically walk to their jobs.
- Talk and develop trust, affection, tolerance, and conflict. Gossip retains its origin and who heard it.
- Learn procedures, complete requests, and demonstrate what you have learned.
- Visit homes, browse albums, water plants, open curtains, sit down, drink coffee, and ride a bicycle.
- Watch day and night, lights, fictional weather, vegetation that reacts and regrows, and occasional fruit.

The simulation and its rules work locally. An optional connection uses Jev for bounded decisions and OpenAI for streamed conversations. **Models cannot invent coins, materials, buildings, or unlocks.** The current in-game language is Spanish; repository documentation is English.

## Play locally

Install Git and Godot 4.7; this MVP was validated with Godot 4.7.2. PNGs and fonts are included. Opening the game does not require image generation or API keys.

```sh
git clone https://github.com/cesswhite/my-city.git
cd my-city
godot --headless --editor --path game --import
godot --path game
```

`godot` means the installed Godot executable on your PATH. On macOS with the standard app installation, substitute `/Applications/Godot.app/Contents/MacOS/Godot`. You can also import `game/project.godot` in the editor and run the main scene. The initial import prepares the local resource cache.

Development and validation have taken place on macOS. `Play.command`, `Start-AI.command`, and some integration fixtures assume that Godot installation; they are not universal launchers. There is no published cross-platform installer or packaged release yet.

Choose **Nueva partida** (New game), then **Diario → Pueblo** (Journal → Town) to see your next objective. Existing saves retain their population and progress; they are not reset to the smaller beginning.

| Control | Action |
| --- | --- |
| WASD / arrow keys / click the ground | Walk |
| E / click a highlighted object | Interact |
| Click a neighbor | Open their profile |
| M | View the map |
| Journal in the bottom toolbar | Town and learning activities |
| Space | Pause |
| Esc | Close a panel or open the menu |
| Enter / Shift+Enter in chat | Send / insert a line break |
| F11 | Toggle windowed/fullscreen |

The [gameplay guide](docs/gameplay.md) explains energy, sleep, coffee, visits, requests, and autonomy. The world does not advance while the application is closed.

## AI conversations — optional

Install **Node.js 22** and **Bun**, and use accounts with access to the configured models. Validation used Node 22.23.1 and Bun 1.3.13. Each developer supplies their own credentials and pays for their provider usage. A model available to the development account is not guaranteed to be available to another account.

1. Copy `.env.example` to `.env` at the repository root. Do not overwrite existing configuration.
2. Fill in provider keys and `MY_CITY_DEV_TOKEN` in that local file. Generate a random token with `openssl rand -hex 32`; do not share it.
3. In a terminal, starting at the repository root:

```sh
cd backend
bun install --frozen-lockfile
bun run dev
```

4. On macOS, keep the service running and launch `Play.command` from the root. The launcher gives Godot only the service URL and local token, plus basic system variables. Provider keys remain in the backend. On other systems, read the [configuration contract](backend/README.md) and adapt the launcher's executable path before using it.

The default service address is `http://127.0.0.1:8787`. This runs a local service; model requests still leave the machine and reach their providers. Do not load the whole `.env` file into the game's environment. `.env` and `backend/.dev.vars` are excluded from Git.

Without a connection, the game uses local behavior. Network failures remain explicit failures; a simulated test does not prove a real connection. For incomplete replies, see [chat troubleshooting](docs/chat-reliability.md).

## Develop with a person or an LLM

Start with [AGENTS.md](AGENTS.md), the [agent guide](docs/agent-guide.md), and the [architecture](docs/architecture.md). They explain state ownership, extension points, and invariants. [CONTRIBUTING.md](CONTRIBUTING.md) describes the change and verification workflow.

| Directory | Contents |
| --- | --- |
| `game/scripts/` | Simulation, navigation, persistence, rendering, and UI |
| `game/data/` | Residents, areas, geometry, requests, and catalog-driven economy |
| `game/assets/` | Sprites, atlases, and fonts loaded by Godot |
| `game/tests/` | State, integration, and presentation checks |
| `backend/` | TypeScript Worker, validation, providers, and fixtures |
| `scripts/` | Launcher and art-preparation tools |
| `output/imagegen/` | Source images, prompts, and generated-art provenance |
| `docs/` | Guides, contracts, design, and validation records |

After importing resources, run the basic simulation contract from the root:

```sh
godot --headless --path game --script res://tests/smoke.gd
```

From `backend/`, after installing dependencies:

```sh
bun run check
bun test
```

These checks use synthetic data and mocked providers. Live AI checks are optional and may incur charges; they are not part of ordinary contribution validation. The [agent guide](docs/agent-guide.md) includes scene and visual-test instructions.

## Scope and privacy

Saves are local (`user://colony.json`), without remote synchronization or multiplayer. The backend uses a development token. A public hosted service would need user identity, authorization, and usage limits. Publishing this repository does not deploy that service.

Read [SECURITY.md](SECURITY.md) before sharing logs, saves, or configuration. [Release preparation](docs/publishing.md) describes privacy checks and distribution boundaries.

## License

Original project code, documentation, and original art assets are available under the **[MIT License](LICENSE)**, to the extent the contributors hold rights in them. You may use, modify, redistribute, and sell copies, including in commercial projects, while retaining the required copyright and license notice.

Bundled fonts and other third-party material retain their own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Generated-art records document provenance; they do not guarantee exclusivity or third-party clearance. Provider credentials, access to AI services, and service subscriptions are not included.
