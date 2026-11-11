extends Node2D
## Игровой экран: земля (WorldView), камера и верхняя панель.
## Тап по карте показывает сведения о клетке внизу экрана.

const WorldState = preload("res://sim/world.gd")
const MENU_SCENE := "res://ui/main_menu.tscn"

@onready var _view = $WorldView
@onready var _cam = $Camera
@onready var _date: Label = %DateLabel
@onready var _info: Label = %InfoLabel
@onready var _status: Label = %StatusLabel


var _world: WorldState


func _ready() -> void:
	_world = WorldState.current
	if _world == null or not _world.has_world():
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return
	_view.setup(_world.data, Defs)
	_cam.setup(Vector2(_world.data.width, _world.data.height))
	_cam.tapped.connect(_on_tapped)
	%SaveButton.pressed.connect(_on_save)
	%MenuButton.pressed.connect(_on_menu)
	%HomeButton.pressed.connect(_cam.show_all)
	GameClock.day_passed.connect(func(_d): _refresh_date())
	GameClock.paused_changed.connect(func(_p): _refresh_date())
	_refresh_date()
	var gen := " · создан за %d мс" % _world.gen_ms if _world.gen_ms > 0.0 else ""
	_status.text = "%s · %d×%d · сид %s%s · картинка %d мс" % [
		_world.world_name, _world.data.width, _world.data.height,
		str(_world.params.get("seed", "?")), gen, _view.last_build_ms]
	_info.text = "Тап по карте — сведения о клетке. Два пальца — сдвиг и масштаб."


func _refresh_date() -> void:
	_date.text = GameClock.get_date_string() + ("  (пауза)" if GameClock.paused else "")


func _on_tapped(p: Vector2) -> void:
	var c := Vector2i(floori(p.x), floori(p.y))
	var w = _world.data
	if not w.in_bounds(c.x, c.y):
		return
	var cell: Dictionary = w.get_cell(c.x, c.y)
	var parts: PackedStringArray = ["(%d, %d)" % [c.x, c.y]]
	if cell["height"] < 0:
		parts.append("вода, глубина %d" % -cell["height"])
	else:
		var b: int = cell["biome"]
		parts.append(Defs.biomes[Defs.biome_ids[b]]["name"] if b >= 0 else "?")
		parts.append("высота %d" % cell["height"])
		parts.append("влажность %d" % cell["moisture"])
	if w.is_river(c.x, c.y):
		parts.append("река")
	if cell["resource"] >= 0:
		parts.append("жила: " + Defs.resources[Defs.resource_ids[cell["resource"]]]["name"])
	_info.text = " · ".join(parts)


func _on_save() -> void:
	var err := SaveLoad.save_game(_world.slot_name())
	_status.text = ("Сохранено: %s, %s" % [_world.world_name, GameClock.get_date_string()]) if err == "" else "Ошибка: " + err


func _on_menu() -> void:
	GameClock.set_paused(true)
	get_tree().change_scene_to_file(MENU_SCENE)
