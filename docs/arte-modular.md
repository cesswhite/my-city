# Modular art for My City

**Current revision, September 24:** the `art-v2` batch replaces 54 environment assets and preserves character, bicycle, and interface layers. Its analysis, rules, provenance, and reproduction are in [pixel-art-production.md](pixel-art-production.md). The following sections document the first batch and its original architecture.

This document records the initial modular integration of September 23, 2026. Production already includes PNG sources, prompts, an import catalog, and a renderer. For the later September 24 visual revision, see the [pixel art system](pixel-art-design-system.md) and [production record](pixel-art-production.md). The detailed options and anchors catalog is in [sprite-catalog.md](sprite-catalog.md), and completed checks are distinguished from pending work in [validacion.md](validacion.md).

## Provenance and files

The model pinned for this production is **`gpt-image-2.5-sunburst-2026-09-08`**, from the GPT Image 2.5 family requested by the user. The official installed Imagegen skill CLI, `scripts/image_gen.py`, was used through `generate-batch`, `edit`, and `generate`; output is PNG. The catalog and `game/assets/sprites/manifest.json` record `generation.model`, date, format, source and prompt directories, mode, and post-processing. That metadata is the pipeline record; model identity is not inferred from PNG pixels.

Accessory sheets use the body sheet as a reference to maintain head position and scale. Original sources remain in `output/imagegen/`; their exact prompts are in `output/imagegen/prompts/` under the same name. The five initial jobs are also in `output/imagegen/initial-sprites.jsonl`.

For all nine sources, `output/imagegen/provenance.json` retains the requested model, CLI and generation mode, quality, format, edit reference, dimensions, and complete image and prompt SHA-256 hashes. It identifies the exact batch that produced the imported sprites.

| Source | Source dimensions | Contents | Prompt |
| --- | --- | --- | --- |
| `body.png` | 1024×1024 | Bald base, four directions and four poses | `prompts/body.txt` |
| `hair.png` | 1024×1024 | Four hairstyles, four directions | `prompts/hair.txt` |
| `hats.png` | 1024×1024 | Hats and caps aligned to the body | `prompts/hats.txt` |
| `beards.png` | 1024×1024 | Mustaches and beards by direction | `prompts/beards.txt` |
| `buildings.png` | 1536×1024 | Café, duplex, Alma's home, workshop, player home, and shop | `prompts/buildings.txt` |
| `outdoors.png` | 1024×1024 | Trees, fountain, benches, patio, garden, bicycle, and objects | `prompts/outdoors.txt` |
| `interiors.png` | 1024×1024 | Furniture, mementos, projects, tea, and planter | `prompts/interiors.txt` |
| `terrain.png` | 1024×1024 | Repeatable floors, walls, and materials | `prompts/terrain.txt` |
| `ui.png` | 1024×1024 | Sixteen control surfaces and states | `prompts/ui.txt` |

Cutout originals have real alpha; `terrain.png` is deliberately opaque. The user authorized flat fluorescent green or pink chroma as an alternative only if transparency cannot be obtained. The first batch has alpha, so its import does not need that background replacement. Do not confuse the presence of alpha with visual validation of every edge.

OpenAI documents explicit model selection and transparent PNG in the [image guide](https://developers.openai.com/api/docs/guides/image-generation). Sunburst prioritizes quality; Flare prioritizes speed. Models are not silently interchanged. [Sunburst model](https://developers.openai.com/api/docs/models/gpt-image-2.5-sunburst), [prompting guide](https://developers.openai.com/api/docs/guides/image-prompting).

## Local normalization and customization

`scripts/sprite-body-catalog.json` defines body layers and masks. `scripts/build-sprite-catalog.mjs` combines that configuration with measured scenery and UI crops and sizes from `game/data/world_layout.json`, producing `scripts/sprite-catalog.json`. `scripts/prepare-sprites.mjs` transforms only local files with Sharp; it does not call a model, read credentials, or install packages. Final import produces **88 PNGs** and a manifest in `game/assets/sprites/`. The garden uses four beds with two same-size variants, without stretching its crops.

The grid requested in prompts is not a geometric guarantee: several scenery objects crossed their cells. The world catalog therefore uses absolute crops measured on the originals, with `crop_space: sheet`, rather than assuming each cell contains the correct object. Those crops must be measured again if a sheet is regenerated.

For characters, each final cell is **24×32**, with foot anchor **(12,30)**. The body uses a normalized **96×128** sheet, four columns `idle/walk_a/neutral/walk_b`, and rows `down/left/right/up`. A 192×256 source region is cropped from each 256×256 cell and reduced with Nearest; the square cell is not directly deformed. Accessories retain one frame per direction and use their catalog's scale/position corrections. These values were calibrated for the present sources and must not be reused blindly with another generation.

HSV masks extract skin, shirt, trousers, and eyes; eyes also have a selection region limited to the head. Recolorable areas are converted to grayscale while preserving tonal variation, and Godot applies the selected palette only to that layer. `char_details` retains the remaining pixels: outline, shoes, and other details. Hair and beards are tinted with their palette; hats retain the imported piece's color. Changing a shirt must not tint skin or eyes.

The eight saved fields remain `skin`, `hair_style`, `hair`, `eyes`, `beard`, `hat`, `shirt`, and `pants`. César, Lupita, Mateo, Inés, Alma, and the player are presets of these options. Their combinations are not generated as indivisible characters. The order declared in `manifest.characters.layers` keeps body, clothes, eyes, details, and accessories compatible; pay particular attention to long hair, profile beards, and hats during walking.

Import preserves alpha and, for this batch, applies **threshold 128** to obtain binary 0/255 edges before reduction. Sources contain many partial alpha values; hardening them requires inspection to avoid losing an eye or strand of hair. `background: alpha` preserves the existing channel. The `edge-chroma` alternative removes only edge-connected green/magenta and rejects an ambiguous border; it must not erase interior object colors.

## Rendering, world, and game state

`game/scripts/sprite_art.gd` loads the manifest and decodes/caches PNG textures. Rendering uses Nearest and integer positions; it does not generate images per frame. The project retains a 768×432 viewport; current fullscreen fitting supports fractional scaling. Pixel art reviews also use captures at integer scales. Character layers receive the same frame and direction; the renderer exposes scenery objects with Y-based depth so integration can sort them with residents.

`game/data/world_layout.json`, read by `world_layout.gd`, centralizes sizes, positions, physical footprints, depth, access, and interaction points. Drawing, navigation, routines, and learning stations read that same geometry. Scale calibration redistributed five facades along the top row, enlarged smaller homes, and compacted interiors. The six logical homes retain their identity: César and Lupita share a facade, and Inés's and Mateo's homes are associated with the café and workshop. Saves preserve knowledge and inventory; load-time position recovery resolves old coordinates that fall inside a new footprint.

The size reference is the character silhouette, about 22 pixels tall, inside its 24×32 cell. The customization portrait is enlarged 3×. New dimensions come from reimporting original sources, without enlarging small PNGs or requesting another generation. Measurements and checks for this calibration are in [escala-del-mundo.md](escala-del-mundo.md).

Interiors retain their lore and are visually distinguished by palette and personal project. The photograph and some furniture are shared pieces; they are not yet six unique visual mementos that literally represent each story. Contextual text remains in Godot, using PixelifySans, instead of depending on tiny letters generated in images.

The bicycle changes between broken and repaired according to verified progress; tea and planter also have state pieces. The renderer can hide the bicycle with `bicycle_away`, but `main.home_project_state()` currently supplies `false`: the station remains represented while riding. There is no separate empty-stand piece yet; enabling the absent state will require resolving the hotspot representation and its obstacle. This does not alter unlocking or inventory.

The UI uses a surface atlas for buttons, panels, fields, focus, and scrolling, while retaining native controls, dynamic text, and keyboard navigation. The atlas does not replace selection, conversation, or customization logic. Review of its application in the main scene is recorded as a separate check from PNG import.

## Reimport and regenerate

To reimport **the same sources**, from the project root:

```sh
node scripts/build-sprite-catalog.mjs
node scripts/prepare-sprites.mjs --catalog scripts/sprite-catalog.json --out game/assets/sprites --manifest game/assets/sprites/manifest.json
node scripts/prepare-sprites.mjs --self-test
```

This is a reproducible local process using the retained PNGs and catalogs. Files are written atomically. For an experiment, use another directory inside `game/` and a different manifest, without replacing the approved batch.

Regeneration is a separate step: use the [catalog's safe command](sprite-catalog.md#model-output-and-cost), with this batch's exact model, the installed CLI, the retained prompt, and versioned PNG output. For accessories, use `edit` with `body.png` as the reference and the specific prompt; for terrain, use `background=opaque`. The build keeps the key exclusively in the process environment, never in visible commands, manifests, or the Godot client. Do not execute `.env` contents as shell code.

Model regeneration is not reproducible pixel for pixel: boundaries, palette, or poses may change even with the same prompt. Before replacing sources, review alpha, grid, crops, material masks, accessory scale, and anchors; update explicit calibration and reimport. Record model, parameters, prompt, reference, and the accepted source hash. Do not automatically copy a new image over the previous source.

Rebuilding local sprites makes no AI calls. Generation does use the API; no verified total cost is recorded for this batch. [Official prices](https://developers.openai.com/api/docs/pricing) are token-based and do not allow a per-sprite cost to be inferred without actual usage.

Before accepting a version: check appearance options at 1×/3×, all four directions and phases, accessory overlap, doors and interactive objects, depth, learning states, UI with long text, and stability during movement. Importer and atlas-structure tests do not replace that in-game review.
