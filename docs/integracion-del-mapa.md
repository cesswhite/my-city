# Map integration

The map uses logical pixel coordinates. A character's point represents its feet: the drawing may extend above its position, while navigation checks the ground it stands on. Enlarging or moving an image must not implicitly change its collisions or the point where an interaction happens.

## Shared geometry

`game/data/world_layout.json` is the source for positions, footprints, destinations, and stations. `game/scripts/world_layout.gd` converts its arrays into `Vector2` and `Rect2` for consumers:

- `sprite_art.gd` composes images at native size and uses catalog positions; `crop_sprites.gd` arranges row plants using crops from existing foliage.
- `navigation.gd` derives bounds, obstacles, and portals. Routes are calculated on a 4-pixel grid with a 1-pixel margin along its connections.
- `colony.gd` shares doors and routine destinations; the garden retains a semantic destination, `places.huerto`.
- `main.gd` uses those routes to move characters and resolves arrival before observing, entering, or performing an interaction.
- `progression.gd` resolves the shop and stations by ID when loading the learning catalog. A character's text does not alter these physical checks.

Each object distinguishes its visual rectangle from its `footprint`. Garden beds are occupied ground: their footprint must cover the crop so nobody walks through it. A fence needs both a drawing and a solid footprint; an opening in the drawing must match a physical opening. Suspended bunting needs supports and coherent draw order, but its string is not a wall on the ground.

## Applied composition

Bunting occupies `(263,115,96,23)`. Its local points `(15,0)` and `(79,0)` match the anchors on Alma's home `(58,29)` and the workshop `(50,27)`, respectively. Its depth order is `160.1`, in front of facades at depth `159.99`; the decoration does not add a navigation wall. The streetlight and café tables use their visible base for depth sorting.

Visual anchors and depth serve different purposes: the former says where the string attaches to a facade; the latter determines which image covers another. Using the string's height as depth placed it behind buildings sorted by their bases and hid the bunting. Its `160.1` value describes overlap relative to facades, without pretending that the string rests on the ground or moving its anchors. Characters remain sorted by foot position.

The five facades have a solid footprint down to their base, exclusive `y=160`. Previously they had no footprint, and the general street boundary allowed walking over them between `y=156` and `y=159`. Walls, windows, and integrated pots are now inside the solid building. The upper street boundary also starts at `y=160`, closing four-pixel gaps between facades that cannot fit the character's body; the lower edge remains at `y=292`. All six doors retain their exact access at `y=160`; facade drawing is sorted immediately before the character's feet at that threshold. This prevents crossing walls without blocking entrances or widening obstacles to the character's full size. Load-time reconciliation moves old positions that now fall inside these footprints.

The garden forms a soil plot with two long rows. Its ground uses these catalog pieces:

| Layer | Logical rectangle | Purpose |
| --- | --- | --- |
| `garden_approach` | `(276,212,68,14)` | Sand connection from the plaza |
| `garden_ground` | `(330,214,134,74)` | Shared warm-soil base with cropped corners |
| `garden_soil` | `(344,232,112,46)` | Continuous cultivated soil |
| `garden_path` | `(344,248,112,12)` | Horizontal path between the rows |
| `garden_side_path` | `(330,220,12,60)` | Access and passage along the west side |
| `garden_south_path` | `(330,280,134,8)` | Passage south of the plot |

Ground textures share a global grid originating at the world rectangle `(12,48)`. `_tile(..., world_aligned=true)` crops edges on that grid, preserving native pixel size. Object pieces, such as the fence, retain local anchoring.

The north row occupies `(344,232,112,16)` and the south row `(344,260,112,18)`. Each retains the full area declared by `crop_row`; it is not compressed to a PNG's size. `Crops.plant_specs(row)` places eight plants per row using crops from `garden_left` and `garden_right`. Every crop preserves a 1:1 source-to-destination pixel ratio. Rendering uses only opaque green foliage fragments, removing the old garden-bed sprites' rectangular backgrounds from the composition. No new images are generated and source PNGs are not rewritten.

The fence sits behind crops at `(342,214,122,17)`, with the sign attached to it. Stone borders surround the north and sides. The west border is split: it ends at `y=248` and resumes at `y=260`, leaving an entrance aligned with the horizontal path. A continuous side would enclose the path between two solid rows. The east border stays closed; the outside route connects through the west and south.

The semantic destination `places.huerto` and Alma's initial position are `(386,254)`, on the path. Fixtures that suspend or restore a conversation route read that destination from the catalog to preserve intent when the layout changes.

## Routes that must remain available

The garden destination must be on free ground and connect in both directions with all six doors, the plaza, café, workshop, and shop. Checks require arrival at the exact coordinate and sample every route segment; finding a nearby node is insufficient evidence that a station or door is usable.

The search may adjust a click on an obstacle edge by up to 12 pixels, but that convenience does not replace a designed entrance. The grid margin also prevents treating a visual slit as a valid passage. When changing beds, signs, or fences, check access and return routes, including the connection between workshop and garden.

On loading a save, `Navigation.recover_position()` reconciles a position occupied by a new footprint. This adjustment happens only at load time: normal movement does not teleport a character out of an obstacle.

## Dedicated test

`game/tests/environment_smoke.gd` validates environment integration without instantiating the main scene, reading a save, or calling external services. It checks correspondence between the two bunting anchors and their supports, depth, shared ground, and both solid rows. Its routes use real navigation and shared catalog coordinates; it includes manually crossing the west opening, following the perimeter, and rejecting passage through the rear fence and east border.

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path game --script res://tests/environment_smoke.gd
```

The `navigation_smoke.gd`, `sprite_smoke.gd`, and `scale_smoke.gd` suites complement this test with collisions, composition, and PNG dimensions. An inspected capture is still needed to judge whether supports and ground elements feel like parts of the same place; a traversable route alone does not demonstrate visual integration.

## Executed evidence

Paths under `artifacts/` below refer to historical local captures and logs, excluded from the public repository.

Local validation on September 23, 2026:

| Suite | Result |
| --- | --- |
| `environment_smoke.gd` | 56/56; 7,068 positions sampled along real routes |
| `navigation_smoke.gd` | 99/99 |
| `sprite_smoke.gd` | 51/51; 1:1 sources and destinations, crops without soil backgrounds |
| `scale_smoke.gd` | 69/69 |
| `autonomy_smoke.gd` | 35/35 |
| `autonomy_ai_smoke.gd` | 39/39; simulated requests, no providers |
| `keyboard_navigation_smoke.gd` | 26/26 |
| `controls_world_smoke.gd` | 44/44 |
| `progression_smoke.gd` | 72/72 |
| `learning_world_smoke.gd` | 31/31; 25,200 sampled positions |

Complete logs are in `artifacts/garden-redesign-validation/`. These ten suites total 522 passing checks. Composition expectations and fixture coordinates were updated for the new layout, preserving collision, exact-destination, persistence, and native-scale checks. The navigation algorithm was not modified.

The complete capture `artifacts/garden-v2/after.png` was inspected: the plot connects with neighborhood ground, plants form two continuous rows, and Alma stands on the middle path. The capture also retains bunting attached to its facades. Visual readability was reviewed in that image; automated tests do not replace the user's assessment of the design.

Additional validation by the main agent against the same final contract confirmed `smoke.gd` 138/138, `world_smoke.gd` 51/51 with 25,200 traversable positions, and 56 passing backend tests with no failures. Logs are in `artifacts/garden-v2/core.log`, world.log (`artifacts/garden-v2/world.log`), and backend.log (`artifacts/garden-v2/backend.log`).

## Facade and window regression

`facade_collision_smoke.gd` checks measured windows in all five PNGs, integrated pot bases, narrow edges between buildings, forward and diagonal movement, NPC routes toward old coordinates, and real clicks on all six doors. It also loads a temporary save through the real `Main` startup: position and destination are recovered without losing memories, name, or energy, or rewriting the save. Result: **82/82**, with **1,292 samples**.

With the final upper street edge at `y=160`, navigation **99/99**, environment **56/56**, seating **57/57**, portals **21/21**, world **51/51**, resident separation **56/56**, world controls **47/47**, and keyboard **26/26** were rerun. World routes preserved **25,200 legal positions** and resident-separation routes **8,114 samples**. Records are in `artifacts/facade-collision/`.

`world_occlusion_smoke.gd` passed **11/11** with the real renderer: lit surfaces stay behind the character and preserve previous brightness with a maximum difference of **1/255**. The global layer only adds soft halos. Lighting passed **14/14**, hover **35/35**, core **141/141**, and service **73/73**. The night capture in front of Alma's window (`artifacts/facade-collision/alma-window-night.png`) was inspected: feet stop at `(269,160)` and glass is not drawn over the head or hat.
