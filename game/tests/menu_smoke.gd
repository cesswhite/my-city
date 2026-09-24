extends SceneTree
const Shell = preload("res://scenes/shell.tscn")
const Store = preload("res://scripts/session_store.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Colony = preload("res://scripts/colony.gd")
var checks := 0
var failures := 0
var path := "user://menu_test_%d.json" % OS.get_process_id()
var settings_path := "user://menu_settings_test_%d.cfg" % OS.get_process_id()
var archives: Array[String] = []

func _init() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	for frame in range(4): await process_frame

func capture(environment_key: String) -> void:
	if not "--capture-menu" in OS.get_cmdline_user_args(): return
	var capture_path := OS.get_environment(environment_key)
	if capture_path.is_empty(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_path)

func discard_game(shell: Control) -> void:
	if is_instance_valid(shell.game):
		shell.remove_child(shell.game)
		shell.game.queue_free()
		shell.game = null

func run() -> void:
	root.size = Vector2i(1536, 864)
	var shell = Shell.instantiate()
	shell.test_mode = true
	shell.store = Store.new(path)
	shell.settings = Settings.new(settings_path, false)
	root.add_child(shell)
	await settle()
	expect(shell.game == null and shell.menu.visible and shell.current_page == "home", "startup shows the title without creating or ticking a colony")
	expect(not FileAccess.file_exists(path), "viewing the menu does not create a save")
	expect(shell.primary_button.text == "Iniciar partida", "a first visit has a clear start action")
	expect(shell.menu.mouse_filter == Control.MOUSE_FILTER_STOP, "the full-screen menu intercepts clicks outside its card")
	var surface: StyleBoxFlat = shell.panel.get_theme_stylebox("panel")
	expect(surface.bg_color.a < 1.0 and surface.shadow_size > 0 and surface.get_border_width(SIDE_LEFT) == 0, "the menu uses a translucent surface and shadow without a heavy border")
	for resolution in [Vector2i(768, 432), Vector2i(1536, 864), Vector2i(1536, 960), Vector2i(2048, 864), Vector2i(1152, 864)]:
		root.size = resolution
		for page in ["home", "settings", "controls", "new"]:
			shell.show_page(page)
			await settle()
			var bounds: Rect2 = shell.get_viewport_rect()
			expect(bounds.encloses(shell.panel.get_global_rect()), "menu page fits viewport %s: %s" % [resolution, page])
			expect(shell.panel.size.x <= 336 and shell.primary_button.size.y >= 40 and shell.primary_button.has_focus(), "compact card preserves a full-size focused action %s: %s" % [resolution, page])
	root.size = Vector2i(768, 432)
	shell.show_page("settings")
	shell._set_status("No se pudo guardar el ajuste. Revisa que la carpeta siga disponible. ".repeat(12))
	await settle()
	var scroll_bar: VScrollBar = shell.card_scroll.get_v_scroll_bar()
	expect(shell.get_viewport_rect().encloses(shell.panel.get_global_rect()) and scroll_bar.visible and scroll_bar.size.x >= 6, "an unusually long settings error scrolls within the minimum viewport")
	scroll_bar.value = scroll_bar.max_value
	await settle()
	expect(shell.card_scroll.get_global_rect().end.y >= shell.status_label.get_global_rect().end.y, "scrolling reaches the complete error without clipping away its end")
	expect(shell.card_scroll.follow_focus, "keyboard focus scrolls menu actions into view")
	shell.status_text = ""
	root.size = Vector2i(1536, 864)
	shell.show_page("home")
	await capture("MY_CITY_MENU_CAPTURE")
	shell.request_new_game()
	await settle()
	expect(is_instance_valid(shell.game) and not shell.menu.visible and FileAccess.file_exists(path), "start creates a valid isolated save and enters gameplay")
	expect(not shell.game.inspector.visible and not shell.game.can_edit_appearance("player"), "a new story opens the world; customization is available at the home closet")
	shell.game.paused = true
	shell.game.colony.get_resident("player").name = "Ana de prueba"
	shell.game.chat_drafts.mateo = "Un mensaje pendiente"
	var instance: int = shell.game.get_instance_id()
	shell.open_pause_menu()
	var minute: int = shell.game.colony.minute
	await settle()
	expect(shell.menu.visible and shell.current_page == "pause" and shell.game.visible and not shell.game.is_processing() and not shell.game.is_processing_input(), "pause menu shows the frozen game with processing and input suspended")
	expect(not shell.landscape.visible and shell.game._menu_suspended, "pause backdrop is the current world, not the title landscape")
	expect(shell.game.colony.minute == minute, "time does not advance while browsing the menu")
	await capture("MY_CITY_PAUSE_CAPTURE")
	shell.open_subpage("settings")
	await settle()
	expect(shell.game.visible and not shell.landscape.visible and not shell.game.is_processing(), "settings opened from pause keep the same frozen world")
	await capture("MY_CITY_SETTINGS_CAPTURE")
	shell.back()
	await settle()
	expect(shell.current_page == "pause" and shell.game.visible, "returning from pause settings preserves the backdrop")
	shell.save_current()
	var saved = Colony.new()
	saved.save_path = path
	saved.setup(false, true)
	expect(saved.load_game() and saved.get_resident("player").name == "Ana de prueba", "save menu persists the current session")
	shell.return_home()
	expect(shell.current_page == "home" and shell.primary_button.text == "Continuar partida", "return to title exposes Continue for the current story")
	expect(not shell.game.visible and shell.landscape.visible and not shell.game.is_processing(), "title uses its landscape while keeping the saved session suspended")
	shell.continue_game()
	expect(shell.game.get_instance_id() == instance and shell.game.visible and not shell.menu.visible, "Continue resumes the same in-memory instance")
	expect(shell.game.paused and shell.game.chat_drafts.mateo == "Un mensaje pendiente", "resume preserves previous pause and unsent draft")
	shell.open_pause_menu()
	shell.return_home()
	var before := FileAccess.get_file_as_string(path)
	shell.request_new_game()
	expect(shell.current_page == "new" and shell.game.get_instance_id() == instance and FileAccess.get_file_as_string(path) == before, "requesting a replacement only opens confirmation")
	shell.back()
	expect(shell.current_page == "home" and shell.game.get_instance_id() == instance, "cancel preserves the live game and title")
	shell.request_new_game()
	shell.confirm_new_game()
	archives.append(shell.store.last_archive)
	await settle()
	var archived = Colony.new()
	archived.save_path = shell.store.last_archive
	archived.setup(false, true)
	expect(archived.load_game() and archived.get_resident("player").name == "Ana de prueba", "confirmed replacement retains a separately loadable archive of the previous story")
	expect(shell.game.get_instance_id() != instance and shell.game.colony.get_resident("player").name == "Tú", "confirmed new game creates a fresh character")
	shell.game.colony.get_resident("player").name = "Nombre guardado"
	shell.open_pause_menu()
	shell.save_current()
	discard_game(shell)
	shell.show_page("home")
	shell.continue_game()
	await settle()
	expect(shell.game.colony.get_resident("player").name == "Nombre guardado", "Continue after a fresh load restores the saved player")
	shell.open_pause_menu()
	shell.game.colony.save_path = path + ".missing/colony.json"
	shell.return_home()
	expect(shell.current_page == "pause" and is_instance_valid(shell.game) and shell.status_text.contains("No se pudo guardar"), "failed save keeps the session open with an actionable message")
	shell.game.colony.save_path = path
	discard_game(shell)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{damaged save")
	file.close()
	shell.show_page("home")
	shell.continue_game()
	expect(shell.game == null and shell.menu.visible and FileAccess.get_file_as_string(path) == "{damaged save", "a damaged Continue never launches a default colony or overwrites the original")
	shell.request_new_game()
	shell.confirm_new_game()
	archives.append(shell.store.last_archive)
	expect(FileAccess.get_file_as_string(shell.store.last_archive) == "{damaged save" and shell.store.validate_save(), "explicit restart archives even a damaged original byte for byte")
	shell.open_pause_menu()
	shell.open_subpage("settings")
	var fullscreen_before: bool = shell.settings.fullscreen
	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	f11.pressed = true
	shell._input(f11)
	expect(shell.settings.fullscreen != fullscreen_before and shell.window_option.selected == 1, "F11 changes the selected preference and visible mode together")
	var reloaded = Settings.new(settings_path, false)
	expect(reloaded.load_settings() == OK and reloaded.fullscreen == shell.settings.fullscreen, "display choice survives restarting the settings controller")
	f11.echo = true
	shell._input(f11)
	expect(shell.settings.fullscreen == reloaded.fullscreen, "holding F11 does not oscillate the mode")
	shell.free()
	await process_frame
	for cleanup in [path, path + ".bak", path + ".tmp", settings_path, settings_path + ".tmp"] + archives:
		if not str(cleanup).is_empty() and FileAccess.file_exists(cleanup): DirAccess.remove_absolute(ProjectSettings.globalize_path(cleanup))
	print("MENU: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
