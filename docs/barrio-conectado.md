# Connected neighborhood

This implementation record describes the five-area neighborhood before the later settlement expansion. The colony has five outdoor areas and preserves the five existing neighbors and their interiors. See [settlement design](settlement-design.md) for the later grove and staged growth.

```text
                         César's garden ─── Alma's corner
                                │                  │
Homes street ─────── Neighborhood plaza ─── Workshop courtyard
```

North is up. **M** opens the map and marks the current area; **M** or **Esc** closes it. The location card also opens it. Exits follow paths toward the edges and indicate their destinations. Cross them on foot, by bicycle, or by clicking the exit. Only the drawn connections exist; returning through the same crossing brings you to the opposite side of the original block.

| Area | Homes and local life |
| --- | --- |
| Neighborhood plaza (`street`) | Inés lives beside her café. Tables, the shop, fountain, benches, and banners form the common meeting place. |
| Homes street (`homes`) | Lupita and the player live west of the plaza. Lupita's welcome table, flowers, and bench invite visitors; the player has a private yard. |
| César's garden (`gardens`) | His house sits beside crops, seeds, and planters, with vegetation and a bench for resting. |
| Workshop courtyard (`workshops`) | Mateo's home and workshop are nearby, with tools and bicycles at different repair stages. |
| Alma's corner (`atelier`) | Her house faces a courtyard with an easel, memory table, and reading bench, between the garden and workshop. |

Inspectable objects record what a character actually observes. Public decoration does not reveal personal secrets or grant skills. Interiors, entry permissions, wardrobe, bed, and learning projects retain their interactions.

## Movement and simulation

Each character has a physical room (`room`) and local position (`pos`). The five outdoor areas have their own identifiers; interiors retain their resident's identifier. Identical positions in different rooms never imply proximity.

`Colony.travel_to()` retains the final destination and prepares the next segment. It finds a sequence of connected areas and routes around obstacles in the current area. On reaching a connection, it checks that the entrance is free, changes area, and continues the route. The entrance is twenty pixels inward from the crossing to prevent bouncing back and allow travel in opposite directions. If occupied, the character waits and retries.

NPCs move and follow routines even when their area is not visible. Going home, visiting the café, working in the workshop, and tending the garden use the same connections as the player. Conversations stop their participants. Encounters, greetings, witnesses, and AI context require the same area and sufficient proximity. A memory about someone does not reveal their current location.

Journal shortcuts to the shop, mentor, and home traverse the necessary streets. Delivering materials to a mentor still does not require a specific building. Buying requires reaching the shop; practicing requires reaching the home project.

## Data and extension

`game/data/neighborhood.json` declares the graph and outdoor composition. `world_layout.json` retains interiors, doors, and activity points. `WorldLayout` provides shared geometry for drawing, navigation, lighting, and interaction.

To add a street:

1. Add an identifier to `areas`, with `title`, `description`, `grid`, `bounds`, `ground`, `props`, `interactions`, and `exits`.
2. Declare both directions of each connection. `at` lies at the source edge; `spawn` belongs to the opposite edge of the destination. `grid` positions must match the directions.
3. Compose with sprites at native scale. `footprint` defines the solid part; `stand_at` indicates where an object is used. Objects on tables use `support` and `support_offset`.
4. Register homes in `home_areas` and routine locations in `place_areas`. `spawns` defines initial placement for a new save.
5. Run geometry and route tests. Every door, entrance, seat, and object must be reachable without passing through furniture.

Adding an NPC also requires registration in resident data, save rules, and contracts that validate identifiers. It does not require rebuilding the map or writing character-specific transitions.

Transitions add a 0.22-second fade when changing blocks without changing scale or querying AI. Existing PNGs are reused, including duplex cutouts that separate César's and Lupita's houses. No new images were generated.

## Previous saves

The save adds `world_revision: 2` and an optional `{room, position}` route. An older save preserves residents in the plaza if they were there, along with memories, relationships, appearance, items, coins, and energy. Only positions now inside an obstacle are recovered. Subsequent routes use the new streets. Loading does not rewrite the original file or restart the save.

Manual and NPC physical routes can continue after saving and loading. Pending UI actions, such as opening the shop on arrival or following a moving mentor, are not saved; they can be requested again from the Journal. Player autonomy still requires voluntary activation when opening a save.

## Validation

From the project root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/neighborhood_layout_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/neighborhood_core_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/multi_area_smoke.gd -- --ui-test
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/smoke.gd
```

Tests use isolated data without the user's save or providers. They cover reciprocal connections, occupied entrances, simultaneous opposite crossings, routes, saving during travel, area-specific memory, façades, doors, and the map. A two-day simulation verifies sleep and activity for every neighbor. The backend retains its context tests.
