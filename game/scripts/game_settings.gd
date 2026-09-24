extends RefCounted
## Display preferences are separate from colony progress. Loading never applies them.

const DEFAULT_PATH := "user://settings.cfg"
const BASE_WINDOW_SIZE := Vector2i(1536, 864)
const MAX_CONFIG_BYTES := 8192

var fullscreen: bool = true
var vsync: bool = true
var _path: String
var _apply_display: bool
var _last_applied_fullscreen: Variant = null

func _init(path: String = DEFAULT_PATH, apply_display: bool = true) -> void:
	_path = path
	_apply_display = apply_display

func _isolated_run() -> bool:
	return DisplayServer.get_name() == "headless" or "--ui-test" in OS.get_cmdline_user_args()

func load_settings() -> Error:
	fullscreen = true
	vsync = true
	# Preview/test scenes must not read the player's actual preferences.
	if _path == DEFAULT_PATH and _isolated_run(): return OK
	if not FileAccess.file_exists(_path): return OK
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null: return FileAccess.get_open_error()
	var too_large := file.get_length() > MAX_CONFIG_BYTES
	file.close()
	if too_large: return ERR_INVALID_DATA
	var config := ConfigFile.new()
	var error: Error = config.load(_path)
	if error != OK: return error
	var stored_fullscreen: Variant = config.get_value("display", "fullscreen", true)
	var stored_vsync: Variant = config.get_value("display", "vsync", true)
	# Do not coerce "false", integers, arrays, or null into a preference.
	if typeof(stored_fullscreen) == TYPE_BOOL: fullscreen = stored_fullscreen
	if typeof(stored_vsync) == TYPE_BOOL: vsync = stored_vsync
	return OK if typeof(stored_fullscreen) == TYPE_BOOL and typeof(stored_vsync) == TYPE_BOOL else ERR_INVALID_DATA

func save_settings() -> Error:
	if _path == DEFAULT_PATH and _isolated_run(): return ERR_UNAVAILABLE
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync", vsync)
	return config.save(_path)

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled

func set_vsync(enabled: bool) -> void:
	vsync = enabled

static func windowed_rect(usable: Rect2i, decorations: Vector2i = Vector2i.ZERO, client_offset: Vector2i = Vector2i.ZERO) -> Rect2i:
	var available := Vector2i(maxi(1, usable.size.x - maxi(0, decorations.x)), maxi(1, usable.size.y - maxi(0, decorations.y)))
	var client_size := Vector2i(mini(BASE_WINDOW_SIZE.x, available.x), mini(BASE_WINDOW_SIZE.y, available.y))
	var outer_size := client_size + Vector2i(maxi(0, decorations.x), maxi(0, decorations.y))
	var centered := usable.position + Vector2i(maxi(0, (usable.size.x - outer_size.x) / 2), maxi(0, (usable.size.y - outer_size.y) / 2))
	return Rect2i(centered + client_offset, client_size)

func apply() -> bool:
	# No DisplayServer mutations in a test, even if an explicit config path is used.
	if not _apply_display or _isolated_run(): return false
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if _last_applied_fullscreen != fullscreen or DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
		if not fullscreen:
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			if usable.size.x <= 0 or usable.size.y <= 0:
				usable = Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
			var decorations := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
			var client_offset := DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()
			var rect := windowed_rect(usable, decorations, client_offset)
			DisplayServer.window_set_size(rect.size)
			DisplayServer.window_set_position(rect.position)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	_last_applied_fullscreen = fullscreen
	return true
