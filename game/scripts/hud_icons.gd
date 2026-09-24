extends RefCounted
## Generated HUD glyphs, cached as native 16×16 atlas regions.

const PATH := "res://assets/sprites/hud_icons.png"
const IDS: Array[String] = ["pause", "play", "eye", "hand", "save", "menu", "person", "journal", "home", "bicycle", "spark", "clock", "energy", "coin", "seed", "people"]
static var _sheet: Texture2D
static var _icons: Dictionary = {}

static func texture(id: String) -> Texture2D:
	var index: int = IDS.find(id)
	if index < 0: return null
	if _icons.has(id): return _icons[id]
	if _sheet == null:
		var has_original: bool = FileAccess.file_exists(PATH)
		if ResourceLoader.exists(PATH, "Texture2D") and (FileAccess.file_exists(PATH + ".import") or ResourceLoader.has_cached(PATH) or not has_original):
			_sheet = ResourceLoader.load(PATH, "Texture2D") as Texture2D
		elif has_original:
			var image := Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(PATH)) == OK:
				_sheet = ImageTexture.create_from_image(image)
		if _sheet == null or _sheet.get_size() != Vector2(64, 64):
			_sheet = null
			return null
	var icon := AtlasTexture.new()
	icon.atlas = _sheet
	icon.region = Rect2((index % 4) * 16, (index / 4) * 16, 16, 16)
	icon.filter_clip = true
	_icons[id] = icon
	return icon
