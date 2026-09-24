# Bicycle and movement

The repaired bicycle travels at **120 world pixels per second** at 1× world speed, versus **48 px/s** on foot: **2.5 times faster**. Neighbors retain their 30 px/s. Keyboard movement and route destinations use the same canonical `BICYCLE_SPEED` value in `main.gd`. Dismounting or entering a house restores walking speed; verified repair remains mandatory.

The speed change preserves existing physical safeguards. Keyboard movement caps a frame at 0.1 seconds, and `CrowdMotion.manual_step` divides movement into steps of at most one pixel. Each step checks navigation and spacing between residents. `move_resident` performs the same sweep along routes, including larger deltas from accelerating the clock. The player cannot pass through or push a stationary neighbor. Slow frames do not require jumping directly to the destination.

On September 23, 2026, these isolated tests ran without loading or writing the user's save or calling providers:

| Test | Result | Coverage |
| --- | --- | --- |
| `bicycle_motion_smoke.gd` | 27/27; 1,476 sweeps | 120 px/s by keyboard and route at 30/60/120 FPS, variable deltas, diagonals, frame spikes, pause, home, facades, fountain, garden edge, and neighbors |
| `controls_world_smoke.gd` | 47/47 | Actual keyboard input, manual control, focus, pause, and autonomy |
| `keyboard_navigation_smoke.gd` | 26/26 | Manual navigation, obstacles, and corners |
| `learning_world_smoke.gd` | 31/31; 25,200 walkable positions | Purchase, delivery, physical repair, mounting at 120 px/s, and returning to 48 px/s |
| `smoke.gd` | 141/141 | State, memory, persistence, and engine contracts |
| `bicycle_visual_smoke.gd` | 66/66 headless; 71/71 with OpenGL | Four views, sixteen phases, customization, native regions, clicks near the bicycle, stationary pose, and bounded cache |
| `sprite_smoke.gd` | 51/51 | Atlas, resources, customization, and scene composition |
| `hover_ui_smoke.gd` / `hud_smoke.gd` | 35/35 and 96/96 | Selection and interface over the world |
| Backend | 79/79; type checking passed | Service contracts, with no provider calls |

The learning test was adjusted to existing physical separation between residents: reaching a mentor means being within conversation distance without overlapping bodies. Its speed sample waits for grid alignment to finish and ends on clear ground; the previous destination ended inside a garden bed.

Historical logs: `artifacts/bicycle-motion/motion.log`, `artifacts/bicycle-motion/controls_world_smoke.log`, `artifacts/bicycle-motion/keyboard_navigation_smoke.log`, `artifacts/bicycle-motion/learning_world_smoke.log`, and `artifacts/bicycle-motion/smoke.log`. Validation artifacts are local and excluded from Git.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/bicycle_motion_smoke.gd -- --ui-test
```

The mounted bicycle now uses a **16-frame** PNG atlas: four pedaling phases in four directions—front, left, right, and back. The left view has its own row. Each cell is 40 × 32 pixels with a shared anchor at (20, 30); it is drawn at native scale with nearest filtering. The frame's visible side-view size is 34 × 21 pixels.

The rider retains their appearance layers. Head and accessories keep their original pixels; arms and legs are composed from existing sprite regions to hold the handlebar and pedal. Each direction has its own saddle, handlebar, and axle points in `world_layout.json`. When stopped, the bicycle retains its orientation and stops pedaling. Selection bounds include both the bicycle and this pose.

The image was generated through the official CLI with **`gpt-image-2.5-sunburst-2026-09-08`**, verified in the catalog and explicitly requested, as a transparent PNG. The CLI accepted generation but does not retain the model field in the response. The [prompt](../output/imagegen/bicycle-directions-prompt.txt), [source](../output/imagegen/bicycle-directions-source.png), [provenance and hashes](../output/imagegen/bicycle-directions-provenance.json), and [game atlas](../game/assets/sprites/bicycle_riding.png) are retained. No model substitution occurred.

The importer `scripts/import-bicycle-sprites.mjs` crops cells using measured margins per direction, downsamples with nearest-neighbor, and normalizes alpha. Running it again reproduces the atlas without new AI calls. The repaired bicycle shown inside the house still uses its object sprite.

Opaque bounds for each direction are calculated during import. Transparent cell margins do not occupy selectable ground, and the game does not read textures every frame to calculate them. Arm and leg poses are reused in a bounded cache.

Reviewed Godot captures: four directions and sixteen phases at 4× (`artifacts/bicycle/bicycle-directions.png`) and the left-facing bicycle in town (`artifacts/bicycle/world-left.png`). The side-view torso lean brings the shoulders toward the handlebar without deforming the head or accessories.
