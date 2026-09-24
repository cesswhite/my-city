extends SceneTree
## Uses a private temporary directory, never the user's settings or saved colony.
const Settings = preload("res://scripts/game_settings.gd")
var checks: int = 0
var failures: Array[String] = []
var directory: String
var path: String

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func write_config(fullscreen_value: Variant, vsync_value: Variant) -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen_value)
	config.set_value("display", "vsync", vsync_value)
	return config.save(path)

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Run with -- --ui-test to isolate preferences and display changes.")
		quit(1)
		return
	directory = OS.get_cache_dir().path_join("my-city-settings-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	path = directory.path_join("settings.cfg")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not create an isolated settings fixture directory.")
		quit(1)
		return
	var display_before := {"mode": DisplayServer.window_get_mode(), "vsync": DisplayServer.window_get_vsync_mode(), "size": root.size, "position": root.position}
	var settings = Settings.new(path, false)
	expect(settings.fullscreen and settings.vsync, "first launch defaults to fullscreen with VSync")
	expect(settings.load_settings() == OK and settings.fullscreen and settings.vsync, "missing file loads defaults without an error")
	expect(not FileAccess.file_exists(path), "loading defaults does not create a config file")
	settings.set_fullscreen(false)
	settings.set_vsync(false)
	expect(not FileAccess.file_exists(path), "changing preferences is separate from saving")
	expect(settings.save_settings() == OK, "preferences save in an isolated ConfigFile")
	var restored = Settings.new(path, false)
	expect(restored.load_settings() == OK and not restored.fullscreen and not restored.vsync, "windowed choice and disabled VSync survive a restart")
	settings.set_fullscreen(true)
	settings.set_vsync(true)
	expect(settings.save_settings() == OK and restored.load_settings() == OK and restored.fullscreen and restored.vsync, "subsequent saves replace old preference values")
	for invalid_value in ["false", 0, 1.0, [], {"enabled": false}]:
		expect(write_config(invalid_value, false) == OK, "malformed preference fixture writes")
		expect(restored.load_settings() == ERR_INVALID_DATA and restored.fullscreen and not restored.vsync, "invalid fullscreen falls back while valid VSync is preserved: " + str(invalid_value))
	expect(write_config(false, "true") == OK and restored.load_settings() == ERR_INVALID_DATA and not restored.fullscreen and restored.vsync, "invalid VSync falls back without discarding a valid windowed preference")
	var incomplete := ConfigFile.new()
	incomplete.set_value("unrelated", "fullscreen", false)
	expect(incomplete.save(path) == OK and restored.load_settings() == OK and restored.fullscreen and restored.vsync, "unknown sections and absent keys leave safe defaults")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[display]\nfullscreen=false\nvsync=true\n#" + "x".repeat(Settings.MAX_CONFIG_BYTES))
	file.close()
	expect(restored.load_settings() == ERR_INVALID_DATA and restored.fullscreen and restored.vsync, "oversized files cannot apply a partial preference")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[display]\nfullscreen=not_valid_config\n")
	file.close()
	expect(restored.load_settings() != OK and restored.fullscreen and restored.vsync, "invalid ConfigFile syntax resets preferences and reports an error")
	var invalid_destination = Settings.new(directory.path_join("absent/settings.cfg"), false)
	expect(invalid_destination.save_settings() != OK, "save failure is reported to the menu")
	expect(not settings.apply(), "explicit apply=false prevents display mutations")
	var preview_settings = Settings.new(path, true)
	expect(not preview_settings.apply(), "UI-test mode prevents display changes even with apply enabled")
	var real_path_guard = Settings.new()
	expect(real_path_guard.load_settings() == OK and real_path_guard.fullscreen and real_path_guard.vsync, "UI tests never read the player's real preferences")
	expect(real_path_guard.save_settings() == ERR_UNAVAILABLE, "UI tests cannot write the player's real preferences")
	var display_after := {"mode": DisplayServer.window_get_mode(), "vsync": DisplayServer.window_get_vsync_mode(), "size": root.size, "position": root.position}
	expect(display_after == display_before, "load, setters, save and guarded apply leave the display unchanged")
	expect(Settings.windowed_rect(Rect2i(0, 0, 1920, 1080)) == Rect2i(192, 108, 1536, 864), "base window is centered within a large work area")
	expect(Settings.windowed_rect(Rect2i(-1280, 24, 1280, 696)) == Rect2i(-1280, 24, 1280, 696), "small work area and negative monitor origin are respected")
	var usable := Rect2i(20, 40, 1024, 768)
	var decorated: Rect2i = Settings.windowed_rect(usable, Vector2i(8, 30), Vector2i(4, 26))
	var outer := Rect2i(decorated.position - Vector2i(4, 26), decorated.size + Vector2i(8, 30))
	expect(outer == usable, "window decorations stay inside the usable screen area")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	expect(not DirAccess.dir_exists_absolute(directory), "temporary preferences are removed after the test")
	print("Settings smoke: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
