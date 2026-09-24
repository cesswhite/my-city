# Audit of the current pixel art

September 24, 2026. State before the visual refresh. Read-only audit: source PNGs, imported PNGs, the catalog, geometry, and existing captures were inspected; no images or production code were generated or modified.

## Identity worth preserving

The neighborhood already has a recognizable direction: cream, pink, and lavender adobe, terracotta roof tiles, warm wood, muted green foliage, teal details, and papel picado. The café, workshop, garden, and homes are recognizable by silhouette and activity. Modular customization preserves the identity of all six characters.

The common perspective is frontal three-quarter, with horizontal and vertical axes and visible top surfaces. It is not isometric. Daylight comes primarily from the upper left. This foundation allows a coherent refresh without changing the game's visual language or enlarging the characters.

## Evidence inspected

Paths under `artifacts/` below are historical local evidence, excluded from the public repository. Source PNGs and production contracts remain versioned.

- Sources: [buildings](../output/imagegen/buildings.png), [outdoors](../output/imagegen/outdoors.png), [interiors](../output/imagegen/interiors.png), [terrain](../output/imagegen/terrain.png).
- Current scenes: initial plaza (`artifacts/settlement-world/initial-street.png`), initial homes (`artifacts/settlement-world/initial-homes.png`), forest (`artifacts/settlement-world/forest.png`), growing garden (`artifacts/settlement-world/growing-garden.png`).
- Interior and hierarchy: César's home (`artifacts/home-ui/after/768x432-cesar-entry.png`). Characters: appearance layers (`artifacts/ui-learning-review/characters-modular-preview.png`) and four bicycle views (`artifacts/bicycle/bicycle-directions.png`).
- Lighting: night exterior (`artifacts/living-neighborhood/night.png`) and night interior (`artifacts/living-neighborhood/home_night.png`). These two captures document lighting and materials in an earlier layout; they do not represent the current placement of every home.
- Contracts: [manifest](../game/assets/sprites/manifest.json), [catalog](../scripts/sprite-catalog.json), [catalog builder](../scripts/build-sprite-catalog.mjs), [geometry](../game/data/world_layout.json), and [neighborhoods](../game/data/neighborhood.json).

Reviewed complete scenes include interfaces at 768×432 and 960×540. The four listed `settlement-world` captures are 936×488 and show only the world at 2×, without the HUD. Do not confuse readability in that crop with readability of an object next to text or controls during gameplay.

## Detail measurements

Final PNGs were read in memory with Sharp, counting distinct RGB colors only where alpha >127. These measurements describe imported art, not the background used by the viewer to present transparency.

| Final PNG | Native canvas | Opaque pixels | Distinct RGB colors |
| --- | --- | ---: | ---: |
| `cafe.png` | 100×90 | 7530 | 6698 |
| `homes.png` | 96×76 | 6638 | 5339 |
| `alma_home.png` | 68×74 | 4132 | 3811 |
| `tree.png` | 42×56 | 1144 | 1139 |
| `fountain.png` | 61×46 | 1938 | 1902 |
| `table.png` | 40×27 | 840 | 703 |
| `flowerpot.png` | 12×16 | 126 | 126 |
| `tile_grass.png` | 32×32 | 1024 | 573 |
| `tile_sand.png` | 32×32 | 1024 | 769 |
| `tile_wood.png` | 32×32 | 1024 | 860 |
| `tile_soil.png` | 32×32 | 1024 | 858 |
| `rug.png` | 88×60 | 5280 | 4581 |

Color count alone does not determine quality, but it confirms what is visible: heavily textured illustrations reduced with Nearest predominate, with many isolated detail pixels. There is no limited shared palette yet. Downsizing an illustration preserves its fine noise; it does not automatically produce deliberate pixel clusters.

Building sources are 1536×1024; outdoors, interiors, and terrain are 1024×1024. The first three contain real alpha, normalized to binary at import. Terrain is opaque. Small final PNGs must not be enlarged and reduced again to manufacture detail.

## Scale, perspective, and lighting

- The visual unit is the standing body of approximately 10×22 pixels inside a 24×32 cell with foot anchor `(12,30)`. Body layers share four directions and four phases; accessories must remain aligned. They also contain tonal variation, so they are not a literal example of a limited palette, but their silhouette is much simpler than the environment.
- Logical world: `Rect2(12,48,468,244)`. The client enlarges it uniformly to fill the viewport and draws the HUD in screen space. Review native 1×, integer 2×/4×, and actual 768×432/960×540 views; a large source sheet can look excellent yet lose hierarchy during play.
- Interaction proportions are already calibrated: bed 26×38, table 40×27, chair 10×16, planter 42×28, cup 8×10. Doors are 24–27 high and 11–15 wide. Preserve support surfaces, openings, and anchors as well as outer canvas size.
- Facades, benches, and furniture share the correct axes. The side-view bicycle is deliberately in profile. Do not make some objects isometric or vary top-surface angles between batches.
- Upper-left light works as the common direction. Texture contrast should be reduced without removing volume. Avoid large highlights or baked ambient shadows that compete with the day/night cycle.
- Glass and bulbs have specific light masks in `world_lighting.gd`. A new window requires its panes to be reviewed; a same-size facade does not guarantee that those crops remain aligned. Contact shadows must retain consistent intensity and direction.

## Visual problems and hierarchy

1. **The ground demands too much attention.** Grass, sand, wood, and rugs have detail frequency and contrast similar to furniture. Empty spaces feel noisy. Terrain should be the quietest layer; architecture and vegetation follow; characters and usable objects come forward; notices and readable text come last.
2. **Natural transitions are missing.** Paths, small plots, and the pond are built from texture rectangles. Repetition and 90° joins are visible. In addition to the 16 textures, compatible edges or a common transition strategy are needed, without inadvertently moving physical passages.
3. **César's and Lupita's homes are halves of one duplex.** Each 48×76 crop loses the original building's composition and part of the central window. Mirrored edge finishing repairs the boundary but does not create a recognizable individual home.
4. **Brown blends floors and furniture.** Indoors, tables, cabinets, and floors have similar values, while the rug is too prominent. Improve outline and surface readability, reduce floor texture, and reserve accents for relevant objects.
5. **Vegetation has little variety amid extensive repetition.** Two trees and the same pots repeat across every neighborhood. Coherent families with silhouette and grouping variants provide more identity than extra noise or arbitrary furniture.
6. **Economic states are less recognizable.** Wood, stones, plots, and growth currently use parts of other sprites. This works as a foundation but lacks the clarity of pieces designed for each resource/state. Ready crops should be distinguishable by shape, not just tint.

## Recommended refresh order

1. Establish one complete reference sample: quiet terrain, café, table, tree, and current character, with a shared 64–96-color palette, clear clusters, no dot dithering, and upper-left light. Review it in the game before producing all pieces.
2. Terrain and material joins; then the six existing facades as one family. Prepare the two individual homes described below separately.
3. Outdoors: vegetation, fountain, benches, café table, fence, and bunting; add resources and construction/crop states under the same rules.
4. Interiors: furniture, windows, textiles, plants, personal objects, and stations, including usable and completed states.

References enlarged to 512-pixel cells with integer factors preserve the native object. Future imports must retain canvas, alpha/anchor, door coordinates, and interactive surfaces, without variable automatic trimming. This audit does not validate a new generation model: verifying GPT Images 2.5 and PNG output under `AGENTS.md` remains mandatory before any call.

## Two independent homes, retaining 48×76

Visual proposals only, without art or production changes yet. The following coordinates are local to each future 48×76 image, not the old 96×76 atlas. The full current physical footprint and draw depth remain unchanged.

| Home | Area | World rectangle | Exact local door | Drawn world door | Access point |
| --- | --- | --- | --- | --- | --- |
| César | `gardens` | `(120,84,48,76)` | `(16,44,11,27)` | `(136,128,11,27)` | `(142,160)` |
| Lupita | `homes` | `(168,84,48,76)` | `(21,44,12,27)` | `(189,128,12,27)` | `(195,160)` |

Both currently use `prop_key="homes"` in their own area and `sort_y=159.99`. César comes from crop `(0,0,48,76)` and Lupita from `(48,0,48,76)` of the duplex. Do not move an opening to center it artificially; its small differences already match navigation and hover.

**César: cream adobe home with a garden.** Complete roof contained within the current silhouette; tiles grouped into a few tones and a horizontal band between roof and wall to avoid a tower-like appearance. A plain wooden door exactly in the agreed rectangle. A small sage-green window can occupy `(32,44,8,12)`, with sill `(31,56,10,2)`. On the left, a fiber or hanging-tool detail inside `(5,43,7,15)` communicates everyday garden care. Low plants in already occupied positions, without crossing the access. Do not incorporate private family information into signs or visible decoration.

**Lupita: warm cream home with muted pink accents.** Keep the door at `(21,44,12,27)` and reinforce horizontality with subtle lintel/cornice details. The small window stays on the left, proposed at `(7,44,9,12)` with sill `(6,56,11,2)`. A warm curtain and small planter create a domestic welcome without copying the player's home or turning it into a shop. A text-free ceramic motif inside `(36,43,6,8)` distinguishes the facade. Do not reveal her private fear of organizing meals or imply romantic relationships through portraits or symbols.

The proposed windows are new internal compositions within the same silhouette; their panes and lighting must be defined with the final art. Each facade needs its own complete edges, removing the `edge_finish` patch and half-home crop only during future integration. If IDs `cesar_home` and `lupita_home` are created, keep `prop_key`, door, footprint, depth, and construction state stable. This is a pending renderer/catalog adaptation, not a change made by this audit.
