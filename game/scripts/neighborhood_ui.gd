extends RefCounted
## Presentation of the registered neighborhood graph; never changes simulation coordinates.
const Layout = preload("res://scripts/world_layout.gd")
const PAPER := Color("f4edda")
const INK := Color("303e37")
var host: Control
var veil: ColorRect
var transition: Tween

class MapGraph extends Control:
	var room: String
	var font: Font
	var home_names: Dictionary = {}
	var open_areas: Array = []
	func _draw() -> void:
		var ids: Array = Layout.outdoor_ids()
		var minimum := Vector2(100,100)
		var maximum := Vector2(-100,-100)
		for id in ids:
			var grid := Vector2(Layout.area_grid(id))
			minimum = minimum.min(grid)
			maximum = maximum.max(grid)
		var cell := Vector2(minf(162,(size.x-12)/(maximum.x-minimum.x+1)),76)
		var nodes := {}
		for id in ids:
			var grid := Vector2(Layout.area_grid(id))-minimum
			nodes[id] = Rect2(Vector2(6,18)+grid*cell,Vector2(cell.x-16,58))
		for id in ids:
			for link in Layout.exits(id):
				if not nodes.has(link.to): continue
				draw_line(nodes[id].get_center(),nodes[link.to].get_center(),Color("a0aa87"),3)
		for id in ids:
			var box: Rect2 = nodes[id]
			var selected: bool = room == id
			draw_rect(box,INK if selected else Color("e1e3cb") if id in open_areas else Color("c8c7b7"))
			var text_color := PAPER if selected else INK
			draw_string(font,box.position+Vector2(8,19),Layout.area_title(id),HORIZONTAL_ALIGNMENT_LEFT,-1,14,text_color)
			var names: Array[String] = []
			for home in Layout.door_positions():
				if Layout.home_area(home) == id and home_names.has(home):
					names.append(str(home_names.get(home, home)))
			draw_string(font,box.position+Vector2(8,36),(" · ".join(names) if id in open_areas else "Camino por recuperar"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,text_color)
			if selected: draw_string(font,box.position+Vector2(8,51),"Estás aquí",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("b3c995"))

func _init(owner: Control) -> void:
	host = owner

func show_map() -> void:
	if is_instance_valid(host.help_panel) and host.help_panel.has_meta("neighborhood_map"):
		host.close_help()
		return
	var column: VBoxContainer = host.open_reading_panel("EL BARRIO")
	host.help_panel.set_meta("neighborhood_map",true)
	var map := MapGraph.new()
	map.room = host.current_room if Layout.is_outdoor(host.current_room) else Layout.home_area(host.current_room)
	map.font = host.ui_font
	map.open_areas = host.colony.settlement.state.areas.duplicate()
	for person: Dictionary in host.colony.active_residents():
		map.home_names[person.id] = "Tú" if person.id == "player" else str(person.name)
	map.custom_minimum_size = Vector2(500,176)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(map)
	host.reading_text(column,"NORTE ↑", "Los caminos unen las zonas. Al volver, entrarás por el lado opuesto. M o Esc para cerrar.")

func changed_area() -> void:
	if host.preview_mode: return
	if not is_instance_valid(veil):
		veil = ColorRect.new()
		veil.name = "AreaTransition"
		veil.color = Color("23392b")
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(veil)
		host.move_child(veil,host.world_clip.get_index()+1)
	veil.size = host.layout_size()
	if is_instance_valid(transition): transition.kill()
	veil.modulate.a = 0.65
	veil.show()
	transition = host.create_tween()
	transition.tween_property(veil,"modulate:a",0.0,0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transition.tween_callback(veil.hide)
