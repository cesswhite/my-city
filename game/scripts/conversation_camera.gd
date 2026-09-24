extends RefCounted
## Presentation-only framing. Navigation and resident positions stay in world space.
const TRANSITION_SECONDS := 0.24
var host: Control
var offset := Vector2.ZERO
var _origin := Vector2.ZERO
var _destination := Vector2.ZERO
var _elapsed := TRANSITION_SECONDS

func _init(owner: Control) -> void:
	host = owner

func _reader_panel() -> Control:
	# HomeUI is optional while the scene is being assembled and in older hosts.
	var home = host.get("home_ui")
	if home == null or not is_instance_valid(home) or not home.has_method("is_reading") or not home.is_reading(): return null
	var panel = home.get("reading_panel")
	return panel if panel is Control and is_instance_valid(panel) and panel.is_visible_in_tree() else null

func _panel_rect(panel: Control) -> Rect2:
	# Exit is nested in the location card; do not confuse its parent-local rect
	# with viewport coordinates. Camera offsets use the host's local space.
	return host.get_global_transform().affine_inverse() * panel.get_global_rect()

func safe_rect() -> Rect2:
	var reader: Control = _reader_panel()
	var right: float = _panel_rect(reader if reader != null else host.inspector).position.x - 20.0
	var left := 20.0
	var top: float = _panel_rect(host.hud.stats_panel).end.y + 16.0
	if host.exit_button.is_visible_in_tree(): top = maxf(top, _panel_rect(host.exit_button).end.y + 12.0)
	var bottom: float = host.size.y - 16.0
	if host.hud.dock_panel.is_visible_in_tree():
		var dock: Rect2 = _panel_rect(host.hud.dock_panel)
		if dock.size.y > dock.size.x: left = maxf(left, dock.end.x + 16.0)
		else: bottom = minf(bottom, dock.position.y - 16.0)
	for panel: Control in [host.overlay.hint, host.overlay.toast]:
		if not panel.is_visible_in_tree(): continue
		var obstacle: Rect2 = _panel_rect(panel)
		# A right-aligned notice outside the framing band must not lift the world.
		if obstacle.end.x > left and obstacle.position.x < right:
			bottom = minf(bottom, obstacle.position.y - 12.0)
	return Rect2(Vector2(left, top), Vector2(maxf(100, right - left), maxf(100, bottom - top)))

func subjects() -> Array[String]:
	if _reader_panel() != null:
		var player: Dictionary = host.colony.get_resident("player")
		return ["player"] if not player.is_empty() and player.get("room", "street") == host.current_room else []
	if not host.inspector.visible: return []
	var id: String = host.chat_partner_id if not host.chat_partner_id.is_empty() else host.selected_id
	var person: Dictionary = host.colony.get_resident(id)
	if person.is_empty() or person.get("room", "street") != host.current_room: return []
	var result: Array[String] = [id]
	var player: Dictionary = host.colony.get_resident("player")
	if id != "player" and player.room == person.room and (not host.chat_partner_id.is_empty() or host.position_of(player).distance_to(host.position_of(person)) <= 64.0):
		result.append("player")
	return result

func desired_offset(base_rect: Rect2) -> Vector2:
	var bounds := Rect2()
	for id in subjects():
		var resident: Dictionary = host.colony.get_resident(id)
		var actor: Rect2 = host.pointer_actor_rect(resident, host.colony.daily_state(id))
		# Include hats, feet, and a small breathing space around the actual sprite.
		actor.position = base_rect.position + (actor.position - host.WORLD_RECT.position) * host.world_scale
		actor.size *= host.world_scale
		bounds = bounds.merge(actor) if bounds.has_area() else actor
	if not bounds.has_area(): return Vector2.ZERO
	var safe: Rect2 = safe_rect().grow(-12)
	return Vector2(_fit_axis(bounds.position.x, bounds.end.x, safe.position.x, safe.end.x), _fit_axis(bounds.position.y, bounds.end.y, safe.position.y, safe.end.y)).round()

func _fit_axis(start: float, end: float, safe_start: float, safe_end: float) -> float:
	if end - start > safe_end - safe_start: return (safe_start + safe_end - start - end) / 2.0
	# Move only as much as needed to uncover the pair, preserving the world scale.
	return clampf(0.0, safe_start - start, safe_end - end)

func advance(delta: float, base_rect: Rect2, immediate: bool = false) -> Vector2:
	var desired: Vector2 = desired_offset(base_rect)
	if desired != _destination:
		_origin = offset
		_destination = desired
		_elapsed = 0.0
	if immediate:
		offset = desired
		_elapsed = TRANSITION_SECONDS
	else:
		_elapsed = minf(TRANSITION_SECONDS, _elapsed + maxf(0.0, delta))
		var progress: float = _elapsed / TRANSITION_SECONDS
		offset = _origin.lerp(_destination, 1.0 - pow(1.0 - progress, 3.0))
	return offset.round()
