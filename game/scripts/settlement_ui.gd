extends RefCounted
## Presentation only. Offers are previews; all commitments pass through the world.
const Controls = preload("res://scripts/resident_controls.gd")
const Layout = preload("res://scripts/world_layout.gd")
const PAPER = Color("f4edda")
const INK = Color("303e37")
const MUTED = Color("535f50")
const GREEN = Color("476b50")
const ACCENT = Color("92503b")
const TABS = {"town":"Pueblo", "resources":"Recursos", "projects":"Proyectos", "jobs":"Trabajos", "orders":"Pedidos"}
const PHASES = {"travelling":"En camino", "working":"Trabajando", "returning":"Volviendo al tablón", "paused":"En pausa"}

var host: Control
var panel: Panel
var modal_shade: ColorRect
var tab := "town"
var selected_worker := "player"
var selected_task := ""
var last_message := ""
var _body: VBoxContainer
var _primary: Button
var _close_button: Button
var _job_rows: Array[Dictionary] = []

func _init(owner: Control) -> void:
	host = owner

func close() -> void:
	if is_instance_valid(modal_shade):
		modal_shade.get_parent().remove_child(modal_shade)
		modal_shade.queue_free()
	panel = null
	modal_shade = null
	_primary = null
	_job_rows.clear()

func layout() -> void:
	if not is_instance_valid(panel): return
	var extent: Vector2 = host.layout_size()
	panel.size = Vector2(minf(840, extent.x - 48), minf(480, extent.y - 40))
	panel.position = ((extent - panel.size) / 2).round()

func _box(parent: Node, horizontal := false, gap := 8) -> BoxContainer:
	var box: BoxContainer = HBoxContainer.new() if horizontal else VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _text(parent: Container, text: String, size := 16, color := INK) -> Label:
	return host.learning.flow_text(parent, text, size, color)

func _button(parent: Container, text: String, action: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.accessibility_name = text
	button.set_meta("settlement_action", action)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host.learning.style_button(button, primary)
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	parent.add_child(button)
	if primary: _primary = button
	return button

func _group(parent: Container) -> VBoxContainer:
	return host.learning.inset_group(parent)

func _scroll(parent: Container) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "SettlementContent"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.clip_contents = true
	parent.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 8)
	scroll.add_child(margin)
	return _box(margin, false, 12)

func _frame(title: String) -> void:
	close()
	host.learning.close()
	host.home_ui.close()
	host.close_door_panel()
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.10, 0.16, 0.13, 0.54)
	modal_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(modal_shade)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = Panel.new()
	panel.name = "SettlementJournal"
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var skin := Controls.surface(PAPER, Color("b6bba0"))
	skin.shadow_color = Color(0, 0, 0, 0.25)
	skin.shadow_size = 4
	skin.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", skin)
	modal_shade.add_child(panel)
	layout()
	var margin := MarginContainer.new()
	panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	var shell := _box(margin, false, 12)
	var header := _box(shell, true, 12)
	_text(header, "Diario", 20)
	var learn := _button(header, "Aprendizajes", "learning", func():
		close()
		host.learning.show_journal())
	learn.size_flags_horizontal = Control.SIZE_SHRINK_END
	learn.custom_minimum_size.x = host.ui_font.get_string_size("Aprendizajes", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 24
	_close_button = _button(header, "×", "close", close)
	_close_button.custom_minimum_size.x = 32
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close_button.tooltip_text = "Cerrar diario · Esc"
	_close_button.accessibility_name = "Cerrar diario"
	var columns := _box(shell, true, 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var navigation := _box(columns, false, 6)
	navigation.custom_minimum_size.x = 132
	navigation.size_flags_horizontal = Control.SIZE_FILL
	for id: String in TABS:
		var choice := _button(navigation, str(TABS[id]), "tab:" + id, func(): show_overview(id), false)
		choice.toggle_mode = true
		choice.set_pressed_no_signal(tab == id)
		choice.accessibility_description = "Sección seleccionada" if tab == id else "Abrir sección"
		if tab == id: Controls.style(choice, true)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	_button(navigation, "Actualizar", "refresh", _refresh_view)
	_body = _box(columns, false, 10)
	_text(_body, title, 20)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_refresh_jobs)
	panel.add_child(timer)
	timer.start()

func _finish() -> void:
	var controls: Array[Control] = []
	for child in panel.find_children("*", "Control", true, false):
		if not child.is_visible_in_tree() or child.focus_mode == Control.FOCUS_NONE: continue
		if child is BaseButton and child.disabled: continue
		controls.append(child)
	for index in range(controls.size()):
		controls[index].focus_next = controls[index].get_path_to(controls[(index + 1) % controls.size()])
		controls[index].focus_previous = controls[index].get_path_to(controls[posmod(index - 1, controls.size())])
	if is_instance_valid(_primary) and not _primary.disabled: _primary.grab_focus()
	else: _close_button.grab_focus()

func _feedback(parent: Container) -> void:
	if not last_message.is_empty(): _text(_group(parent), last_message, 16, ACCENT)

func _name(id: String) -> String:
	return "Tú" if id == "player" else str(host.colony.get_resident(id).get("name", id))

func _item(id: String) -> String:
	var resource: Dictionary = host.colony.settlement.catalog.resources.get(id, {})
	return str(resource.get("name", host.colony.progression_item_name(id)))

func _items(parent: Container, items: Dictionary, requirements := false) -> void:
	var inventory: Dictionary = host.colony.progression_state().inventory
	for id: String in items:
		var row := _box(parent, true)
		_text(row, _item(id))
		var amount := _text(row, "%d / %d" % [int(inventory.get(id, 0)), int(items[id])] if requirements else "×%d" % int(items[id]), 16, MUTED)
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount.size_flags_horizontal = Control.SIZE_SHRINK_END

func show_overview(section := "town") -> void:
	tab = section if TABS.has(section) else "town"
	selected_task = ""
	_frame(str(TABS[tab]))
	var content := _scroll(_body)
	_feedback(content)
	match tab:
		"town": _town(content)
		"resources": _resources(content)
		"projects": _projects(content)
		"jobs": _jobs(content)
		"orders": _orders(content)
	_finish()

func _town(content: Container) -> void:
	var stage: Dictionary = host.colony.settlement.stage()
	var summary := _group(content)
	_text(summary, str(stage.get("title", "Primeros vecinos")), 20)
	_text(summary, str(stage.get("next", "")), 16, MUTED)
	var names: Array[String] = []
	for person in host.colony.residents:
		if person.id != "player" and host.colony.settlement.is_present(person.id): names.append(str(person.name))
	_text(content, "En el barrio: " + ", ".join(names) + ".")
	if not host.colony.settlement.building_ready("workbench"):
		_text(content, "Empieza con 2 de madera y 2 de piedra. Recoge ramas y piedras en la calle de las casas; después prepara la mesa de trabajo.", 16, MUTED)
		_button(content, "Buscar recursos", "resources", func(): show_overview("resources"), true)
		_button(content, "Ver la mesa de trabajo", "task", func(): show_task("build:workbench")).set_meta("task_id", "build:workbench")
	else:
		_text(content, "Reúne recursos y completa proyectos para abrir caminos y recibir vecinos. Cada trabajo ocurre en el mundo.", 16, MUTED)
		_button(content, "Ver proyectos", "projects", func(): show_overview("projects"), true)
	_job(content, "player")

func _task_card(parent: Container, task: Dictionary, worker: String) -> void:
	var group := _group(parent)
	_text(group, str(task.title))
	_text(group, "%s · %d min · %d energía" % [Layout.area_title(str(task.room)) if Layout.is_outdoor(str(task.room)) else "Casa de " + _name(str(task.room)), int(task.minutes), int(task.energy)], 16, MUTED)
	if not bool(task.get("ok", true)): _text(group, str(task.get("message", "Revisa los requisitos.")), 16, ACCENT)
	var button := _button(group, "Ver trabajo", "task", func():
		selected_worker = worker
		show_task(str(task.id)))
	button.set_meta("task_id", task.id)
	button.set_meta("worker_id", worker)

func _resources(content: Container) -> void:
	var bag := _group(content)
	_text(bag, "Tus recursos", 16, GREEN)
	var inventory: Dictionary = host.colony.progression_state().inventory
	var resources: Dictionary = {}
	for id: String in host.colony.settlement.catalog.resources:
		if int(inventory.get(id, 0)) > 0: resources[id] = inventory[id]
	if resources.is_empty(): _text(bag, "Aún no tienes recursos. Puedes recoger ramas, piedras y fibra sin gastar monedas.", 16, MUTED)
	else: _items(bag, resources)
	_button(content, "Vender en la tienda", "market", show_market)
	for task: Dictionary in host.colony.settlement.tasks("player"):
		if not str(task.id).begins_with("build:"): _task_card(content, task, "player")

func _projects(content: Container) -> void:
	_text(content, "Los materiales se invierten una sola vez. Puedes interrumpir la obra sin perder lo construido.", 16, MUTED)
	var known: Array[String] = []
	for task: Dictionary in host.colony.settlement.tasks("player"):
		if str(task.id).begins_with("build:"): known.append(str(task.id).trim_prefix("build:"))
	var future: Array[String] = []
	for id: String in host.colony.settlement.catalog.projects:
		var project: Dictionary = host.colony.settlement.project_status(id)
		if id not in known and project.status != "completed": future.append(id)
		else: _project_card(content, id)
	if not future.is_empty():
		var toggle := _button(content, "Más adelante · %d proyectos" % future.size(), "future_projects", func(): pass)
		toggle.toggle_mode = true
		var later := _box(content, false, 12)
		for id: String in future: _project_card(later, id)
		later.hide()
		toggle.toggled.connect(func(visible: bool): later.visible = visible)

func _project_card(parent: Container, id: String) -> void:
	var project: Dictionary = host.colony.settlement.project_status(id)
	var group := _group(parent)
	_text(group, str(project.title))
	var completed: bool = project.status == "completed"
	_text(group, "Terminado" if completed else str(project.get("message", "Listo para construir")), 16, GREEN if completed else MUTED)
	if not completed:
		var button := _button(group, "Ver requisitos", "task", func(): show_task("build:" + id))
		button.set_meta("task_id", "build:" + id)

func _job(parent: Container, worker: String) -> void:
	var job: Dictionary = host.colony.settlement.state.jobs.get(worker, {})
	if job.is_empty(): return
	var group := _group(parent)
	var spec: Dictionary = host.colony.settlement.task_spec(str(job.task_id), worker)
	_text(group, _name(worker) + " · " + str(spec.get("title", "Trabajo en curso")))
	var status := _text(group, "", 16, MUTED)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", Controls.surface(Color("d0d7bc")))
	bar.add_theme_stylebox_override("fill", Controls.surface(GREEN))
	group.add_child(bar)
	_job_rows.append({"worker":worker, "label":status, "bar":bar})
	var button := _button(group, "Cancelar trabajo", "cancel", func():
		_result(host.colony.settlement_jobs.cancel(worker)))
	button.set_meta("worker_id", worker)
	_refresh_jobs()

func _refresh_jobs() -> void:
	for row: Dictionary in _job_rows:
		if not is_instance_valid(row.label): continue
		var job: Dictionary = host.colony.settlement.state.jobs.get(row.worker, {})
		if job.is_empty():
			row.label.text = "Trabajo terminado. Actualiza para ver los resultados."
			row.bar.value = 100
			continue
		row.label.text = "%s · %d de %d min" % [str(PHASES.get(str(job.phase), str(job.phase))), int(job.progress), int(job.required)]
		row.bar.value = 100.0 * float(job.progress) / maxf(1.0, float(job.required))

func _jobs(content: Container) -> void:
	_text(content, "Pide colaboración a quienes están en el barrio. Pueden descansar o rechazar un trabajo; revisar opciones no los compromete.", 16, MUTED)
	for person in host.colony.residents:
		if not host.colony.settlement.is_present(person.id): continue
		_job(content, str(person.id))
		var button := _button(content, "Ver mis trabajos" if person.id == "player" else "Ver trabajos para " + _name(str(person.id)), "person", func(): show_person(str(person.id)))
		button.set_meta("worker_id", person.id)

func show_person(id: String) -> void:
	if not host.colony.settlement.is_present(id):
		last_message = "Este vecino todavía no está en el barrio."
		show_overview("jobs")
		return
	tab = "jobs"
	selected_task = ""
	selected_worker = id
	_frame("Mis trabajos" if id == "player" else "Trabajos para " + _name(id))
	var content := _scroll(_body)
	_feedback(content)
	_job(content, id)
	var tasks: Array = host.colony.settlement.tasks(id)
	if tasks.is_empty(): _text(content, "No hay trabajos disponibles por ahora.", 16, MUTED)
	for task: Dictionary in tasks: _task_card(content, task, id)
	_finish()

func show_task(task_id: String) -> void:
	selected_task = task_id
	if not host.colony.settlement.is_present(selected_worker): selected_worker = "player"
	tab = "projects" if task_id.begins_with("build:") else "jobs"
	var spec: Dictionary = host.colony.settlement.task_spec(task_id, selected_worker)
	_frame(str(spec.get("title", "Trabajo no disponible")))
	var content := _scroll(_body)
	_feedback(content)
	if spec.is_empty():
		_text(content, "Este trabajo no está disponible en este momento.", 16, MUTED)
		_finish()
		return
	_text(content, "%d min de trabajo · %d energía" % [int(spec.minutes), int(spec.energy)], 16, MUTED)
	if task_id.begins_with("build:"):
		var project: Dictionary = host.colony.settlement.project_status(task_id.trim_prefix("build:"))
		var cost: Dictionary = project.get("cost", {})
		var materials := _group(content)
		_text(materials, "Requisitos", 16, GREEN)
		if host.colony.settlement.state.projects.has(project.id):
			_text(materials, "Materiales ya invertidos. El avance se conserva.", 16, GREEN)
			_text(materials, "%d de %d min completados" % [int(project.progress), int(project.minutes)], 16, MUTED)
		else:
			_text(materials, "%d / %d monedas" % [int(host.colony.progression_state().coins), int(cost.get("coins", 0))] if int(cost.get("coins", 0)) > 0 else "Sin coste de monedas", 16, MUTED)
			_items(materials, cost.get("items", {}), true)
		for required in project.get("requires", []):
			_text(materials, "Proyecto: " + str(host.colony.settlement.catalog.projects.get(required, {}).get("title", required)), 16, MUTED)
		var discovery: String = str(project.get("discovery", ""))
		if not discovery.is_empty(): _text(materials, "Exploración: " + str(host.colony.settlement.catalog.explorations.get(discovery, {}).get("title", discovery)), 16, MUTED)
		if not str(project.get("arrival", "")).is_empty(): _text(content, "Al terminar llegará " + _name(str(project.arrival)) + ".", 16, GREEN)
	else:
		if not spec.get("inputs", {}).is_empty():
			var materials := _group(content)
			_text(materials, "Necesitas", 16, GREEN)
			_items(materials, spec.inputs, true)
		if not spec.get("outputs", {}).is_empty():
			_text(content, "Al completar el trabajo", 16, GREEN)
			_items(content, spec.outputs)
	_text(content, "Quién lo hará", 16, MUTED)
	var workers := OptionButton.new()
	workers.name = "SettlementWorker"
	workers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workers.custom_minimum_size.y = 36
	workers.focus_mode = Control.FOCUS_ALL
	workers.accessibility_name = "Elegir quién hará el trabajo"
	host.learning.style_button(workers)
	for person in host.colony.residents:
		if not host.colony.settlement.is_present(person.id): continue
		workers.add_item(_name(str(person.id)))
		workers.set_item_metadata(workers.item_count - 1, str(person.id))
		if person.id == selected_worker: workers.select(workers.item_count - 1)
	workers.item_selected.connect(func(index: int):
		selected_worker = str(workers.get_item_metadata(index))
		last_message = ""
		show_task(task_id))
	content.add_child(workers)
	var offer: Dictionary = host.colony.settlement_jobs.preview(selected_worker, task_id)
	_text(content, str(offer.get("message", "")), 16, GREEN if bool(offer.get("ok", false)) else ACCENT)
	var action := _button(_body, "Hacer este trabajo" if selected_worker == "player" else "Pedir ayuda a " + _name(selected_worker), "start", func(): host.begin_settlement_task(task_id, selected_worker), true)
	action.set_meta("task_id", task_id)
	action.set_meta("worker_id", selected_worker)
	action.disabled = not bool(offer.get("ok", false))
	action.tooltip_text = str(offer.get("message", action.text))
	_finish()

func show_market() -> void:
	tab = "resources"
	selected_task = ""
	_frame("Vender recursos")
	var content := _scroll(_body)
	_feedback(content)
	_text(content, "Vende junto a la tienda. Cada recurso tiene una demanda diaria limitada.", 16, MUTED)
	var player: Dictionary = host.colony.get_resident("player")
	var shop: Dictionary = host.colony._progression.catalog.shop
	var near: bool = player.room == shop.room and Layout.point(player.pos).distance_to(Layout.point(shop.pos)) <= float(shop.radius)
	if not near: _button(content, "Ir a la tienda", "shop", func():
		close()
		host.walk_to_shop(), true)
	for item: Dictionary in host.colony.settlement.market():
		var row := _group(content)
		_text(row, str(item.name))
		_text(row, "%d en mochila · %d monedas · aceptan %d más hoy" % [int(item.owned), int(item.price), int(item.remaining)], 16, MUTED)
		var sell := _button(row, "Vender 1", "sell", func():
			_result(host.colony.settlement.sell(str(item.id), 1), true))
		sell.set_meta("item_id", item.id)
		sell.disabled = not near or int(item.owned) <= 0 or int(item.remaining) <= 0
	_finish()

func _orders(content: Container) -> void:
	_text(content, "Entrega junto a quien lo pidió. Las monedas llegan sólo después de la entrega.", 16, MUTED)
	var orders: Array = host.colony.settlement.orders()
	if orders.is_empty(): _text(content, "No hay pedidos disponibles por ahora.", 16, MUTED)
	for order: Dictionary in orders:
		var group := _group(content)
		_text(group, str(order.title))
		_text(group, _name(str(order.requester)) + " · %d monedas" % int(order.coins), 16, GREEN)
		_items(group, order.items, true)
		_text(group, str(order.get("message", "")), 16, MUTED)
		var near: bool = host.colony._distance(host.colony.get_resident("player"), host.colony.get_resident(str(order.requester))) < host.colony.MAX_DISTANCE
		if not near:
			_button(group, "Ir con " + _name(str(order.requester)), "requester", func():
				close()
				host.walk_to_mentor(str(order.requester)))
		else:
			var deliver := _button(group, "Entregar pedido", "deliver", func(): _result(host.colony.settlement.deliver_order(str(order.id))))
			deliver.set_meta("order_id", order.id)
			deliver.disabled = not bool(order.get("ok", false))

func _result(result: Dictionary, market := false) -> void:
	last_message = str(result.get("message", "No se pudo completar esa acción."))
	host.message(last_message)
	if market: show_market()
	else: _refresh_view()

func _refresh_view() -> void:
	if not selected_task.is_empty(): show_task(selected_task)
	else: show_overview(tab)
