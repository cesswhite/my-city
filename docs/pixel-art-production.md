# Environment revision · September 24, 2026

This revision is **active** in the game's normal manifest. It replaced 54 sprites after an audit of the render and existing sources. The neighborhood retains its stucco homes, terracotta, awnings, warm woodwork, turquoise doors, and customizable characters.

The [audit](pixel-art-audit.md) describes issues found before editing. The [pixel art system](pixel-art-design-system.md) defines perspective, sizes, materials, light, and criteria for adding content. Farming games serve as a readability and finish target; no assets from other games are incorporated.

## What changed

| Group | Count | Contents |
| --- | ---: | --- |
| Buildings | 6 | Café, duplex, Alma's home, workshop, player home, and shop |
| Outdoors | 16 | Trees, fountain, benches, tables, streetlights, bunting, fences, plants, crops, and objects |
| Indoors | 16 | Bed, tables, chairs, cabinets, shelf, windows, rug, mementos, and projects |
| Terrain | 16 | Grass, paths, plaza, wood, walls, soil, water, and materials |

Silhouettes and planes are more defined; floors and walls have less noise to give priority to actors, plants, and furniture. All replacements share **255 opaque colors**, quantized together without dithering. The 96-color trial was rejected because it lost terracotta, foliage, and bunting nuances. The first generated terrain was also replaced with a second, quieter version.

Dimensions, identifiers, anchors, collisions, doors, and progression are preserved. Characters, their appearance layers, bicycles, and UI sprites remain intact. All six areas retain their layout and interiors retain their residents' objects and identities.

The renderer adds subtle path edges using the same textures, without moving passages or narrowing routes. Pond corners remain inside its solid area. The background around the camera takes the actual tint of each zone, avoiding a seam when moving through the forest.

## Integrating drawings with interactions

Preserving a canvas does not guarantee that a window or pillow stays on the same pixel. Facade glass, interior window panels, streetlight flames, chimneys, the six moving bunting flags, pillow and blanket, sprouts, and the fountain's north rim were recalibrated. The seat crop now excludes the water jet; the character position and access point remain unchanged.

`Sprites.uses_revised_art(id)` selects the profile using each asset's provenance, even after publication at its usual path. Lighting, wind, and seating invalidate their caches when the manifest changes. The previous profile remains available. Actual crop growth retains its own representation; wind does not replace it with static plants.

## Sources and provenance

The **official Imagegen skill CLI** was used, with explicit selection of `gpt-image-2.5-sunburst-2026-09-08` and PNG output, in accordance with `AGENTS.md`. The ID was verified in the official catalog before generation. The five generation records retain the requested model; the CLI did not return additional attestation of the effective model, and its identity is not inferred from pixels.

- Enlarged native references: `output/imagegen/art-v2/references/`.
- Exact prompts: `output/imagegen/art-v2/prompts/` (`buildings`, `outdoors`, `interiors`, `terrain`, `terrain-calm`).
- Unmodified original responses: `output/imagegen/art-v2/sources/`.
- Catalog verification: `output/imagegen/art-v2/model-verification.json`.
- Generation records: `output/imagegen/art-v2/*-generation.json` and their logs. Files named `*-generation-preflight-failed.*` record local attempts that failed before calling the provider.
- Alignment measurements: `scripts/art-source-alignment.json`; results and traceability in `output/imagegen/art-v2/aligned/`.
- Accepted batch and hashes: `output/imagegen/art-v2/accepted.json` and `output/imagegen/art-v2/accepted/`.
- Palette and complete source chain: `game/assets/sprites/art-v2/palette256/provenance.json`.
- Immutable original backup: `output/imagegen/art-v2/before/`.

Generated sheets did not precisely respect every cell boundary. Each object is therefore cropped using an inspected rectangle tied to the source hash. It is normalized with uniform scaling and Nearest to native space, retains binary alpha, then receives the shared palette. The pipeline does not draw procedural substitutes for the sprites.

Accepted package hash: `35eb357cbca8b91cf6d31aa7c8f4e0f5252a6eb26a0347904c356ccfd5d7561d`.

## Local reproduction without regenerating images

To rebuild staging from the recorded sources:

```sh
node scripts/align-art-sources.mjs
node scripts/art-direction.mjs import --palette shared256
```

Activation is explicit and copies accepted PNGs to their usual paths:

```sh
node scripts/art-direction.mjs activate --palette shared256
```

Normal import preserves the accepted batch and additional assets:

```sh
node scripts/build-sprite-catalog.mjs
node scripts/prepare-sprites.mjs --catalog scripts/sprite-catalog.json --out game/assets/sprites
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path game --import
```

The last step updates Godot's imported textures. Changing only the PNG can leave the executable reading the previous `.ctex`. A game that is already open must restart to load the new textures.

## Validation performed

- Actual reimport: **54/54** replacements retain their hashes; **90/90** production PNGs byte-for-byte identical before/after reimport; metadata for **35 protected assets** intact.
- Pipeline: **774/774** checks; base importer: **27/27**.
- Pixel calibration and caches: **40/40**. Lighting: **14/14**; environment with the real renderer: **24/24**.
- Sprites: **64/64**; zone layout: **245/245**; interiors: **71/71**.
- Seating: **57/57** and 607 motion samples; facades: **88/88** and 1,302 samples; highlighting: **27/27**; occlusion: **7/7**.
- Terrain transitions: **69/69**, preserving 328,114 ground samples and navigation connections.
- Responsive: **73/73**; interior UI: **105/105**; bicycle: **66/66**; core simulation: **141/141**.
- Final OpenGL visual audit: **258/258**, with **37 captures** of all six zones and six interiors in daylight, at night, and with markers. Occupied seats were also reviewed.

Older sprite/interior fixtures assumed that all homes, streetlights, and crops were still in `street`. They were updated to verify their actual areas, preserving guarantees for scale, collisions, supports, and routes.

Logs are in `artifacts/art-direction/after/checks/` and `artifacts/art-direction/recalibration/`. Reimport evidence is in `artifacts/art-direction/reimport-result.json`. Previous and final captures are in `artifacts/art-direction/before/` and `artifacts/art-direction/after/`. No test loads or overwrites the real save.

Fullscreen fitting still permits fractional scaling; sprite review captures use integer scaling. This batch improves the environment and preserves the current character system; it is not a complete replacement of all project art.
