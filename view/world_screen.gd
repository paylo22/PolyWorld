extends Node2D
## Игровой экран: земля (WorldView), флора (FloraView), камера, верхние
## панели и нижняя панель палитры бога.
##
## Один палец — действие выбранного инструмента (кисть или лупа),
## два пальца — камера. Все изменения мира — через команды sim
## (WorldState.palette), рост леса идёт по шагам GameClock.

const WorldState = preload("res://sim/world.gd")
const FloraView = preload("res://view/flora_view.gd")
const BrushInput = preload("res://view/brush_input.gd")
const PalettePanel = preload("res://ui/palette_panel.gd")
const CellInfo = preload("res://ui/cell_info.gd")
const MENU_SCENE := "res://ui/main_menu.tscn"

@onready var _view = $WorldView
@onready var _cam = $Camera
@onready var _date: Label = %DateLabel
@onready var _info: Label = %InfoLabel
@onready var _status: Label = %StatusLabel

var _world: WorldState
var _flora: FloraView
var _input: BrushInput
var _palette: PalettePanel
var _cell_info: CellInfo


func _ready() -> void:
	_world = WorldState.current
	if _world == null or not _world.has_world():
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return
	_world.start_sim(Defs)
	_view.setup(_world.data, Defs)
	_cam.setup(Vector2(_world.data.width, _world.data.height))

	_flora = FloraView.new()
	_flora.name = "FloraView"
	add_child(_flora)
	move_child(_flora, _view.get_index() + 1)
	_flora.setup(_world.data, Defs, _cam)

	_palette = PalettePanel.new()
	_palette.name = "Palette"
	$Hud.add_child(_palette)
	_palette.setup(Defs)
	_palette.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_palette.offset_left = 10
	_palette.offset_right = -10
	_palette.offset_bottom = -10
	_palette.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_palette.tool_changed.connect(_on_tool_changed)
	_palette.size_changed.connect(func(_s): _input.finish())
	_palette.undo_pressed.connect(_on_undo)
	_palette.set_undo_count(0)

	_cell_info = CellInfo.new()
	_cell_info.name = "CellInfo"
	$Hud.add_child(_cell_info)
	_cell_info.position = Vector2(10, 104)

	_input = BrushInput.new()
	_input.name = "BrushInput"
	_input.camera = _cam
	_input.blockers = [_palette, _cell_info, $Hud/TopBar]
	add_child(_input)
	_input.started.connect(_on_stroke_started)
	_input.moved.connect(_on_stroke_moved)
	_input.finished.connect(_on_stroke_finished)
	_input.cancelled.connect(_on_stroke_cancelled)

	%SaveButton.pressed.connect(_on_save)
	%MenuButton.pressed.connect(_on_menu)
	%HomeButton.pressed.connect(_cam.show_all)
	GameClock.day_passed.connect(_on_day)
	GameClock.paused_changed.connect(_on_paused)
	GameClock.step.connect(_world.step)
	_refresh_date()
	var gen := " · создан за %d мс" % _world.gen_ms if _world.gen_ms > 0.0 else ""
	_status.text = "%s · %d×%d · сид %s%s · картинка %d мс" % [
		_world.world_name, _world.data.width, _world.data.height,
		str(_world.params.get("seed", "?")), gen, _view.last_build_ms]
	_info.text = "Один палец — кисть, два — камера."


func _exit_tree() -> void:
	if _world == null:
		return
	if GameClock.step.is_connected(_world.step):
		GameClock.step.disconnect(_world.step)
	if GameClock.day_passed.is_connected(_on_day):
		GameClock.day_passed.disconnect(_on_day)
	if GameClock.paused_changed.is_connected(_on_paused):
		GameClock.paused_changed.disconnect(_on_paused)


func _on_day(_d: int) -> void:
	_refresh_date()


func _on_paused(_p: bool) -> void:
	_refresh_date()


func _refresh_date() -> void:
	_date.text = GameClock.get_date_string() + ("  (пауза)" if GameClock.paused else "")


# --- Кисти ----------------------------------------------------------------

func _on_tool_changed(_tool: String, _arg: String) -> void:
	_input.finish()


func _on_stroke_started(cell: Vector2i) -> void:
	if _palette.tool == "lupa":
		_cell_info.show_cell(_world.data, cell.x, cell.y, Defs)
		return
	var err: String = _world.palette.begin_stroke(_palette.tool, _palette.brush_size, _palette.arg)
	if err != "":
		_info.text = "Ошибка: " + err
		return
	_world.palette.stroke_to(cell.x, cell.y)


func _on_stroke_moved(cell: Vector2i) -> void:
	if _palette.tool == "lupa":
		_cell_info.show_cell(_world.data, cell.x, cell.y, Defs)
		return
	_world.palette.stroke_to(cell.x, cell.y)


func _on_stroke_finished() -> void:
	_world.palette.end_stroke()
	_palette.set_undo_count(_world.palette.undo_count())


func _on_stroke_cancelled() -> void:
	_world.palette.cancel_stroke()


func _on_undo() -> void:
	_input.finish()
	_world.palette.undo()
	_palette.set_undo_count(_world.palette.undo_count())


# --- Верхняя панель -------------------------------------------------------

func _on_save() -> void:
	var err := SaveLoad.save_game(_world.slot_name())
	_status.text = ("Сохранено: %s, %s" % [_world.world_name, GameClock.get_date_string()]) if err == "" else "Ошибка: " + err


func _on_menu() -> void:
	GameClock.set_paused(true)
	get_tree().change_scene_to_file(MENU_SCENE)
