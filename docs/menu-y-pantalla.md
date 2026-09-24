# Menus and display

The entry scene is `game/scenes/shell.tscn`. The menu displays the neighborhood as a backdrop without creating a simulation or starting AI requests. A game is instantiated after choosing "Iniciar partida" (start game) or validating "Continuar partida" (continue game).

## Flow

- **Start:** "Iniciar partida" appears when there is no progress; "Continuar partida" and "Nueva partida" (new game) appear when a save exists. Settings, controls, and quit are also available.
- **New game:** enters the neighborhood. Customization opens at your home wardrobe when you approach and use it by click or E. If a save already exists, the game first shows the "Una nueva historia" (a new story) confirmation, with "Conservar mi partida" (keep my save) as the primary action and "Empezar de nuevo" (start over) as an explicit choice.
- **In-game menu:** resume game, save game, settings, controls, main menu, and quit. Resuming preserves the same world instance and previous pause state.
- **Settings:** fullscreen/windowed mode and vertical sync. Changes apply when selected and are saved in `user://settings.cfg`, separately from progress.

The main menu and settings pages keep the world stopped. Returning to the main menu saves the current session; quitting also attempts to save. If saving fails, the game stays open and shows the error.

## In-game shortcuts

Player status occupies a single 232 × 32 logical-pixel row, using 37% less area than before. It shows mode through an icon, day and time, energy percentage with a thin bar, and coins. It uses 14-pixel Pixel Operator, aligned numbers, and a dark borderless background. Large amounts are abbreviated; the exact value, control mode, and weather are available through hover or keyboard focus.

The bottom-left corner contains only journal and bicycle controls, with 28 × 28 logical-pixel buttons in a 68 × 36 panel. Icons retain tooltips and keyboard focus. There are no lower shortcuts for customization, home, AI, or history.

The top bar groups speed, pause, AI, autonomy, save, and menu. AI starts enabled when local configuration exists; tests and previews remain offline. The button can disable it for the session.

The contextual hint, such as "Clic: Sentarte · Banco" (click: sit · bench), occupies only its text area at the bottom right. It moves into free space when a panel is open and hides while a notice is visible to avoid overlap.

## Keyboard and display

**Esc** first closes help, the learning journal, or a door dialog. If a text editor has focus, it releases that focus. The next press closes the open profile or ends the visible conversation. With none of those priorities active, it opens the pause menu. Holding the key does not repeat the action. In the menu, Esc returns from settings, controls, or new-game confirmation; if a session is open, it resumes it.

**F11** toggles fullscreen/windowed mode and retains the preference. The initial mode is fullscreen with vertical sync. Windowed mode starts at 1536 × 864 and fits the monitor's usable area, including window decorations.

The logical base is 768 × 432. The project uses `viewport` stretching, `expand` aspect, and fractional scaling; the interface redistributes its space while the world retains its proportions. Textures use nearest filtering. This avoids smoothing sprites, but a non-integer scale factor can produce pixels of different on-screen widths: there is no guarantee that one game pixel maps exactly to an integer number of monitor pixels at every resolution.

## Session contract

`main.gd` exposes `managed_by_shell`, `start_new_game`, `save_allowed`, the `menu_requested` signal, and `suspend_for_menu()` / `resume_from_menu()` methods. The shell sets `colony.save_path` before adding the scene to the tree. `save_allowed` stays disabled when loading fails; the shell discards that instance and shows the error.

Suspension is idempotent and preserves the previous pause state. It ends manual conversation, restores neighbors' current destinations, and then cancels decision, visit, and dialogue transports. It invalidates control and dialogue generations, releases reservations and keys, disables processing, and hides the scene. For the pause page, the shell shows the scene again as a still backdrop while input blocking and suspension remain active. The menu occupies the input surface; returning to the start screen hides the scene and shows the title landscape. An interrupted conversation adds no partial memories. Drafts remain in memory; if no other draft has been written, the chat session restores the pending question.

Resuming shows the same scene, restores its previous pause state, and enables controls according to window focus. It does not itself send an AI request. Applicable routines and requests resume during subsequent normal game cycles. Drafts remain while navigating the menu during the session; they are not serialized as part of the save.

The game scene delegates window closing to the shell when `managed_by_shell` is active. Direct scene runs retain their previous behavior. `--preview` and `--ui-test` still prevent `main.gd` from loading user progress.

## Saving and replacement

`session_store.gd` validates continue using a candidate colony before creating the scene. An invalid file is neither presented as a successfully loaded save nor silently replaced.

When a new game is confirmed, the shell first saves the open session. The store prepares and validates an initial save in a separate temporary file; if a previous file exists, it copies it to `colony.json.archive-<seconds>-<microseconds>`. Only after that backup succeeds does it replace the main file by renaming. A failed copy or replacement preserves the previous file. These unique backups are independent of the `.bak` file rotated during ordinary saves. The original contents of a corrupt file are also retained when the user explicitly chooses to replace it.

## Recorded validation

A house modal is centered using the current screen and panel size. Help and journal use the same calculation; sleep retains its existing centering. In the door modal, the primary button receives focus on opening, arrows and Tab cycle between the two actions, and Enter confirms the selection. Only the focused button has a dark background and gold outline. Back or Escape releases focus; reopening selects the primary action again.

This fix passed `modal_keyboard_smoke.gd` **58/58** (768×432, 960×600, 1280×540) and `responsive_smoke.gd` **71/71**. Captures of the primary action (`artifacts/modal-keyboard/primary.png`) and back action (`artifacts/modal-keyboard/back.png`) were reviewed. The older general `layout_smoke.gd` test scored **37/46**: eight expectations still described the previous fixed HUD, and one detected overflow in a long suggested reply. Those HUD/chat cases were not changed by this fix; its help, journal, and shop checks passed. Full log: `artifacts/modal-layout.log`.

- `menu_lifecycle_smoke.gd`: **34/34**. Suspension and resumption, stopped clock, released keys, drafts, restored routes, manual and neighbor-to-neighbor cancellation, late responses, Esc priority, and delegated closing. Log: `artifacts/menu-validation/lifecycle.log`.
- `player_chat_smoke.gd`: **64/64** after lifecycle integration. Reservations, drafts, complete memory, brief formatting, and in-memory streaming.
- `autonomy_ai_smoke.gd`: **39/39** after lifecycle integration. Cancellation, stale serials, and a request budget independent of world speed.
- `menu_smoke.gd`: **38/38**, run by the shell integrator and confirmed in the log. Startup without simulation, pages, persistence, continue, confirmation, backups, and corrupt files. Log: `artifacts/main-menu/menu.log`.

These tests use isolated files and transports captured in memory; they neither consume provider APIs nor modify the user's save. The integrator visually reviewed `artifacts/main-menu/title.png`; the automated checks above do not replace reviewing each physical monitor resolution. Historical validation artifacts are local and excluded from Git.

The real macOS application was also reviewed: fullscreen startup without black margins, settings, F11 toggling in both directions, continuing an existing save, Escape opening pause, and returning to the main menu with saving. The game was left at the main menu with the fullscreen preference saved. Additional suites confirmed settings 31/31, responsive layout 55/55, core 141/141, and service 57/57. Core and service logs are in `artifacts/main-menu/`.

To repeat the lifecycle test from the project root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/menu_lifecycle_smoke.gd -- --ui-test
```
