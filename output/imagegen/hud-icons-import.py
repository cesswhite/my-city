"""Normalize the generated sheet; never draw or substitute an icon silhouette."""
from hashlib import sha256
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "output/imagegen/hud-icons-source.png"
DESTINATION = ROOT / "game/assets/sprites/hud_icons.png"
IDS = ["pause", "play", "eye", "hand", "save", "menu", "person", "journal", "home", "bicycle", "spark", "clock", "energy", "coin", "seed", "people"]
PALETTE = {"ink": (48, 62, 55), "ivory": (244, 237, 218), "terracotta": (185, 104, 79), "gold": (213, 171, 89), "sage": (108, 142, 113)}
ACCENTS = ["sage", "terracotta", "sage", "gold", "terracotta", "sage", "terracotta", "sage", "terracotta", "sage", "gold", "gold", "gold", "gold", "sage", "terracotta"]

source = Image.open(SOURCE).convert("RGBA")
if source.size != (1024, 1024):
    raise ValueError("Expected the requested 1024×1024 four-by-four source sheet")
if source.getchannel("A").getextrema()[0] == 255:
    raise ValueError("The generated source is opaque; inspect its background before extraction")
atlas = Image.new("RGBA", (64, 64))
metadata = []
for index, name in enumerate(IDS):
    x, y = index % 4 * 256, index // 4 * 256
    cell = source.crop((x, y, x + 256, y + 256))
    cell.putalpha(cell.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0))
    box = cell.getbbox()
    if box is None:
        raise ValueError(f"Missing generated icon: {name}")
    cutout = cell.crop(box)
    # The clock's central hand needs an odd native grid to retain its source pixels.
    limit = 13 if name == "clock" else 14
    factor = min(limit / cutout.width, limit / cutout.height)
    logical_size = (max(1, round(cutout.width * factor)), max(1, round(cutout.height * factor)))
    native = cutout.resize(logical_size, Image.Resampling.NEAREST)
    colors = [PALETTE["ink"], PALETTE["ivory"], PALETTE[ACCENTS[index]]]
    normalized = []
    for red, green, blue, alpha in native.get_flattened_data():
        if not alpha:
            normalized.append((0, 0, 0, 0))
        else:
            nearest = min(colors, key=lambda color: sum((a - b) ** 2 for a, b in zip(color, (red, green, blue))))
            normalized.append((*nearest, 255))
    native.putdata(normalized)
    at = (index % 4 * 16 + (16 - native.width) // 2, index // 4 * 16 + (16 - native.height) // 2)
    atlas.alpha_composite(native, at)
    metadata.append({"id": name, "source_cell": [x, y, 256, 256], "alpha_crop": list(box), "native_visible_size": list(logical_size), "accent": ACCENTS[index]})

DESTINATION.parent.mkdir(parents=True, exist_ok=True)
atlas.save(DESTINATION)
preview = Image.new("RGBA", (64 * 8 * 2 + 16, 64 * 8), (*PALETTE["ivory"], 255))
preview.paste((*PALETTE["ink"], 255), (64 * 8 + 16, 0, preview.width, preview.height))
large = atlas.resize((512, 512), Image.Resampling.NEAREST)
preview.alpha_composite(large, (0, 0))
preview.alpha_composite(large, (528, 0))
preview.save(ROOT / "output/imagegen/hud-icons-preview.png")
provenance_path = ROOT / "output/imagegen/hud-icons-provenance.json"
provenance = json.loads(provenance_path.read_text())
provenance.update({"source_sha256": sha256(SOURCE.read_bytes()).hexdigest(), "atlas_sha256": sha256(DESTINATION.read_bytes()).hexdigest(), "prompt_sha256": sha256((ROOT / "output/imagegen/hud-icons-prompt.txt").read_bytes()).hexdigest(), "import": {"script": "output/imagegen/hud-icons-import.py", "output": "game/assets/sprites/hud_icons.png", "size": [64, 64], "native_icon": [16, 16], "processing": "Per-cell alpha crop, nearest-neighbor fit within14×14, binary alpha, three-color quantization; generated silhouettes only.", "icons": metadata}})
provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")
print("Imported sixteen generated icons into a64×64 RGBA atlas.")
