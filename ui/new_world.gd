extends Control
## Экран «Новый мир»: название, сид, размер, ползунки (вода, гористость,
## острова) и кнопка «Создать». Генерация идёт по этапам, между ними
## экран обновляется и показывает, что сейчас делается.
## Пределы и значения по умолчанию — из data/worldgen.json.

const WorldGen = preload("res://sim/world_gen.gd")
const WorldState = preload("res://sim/world.gd")
const WORLD_SCENE := "res://view/world_screen.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"

var _name_edit: LineEdit
var _seed_edit: LineEdit
var _size_opt: OptionButton
var _water: HSlider
var _mount: HSlider
var _islands: HSlider
var _create_btn: Button
var _back_btn: Button
var _progress: ProgressBar
var _status: Label
var _sizes: Array[int] = []
var _busy := false


func _ready() -> void:
	var cfg: Dictionary = Defs.worldgen
	var lim: Dictionary = cfg["limits"]
	var d := WorldGen.default_params(cfg)

	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.17, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Новый мир"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)

	var seed_text := str(randi() % 1000000)
	_name_edit = _line_edit("Мир " + seed_text)
	_row(grid, "Название", _name_edit)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	_seed_edit = _line_edit(seed_text)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	var rnd := _button("Случайный", 150)
	rnd.pressed.connect(_on_random_seed)
	seed_row.add_child(rnd)
	_row(grid, "Сид", seed_row)

	_size_opt = OptionButton.new()
	_size_opt.custom_minimum_size = Vector2(0, 56)
	_size_opt.focus_mode = Control.FOCUS_NONE
	var s: int = cfg["size_min"]
	while s <= cfg["size_max"]:
		_sizes.append(s)
		_size_opt.add_item("%d × %d" % [s, s])
		if s == d["size"]:
			_size_opt.select(_sizes.size() - 1)
		s += cfg["size_step"]
	_row(grid, "Размер", _size_opt)

	_water = _slider(grid, "Вода", lim["water_min"], lim["water_max"], d["water"], "%d%%")
	_mount = _slider(grid, "Гористость", 0, 100, d["mountains"], "%d%%")
	_islands = _slider(grid, "Острова", lim["islands_min"], lim["islands_max"], d["islands"], "%d")

	_progress = ProgressBar.new()
	_progress.max_value = WorldGen.STAGES.size()
	_progress.custom_minimum_size = Vector2(0, 24)
	_progress.show_percentage = false
	_progress.visible = false
	box.add_child(_progress)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	_back_btn = _button("Назад", 200)
	_back_btn.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	buttons.add_child(_back_btn)
	_create_btn = _button("Создать", 280)
	_create_btn.add_theme_font_size_override("font_size", 30)
	_create_btn.pressed.connect(_on_create)
	buttons.add_child(_create_btn)


func _on_random_seed() -> void:
	var old_seed := _seed_edit.text
	var new_seed := str(randi() % 1000000)
	_seed_edit.text = new_seed
	if _name_edit.text == "Мир " + old_seed:
		_name_edit.text = "Мир " + new_seed


func _on_create() -> void:
	if _busy:
		return
	_busy = true
	_create_btn.disabled = true
	_back_btn.disabled = true
	if _seed_edit.text.strip_edges() == "":
		_seed_edit.text = str(randi() % 1000000)
	var params := {
		"seed": WorldGen.seed_from_text(_seed_edit.text),
		"size": _sizes[_size_opt.selected],
		"water": int(_water.value),
		"mountains": int(_mount.value),
		"islands": int(_islands.value),
	}
	var world_name := _name_edit.text.strip_edges()
	if world_name == "":
		world_name = "Мир " + _seed_edit.text.strip_edges()
	var gen = WorldGen.new(Defs, params)
	_progress.visible = true
	for i in WorldGen.STAGES.size():
		_progress.value = i
		_status.text = "Создаём мир: %s…" % WorldGen.STAGES[i]
		# Два кадра, чтобы надпись точно успела нарисоваться до тяжёлого этапа.
		await get_tree().process_frame
		await get_tree().process_frame
		gen.run_stage(i)
	_progress.value = WorldGen.STAGES.size()
	_status.text = "Рисуем карту…"
	await get_tree().process_frame
	WorldState.current = WorldState.new(gen.world, gen.params, world_name, gen.total_ms())
	print("Мир %d×%d создан за %d мс: %s" % [gen.world.width, gen.world.height, gen.total_ms(), gen.stage_ms])
	GameClock.reset()
	GameClock.set_paused(false)
	get_tree().change_scene_to_file(WORLD_SCENE)


# --- Построение формы -------------------------------------------------------

func _row(grid: GridContainer, caption: String, control: Control) -> void:
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size = Vector2(180, 0)
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _slider(grid: GridContainer, caption: String, lo: int, hi: int, value: int, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.custom_minimum_size = Vector2(0, 56)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(70, 0)
	v.text = fmt % value
	s.value_changed.connect(func(x): v.text = fmt % int(x))
	row.add_child(v)
	_row(grid, caption, row)
	return s


func _line_edit(text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(0, 56)
	return e


func _button(text: String, width: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 64)
	b.focus_mode = Control.FOCUS_NONE
	return b
