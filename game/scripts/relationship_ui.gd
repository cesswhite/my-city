extends RefCounted
## Compact, directional relationship readout. Values are provided by the simulation.
const INK := Color("303e37")
const MUTED := Color("535f50")
const HEADING := Color("88533c")
const TRACK := Color("d1d0b8")
const FONT = preload("res://assets/fonts/PixelOperator.ttf")
const METRICS := [
	["trust", "Confianza", "Qué tan seguro se siente al compartir contigo.", Color("56765f")],
	["affection", "Afecto", "El cariño que te tiene; no implica una relación romántica.", Color("875f4f")],
	["tolerance", "Tolerancia", "Su disposición a tener paciencia contigo.", Color("536e6b")],
	["frustration", "Frustración", "Su incomodidad contigo en este momento.", Color("9d533b")]
]
const MOODS := {"calm":"En calma", "warm":"A gusto", "guarded":"Con cautela", "tired":"Con cansancio", "irritated":"Con molestia"}

static func _label(parent: Node, text: String, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func _fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style

static func build(parent: Control, snapshot: Dictionary) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = "RelationshipToPlayer"
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 4)
	parent.add_child(group)
	_label(group, "Su relación contigo", HEADING)
	var mood := _label(group, "", MUTED)
	mood.name = "Mood"
	for spec: Array in METRICS:
		var row := HBoxContainer.new()
		row.name = str(spec[0])
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.tooltip_text = str(spec[2])
		group.add_child(row)
		# Measured at the native font size: the longest label uses 74 px and
		# "100" uses 21 px. Fixed columns keep all four meters and values aligned.
		var caption := _label(row, str(spec[1]))
		caption.custom_minimum_size.x = 76
		var bar := ProgressBar.new()
		bar.name = "ValueBar"
		bar.min_value = 0
		bar.max_value = 100
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(36, 4)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", _fill(TRACK))
		bar.add_theme_stylebox_override("fill", _fill(spec[3]))
		row.add_child(bar)
		var value := _label(row, "")
		value.name = "Value"
		value.custom_minimum_size.x = 24
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	update(group, snapshot)
	return group

static func update(group: VBoxContainer, snapshot: Dictionary) -> void:
	var mood: Label = group.get_node("Mood")
	mood.text = "Ánimo: " + str(MOODS.get(str(snapshot.get("mood", "")), "Sin conocer aún"))
	for spec: Array in METRICS:
		var row: HBoxContainer = group.get_node(str(spec[0]))
		var raw: Variant = snapshot.get(spec[0])
		var known: bool = (raw is float or raw is int) and is_finite(float(raw))
		var value: int = clampi(roundi(float(raw)), 0, 100) if known else 0
		(row.get_node("ValueBar") as ProgressBar).value = value
		(row.get_node("Value") as Label).text = str(value) if known else "?"
		row.tooltip_text = "%s: %s de 100. %s" % [spec[1],str(value) if known else "sin conocer",spec[2]]
