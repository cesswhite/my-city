extends RefCounted
## Immutable content shared by state, world adapters and UI. No saved state here.
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/settlement.json"))
		if parsed is Dictionary: _data = parsed
	return _data
