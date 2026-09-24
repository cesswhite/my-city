# Persistent environment art

`EnvironmentArt` projects `state.environment`, the pure view of `Colony.environment`. It does not alter saves, the geometry catalog, or cached sprites. `SpriteArt.scenery_objects` incorporates its objects into the usual depth order.

## Representation

- Crops: each cell retains the leaves from `garden_left`/`garden_right` at native scale, with four states: soil, sprout, small, and full. Damage tilts the upper rows by one or two pixels and dims the color; the root stays fixed. Destruction hides the leaves; regrowth shows the corresponding stage again. Leaves are not invented with primitives.
- Plot soil is drawn in `draw_world`, before actors. Each plant is a separate object, sorted by its root; walking over the garden cannot cause the soil rectangle to cover the character.
- Trees: soil 8×4, existing sprout 7×9, newly established tree 18×26, young tree 26×36, `tree_small` 33×47, and `tree` 42×56. All six stages share the root point; none changes size during rendering.
- Apples: red and golden, both 8×9. Objects retain `environment_fruit` (tree), `fruit_id`, `fruit_kind`, and `tree_id` for physical interaction.
- Curtains: `households[room].curtains[prop_key]` replaces only that window with `window_closed`, 28×29. Lighting reads the same state to remove the outside view and daylight beam.
- Watering: `households[room].watered[prop_key]` activates a slightly damp tint and three temporary effect droplets for ten simulated minutes, then returns to the normal sprite. It does not change statistics.

`EnvironmentArt.curtains_closed(room, state, prop_key="window")` exposes the same query to the rest of the renderer. Objects with `environment_object` are drawn once; the environment does not overlay a previous plant or tree.

## Five new pieces and provenance

The official imagegen skill CLI was used with the exact model `gpt-image-2.5-sunburst-2026-09-08`. Before generation, the official catalog query returned HTTP 200 and that same ID. The CLI finished with exit code 0 and no fallback. The CLI does not save an echoed model in the response; `model_response` remains `null` and is not presented as additional provider confirmation.

Files under `output/imagegen/environment-growth/` retain `prompt.txt`, `reference.png`, `source.png`, `model-verification.json`, `generation.json`, `generation.log`, and `import.json`. The reference combines only existing project PNGs.

The deterministic importer crops each cell of the original sheet using alpha ≥250, removes the outer semitransparent halo, downsizes with nearest-neighbor sampling to its native canvas, and applies the existing shared palette's 255 opaque colors without dithering. Trees fit within their canvas and are anchored at the bottom. It does not modify any of the previous 54 environment sprites.

To reproduce the import from the generated original:

```sh
.venv/bin/python scripts/import-environment-sprites.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --editor --import
```

The new PNGs in `game/assets/sprites/` are `tree_sapling`, `tree_young`, `apple`, `apple_golden`, and `window_closed`; their manifest entries record source, size, crop, and provenance.
The importer also retains these five entries as pass-through assets in `sprite-body-catalog.json` and `sprite-catalog.json`, so a general rebuild does not remove them. Repeated imports do not rewrite identical PNGs.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/environment_art_smoke.gd -- --ui-test
```

The `--capture` option without `--headless` exports a real Godot render. Tests check native scale and stable roots, mask reuse, damage and regrowth, soil/plant separation, fruit metadata, independent windows, and expiration of the watering effect. They do not call providers or load or save the user's game. Evidence is in `artifacts/environment-growth/`.
