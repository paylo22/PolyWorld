extends PanelContainer
## Нижняя панель палитры бога: вкладки «Земля», «Флора», «Инструменты».
##
## Панель только хранит выбор игрока (инструмент, вариант, размер кисти)
## и сообщает о нём сигналами. Мир меняет экран мира через команды sim.
##
## Ряды панели:
##   1) вкладки + что выбрано + «Отмена»;
##   2) кнопки инструментов текущей вкладки;
##   3) варианты (биомы или жилы) — только для «Биом» и «Жила».

signal tool_changed(tool: String, arg: String)
signal size_changed(size: int)
signal undo_pressed

const BTN_H := 60
const SPRITE_DIR := "res://assets/sprites/flora"

## Инструменты вкладок: [id, подпись]. "lupa" — не кисть, а лупа.
const LAND_TOOLS := [["raise", "Поднять"], ["lower", "Опустить"], ["level", "Выровнять"],
	["water", "Вода"], ["river", "Река"], ["biome", "Биом"], ["vein", "Жила"]]
const TOOL_TOOLS := [["lupa", "Лупа"], ["erase", "Ластик"]]
const TOOL_NAMES := {"raise": "Поднять", "lower": "Опустить", "level": "Выровнять", "water": "Залить водой",
	"river": "Река", "biome": "Биом", "vein": "Жила", "flora": "Флора", "lupa": "Лупа", "erase": "Ластик"}

var tool := "lupa"
var arg := ""
var brush_size := 3

var _defs
var _tabs := {}          # имя вкладки → кнопка
var _pages := {}         # имя вкладки → ряд инструментов
var _tool_group := ButtonGroup.new()
var _tool_btns := {}     # "tool:arg" → кнопка
var _options_row: HFlowContainer
var _option_group := ButtonGroup.new()
var _size_btns := {}
var _undo_btn: Button
var _label: Label
var _biome_arg := ""
var _vein_arg := ""


func setup(defs) -> void:
	_defs = defs
	_biome_arg = defs.biome_ids[0]
	_vein_arg = defs.palette["veins"][0]
	var sizes: Array = defs.palette["brush_sizes"]
	brush_size = sizes[mini(1, sizes.size() - 1)]
	_build()
	_select_tab("land")
	_select_tool("lupa", "")


## Обновляет число на кнопке «Отмена».
func set_undo_count(n: int) -> void:
	_undo_btn.text = "Отмена (%d)" % n
	_undo_btn.disabled = n == 0


func _build() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.85)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	var tab_group := ButtonGroup.new()
	for t in [["land", "Земля"], ["flora", "Флора"], ["tools", "Инструменты"]]:
		var b := _button(t[1], 150)
		b.toggle_mode = true
		b.button_group = tab_group
		b.pressed.connect(_select_tab.bind(t[0]))
		top.add_child(b)
		_tabs[t[0]] = b
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.78))
	top.add_child(_label)
	_undo_btn = _button("Отмена (0)", 150)
	_undo_btn.pressed.connect(func(): undo_pressed.emit())
	top.add_child(_undo_btn)

	# Земля
	var land := _row()
	for t in LAND_TOOLS:
		land.add_child(_tool_button(t[0], "", t[1], null))
	_pages["land"] = land
	vb.add_child(land)
	# Флора
	var fl := _row()
	for id in _defs.flora_ids:
		var f: Dictionary = _defs.flora[id]
		var tex := load(SPRITE_DIR.path_join(f["sprite"])) as Texture2D
		fl.add_child(_tool_button("flora", id, f["name"], tex))
	_pages["flora"] = fl
	vb.add_child(fl)
	# Инструменты
	var tl := _row()
	for t in TOOL_TOOLS:
		tl.add_child(_tool_button(t[0], "", t[1], null))
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(16, 0)
	tl.add_child(sep)
	var lbl := Label.new()
	lbl.text = "Кисть:"
	tl.add_child(lbl)
	var size_group := ButtonGroup.new()
	for s in _defs.palette["brush_sizes"]:
		var b := _button(str(s), 64)
		b.toggle_mode = true
		b.button_group = size_group
		b.button_pressed = s == brush_size
		b.pressed.connect(_select_size.bind(s))
		tl.add_child(b)
		_size_btns[s] = b
	_pages["tools"] = tl
	vb.add_child(tl)

	_options_row = HFlowContainer.new()
	_options_row.add_theme_constant_override("h_separation", 6)
	_options_row.add_theme_constant_override("v_separation", 6)
	vb.add_child(_options_row)


func _select_tab(tab: String) -> void:
	for t in _tabs:
		(_tabs[t] as Button).set_pressed_no_signal(t == tab)
		(_pages[t] as Control).visible = t == tab
	_refresh_options()


func _select_tool(t: String, a: String) -> void:
	tool = t
	match t:
		"biome":
			a = _biome_arg
		"vein":
			a = _vein_arg
	arg = a
	var key := t + ":" + ("" if t == "biome" or t == "vein" else a)
	for k in _tool_btns:
		(_tool_btns[k] as Button).set_pressed_no_signal(k == key)
	_refresh_options()
	_refresh_label()
	tool_changed.emit(tool, arg)


func _select_option(a: String) -> void:
	if tool == "biome":
		_biome_arg = a
	elif tool == "vein":
		_vein_arg = a
	arg = a
	_refresh_label()
	tool_changed.emit(tool, arg)


func _select_size(s: int) -> void:
	brush_size = s
	_refresh_label()
	size_changed.emit(s)


## Ряд вариантов: биомы или жилы — только на вкладке «Земля».
func _refresh_options() -> void:
	for ch in _options_row.get_children():
		ch.queue_free()
	var on_land: bool = (_pages["land"] as Control).visible
	var show := on_land and (tool == "biome" or tool == "vein")
	_options_row.visible = show
	if not show:
		return
	_option_group = ButtonGroup.new()
	var items := []
	if tool == "biome":
		for id in _defs.biome_ids:
			items.append([id, _defs.biomes[id]["name"], _defs.biomes[id]["color"]])
	else:
		for id in _defs.palette["veins"]:
			var r: Dictionary = _defs.resources[id]
			items.append([id, r["name"], r.get("map_color", Color.GRAY)])
	for it in items:
		var b := _button(it[1], 0)
		b.toggle_mode = true
		b.button_group = _option_group
		b.button_pressed = it[0] == arg
		b.icon = _swatch(it[2])
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_select_option.bind(it[0]))
		_options_row.add_child(b)


func _refresh_label() -> void:
	var name: String = TOOL_NAMES.get(tool, tool)
	if tool == "biome" and arg != "":
		name += ": " + str(_defs.biomes[arg]["name"])
	elif tool == "vein" and arg != "":
		name += ": " + str(_defs.resources[arg]["name"])
	elif tool == "flora" and arg != "":
		name = str(_defs.flora[arg]["name"])
	var size_txt := "" if tool == "lupa" else " · кисть %d" % brush_size
	_label.text = name + size_txt


func _tool_button(t: String, a: String, text: String, icon: Texture2D) -> Button:
	var b := _button(text, 0)
	b.toggle_mode = true
	b.button_group = _tool_group
	if icon:
		b.icon = _big_icon(icon)
	b.pressed.connect(_select_tool.bind(t, a))
	_tool_btns[t + ":" + a] = b
	return b


func _button(text: String, min_w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(maxi(min_w, 64), BTN_H)
	return b


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	return r


## Пиксельная картинка 16×16 → 48×48 без размытия (кнопка должна быть видна пальцу).
func _big_icon(tex: Texture2D) -> ImageTexture:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _swatch(c: Color) -> ImageTexture:
	var img := Image.create_empty(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.1))
	img.fill_rect(Rect2i(2, 2, 20, 20), c)
	return ImageTexture.create_from_image(img)
