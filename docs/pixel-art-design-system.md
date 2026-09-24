# My City — pixel art system

Art direction, September 24, 2026. Read alongside `pixel-art-audit.md`. This review starts from the PNGs loaded by the game, their sources, and render captures, rather than the dimensions of the original illustrations.

## Identity to preserve

A neighborhood of stucco houses, clay roof tiles, warm woodwork, dark ironwork, turquoise doors, pots, and abundant vegetation. Coral café with a cream/red awning; cream duplex; Alma's lavender home and flowers; open sage workshop with a bicycle and tools; cream player home with a turquoise door; shop with a green awning. The characters, their mix-and-match appearances, and their stories remain the same.

References to farming games indicate a target level of finish and readability, not a source of sprites, palettes, or buildings to copy.

## Scale and camera

- One PNG pixel is one logical pixel. Do not use blurry images, antialiasing, mipmaps, independent X/Y scaling, or detail that only works on the large source sheet.
- The terrain module is **32 × 32**; the **4**-unit navigation module is not an art tile. Each block's logical scene occupies **468 × 244**. The base viewport is **768 × 432**; current fullscreen fitting uses a fractional factor, so art inspection must also happen at integer 1×/2× scales.
- Character: cell **24 × 32**, feet **(12,30)**, visible body **10 × 22**. Do not enlarge furniture to fill an empty cell or shrink doors to add more decoration.
- Facades: horizontal fronts, straight verticals, visible roofs and top surfaces. Elevated three-quarter orthographic projection, with no vanishing point or isometric rotation. There is no measured 3D camera: do not assign it a fictitious exact angle.
- Horizontal plane: depth compressed to approximately half the width in round tables and fountain rims. Roofs may have different slopes; all retain their front eave and vertical support.
- Current sizes in `game/data/world_layout.json`: café 100×90, duplex 96×76, Alma 68×74, workshop 110×72, player 70×70, shop 54×46; tree 42×56; fountain 61×46; bench 36×18; café table 38×23; bed 26×38; table 40×27; chair 10×16. These are canvas sizes, not alpha bounds.

## Pixel construction and materials

1. Readable silhouette, large planes, contact shadows, then texture. Every detail must survive at actual logical size.
2. Shared material palette, with short ramps for each surface. The accepted batch contains **255 opaque colors shared across 54 assets**, obtained by quantizing the whole set once without dithering. The 96-color trial was rejected because it dulled terracotta, foliage, and bunting. Dynamic tints and customizable layers remain separate. Do not quantize each sprite independently.
3. A dark outer outline one logical pixel wide, colored for the material. Avoid uniform black borders several pixels wide, accidental double lines, and halos.
4. Texture in connected clusters of 2–5 pixels. No random dithering, grain, photographic gradients, or a different color for almost every pixel. Floors and walls have lower contrast than interactive objects and characters.
5. Terracotta: deep reddish shadow, warm orange body, peach edge. Wood: reddish brown, honey-colored plane, sparse grain. Metal: charcoal blue with small cool highlights. Stone: warm gray/sand, clear joints. Leaves: deep bluish green, medium green, yellow-green tips. Glass/water: dark turquoise and restrained cream reflections.
6. Tree canopies with recognizable leaf masses and gaps; visible trunk, stable base, shaded volume at the lower right. Flowers and fruit are localized accents, not noise covering the entire canopy.
7. Doors and windows have clearly distinct frames, depth, and leaves/panes. Roof tiles form structured rows. Facades rest on a continuous base and furniture legs rest on a common plane.

## Light and states

Soft daylight from the upper left. Shadows toward the lower right; occlusion beneath eaves, seats, foliage, and furniture feet. Do not bake in nighttime glows, huge ambient shadows, or conflicting directional spotlights: Godot already simulates night, windows, streetlights, wind, smoke, and water.

Keep soil/seed/crop, broken/repaired bicycle, ready tea, and projects distinct. A visual improvement does not change costs, collisions, access, routines, inventory, saves, or progression.

## Integration contract

- Preserve IDs, canvases, and anchors. Generation uses reference sheets composed of native PNGs enlarged by integer factors. A sheet does not redefine game geometry. Measure actual crops in the response: generation may enlarge an object or cross its cell. `scripts/art-source-alignment.json` pins those rectangles to the original's SHA-256; `align-art-sources.mjs` normalizes them with Nearest and uniform scaling before import. Never crop blindly using the prompt's grid.
- Keeping the outer rectangle is not enough. Preserve doors, glass, chimneys, string/bunting, bench/stool seats, fountain rim and water, pillow/blanket, and sprout crops. If a piece moves any of these, recalibrate its consumer and check the result in the game.
- Transparent sheets: PNG RGBA and final binary alpha; no painted checkerboard or halos. Opaque terrain: repeatable modules without outer frames or high-contrast seams.
- Do not alter character layers through the scenery palette: eyes, skin, clothes, and accessories have their own contract and must remain interchangeable.
- Record source PNG, reference, prompt, model, parameters, SHA-256, and normalization. Retain the previous version for comparison and rollback. Use **GPT Images 2.5**, verifying its ID before generation, as required by `AGENTS.md`.

## Acceptance

Compare before/after at 1× and 2× in complete scenes: all six blocks, inhabited homes, construction, garden, forest, seats, and project states. Review day/night, glass crops, and hover. Geometric tests are necessary but do not replace this visual inspection. Reject pieces that gain detail on the sheet but lose their form at game scale.
