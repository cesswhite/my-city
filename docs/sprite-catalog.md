# My City sprite catalog

Production reference for the first batch of September 23, 2026. Coordinates and fitting boxes in this document describe the initial layout, before the subsequently requested proportion correction. Current geometry is in `game/data/world_layout.json`, explained in [escala-del-mundo.md](escala-del-mundo.md); use those data for new imports, doors, routes, and interactions. This catalog's prompts, sources, layers, and style references continue to document the original batch.

<a id="modelo-salida-y-coste"></a>

## Model, output, and cost

Explicitly use `gpt-image-2.5-sunburst` or its snapshot `gpt-image-2.5-sunburst-2026-09-08`. This is the initial choice for establishing piece quality and consistency. `gpt-image-2.5-flare` and `gpt-image-2.5-flare-2026-09-08` also belong to the requested family; they prioritize speed. On 2026-09-23, the project's model list returned HTTP 200 and included all four IDs. This verifies the available catalog, not a generation or remaining quota.

| Model | Proposed use | Official evidence |
| --- | --- | --- |
| Sunburst | Initial silhouette, aligned pieces, and precise editing | [Sunburst model](https://developers.openai.com/api/docs/models/gpt-image-2.5-sunburst) |
| Flare | Later comparison once an approved reference exists | [Flare model](https://developers.openai.com/api/docs/models/gpt-image-2.5-flare) |

The documentation describes Sunburst as quality-oriented and Flare as speed-oriented, with quality comparable to GPT Image 2. It offers no fixed speedup for this work. [Prompting guide](https://developers.openai.com/api/docs/guides/image-prompting).

Both have the same standard rates per million tokens: image input US$8, cached input US$2, and output US$30; text input US$5 and cached input US$1.25. Usage may differ, so these rates are not a fixed price per sprite or image. Record `usage` when available. [Official pricing](https://developers.openai.com/api/docs/pricing). These are the rates recorded for the original production, not a guarantee of current pricing.

PNG output is mandatory. Request `background=transparent` for cutout pieces; both models support it. Verify real alpha, especially edges, hair, and gaps. Visible room floors and walls may be opaque. If transparency fails, use only a flat fluorescent green or fluorescent Mexican pink background absent from the subject, without gradients, texture, shadows, or a painted checkerboard; then remove only that background. [Generation and transparency](https://developers.openai.com/api/docs/guides/image-generation).

The local CLI accepts an explicit model, PNG, and transparency. Its size/quality validators lag behind: for 2.5 use `1024x1024`, `1536x1024`, `1024x1536`, or `auto`, and `low`, `medium`, `high`, or `auto`. Do not modify the installed CLI. The integrated image tool in the production session exposes no model selector and cannot verify its identity.

Future execution command from the project root, using the existing key without printing it or including it in process arguments. It runs the official installed CLI, not an alternative image client. The prompt file is an input that must be prepared first; this catalog does not create it or execute the command:

```sh
node --input-type=module <<'NODE'
import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { spawnSync } from 'node:child_process';
const projectEnv = parseEnv(readFileSync('.env', 'utf8'));
if (!projectEnv.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is missing from .env');
const imagegenCli = process.env.IMAGEGEN_CLI;
if (!imagegenCli) throw new Error('Set IMAGEGEN_CLI to the path of your installed image CLI.');
const result = spawnSync('python3', [
  imagegenCli,
  'generate',
  '--model', 'gpt-image-2.5-sunburst-2026-09-08',
  '--prompt-file', 'tmp/imagegen/body-master.txt',
  '--size', '1024x1024',
  '--quality', 'high',
  '--background', 'transparent',
  '--output-format', 'png',
  '--no-augment',
  '--out', 'output/imagegen/body-master-v1.png'
], {
  env: { ...process.env, OPENAI_API_KEY: projectEnv.OPENAI_API_KEY },
  stdio: 'inherit'
});
if (result.error) throw new Error('Could not start the image CLI');
process.exit(result.status ?? 1);
NODE
```

This CLI belongs to the production environment's tools and is not included in this repository. `IMAGEGEN_CLI` must point to your installation; it is not needed to play. The interpreter needs the `openai` package. Adding `--dry-run` to the arguments validates the payload without generating; the Sunburst + transparent PNG + `1024x1024` + `high` dry run already passed. For pieces derived from a visual reference, use `edit --image <reference.png>` in the same CLI and retain model, format, and background. Keys stay outside the Godot client and repository.

## Shared contract

- Logical viewport: **768×432**. Street world rectangle: **(12,48,468,258)**. All following positions are absolute logical viewport coordinates, with origin at the upper left; `rect=(x,y,w,h)`.
- One logical pixel must occupy an integer number of screen pixels. Lossless PNG, Nearest, no mipmaps or antialiasing at import. Do not apply bilinear interpolation or stretch a cell to correct alignment.
- Oblique top-down RPG perspective, front-facing facades, upper-left light, one-logical-pixel outline, warm terracotta, cream, sage, and wood tones. Two or three levels per material. Avoid 3D volume, photographic gradients, and subpixel noise.
- Distinguish **draw rectangle**, **visual anchor**, **interaction rectangle**, and **physical obstacle**. The new PNG replaces the first. Preserve the other three and navigation destinations.
- Save generation output in `output/imagegen/`; normalized Godot assets in `game/assets/sprites/v1/`. Do not overwrite approved versions. Do not link assets to personal generation paths.
- Future per-piece manifest: `id`, `source_model`, `prompt_file`, `source_png`, `texture`, `source_rect`, `logical_size`, `pivot`, `draw_at`, `layer`, `direction`, `animation`, `frame`, `duration_ms`, `palette_group`, `occlusion_rule`. Atlas rectangles are render metadata, not character save data.
- Place labels, names, values, and UI text continue using PixelifySans in Godot; do not bake letters into generated images. Letterless plaques are sprites.

## Characters: five neighbors and the player

**Final cell 24×32; foot pivot (12,30).** The visible silhouette should remain close to 14×25, leaving transparent space around it. Draw at `pos-pivot`, with one shared transform for all layers. Keep the appearance view at 3×; silhouette and hat must fit inside its current 77×76 box, even if the full transparent canvas is larger.

Master sheet **4 columns × 4 rows**, **1024×1024 source**. Each source cell is 256×256. Reserve 32 transparent pixels on each cell's left and right sides: the useful 192×256 region corresponds to 24×32 at 8× scale. Crop each useful region before reducing with Nearest; do not deform a complete square cell to 24×32. The normalized atlas is **96×128**. The exact positions of generated pixels must be inspected before accepting the crop.

| Axis | Required order |
| --- | --- |
| Rows | 0 `down`, 1 `left`, 2 `right`, 3 `up` |
| Columns | 0 `idle`, 1 `walk_a`, 2 `neutral`, 3 `walk_b` |
| Walking | `walk_a → neutral → walk_b → neutral`; `neutral` may repeat `idle` |
| Idle | `idle` column; anchor and size do not change |

All layers use the same pose index and shared clock. Do not automatically mirror asymmetric details. In the renderer at the time of this catalog, only front view and two phases existed; direction must be derived from movement and retained on stopping during integration. As a transition, `phase=0/1` values may select `walk_a/walk_b`, but this does not replace validation of four directions.

### Eight appearance fields compatible with saves

| Field | Indices, names, and material |
| --- | --- |
| `skin` | 0 Ivory `#f6d4b3`; 1 Sand `#e8b78c`; 2 Honey `#c78c65`; 3 Copper `#a96846`; 4 Cocoa `#80513c`; 5 Ebony `#51392e` |
| `hair_style` | 0 Short; 1 Curly; 2 Long; 3 Shaved |
| `hair` | 0 Dark `#302b2d`; 1 Brown `#624337`; 2 Copper `#a66540`; 3 Blond `#ddb76c`; 4 Gray `#b4b2a6`; 5 White `#eee5d0` |
| `eyes` | 0 Brown `#342d29`; 1 Honey `#796443`; 2 Green `#648278`; 3 Blue `#58819a`; 4 Gray `#999597` |
| `beard` | 0 No beard; 1 Mustache; 2 Full; uses the `hair` palette |
| `hat` | 0 None; 1 Straw; 2 Beanie; 3 Cap. The beanie at this stage takes the shirt color; preserve that dependency |
| `shirt` | 0 Terracotta `#b45f49`; 1 Sage `#5f8277`; 2 Mustard `#cbac65`; 3 Blue `#6c8591`; 4 Pink `#b68b9d`; 5 Cream `#eee3c9` |
| `pants` | 0 Navy `#435664`; 1 Earth `#605b4c`; 2 Olive `#4a5146`; 3 Hazelnut `#8b7056`; 4 Sand `#d0bda0` |

Generate a bald base without beard or hat, with distinct warm skin, neutral blue shirt, and dark purple trousers. Then normalize to separate skin, eye, shirt, and trouser material masks: recoloring the shirt must not modify eyes or skin. Preserve shadows through palette ramps, rather than tinting the whole image. Shoes/outline remain independent of trousers.

Accessory sheets have rows per direction and columns per variant. They use the same cell, useful region, and pivot as the base; never center each hairstyle or hat by its own crop. Each accessory is placed over the exact base reference. Where head movement changes between poses, produce or align all four corresponding poses; reuse one piece only if the head stays still.

| Production ID | Contents and rule |
| --- | --- |
| `person/body_master` | 16 base poses; verified skin/clothes/eye masks |
| `person/hair_front/{short,curly,long,shaved}` | Four directions; recolorable through `hair`; shaved style preserves visual blending with skin |
| `person/hair_back/{short,curly,long,shaved}` | Separate rear part; may be transparent for styles that do not need it |
| `person/beard/{mustache,full}` | Front/profile face; transparent when facing away |
| `person/hat/{straw,beanie,cap}` | Consistent brims/knitting/visors; hair occlusion mask per direction |
| `person/palette_masks` | Skin, eyes, shirt, and trousers with stable material IDs; these are not new user options |
| `person/contact_shadow` | Optional separate shadow aligned to the feet; not drawn onto chroma |

Initial visual order: shadow → rear hair → body/clothes and face → eyes → beard → front hair → hat. Validate the order in all four directions; the hat hides only incompatible hair, without erasing beard or eyes.

All six characters are presets of the same catalog, not six indivisible images. Indices in `skin/hair_style/hair/eyes/beard/hat/shirt/pants` order:

| Resident | Initial preset | Visual character and context |
| --- | --- | --- |
| César `cesar` | `1/0/1/1/1/1/0/1` | Straw hat, mustache, terracotta; plant caretaker raised with his father in the countryside |
| Lupita `lupita` | `2/2/0/0/0/0/1/0` | Long dark hair, sage; sociable organizer raised in the city |
| Mateo `mateo` | `3/1/2/2/2/2/2/1` | Copper curls, full beard, mustard beanie; craft inherited from his grandparents |
| Inés `ines` | `0/2/3/3/0/0/3/2` | Long blond hair and blue shirt; café host |
| Alma `alma` | `1/1/1/1/0/3/4/0` | Brown curls, cap, and pink shirt; illustrator preserving neighborhood stories |
| Player `player` | `1/0/0/0/0/0/5/0` | New resident, cream shirt; all eight fields remain editable |

### Base prompt for the body sheet

```text
Use case: stylized-concept
Asset type: modular pixel-art game character sprite sheet, PNG RGBA
Primary request: One consistent bald adult neighborhood resident, no beard or hat,
in a neutral blue shirt and dark purple trousers, warm skin and simple readable eyes.
Composition: exact 4-by-4 grid in a 1024-by-1024 transparent canvas. Each cell is
256-by-256; keep 32 transparent pixels on both sides inside every cell. The useful
192-by-256 region represents exactly a 24-by-32 logical-pixel cell enlarged 8 times.
Rows: facing down, left, right, up. Columns: idle, left-foot walking contact,
neutral passing pose, right-foot walking contact. Keep proportions, feet anchor,
head anchor and light direction identical. Neutral may reuse idle.
Style: crisp integer pixel clusters, warm cozy neighborhood RPG, restrained palette,
top-down oblique view, one-logical-pixel outlines, no antialiasing or gradients.
Constraints: no text, no grid lines, no labels, no scenery, no visible background,
no baked ground shadow, no extra characters, no missing or overlapping cells.
Each figure stays approximately 14-by-25 logical pixels inside its useful cell;
feet anchor is (12,30). Materials must remain clearly separable for recoloring.
```

For accessories: attach the approved base as a reference and request only the indicated layer on the same canvas. Preserve all cell gaps and anchors; do not redraw body, clothes, or face in the hair/hat/beard PNG.

## Street, facades, and objects

There are **six logical homes**, but not six independent buildings: César and Lupita share the central facade; the café contains Inés's door and the workshop Mateo's. Preserve this layout. The garden is an open space; do not invent a facade or new entrance.

The following boxes are proposed fitting boxes based on the drawing at this stage, including margins where useful. Doors and destinations are exact engine data. Separate shadows, pots, and signs if they are included in another piece to avoid drawing them twice.

| Visual ID | Absolute fit `(x,y,w,h)` | Preserved anchor/interaction | Prompt specification |
| --- | --- | --- | --- |
| `street/cafe_ines` | `(27,55,115,110)` | Inés's door `(82,158)`; café activity `(110,178)` | Salmon facade, roof tiles, chimney, windows, and striped awning; text-free plaque; separate patio |
| `street/homes_cesar_lupita` | `(149,81,90,82)` | César `(174,158)`; Lupita `(214,158)` | One cream two-home facade, shared roof, green left door and pink right door |
| `street/home_alma` | `(268,89,52,74)` | Door `(294,158)` | Compact lavender studio, roof tiles, blue door; retain side passage |
| `street/workshop_mateo` | `(319,63,132,106)` | Mateo's door `(384,158)`; workshop `(386,178)` | Wood/olive workshop, shutters, roof ventilation, and separate supplies |
| `street/home_player` | `(435,171,43,54)` | Door `(456,224)` | Small cream/sage home, roof tiles, and step toward the garden path |
| `street/shop` | `(23,194,54,29)` | Exact hotspot equals fit; service `(48,228)` | Tools, seeds, and tea stand with green/mustard awning and empty plaque |
| `street/garden` | `(339,210,108,72)` | Activity `(386,238)` | Soil, beds, sprouts, low fence, and plaque; open middle passage |
| `street/fountain` | `(209,207,52,41)` | Proposed visual anchor `(234,244)`; plaza `(236,210)` | Tiered stone fountain, teal water; basin separable from the jet |

Activity destinations: `plaza=(236,210)`, `cafe=(110,178)`, `taller=(386,178)`, `huerto=(386,238)`. Preserve exact obstacles in `Navigation.STREET_OBSTACLES`. In particular, the fountain blocks `(204,220,61,29)`, shop `(23,194,56,30)`, and player home `(436,171,40,50)`; enlarging sprite pixels must not enlarge collision.

| Reusable piece | Current anchor/instances | Deliverable |
| --- | --- | --- |
| `street/tree_large` | Trunk foot `(318,283)`, `(45,274)` | Proposed cell 48×56, pivot `(20,52)`; separate canopy/trunk if there will be occlusion |
| `street/tree_small` | `(25,142)`, `(463,150)`, `(112,293)` | Cell 40×48, pivot `(16,44)`; same species and light |
| `street/bench` | Proposed support `(200,209)`, `(262,264)`, `(79,268)` | Cell 34×16, pivot `(17,15)`; equivalent to `_bench(x,y)` placed at `(x-1,y)` |
| `street/pot_plain`, `street/pot_flower` | Calls `(34,148)`, `(122,147)`, `(331,154)`, `(181,248)` | Cell 12×20, pivot `(6,19)`; foot at `(x+4,y+12)` relative to the current call |
| `street/cafe_table_set` | Drawing around `(43,168)` and `(129,168)` | Two compatible sets; obstacles `(31,165,44,24)` and `(117,165,44,24)` |
| `street/garden_bed` | Corner `(349,230)`, `(401,230)`, `(423,230)` | Bed 22×34; sprouts with readable outline; do not fill passage x≈386 |
| `street/lamp` | Base `(158,195)` | Post and lantern approximately 8×34; ground support separate from light |
| `street/bunting` | String x231..324, y119..129 | Terracotta, mustard, sage, and pink papel picado; transparency between pieces |
| `street/crate_stack` | Workshop crates around `(399,150)` and `(413,152)` | Two wooden pieces that do not cover the door |
| `street/cat` | Approximate fit `(149,151,16,10)` | Resting orange cat, decorative; do not add an agent or collision |
| `street/ground_tiles` | 16×16 modules; existing ground compositions | Grass, sand path, paving, edges, and flowers; retain layout geometry |

Prompt for each row: “Indicated object/facade, isolated and complete, oblique top-down perspective identical to the approved reference, proportions of the specified logical fit, upper-left light, neighborhood palette, transparent PNG, no rectangular ground, text, or extra objects.” Attach the approved sample as a reference and export each object separately. Do not request an entire city and then assume it matches the map.

## Six interiors and their objects

Room IDs: `cesar`, `lupita`, `mateo`, `ines`, `alma`, `player`. Shared visible canvas `(12,48,468,242)`. Walkable floor inside `(32,108,428,170)`, minus existing obstacles. Entry `(236,252)`, exit `(236,264)`, owner's rest point `(88,212)`. Do not change doors or route a character through new furniture.

Produce wall/floor backgrounds per palette and separate common furniture. The background must not contain a second copy of dynamic objects. The following interaction areas are exact values from `Art.interior_items()`, not physical navigation boxes:

| Slot and piece | Hotspot `(x,y,w,h)` | `stand_at` | Variations |
| --- | --- | --- | --- |
| `interior/bed` | `(55,109,66,79)` | `(136,172)` | Each home's blanket/upholstery; the drawing at this stage reaches y193, unlike the hotspot |
| `interior/project/{home}` | NPC `(298,190,44,46)`; player `(298,196,44,42)` | `(284,220)` | Personal object per home; `bicycle` station only in the player's home |
| `interior/memento/{home}` | `(274,78,42,27)` | `(284,116)` | Wall photo/postcard without tiny baked-in text |
| `interior/books/{home}` | NPC `(350,157,80,35)`; player `(350,155,80,38)` | `(336,180)` | Books/mementos; `planting` planter in the player's home |
| `interior/table/{home}` | `(172,148,88,45)` | `(276,172)` | Table with notebook/cup; `tea_station` in the player's home |

| Home | Wall / accent / wood palette | Project, memento, and shelf: narrative prompt |
| --- | --- | --- |
| César | `#b9c19b / #6f8c62 / #d1b77f` | Seed packets and three pots; photo of César with his father in the countryside at sunrise; notebook of plants and watering dates |
| Lupita | `#d8b7ad / #b76e68 / #dcc096` | Basket with tablecloths and invitation cards; portrait with her mother and father in a plaza; notebook of gatherings and quiet afternoons |
| Mateo | `#aebabc / #5d7c86 / #baaa86` | Bicycle wheel on a stand and inherited wrench; photograph of his grandparents' workshop; annotated manual for teaching patiently |
| Inés | `#ddc9a9 / #b78458 / #d5b594` | Travel teapot with recipe book; postcards of cafés and cities; recipes and visitors' stories |
| Alma | `#c5b7c7 / #94748e / #c7b7a0` | Easel with an unfinished neighborhood painting; old neighborhood photo; album with a small orange cat as a visual detail |
| Player | `#bcc8b0 / #608a82 / #c9b89a` | Repairable bicycle and stand; welcome postcard; empty/planted planter; table with teapot and empty/prepared cup |

Common elements without their own hotspot: window and curtains `(49,70,75,34)`; walkable rug `(153,137,126,86)`; chair around `(201,199,20,18)`; sideboard `(347,108,84,35)` with jar on top; tall plant `(403,211,22,35)`; exit mat `(216,257,40,16)`. Render the Spanish label “SALIR” (EXIT) and home title with the UI font. Preserve bed, table, chair, sideboard, shelf, project, and plant footprints from `INTERIOR_OBSTACLES`.

States derived from player progress, without granting anything through art:

- `garden_planted=false/true`: dry empty planter / freshly watered soil with seeds and a marker. Do not show instantly mature flowers.
- `tea_ready=false/true`: empty cup / infusion with subtle steam.
- `bicycle_repaired=false/true`: broken / repaired bicycle; see the next section.
- `bicycle_away=true`: the stand remains and the bicycle disappears while riding.

Interior prompt: “The same room and furniture positions as the reference, home of [ID], palette [table], upper wall and wooden floor, narrative objects [table]. Export wall/floor without furniture and each prop isolated in its own layers. Do not move exit, bed, table, shelf, or stand. Do not draw readable text; the story is presented in the game.”

## Bicycle and learning objects

At least two states, `bicycle/broken` and `bicycle/repaired`, with the same shape, fit, and anchor. The broken version shows a deflated tire and loose chain; the repaired version preserves exactly the same bicycle. Frame color `#648d84`. Proposed cell **48×40**, pivot **(24,36)**; the drawing at this stage spans approximately x−20..x+20 and y−24..y+3 relative to its anchor. At home it is placed at **(320,230)**, with a separate stand.

The mounted version retains movement anchor `player.pos` and uses `bicycle_riding.png`: four directions and four phases per direction, with **40×32** cells and anchor **(20,30)**. The cyclist is composed from the same `appearance` layers, seated, with arms and pedals adjusted to each view. See [bicycle art and movement](bicicleta-y-movimiento.md) for implemented measurements and provenance. The mounted state is visual and runtime; `can_ride_bicycle()` remains the unlocking authority.

Inventory PNG icons at 16×16: `aceite`, `semillas`, `hojas_te`, `kit_bicicleta`, `bicicleta_averiada`, `bicicleta`, `kit_jardin`, `jardin_plantado`, `kit_te`, `taza_te`; separate coin. Icons represent existing catalog IDs and never create a new quest variant.

## UI atlas

Proposed logical atlas **256×256**, base grid **16×16**; it can be generated at 1024×1024 (4×) and normalized. Metadata for each region must accompany the PNG; do not infer coordinates through runtime image recognition. Retain PixelifySans, dynamic text, and native controls for focus, keyboard, scrolling, and accessibility.

| Family | Requested regions/states | Rule |
| --- | --- | --- |
| 9-slice frames | Paper panel, raised panel, tooltip, text field | Square corners; logical border 1px, focus 2px; extensible background without scaling corners |
| Primary button | Normal, hover, pressed, disabled | Ink green/cream; perceptible hover and pressed states |
| Secondary button | Normal, hover, pressed, disabled | Paper/sage; sufficient contrast and identical geometry |
| Tabs | Normal, selected, hover, focus | Selected state visible beyond color alone |
| Scroll | Track, normal/hover/drag thumb | Stable width without intruding on content |
| 12–16px icons | Person, story, memory, talk, appearance, schedule, home, shop, backpack, coin, bicycle, tea, seed, save, pause, play, close, arrows | Readable silhouette; 1×/2×/4× states remain text |
| World status | Local, connected, busy, error, objective, complete | Never imply connected AI through an icon; use the host's actual state |

UI prompt: “Pixel art interface element atlas for the reference neighborhood. Square outline, ink #303e37, paper #f4edda, sage #68735e, terracotta #a85540. Transparent PNG, uniform grid without visible guides, isolated pieces; no words, numbers, or full-screen backgrounds. Keep variants the same size with identical margins so they do not jump when pressed.”

## Migration without changing the simulation

1. Save source PNG, prompt, exact model, and inspection result. Approve the body and one facade at actual size first; produce remaining pieces against those references.
2. Normalize crops, alpha, palettes, and anchors for all 16 frames. Do not auto-trim each frame. Explicitly identify any incomplete cell; a generated image does not guarantee a usable sheet.
3. Replace rendering by ID while maintaining the `draw_world`, `draw_interior`, `draw_person`, and `draw_bicycle` signatures or a compatible adapter. Load textures once; do not compose images or load PNGs per frame.
4. Preserve `appearance` and its indices, room IDs, doors, `stand_at`, hotspots, actions, inventory, routines, progression, and memory. No visual change unlocks knowledge or forces a save migration.
5. Separate ground and tall objects when integrating Y sorting. Trees/people/furniture require compatible anchors; do not accidentally hide interfaces or interaction points.
6. Verify: all presets and options; four directions; hair with hats; readable preview eyes; no cut-off pieces; entry/exit for all six homes; purchases and three stations; broken/repaired/absent bicycle; identical collisions and routes; UI without overflow with long text.
7. Validate real PNG RGBA over dark and light backgrounds and at integer 1×/3× zoom. Reject chroma halos, painted checkerboards, mixed perspectives, and duplicate shadows. Measure frame time with six characters; playing local sprites makes no model calls.
