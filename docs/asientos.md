# Colony seating

The original street seating set has eleven places: four café stools, three bench fronts, and four fountain edges. Hover over a place to highlight it, then click: the character walks to its access point and sits on arrival. You can also press **E** near an access point.

Press **E**, **WASD**, the arrow keys, or click to walk to stand up. A new movement order cancels a pending approach. Pause retains the seat and stops the approach; choosing a seat returns to manual control, dismounts the bicycle, and closes a voluntary conversation. Enabling autonomy releases the seat.

Tabletops, water, the fountain jet, and backrests are not seats. Interactive points correspond to specific sprite regions, not each piece of furniture's entire rectangle.

## Position and rendering contract

`seating.gd` provides the catalog and returns copies of its data. Each place defines `rect` for clicking, `source_rect` for the prop region, `stand_at` for the walkable access point, and `anchor`, `facing`, and `sort_y` for the pose and its visual depth.

`player_seating.gd` keeps `pending_id` and `active_id` only for the session. The physical position remains at `stand_at`: the character is not teleported inside furniture, and collision is unchanged. Seated rendering uses existing sprites, with bent legs and the same head and customization. This extension generated no new assets.

The pose is not serialized. Sitting or standing creates no memories, learning, or provider requests.

## Verification

- [Seating test](../game/tests/seating_smoke.gd): **57/57**, with **607 movement samples**. Checks all eleven access points, collision-free routes, positive and negative clicks, pause, cancellation, keyboard, bicycle, autonomy, and conversation. Historical log: `artifacts/seating/smoke.log`.
- [Controls regression](../game/tests/controls_world_smoke.gd): **47/47**. Historical log: `artifacts/seating/controls.log`.
- Interaction resolver: **146/146**, run by the contributor responsible for the resolver. Historical log: `artifacts/fullbleed/seating-interactions.log`.

Tests use `--ui-test`, without reading or writing the actual save or calling providers:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/seating_smoke.gd -- --ui-test
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/controls_world_smoke.gd -- --ui-test
```

The team reviewed the eleven-pose contact sheet (`artifacts/seating/all-seats.png`) and in-game captures, including the north fountain (`artifacts/seating/fountain_north.png`), bench (`artifacts/seating/bench_north_front.png`), café (`artifacts/seating/cafe_table_left_left.png`), and seat highlight (`artifacts/seating/hover.png`). These historical validation artifacts are local and excluded from Git.
