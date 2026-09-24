extends RefCounted
## Save operations used by the title screen. Never replace a save without a durable archive.
const Colony = preload("res://scripts/colony.gd")
var save_path: String
var last_error := ""
var last_archive := ""

func _init(path: String = "user://colony.json") -> void:
	save_path = path

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func validate_save() -> bool:
	var candidate = Colony.new()
	candidate.save_path = save_path
	candidate.setup(false)
	var valid: bool = candidate.load_game()
	last_error = candidate.last_error
	return valid

func new_game() -> bool:
	last_error = ""
	last_archive = ""
	var suffix := "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var staging := save_path + ".new-" + suffix
	var candidate = Colony.new()
	candidate.setup(false)
	candidate.save_path = staging
	if not candidate.save_game():
		last_error = "No se pudo preparar la nueva partida. " + candidate.last_error
		return false
	if has_save():
		last_archive = save_path + ".archive-" + suffix
		var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(last_archive))
		if copied != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(staging))
			last_archive = ""
			last_error = "No se pudo respaldar la partida anterior. Puedes seguir con ella."
			return false
	var replaced := DirAccess.rename_absolute(ProjectSettings.globalize_path(staging), ProjectSettings.globalize_path(save_path))
	if replaced != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staging))
		last_error = "No se pudo iniciar la nueva partida. La anterior sigue conservada."
		return false
	return true
