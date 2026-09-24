# My City

## Project rules

- The client uses Godot 4.7 / GDScript; the optional service is a TypeScript Worker.
- Keep the entire presentation pixel art: world, people, objects, portraits, and UI.
- PNG sprites and a unified visual direction already exist. Read `docs/pixel-art-design-system.md` before changing art. Installing or testing the game does not require regenerating assets.
- TypeSafe Jev chooses structured actions; it does not generate free-form dialogue. Never present local rules as a live AI connection.
- Separate biography, experiences, relationships, and knowledge. Each character accesses only what they know or perceive.
- Learning means remembering instructions and demonstrating their execution, not XP or automatic model-weight training.
- Provider keys belong exclusively to the local service/server, outside the client and repository.
- Before completing simulation changes, run `game/tests/smoke.gd` and the backend tests.
- Do not introduce web frameworks or remote services into the Godot foundation without a concrete need.
- Conversation responsiveness and performance are explicit priorities: preserve real streaming, bounded pair-specific context, nonblocking transport, and first-fragment/total timing measurements.
- Do not query AI every frame. The clock and routines are local; Jev runs at decision points and OpenAI when dialogue is needed.
- Characters may discuss others only using what they observed or heard. Preserve source and time; testimony is not a verified fact.
- The agreed stack is Cloudflare Worker, Jev, and OpenAI. Do not describe mocks, dry runs, or local mode as real provider connections.

## Reading order

1. Read `README.md` for setup and current scope.
2. Read `docs/architecture.md` to locate state, modules, and flows.
3. Use `docs/agent-guide.md` to choose files and tests for the task.
4. Consult `docs/README.md` and the relevant implementation. Historical records describe their revision; they are not current instructions and do not override the code.

## Implementation invariants

- Inspect existing systems before adding another. Extend modules and catalogs rather than concentrating new mechanics in `main.gd`.
- `Colony` coordinates state. `Progression` owns the only player inventory and wallet; `Settlement` owns growth and persistent jobs. Do not create duplicate wallets or unlock registries.
- Economy, costs, rewards, access, construction, and persistence are engine rules. Models receive filtered context and choose among allowed options.
- Proximity requires the same area and valid positions. Respect routes, obstacles, presence, and conversation/sleep pauses. Jobs must not progress while the actor is still travelling.
- Preserve catalog IDs and save compatibility. A new game and a migrated old save have different starting states; test both when changing persistence.
- A chat response is committed only on `done`. Cancellation, errors, and partial text must not create memories; retries must not duplicate social consequences.
- Do not read, print, overwrite, or upload `.env`, `.dev.vars`, personal saves, or real tokens for ordinary development. Use empty templates and synthetic data. Do not run paid checks or deploy by default.
- Document actual limitations. A configured model is not necessarily available to every account; one screenshot does not validate the entire simulation.

## Delivery

- Follow `CONTRIBUTING.md`; run the relevant checks and report exactly what was verified. Documentation-only changes need link, path, and consistency checks, not provider calls.
- Scene fixtures that require it must receive `-- --ui-test` to isolate saves and providers. Do not run every test script blindly: the directory also includes captures and opt-in live checks.
- Do not change repository visibility, licensing, published history, or infrastructure as an implicit side effect of a game change.
- Project documentation is written in English. Spanish game dialogue, UI labels quoted for accuracy, NPC names, and persistent identifiers can remain unchanged; documentation work does not authorize a runtime localization rewrite.

## Art-generation requirement

- Every AI-generated asset must use **GPT Images 2.5** and be delivered as **PNG**. Verify the effective model before generating. Do not silently substitute another model if the tool cannot select the required one.
- Prefer genuine transparent RGBA PNGs for characters, accessories, and cutout objects.
- If transparency is unavailable, generate on a completely uniform fluorescent green or fluorescent Mexican pink background, choosing a color absent from the subject. No shadows, texture, or gradients on that background. Remove the background while preserving subject pixels without halos or holes, and export PNG with alpha.
- Keep palette, perspective, scale, anchors, and animation frames compatible across pieces. Preserve visible scene backgrounds; chroma applies only to assets intended as cutouts.
