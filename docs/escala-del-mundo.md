# World scale

The character is the reference: its frame is 24 × 32 pixels and its visible body is about 22 pixels tall. The feet use anchor `(12, 30)`. The street and homes maintain that scale; opening an interior does not enlarge the character or stretch furniture.

Shared geometry lives in `game/data/world_layout.json`, accessed through `world_layout.gd`. It brings together doors, destinations, walkable bounds, objects, collision footprints, and stopping points for interactions. Navigation, simulation, and progression read the same source. An object's visual size and its ground footprint serve different purposes: an actor can pass behind a tree canopy but cannot walk through its trunk.

| Reference | Logical size |
| --- | --- |
| Character | Frame 24 × 32; visible body approximately 22 high |
| Doors | Openings measured per building; clearance around the base body |
| Bed | 26 × 38 |
| Table | 40 × 27 |
| Chair | 10 × 16 |
| Bicycle at home | 34 × 24 |
| Mounted bicycle | Cell 40 × 32; visible profile 34 × 21 |
| Outdoor garden bed | 24 × 22 per piece |
| Home planter | 42 × 28 |
| Served tea | Frame 8 × 10, including the visible part of the asset |

PNGs are prepared at import time. In the world, each texture pixel occupies one logical pixel; integer window scaling preserves the grid. `scenery_objects()` provides rectangles at the frame's native size. Placement spaces are retained as `slot`, so changing a planter, cup, or project does not deform the image. Floors and fences repeat pieces, cropping the last piece's edge rather than stretching them.

Opening measurements are recorded in `door_openings` as a building and a rectangle local to its PNG. They allow checks of both size relative to the character and correspondence between the drawn door and the walkable point. These are measured art annotations, not automatic door detection. The height of a whole building does not demonstrate that its opening has the right scale.

The current standing-body measurement is **10 × 22**. Openings are: Inés **15 × 27**, César **11 × 27**, Lupita **12 × 27**, Alma **14 × 24**, Mateo **11 × 24**, and player **12 × 26**. César and Mateo have close-fitting doors, with one additional pixel of total width relative to the body, not one pixel per side. All retain at least two additional pixels of height. Physical passage uses the feet; hairstyles, hands, and hats do not enlarge the collider.

## Verify a change

After updating the catalog, rebuilding the PNGs, and importing them into Godot, run from the project root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/scale_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --path game --script res://tests/scale_capture.gd
```

`scale_smoke` creates a new neighborhood without reading the save. It checks door/destination correspondence, exact routes to services and stations, actual PNG dimensions, native drawing in all 16 interior state combinations, and basic door, bed, cup, and garden-bed proportions. It measures the body using its layers' alpha, without counting the transparent canvas as visible height.

`scale_capture` needs the graphical renderer. It draws the existing assets in 500 × 330 pixel views and saves `street.png`, `player-initial.png`, `player-completed.png`, and `neighbor.png` in `artifacts/world-scale/`. It places reference avatars in front of doors, services, and furniture. It does not run a game session, providers, or image generation.

Geometric tests do not replace review of these captures. Check faces and feet, opening readability, the garden passage, tabletop surfaces, object overlap, and apparent walking space. Hats or tall hairstyles may extend beyond the body used as a reference. Different directions and styles still require visual review when their PNGs change.

## Results of this review

On September 23, 2026, `scale_smoke` passed **69/69 checks**. The four captures were produced with Godot 4.7.2 and OpenGL in native 500 × 330 views. Review covered the row of doors with avatars, the garden passage, bed and table size, tea on the table, the planter, and changes between the broken and repaired bicycle. The initial and completed home retain object sizes; César's room shows his project on a table.

These captures are scale and composition samples. They do not represent a real game session with five copies of the player inside a home, nor do they test entry animations or every appearance combination. The save was not loaded or modified, and this check used no network or art generation.
