extends RefCounted
## Pointer feedback is local and shares the exact target used by clicks.
var host: Control
var target: Dictionary = {}
var _pointer := Vector2.ZERO
var _tracking := false
var _signature: Array = []

func _init(owner: Control) -> void:
	host = owner

func blocked() -> bool:
	return not host.controls_active or host._menu_suspended or not host.is_visible_in_tree() or host.colony.is_sleeping("player") or is_instance_valid(host.help_panel) or is_instance_valid(host.door_panel) or (is_instance_valid(host.settlement_ui) and is_instance_valid(host.settlement_ui.panel)) or is_instance_valid(host.learning.panel) or is_instance_valid(host.sleep_ui.panel)

func update(at: Vector2) -> void:
	_pointer = at
	_tracking = true
	refresh()

func refresh() -> void:
	if not _tracking: return
	if blocked() or not host.world_map_rect.has_point(_pointer) or host.point_over_interface(_pointer):
		clear()
		return
	var state: Dictionary = host.home_project_state()
	var signature: Array = [_pointer, host.current_room, state, host.world_map_rect, host.pointer_actor_signature()]
	if signature == _signature: return
	_signature = signature
	var picked: Dictionary = host.pick_world_target(host.screen_to_world(_pointer), state)
	if picked.get("kind", "") == "resident":
		var id: String = str(picked.get("resident_id", ""))
		if id == "player":
			_set_target({})
			return
		var person: Dictionary = host.colony.get_resident(id)
		picked["title"] = str(person.name)
		# A click opens the neighbor's profile; hovering never starts a chat or
		# promises availability when they are asleep or have asked for space.
		picked["action"] = "ver perfil"
	_set_target(picked)

func clear() -> void:
	_tracking = false
	_signature.clear()
	_set_target({})

func _set_target(value: Dictionary) -> void:
	if target == value: return
	target = value
	host.mouse_default_cursor_shape = Control.CURSOR_ARROW if target.is_empty() else Control.CURSOR_POINTING_HAND
	host.actors.queue_redraw()
	host.update_hint()

func hint() -> String:
	if target.is_empty() or blocked(): return ""
	var action: String = str(target.action)
	return "Clic: %s · %s" % [action.left(1).to_upper() + action.substr(1), str(target.title)]
