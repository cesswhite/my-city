# Environment and day cycle

The neighborhood retains its positions and physical rules while water, plants, and bunting move subtly. `ambient_environment.gd` reuses existing PNGs: water moves continuously, and gusts last five seconds in a 22-second cycle. Foliage shifts by at most one pixel; roots, pots, and supports stay fixed. Smoke and dust are drawn at runtime, with at most 12 small outdoor particles. These effects neither generate art files nor query AI.

Animation pauses with the game and menu. Image regions are prepared and cached, not reread for each vegetation movement. Visual displacement does not alter collision footprints or click actions.

## Lighting follows the game clock

`world_lighting.gd` uses the saved neighborhood time, visually interpolating between five-minute intervals:

| Period | Game time |
| --- | --- |
| Gradual dawn | 06:30–08:00 |
| Day | 08:00–17:30 |
| Gradual dusk | 17:30–20:00 |
| Night | 20:00–06:30 |

Streetlights and windows gradually illuminate as darkness falls. Interiors retain more ambient light and have wall lamps. Lit glass and light emitters belong to their object's depth ordering: a character walking in front correctly occludes them. Soft halos and projected light render after people and before world text. Only scenery, characters, and atmosphere are tinted; HUD and reading panels retain their colors.

Each façade's panes are measured separately to preserve mullions, frames, and window boxes. Wall sconces reuse the streetlight PNG's head. Luminous surfaces render with their object; only halos use the global additive layer. Source colors are cached and compensated for ambient light, preserving brightness without drawing glass over characters. Indoor glass darkens at night while retaining curtains. The complete-cycle review is in the local `artifacts/living-neighborhood/` directory, with day, dusk, night, dawn, and home captures.

Pausing freezes both animation and visual time. Sleeping uses the same accelerated game clock. Lighting does not use system time or a real weather forecast.

## Home layouts

`world_layout.json` retains an interior base and per-resident variants. `WorldLayout.section(room)` combines them; drawing, interactive objects, inspection positions, and practice positions all use that result. Objects resting on furniture are anchored to their supports.

Navigation caches a grid and collisions **per home**. Previously a shared interior grid could allow walking through furniture moved in another home. Routes now account for the room's specific layout. Beds, entrances, exits, and stations remain connected, and reconciliation of old positions remains limited to save loading.

## Recorded validation

These are historical results for the recorded final layout, not checks automatically rerun by reading this document. Scene tests use `--ui-test`; they do not read personal saves or call providers. Captures and logs under `artifacts/` are local development evidence, excluded from the repository.

| Suite | Checks |
| --- | --- |
| `navigation_smoke.gd` | 99/99 |
| `world_interactions_smoke.gd` | 147/147 |
| `world_smoke.gd` | 51/51 |
| `learning_world_smoke.gd` | 31/31 |
| `sleep_ui_smoke.gd` | 29/29 |
| `sleep_timing_smoke.gd` | 58/58 |
| `controls_world_smoke.gd` | 47/47 |
| `hover_ui_smoke.gd` | 35/35 |
| `lighting_smoke.gd` | 14/14 |

**511/511** checks. World and learning suites each sampled 25,200 positions, all walkable. The bicycle chain retained purchasing, delivery, learning, physical repair, and leaving home; sleep retained its real bed and one-game-hour-per-real-second timing.

Older fixtures sending world coordinates directly to the viewport now use `world_to_screen()`. Movement expectations reflect player speed of 48 px/s and resident speed of 30 px/s. Interaction positions come from `WorldLayout`, without maintaining a second layout in the tests.

Logs for that validation are in local `artifacts/living-environment/`. Composition and lighting appearance also require visual review; these tests validate coherence and behavior, not appearance on their own.

The ambient module additionally passed `ambient_environment_smoke.gd` **21/21**. Renderer execution recorded **23/23**, including two exports, in local `artifacts/ambient-environment/renderer.log`. The `gust.png` and `gust-next.png` frames in that directory were reviewed: measured canopy regions move together without fragmented leaves while trunks and roots stay still.

The integration also passed `smoke.gd` **141/141** and backend **73/73** at that revision. After glass and sconce adjustments, lighting passed **14/14** again, and seven full-scene captures completed without runtime errors. Logs are in local `artifacts/living-neighborhood/`.

Interior-specific validation recorded `interior_layout_smoke.gd` **62/62** and `scale_smoke.gd` **69/69**. The six-home composition in local `artifacts/interiors/all-homes.png` was reviewed for supported furniture and clear entrances. After the final Inés table/chair adjustment, navigation, object selection, and world traversal were rerun: **99/99**, **147/147**, and **51/51**, respectively.
