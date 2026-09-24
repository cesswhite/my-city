extends RefCounted
## Stable identities and authored work preferences, independent of saved presence.
static var _residents: Dictionary = {}

static func data() -> Dictionary:
	if _residents.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
		if parsed is Array:
			for resident: Dictionary in parsed: _residents[str(resident.id)] = resident
	return _residents

static func ids() -> Array:
	return data().keys()

static func work_profile(id: String) -> Dictionary:
	return data().get(id, {}).get("work_profile", {}).duplicate(true)

static func merge_work_profile(resident: Dictionary) -> void:
	# Authored capabilities are not learned achievements or editable save authority.
	resident["work_profile"] = work_profile(str(resident.get("id", "")))
