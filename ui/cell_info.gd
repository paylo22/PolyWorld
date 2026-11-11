extends PanelContainer
## Окно лупы: все данные клетки. Только читает мир.

const WorldData = preload("res://sim/world_data.gd")

var _title: Label
var _body: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(300, 0)
	var vb := VBoxContainer.new()
	add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(56, 56)
	close.pressed.connect(hide)
	top.add_child(close)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 19)
	vb.add_child(_body)
	hide()


func show_cell(w: WorldData, x: int, y: int, defs) -> void:
	if not w.in_bounds(x, y):
		return
	var i := w.index(x, y)
	_title.text = "Клетка (%d, %d)" % [x, y]
	var lines: PackedStringArray = []
	var h := w.heights[i]
	if h < 0:
		lines.append("Вода, глубина %d" % -h)
	else:
		var b := w.biomes[i]
		lines.append("Биом: " + (str(defs.biomes[defs.biome_ids[b]]["name"]) if b >= 0 else "—"))
		lines.append("Высота: %d" % h)
	lines.append("Влажность: %d" % w.moistures[i])
	if w.flags[i] & WorldData.FLAG_RIVER:
		lines.append("Река")
	var f := w.floras[i]
	lines.append("Растения: " + (str(defs.flora[defs.flora_ids[f]]["name"]) if f >= 0 else "нет"))
	var r := w.resources[i]
	lines.append("Жила: " + (str(defs.resources[defs.resource_ids[r]]["name"]) if r >= 0 else "нет"))
	lines.append("Владелец: " + ("ничья" if w.owners[i] < 0 else "королевство %d" % w.owners[i]))
	lines.append("Зона %d · чанк %d" % [w.zone_of(x, y), w.chunk_of(x, y)])
	_body.text = "\n".join(lines)
	show()
