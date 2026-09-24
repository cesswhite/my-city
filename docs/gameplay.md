# Gameplay guide · My City

A detailed guide to the current mechanics. Run commands from the repository root. For installation, see the [README](../README.md); for development, see the [agent guide](agent-guide.md).

An experimental game about living together and growing a town, with five neighbors who have their own histories and a customizable player character. A new game begins with Lupita, Inés, and your character; the others arrive or return as you restore their homes. Built with Godot 4.7 and GDScript.

The world contains **six connected areas**, opened in stages: the plaza and Inés's café, Lupita's street and your home, César's garden, Mateo's workshop, Alma's corner, and a grove west of the houses. Walk through the passages at each edge to explore; **M** opens the map. Neighbors also travel these streets as part of their routines. Layout, architecture, and compatibility with older saves: [connected neighborhood](barrio-conectado.md).

The prototype can run on local rules or connect to Jev and OpenAI through a local Worker. On September 23, 2026, a real Jev decision and a real streamed OpenAI conversation were verified using locally configured keys. The service has not been deployed. The world, characters, accessories, furniture, and interface already use PNG sprites produced with **GPT Image 2.5 Sunburst** (`gpt-image-2.5-sunburst-2026-09-08`). The September 24 visual revision unifies 54 building, vegetation, furniture, and terrain sprites with a shared palette and consistent perspective. See the [visual audit](pixel-art-audit.md), [pixel art system](pixel-art-design-system.md), and [production and validation log](pixel-art-production.md). Characters retain eight appearance options through layered sprites and four movement directions. Sources, prompts, provenance, and reproducible imports are documented in [modular art](arte-modular.md).

## Growing the town

You start with **8 coins, two open streets, and two neighbors**. The journal ("Diario") opens the town section ("Pueblo") and shows the next objective. Collect two units of wood and two of stone near the houses, prepare the workbench, and inspect the blocked path to the garden. Objects and plots highlight under the pointer; click to see requirements and begin. Activities first take you to their location on foot and progress only after you arrive.

- **Resources:** branches, stones, fiber, fruit, and crops have reserves that replenish daily. The workbench turns wood into planks and fiber into compost; the workshop and café provide production later.
- **Economy:** sell at the shop against daily demand or deliver orders directly to the people who requested them. Coins and materials use the existing inventory. Coffee and apprenticeships retain their rules.
- **Projects:** invest materials and coins once, work on the plot, and open paths, homes, and useful buildings. Interrupted construction keeps its progress; canceling a recipe returns its ingredients. Upgrades increase harvests or commercial demand. The community hall enables a new community order.
- **Neighbors:** choose "Pedir ayuda" (ask for help) in a profile, or assign an activity from the journal. Their interests, occupation, responsibility, energy, and relationship with you determine whether they accept. They may also offer free work during breaks; they never spend your coins or materials on their own initiative.
- **Exploration:** neighbors walk to the entrance and return to the noticeboard with a report and findings defined by the game. The model does not invent rewards or unlock land. A report you hear retains its provenance.
- **Crops:** preparing the garden, planting, watering, waiting, and harvesting produces vegetables repeatedly. Plants change appearance to reflect their actual state.

César arrives when you restore his home; Mateo returns to the family workshop; Alma returns to her corner, preserving their previous histories. Each opening adds places, activities, and social possibilities. Commitments pause during sleep or conversation and resume afterward; NPCs carry their findings until delivery. Walking manually cancels your current activity.

**Continuing an older save preserves all its neighbors, five streets, money, memories, and learning.** The grove and new upgrades remain available to unlock. Only "Nueva partida" (new game) uses the reduced starting state. A backup is retained before replacing a save, and there is no offline progress.

Previous audit and architecture: [town design](settlement-design.md). Interface and tests: [town journal](settlement-ui.md). Content and rules: `game/data/settlement.json`; willingness to work: `work_profile` in `game/data/residents.json`.

## Launching the game

From the project directory, with Godot installed at `/Applications/Godot.app`:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path game --import
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

The first command imports resources after cloning the repository. To enable conversation services, install dependencies with `cd backend && bun install --frozen-lockfile`, copy `.env.example` to `.env` at the root, and fill in the keys and local token. The example contains only empty values and public options; `.env` and `backend/.dev.vars` are excluded from Git.

You can also import `game/project.godot` in Godot 4.7. The game opens a fullscreen main menu with "Iniciar / Continuar partida" (start/continue), "Nueva partida" (new game), "Ajustes" (settings), "Controles" (controls), and "Salir del juego" (quit). Settings let you choose windowed or fullscreen mode and vertical sync, and retain your choices. A new game opens the neighborhood; customization is available at the wardrobe in your home. If progress already exists, the game asks for confirmation and preserves an independent backup before replacing it.

The world fills the window. Three floating groups contain indicators and shortcuts, leaving more than 90% of the view free at the base logical resolution. The bottom bar contains only compact journal and bicycle buttons. Customization opens when you approach your wardrobe. Selecting a person opens their profile and chat; closing them restores the full view without changing the map scale. Interaction hints appear at the bottom right. Long notices remain until dismissed and allow scrolling through the full text. The logical base is 768 × 432, and the interface adapts to the screen's aspect ratio. Nearest filtering preserves unsmoothed pixel art; fractional scaling fills the screen, although pixels can have unequal widths at non-integer scales. Pixel Operator is used for reading and Pixelify Sans for headings. Details and tests: [menus and display](menu-y-pantalla.md).

To use your `.env` keys, first open **Start-AI.command** and leave that terminal open. Then open **Play.command**: conversations you start use OpenAI if the game received the local token. The "IA" control is in the top bar beside pause and starts enabled when the local token is configured. It enables Jev decisions and background conversations. Tests and previews remain disconnected. Startup prepares the Worker configuration and gives Godot only the local token and service URL. OpenAI and Jev keys stay outside the Godot process and resources. Close and reopen the game if it was already running before you configured `.env`.

## Controls and autonomy

| Control | Action |
| --- | --- |
| **WASD** or **arrow keys** | Walk outdoors or indoors, respecting obstacles |
| **Click** a path | Travel to that point along an available route |
| **M** / location card | View the map; walk or click an exit to cross into another area |
| **Click** a seat / **E** beside it | Approach and sit; press **E**, **WASD**, or click a path to stand |
| **C** while seated at a café table | Order and pay 3 coins for coffee; drink it if you already have a cup |
| **Hover** over an interactive object | See a soft glow and its action; click to approach and use it |
| **Hover** over a neighbor | Highlight their silhouette; click to open their profile and choose an interaction |
| **E** near a door, shop, object, or person | Open the corresponding interaction; beside a person, open their panel |
| **Escape** | Close the active panel or release the text field; with no active panel, open the menu |
| **Arrows / Tab** in a house modal | Move between the main action and "Volver" (back); **Enter** confirms the highlighted option |
| **Menu** icon / **Esc** | Resume, save, view controls and settings, or return to the main menu |
| **F11** | Toggle fullscreen/windowed mode |
| "Historial" (history) | Read neighborhood notices in full |
| **Space** or **pause** icon | Pause or resume the simulation |
| "Vivir solo" (autonomy) | Opt into your character's routine and encounters |
| "Tomar control" (take control) | Return to manual control at **1×** speed |
| **1× / 2× / 4×** | Change the local simulation speed |

Gameplay shortcuts do not run while you are typing in a field or an interaction modal is open. You can also regain control by walking with WASD/arrows or issuing a manual movement or interaction order; this disables "Vivir solo" and resets speed to **1×**. Previous player orders are canceled.

The glow follows the sprite silhouette, and the pointer becomes a hand. The bottom hint names actions such as sleep, inspect, buy, or knock. Doors, usable furniture, and the exit mat share the same hover and click detection, including after window resizing. Decorative items keep their appearance. The effect reuses masks in memory, makes no AI calls, and does not modify PNGs. Tests: `world_interactions_smoke.gd`, `interaction_glow_smoke.gd`, and `hover_ui_smoke.gd` (the last requires `-- --ui-test`).

Neighbors also highlight on hover. The outline follows their clothing, hair, and accessory layers as they walk or work; while asleep, only the head visible above the pillow highlights. The hint reads "Clic: Ver perfil · Nombre" (click: view profile · name). Hovering does not start a conversation, stop them, or change their willingness to talk. Objects in front still cover the outline, and panels block hover over the world behind them.

There are fourteen outdoor seats: eleven in the plaza and three additional benches on the residential street, in the garden, and in Alma's corner. The pointer highlights only the usable sitting area. The character walks to a free point before taking the pose, retains their appearance, and stands when given a new order. Details and tests: [seating](asientos.md).

Sitting on one of the four café stools displays "Pedir café · 3 monedas" (order coffee · 3 coins). Click or press **C** to pay and receive a cup on the table; the button then changes to "Beber café" (drink coffee), without another charge. Each cup consumed restores **5 energy points**, capped at **100%**; purchasing it does not yet restore energy. The indicator updates when you drink, and the benefit is saved. Insufficient funds cause no deduction. You can have only one unconsumed cup, retained in your backpack and save if you stand before drinking. Sitting does not buy anything automatically. Park benches and the fountain do not offer coffee service. `coffee_smoke.gd` and `coffee_world_smoke.gd -- --ui-test` check payment, consumption, energy, saving, controls, and seats.

"Vivir solo" lets you watch your character follow schedules and take part in encounters while the game is open and unpaused. It uses local rules; with "IA" enabled, it can incorporate Jev decisions and OpenAI conversations. **2×/4×** speeds up the local world, not the network: Jev requests remain at least four real seconds apart and are distributed among residents. Provider response times may extend that wait.

General shortcuts use named icons with help on hover or focus. The HUD shows energy, available coins, demonstrated learning, and known neighbors. Energy decreases during waking hours and recovers through rest or sleep in your bed. At **0%**, you fall asleep wherever you are for **8 real seconds**, waking at **5%** without being able to move or wake early. Conversation controls retain text labels. Rules, persistence, and icon provenance: [HUD and statistics](hud-y-estadisticas.md).

To **sleep**, click your bed or press **E** beside it. Choose eight hours, a nap, or until 7:00. **Each hour of sleep takes one real second: eight hours take eight seconds**, while the colony remains active and you recover energy. Pause and the menu stop the countdown; "Despertar" (wake), **E**, or **WASD** wake you early. Sleep persists in saves, with no time advancing while the application is closed. Neighbors alternate short tasks, trips, and social breaks within their schedules, return home, and physically sleep in their beds. Details: [sleep and daily life](sueno-y-vida-cotidiana.md).

The character walks at 48 world pixels per second, both with keys and when clicking a destination. The bicycle moves at 120 pixels per second: 2.5 times walking speed. It has 16 sprites for four directions and pedaling with your customized appearance. Collision checks retain steps of no more than one pixel; see [art, speed, and validation](bicicleta-y-movimiento.md).

NPCs seek a detour if they stop making progress, yield at crossings, and prioritize people leaving houses. They step aside by walking and then resume their destinations, preserving collisions and stationary conversations. See [recovery and spacing between residents](espacio-entre-habitantes.md).

Neighbors display **occasional thoughts** on a single line, `Name: thought`, with an optional emoji. Each lasts four seconds, only one appears at a time, and pauses separate appearances. The lines consider personality, physical task, location, and the colony's fictional time and temperature. Hover over the clock to view the game's weather. Thoughts use no AI and do not become memories: [ambient thoughts](pensamientos-del-barrio.md).

## Talking with a neighbor

Each neighbor has independent **trust, affection, tolerance, and frustration** toward you and toward others. Their relationship with you appears in "Historia" (history). Respectful conversation builds closeness; repeating questions or pressing private topics may make them end the conversation and leave. Their past is revealed according to trust. Neighbors also exchange brief greetings when they cross paths, with lines that vary by time and previous encounters. Rules and persistence: [emotions and relationships](emociones-y-relaciones.md).

The profile uses icon tabs for "Historia" (history), "Memoria" (memory), "Aspecto" (appearance), and "Hablar" (talk). The active section has a dark background and a small marker; each icon shows its name on hover. A single row below groups conversation, learning, schedule, and help requests. Controls support Tab and Enter, and text keeps its native pixel art size with separate paragraphs and aligned figures.

The journal's "Aprendizajes" (learning) section retains errands, backpack, and details. "Qué hacer ahora" (what to do now) and a primary action explain how to progress given your materials and location. Completed errands show the steps performed and what you learned. The errand's story expands separately, and the panel adapts to the window. Details: [journal](diario.md).

Inside houses, location and exit controls are grouped at the top, and icons stay at the edge. Inspecting an object opens a card with its full story; the camera keeps the player visible, and Esc closes the text. Details: [house interface](interiores-ui.md).

The environment retains small changes: you can step onto plots and damage a plant by repeatedly trampling it, observe regrowth, water indoor plants, open or close each curtain, and browse memory albums. Three neighborhood locations show trees at different growth stages. Some trees occasionally drop apples that restore **1% energy**, with a rare golden surprise. Click highlighted objects to approach them; their states are saved with the game. Rules, timing, and controls: [interactive MVP environment](environment-mvp.md).

Notices appear compactly at the bottom right, using 14-pixel text and scrolling when needed. Long notices remain until dismissed; short ones disappear after a few seconds, respecting the pointer and focus while you read. The mouse wheel and focused arrow keys let you read the full text. Notices move away from controls and rest indicators when they share space.

A neighbor may sometimes prefer solitude even if they like you. The first refusal does not harm the relationship; insisting during that break increases frustration and reduces tolerance. This disposition lasts for a while and is saved, rather than being decided again on every click or interrupting an accepted conversation.

Neighbors share locations with separate spots and walk around one another. Each keeps their schedule; meeting does not mean walking to the same coordinate. Movement details and verification: [spacing between residents](espacio-entre-habitantes.md).

Approach someone and open "Hablar" (talk). Greet them by name, choose a suggestion, or type freely up to 1,000 characters. **Enter** sends; **Shift+Enter** inserts a newline. Connected suggestions arrive in the same request as the response; local mode derives them from the last question, topic, and your actual progress. You may draft the next message while a response arrives, but only one turn is sent at a time.

Responses are concrete and broadly worded: the model is asked for one or two short sentences, with limits of 30 words and 180 characters. Responses are displayed and saved without newlines, repeated spaces, or em dashes. The neighbor may ask a relevant question without repeating it every turn. Reply options are brief too.

Conversation retains the actual activity preceding the greeting. The neighbor distinguishes what they were doing from plans and goals; suggestions follow what they just said, without asking an answered question again or revealing biography you have not heard. [Natural conversations](conversaciones-naturales.md) explains this context and its verification.

A conversation stays open with one neighbor. Pressing "Hablar" nearby stops both participants before the first message and keeps them in place between turns, while the rest of the colony continues. The camera gently shifts the map to keep both visible beside the chat, preserving sprite size. Closing the panel restores the general framing. You can consult another panel and return to the conversation. The **×** button or a walking order closes the conversation and releases the neighbor; if you were typing, **Escape** leaves the field so movement keys work again. Interrupting a response does not save partial text.

Each new encounter starts with an empty chat. It shows only up to **20 exchanges from the current session**. Closing the conversation clears messages, draft, options, and scroll position. Earlier completed exchanges remain in the saved game's memory. To respond, the model receives up to **four recent exchanges** and relevant memories. Your draft is retained while you consult another panel during the same conversation. Details and tests: [clean chat](chat-limpio.md).

With a local token, manual conversation attempts to use OpenAI even when Jev decisions are disabled. Without a token, it uses predetermined responses, as the help explains. The panel does not show provider names or technical labels. If the connection fails, it shows a brief notice and "Reintentar envío" (retry sending); it neither silently substitutes a local response nor saves an incomplete exchange. Any new draft you have started is preserved.

A real three-turn conversation from Godot through the local Worker to OpenAI passed **19/19 checks**. First text arrived in **1.78 / 1.61 / 0.98 seconds**, and each response finished in **1.97 / 1.95 / 1.31 seconds**. These are three isolated samples from before the latest concision adjustment, not a benchmark or latency guarantee. Scope and evidence: [validation](validacion.md).

## Things to try

- Watch César, Lupita, Mateo, Inés, and Alma walk around the café, plaza, workshop, and garden.
- Select a neighbor to view their history, personality, memories, and knowledge.
- Enter your home and approach the **wardrobe** to edit name, skin, hairstyle, hair color, eyes, beard, hat, shirt, and trousers with an enlarged preview. Click the cabinet or press **E** beside it.
- Walk with **WASD/arrows** or click a path; use **E** to interact nearby and **pause** to inspect the colony.
- Enable "Vivir solo" to watch your character's routine and regain control whenever you want.
- Talk near another resident, meet again, and recall the topic and time of the previous visit.
- Open "Diario" to view errands, materials, coins, instructions, and the next step.
- Learn bicycle repair from Mateo, cultivation from Alma, and tea preparation from Inés. Each chain requires an errand, an in-person purchase, delivery to the mentor, and practice at home.
- Repair your bicycle step by step and use "Bici" outdoors: speed increases from 48 to 120 pixels per second while preserving routes and collisions.
- Observe individual schedules and daily variations; the history tab shows the neighbor's activity.
- Walk routes that avoid buildings, the fountain, and furniture. Neighbors return to their homes and leave in the morning.
- Click a door to approach it. If someone is inside, knock and wait for permission; the local policy considers encounters, personality, and time, while connected mode consults Jev.
- Enter all five neighbors' homes and your own, inspect objects by approaching, and retain what you discover. Empty homes have open doors in this prototype.
- Watch moving water, gusts in bunting and plants, light smoke, and small particles. The game clock changes the town's lighting and turns on streetlights and windows at night. Each of the six homes has its own layout, with objects supported by furniture and clear routes. Details: [environment and day cycle](entorno-y-ciclo-del-dia.md).

Suggested walkthrough: open "Diario", choose Mateo, and press "Ir con Mateo" (go to Mateo). Once there, open his "Encargos y aprendizajes" (errands and learning) and ask him to teach you. Visit the shop, buy oil, and return to Mateo to deliver it wherever he is. Deliveries and lessons work beside the mentor outdoors or inside a house; you do not need to wait for him to return to work. Walk home, enter, and click the bicycle. Approach it and perform all four steps. Outside, "Bici" lets you mount and "Bajar" lets you return to walking. Save and reopen to retain the errand, materials, steps, and repair.

The three current chains are completed once and consume real backpack materials. A new game starts with 8 coins; the shop limits purchases to pending errands to prevent spending everything on duplicates. The seed leaves a visible planting, and tea leaves a prepared cup. These learning chains are one-time activities. The town system adds repeatable harvests and production; serving apprenticeship tea to guests remains pending. Catalogs are in `game/data/apprenticeships.json`; the mechanism is described in [learning and errands](aprendizaje-y-encargos.md).

## Saves and characters

Godot stores the game at `user://colony.json`. On macOS this corresponds to `~/Library/Application Support/MyCityPrototype/colony.json`. Saving retains a `.bak` copy; an invalid file remains intact and produces an error.

Saved progress—appearance, memories, materials, errands, learning, and energy—persists on reopening. Older saves without energy start at 100. Each load begins in **manual control at 1×**; enable "Vivir solo" again if you want to observe. Closing the game stops the simulation: no days, encounters, or progress are calculated for time spent with the application closed.

Initial histories are in `game/data/residents.json`. The interface supports name and appearance editing; visual biography and personality editing remains pending. Changing the initial JSON does not replace residents in an existing save.

Neighbors retain their own social knowledge: experiences, opinions, testimony, and confidences with sources. They can share news in physical encounters, disagree, discover indiscretions, and clarify them later. Trust and personality affect what they share; nobody automatically receives another person's memories. The system supports existing saves and town growth. Architecture, limits, and tests: [social knowledge design](social-knowledge-design.md).

## Jev, conversation, and infrastructure

The prepared integration uses TypeSafe's Jev to select structured actions and OpenAI for conversation. The canonical backend is a Cloudflare Worker in `backend/`; configuration and instructions are in [Jev](jev.md). Keys belong in the backend, never in the Godot client.

The configured conversation model is `gpt-6-luna` through the Responses API with `reasoning.effort: none`. The [official OpenAI documentation](https://developers.openai.com/api/docs/models/gpt-6-luna) describes it as intended for focused, high-volume tasks and supporting that reasoning level. The first real sample received provider text at 2,486 ms and finished at 2,700 ms; one sample is not a benchmark or a guarantee of future timings.

Local credentials live in Git-ignored files and are not distributed with the project. The Worker has not been deployed. The connection button alone does not prove that models are active. Memory remains local: Cloudflare D1 for shared data and Durable Objects for continuous simulation are future steps and are not configured.

## Verification

Test the simulation without opening a window:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/smoke.gd
```

The test checks memory, individual context, learning, and persistence contracts. See [Jev](jev.md) for backend tests and startup.

Energy, physical rest, and save compatibility: `res://tests/energy_smoke.gd`, using isolated saves and no providers.

Product direction, learning rules, and next stages: [vision](vision.md).

World proportions are based on a character with roughly 22 visible pixels. Homes, doors, crops, and furniture share geometry from `game/data/world_layout.json`; calibration and validation are described in [world scale](escala-del-mundo.md).

Decisions about pair-specific context, streaming, schedules, and future continuity: [daily life and performance](vida-y-rendimiento.md). To open without a terminal, use `Play.command`. Additional client tests: `res://tests/stream_smoke.gd` and `res://tests/ui_smoke.gd` (the latter requires `-- --ui-test`).

Navigation and housing: `res://tests/navigation_smoke.gd` and `res://tests/world_smoke.gd` (the latter requires `-- --ui-test`). Run the real HTTP integration with a simulated provider from `backend` using `bun run test:godot`.

Errands and persistence: `res://tests/progression_smoke.gd`. The playable chain of buttons, routes, shop, home, and bicycle is covered by `res://tests/learning_world_smoke.gd -- --ui-test`. These tests use isolated saves.

Regressions for following mentors with active schedules, chat drafts, memory scrolling, and entering your own home: `res://tests/interaction_smoke.gd -- --ui-test`.

Conversation sessions, compact responses, retries, and separation by neighbor: `res://tests/player_chat_smoke.gd -- --ui-test`. Visual layout: `res://tests/layout_smoke.gd -- --ui-test`. Both use isolated data and make no provider calls. The optional `res://tests/chat_live_check.gd -- --ui-test --live-chat` requires Worker configuration and makes three OpenAI calls, without reading or saving the user's game.

Keyboard and autonomy: `res://tests/keyboard_navigation_smoke.gd`, `res://tests/autonomy_smoke.gd`, `res://tests/controls_world_smoke.gd`, and `res://tests/autonomy_ai_smoke.gd`; the last two require `-- --ui-test`. They verify collisions, control modes, accelerated time, home visits, and AI cancellation without using providers.

The UI floats above the world without a permanent header, sidebar, or notice strip. Histories, conversations, schedules, and errands have their own scrolling when opened. The pause menu keeps the scene visible and stopped. Character labels retain their reading size as the map grows. `res://tests/layout_smoke.gd -- --ui-test` checks long text and panel bounds. `res://tests/sprite_smoke.gd` validates resources, directions, and customization; `node scripts/prepare-sprites.mjs --self-test` checks the importer.

Full view and floating panels: `res://tests/overlay_smoke.gd -- --ui-test`, `responsive_smoke.gd`, `hud_smoke.gd`, and `activity_labels_smoke.gd`. Screenshots and interaction boundaries are documented in [interface over the world](interfaz-sobre-el-mundo.md).
