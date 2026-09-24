extends RefCounted
const Layout = preload("res://scripts/world_layout.gd")
var host: Control
var panel: Panel
var shade: ColorRect
var banner: Panel
var heading: Label
var status: Label
var progress: ProgressBar
var wake_button: Button
var was_paused := false
var sleeping_before := false
var exhausted_before := false
const EXHAUSTION_SECONDS := 8.0

func _init(owner: Control) -> void:
	host = owner

func show_choices() -> void:
	if host.colony.is_exhausted(): return
	if host.current_room != "player": return
	if is_instance_valid(panel): return
	was_paused = host.paused
	host.paused = true
	shade = host.modal_backdrop()
	panel = Panel.new()
	panel.name = "SleepChoices"
	panel.size = Vector2(304, 242)
	panel.add_theme_stylebox_override("panel", host.box(host.PAPER, host.MUTED))
	shade.add_child(panel)
	host.label_at(panel, "A descansar", Vector2(16, 12), Vector2(272, 26), 22)
	host.label_at(panel, "Cada hora de sueño dura un segundo real. Puedes despertar antes.", Vector2(16, 44), Vector2(272, 36)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var first: Button = host.button_at(panel, "Dormir 8 horas", Vector2(16, 88), Vector2(272, 30), func(): start(480))
	host.style_button(first, true)
	host.button_at(panel, "Siesta de 1 hora", Vector2(16, 124), Vector2(272, 30), func(): start(60))
	var until_morning: int = posmod(420 - host.colony.minute % 1440, 1440)
	if until_morning == 0: until_morning = 1440
	var morning: Button = host.button_at(panel, "Hasta las 7:00", Vector2(16, 160), Vector2(272, 30), func(): start(until_morning))
	morning.disabled = until_morning > 900
	morning.tooltip_text = "Disponible desde la tarde" if morning.disabled else "Dormir hasta la mañana"
	host.button_at(panel, "Volver", Vector2(16, 196), Vector2(272, 30), close)
	layout()
	first.grab_focus()
	host.refresh_status()

func close() -> void:
	if not is_instance_valid(panel): return
	shade.queue_free()
	shade = null
	panel = null
	host.paused = was_paused
	host.refresh_status()

func start(duration: int) -> bool:
	if host.colony.is_exhausted(): return false
	close()
	host.take_control()
	# Accelerated rest uses local routines; no outstanding stream can keep a pair held.
	if host.decision_pending:
		host.request.cancel_request()
		host.decision_pending = false
	if not host.dialogue_job.is_empty():
		host.dialogue_request.cancel()
		host.release_conversation()
		host.dialogue_job.clear()
	if not host.colony.start_sleep("player", duration):
		host.message(host.colony.last_error)
		return false
	host.riding_bicycle = false
	host.elapsed = 0.0
	host.gathering = 0.0
	host.paused = false
	host.message("Te acomodaste en la cama. Descansa; la colonia sigue su día.")
	refresh()
	host.refresh_status()
	return true

func wake() -> void:
	if host.colony.is_exhausted(): return
	if host.colony.wake_resident("player"):
		host.elapsed = 0.0
		sleeping_before = false
		host.message("Te despertaste. Ya puedes levantarte y seguir tu día.")
	refresh()
	host.refresh_status()

func refresh() -> void:
	var sleeping: bool = host.colony.is_sleeping("player")
	if not sleeping:
		if is_instance_valid(banner): banner.queue_free()
		banner = null
		if sleeping_before:
			host.message("Recuperaste un poco de energía. Busca tu cama para descansar." if exhausted_before else "Terminaste de descansar. Ya puedes seguir tu día.")
		sleeping_before = false
		exhausted_before = false
		return
	if not is_instance_valid(banner):
		banner = Panel.new()
		banner.name = "SleepStatus"
		banner.size = Vector2(300, 68)
		banner.add_theme_stylebox_override("panel", host.box(host.PAPER, host.MUTED))
		host.add_child(banner)
		heading = host.label_at(banner, "Durmiendo", Vector2(12, 6), Vector2(182, 20))
		status = host.label_at(banner, "", Vector2(12, 26), Vector2(180, 20))
		wake_button = host.button_at(banner, "Despertar", Vector2(198, 16), Vector2(90, 32), wake, "E o WASD también te despiertan")
		progress = ProgressBar.new()
		progress.show_percentage = false
		progress.step = 0.0
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for key in ["background", "fill"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("d2d3b7") if key == "background" else Color("73865b")
			progress.add_theme_stylebox_override(key, style)
		banner.add_child(progress)
		progress.position = Vector2(12, 54)
		progress.size = Vector2(276, 6)
	var sleep: Dictionary = host.colony.get_resident("player").sleep
	var exhausted: bool = host.colony.is_exhausted()
	heading.text = "Sin energía" if exhausted else "Durmiendo"
	wake_button.visible = not exhausted
	wake_button.disabled = exhausted
	banner.size = Vector2(216 if exhausted else 300, 68)
	progress.size.x = banner.size.x - 24
	if exhausted:
		var remaining: float = clampf(float(sleep.get("remaining", EXHAUSTION_SECONDS)), 0.0, EXHAUSTION_SECONDS)
		status.text = "Descansando · %d s" % ceili(remaining)
		progress.value = 100.0 * (1.0 - remaining / EXHAUSTION_SECONDS)
	else:
		var remaining: int = maxi(0, int(sleep.until) - host.colony.minute)
		var seconds_left: int = ceili(remaining / host.SLEEP_MINUTES_PER_SECOND)
		status.text = "%dh %02dm · %s" % [remaining / 60, remaining % 60, "Pausa" if host.paused else "%d s" % seconds_left]
		progress.value = 100.0 * (host.colony.minute - int(sleep.started)) / maxf(1.0, int(sleep.until) - int(sleep.started))
	sleeping_before = true
	exhausted_before = exhausted
	layout()

func layout() -> void:
	if is_instance_valid(shade): shade.size = host.layout_size()
	if is_instance_valid(panel): panel.position = ((host.layout_size() - panel.size) / 2.0).round()
	if is_instance_valid(banner):
		var bounds: Rect2 = host.world_view_rect
		var available: float = bounds.size.x - (286 if host.inspector.visible else 0)
		banner.position = Vector2(maxf(12, (available - banner.size.x) / 2.0), bounds.end.y - banner.size.y - 96).round()
