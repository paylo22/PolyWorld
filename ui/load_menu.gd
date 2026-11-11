extends Control
## Список сохранений: название, дата в игре, размер, сид, когда сохранено.
## «Загрузить» открывает мир, «Удалить» требует второго нажатия.

const WORLD_SCENE := "res://view/world_screen.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"

var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.17, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "Сохранения"
	title.add_theme_font_size_override("font_size", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := _button("Назад", 180)
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	top.add_child(back)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var saves := SaveLoad.list_saves()
	if saves.is_empty():
		var l := Label.new()
		l.text = "Сохранений пока нет."
		_list.add_child(l)
		return
	for s in saves:
		_list.add_child(_make_row(s))


func _make_row(s: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var slot: String = s["slot"]
	if s.has("error"):
		text.text = "%s\nне читается: %s" % [slot, s["error"]]
	else:
		text.text = "%s\n%s · %d×%d · сид %s · сохранено %s" % [
			s.get("name", slot), s.get("date", ""), int(s.get("size", 0)), int(s.get("size", 0)),
			str(s.get("seed", "?")), str(s.get("saved_at", "")).replace("T", " ")]
	row.add_child(text)
	var load_btn := _button("Загрузить", 170)
	load_btn.disabled = s.has("error")
	load_btn.pressed.connect(_on_load.bind(slot))
	row.add_child(load_btn)
	var del_btn := _button("Удалить", 150)
	del_btn.pressed.connect(_on_delete.bind(slot, del_btn))
	row.add_child(del_btn)
	return panel


func _on_load(slot: String) -> void:
	_status.text = "Загружаем…"
	await get_tree().process_frame
	var err := SaveLoad.load_game(slot)
	if err != "":
		_status.text = "Не удалось загрузить: " + err
		push_error(err)
		return
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_delete(slot: String, btn: Button) -> void:
	if btn.text != "Точно?":
		btn.text = "Точно?"
		return
	var err := SaveLoad.delete_save(slot)
	_status.text = "" if err == "" else err
	_fill()


func _button(text: String, width: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 64)
	b.focus_mode = Control.FOCUS_NONE
	return b
