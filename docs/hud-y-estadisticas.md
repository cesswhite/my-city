# HUD and statistics

The HUD groups general shortcuts into 32 × 32 logical-pixel buttons with 16 × 16 PNG icons. Names and explanations appear on hover or keyboard focus, both in the tooltip and help strip. Controls have accessible names and descriptions. Speed retains the text **1× / 2× / 4×**, and conversation actions keep readable words and suggestions.

Time, mode, energy, and coin indicators float at the top left. Speed, pause, autonomy, save, and menu controls are at the top right. The bottom dock groups character, journal, home, bicycle, AI, and history. Learning and neighbor counts appear in the journal and player-character help. No opaque strip reduces the map area. Opening the inspector hides the upper-right controls and centers the dock in the free space; Esc or × closes the panel. Pause and autonomy icons change to express the next action: "Continuar/Pausar" (resume/pause) and "Tomar control/Vivir solo" (take control/autonomy). When running directly without the shell, the menu shortcut retains its help function.

## Data represented

| Indicator | Source and meaning |
| --- | --- |
| Energy | `colony.player_energy()`, from 0 to 100. The bar receives the fractional value, and the written percentage is rounded. At 25 or lower it changes to terracotta. |
| Coins | The actual `colony.progression_state().coins` balance, available for materials. |
| Learning | Procedures with `status == "demostrada"` and `world_verified == true`, against the catalog's total number of chains. Receiving instructions does not yet count as demonstrated practice. |
| Neighbors | Residents present in `player.known_people`, against the colony's total neighbors. Seeing someone on the map is not enough to count them. |

`game_hud.gd` only reads these data. It does not grant objects, coins, or skills. `main.gd` updates readings every 0.2 seconds during normal processing and when refreshing interface state; it does not recalculate them every frame. This presentation does not change Jev's frequency or conversation transport.

## Energy and rest

Energy starts at **100**. Ordinary consumption and rest follow the simulated clock. Each tick represents five minutes:

- Awake: **−0.025 per minute**, or **−0.125 per tick**. Sixteen hours consume 24 points.
- Resting: **+0.10 per minute**, or **+0.5 per tick**. One hour restores 6 points.
- Sleeping in your bed: **+0.25 per minute**, or **+1.25 per tick**. Use E beside the bed to choose a duration; you can wake early. See [sleep and daily life](sueno-y-vida-cotidiana.md).

The result is clamped to 0–100. At **0**, the player falls asleep from exhaustion at their current position. They must wait **8 real seconds of unpaused gameplay** and wake at **5**, with no partial recovery or further consumption during that interval. They cannot move, wake with keys, mount the bicycle, converse, cross doors, or perform errands meanwhile. Pending objectives are canceled. The town clock runs at normal speed during recovery, regardless of the previously chosen multiplier. This bar has no associated damage, combat, health-point, or XP mechanic.

To recover energy through ordinary rest, the player must be **inside their own home and stationary**. Under manual control, they must be beside the bed's interaction point or the map's shared resting location. In autonomy, an active home/rest routine also counts, provided the player is already still inside their home. A reserved conversation counts as waking time.

The check uses room, destination, and physical position. It also compares the position with the previous tick to avoid treating walking beside the bed as rest. Recovery after arriving starts on a later tick once stillness is confirmed. An old rest label, standing still outdoors, or occupying someone else's home is insufficient. The check does not change position or destination.

Ticks do not advance during pause or in the menu, so energy stays unchanged. No consumption or recovery is calculated for time with the application closed.

## Persistence and cost

Only the player adds the numeric `energy` field to their resident in `colony.json`. Save version 1 is retained: if an older save lacks the field, loading assigns 100 and the next save includes it. Validation rejects negative values, values above 100, nonfinite values, and nonnumeric types before replacing the previous state or file.

Exhaustion uses the variant `sleep: {kind: "exhaustion", remaining: seconds}`. Remaining time is saved, so closing and reopening neither skips nor restarts the wait. An older save with zero energy and no sleep state starts this rest when loaded. The timer does not depend on system dates or AI requests.

The two auxiliary position/room samples are temporary, constant-sized, and reset when preparing or loading a colony. Energy calculation adds no events, experiences, historical statistics, or `known_people` entries, and does not add the field to model context. Review of this change found no history growth caused by the new indicator.

## Icons and provenance

The source is a 1024 × 1024 RGBA PNG; Godot's atlas is 64 × 64 and contains sixteen 16 × 16 regions with alpha and nearest filtering. The importer crops generated silhouettes, fits them into their cells, and limits the palette; control geometry remains 32 × 32. `hud_icons.gd` caches the atlas and its regions.

Generation explicitly requested **`gpt-image-2.5-sunburst-2026-09-08`** through the official imagegen CLI with `--background transparent --output-format png`. The provenance record confirms that the identifier was in the catalog and that the request was accepted without model substitution. The CLI does not retain the provider response's model field; the record declares that limitation.

The prompt, PNG source, importer, and hashes are in `output/imagegen/hud-icons-prompt.txt`, `hud-icons-source.png`, `hud-icons-import.py`, and `hud-icons-provenance.json`. The atlas and import process are described in [HUD icons](hud-icons.md).

## Logic evidence

- `energy_smoke.gd`: **51/51**, with simulated time and isolated files. Checks rates, limits, physical rest, rooms, exhaustion blocking, exact recovery, persistence, older saves, and rejection of invalid values.
- `exhaustion_smoke.gd -- --ui-test`: real clock, control blocking, interruptions, pause, menu, and continuity after loading.
- `exhaustion_ui_smoke.gd -- --ui-test`: ground pose, counter, progress, and absence of early waking; preserves normal bed rest.
- `smoke.gd`: **141/141** after adding energy; memory, bounded context, learning, routines, housing, and save protection still pass.

These figures concern simulation logic, not visual HUD validation or real provider calls.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/energy_smoke.gd
```
