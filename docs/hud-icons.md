# HUD icons

The source sheet was generated on September 23, 2026, with the installed official Imagegen CLI, `scripts/image_gen.py`, explicitly selecting **`gpt-image-2.5-sunburst-2026-09-08`**. The API catalog confirmed that identifier with HTTP 200, and generation completed successfully in 39.1 seconds. There was no model change or fallback.

The CLI does not retain the response's model field. Provenance therefore records `model_requested`, the catalog check, and accepted generation, but leaves `model_response: null`; the model is not inferred from pixels.

- RGBA PNG source: [hud-icons-source.png](../output/imagegen/hud-icons-source.png), 1024×1024, 4×4 cells.
- Exact prompt: [hud-icons-prompt.txt](../output/imagegen/hud-icons-prompt.txt).
- Parameters, checks, hashes, and regions: [hud-icons-provenance.json](../output/imagegen/hud-icons-provenance.json).
- CLI log: [hud-icons-generation.log](../output/imagegen/hud-icons-generation.log).
- Game atlas: [hud_icons.png](../game/assets/sprites/hud_icons.png), 64×64, 16 native 16×16 icons.
- Visual comparison on light and dark backgrounds: [hud-icons-preview.png](../output/imagegen/hud-icons-preview.png).

Import reproduces the generated silhouettes; it does not draw alternative symbols. It crops each cell by alpha, downsamples with nearest-neighbor, centers it within a maximum 14×14 area, and limits the palette to green ink, ivory, and a sage, terracotta, or gold accent. Final alpha is binary, and each icon retains at least one transparent pixel at its edges. The clock occupies 13×13 so its central hand falls on a sampling column and does not disappear when reduced. The book retains its sage accent to stand out against dark buttons.

Deterministic reimport without API calls:

```sh
python output/imagegen/hud-icons-import.py
```

Requires Pillow. The script writes only the atlas, comparison, and provenance hashes/regions. It does not modify the generated source.

## Usage in Godot

```gdscript
const HUDIcons = preload("res://scripts/hud_icons.gd")
button.icon = HUDIcons.texture("pause")
button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
```

`texture(id)` returns a cached 16×16 `AtlasTexture`. An unknown ID or missing sheet returns `null`. The loader supports imported/exported resources and local PNGs before import, without scaling or writing files.

| Row | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- |
| 1 | `pause` | `play` | `eye` | `hand` |
| 2 | `save` | `menu` | `person` | `journal` |
| 3 | `home` | `bicycle` | `spark` | `clock` |
| 4 | `energy` | `coin` | `seed` | `people` |

`eye`/`hand` indicate autonomous observation and manual control; `spark` indicates AI, `clock` history, and `seed` learning. Explanations, tooltips, and accessible states belong to the interface and are not baked into the icons.
