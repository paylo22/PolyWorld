extends Node2D
## Игровой экран: земля (WorldView), камера и верхняя панель.
## Тап по карте показывает сведения о клетке внизу экрана.

const MENU_SCENE := "res://ui/main_menu.tscn"

@onready var _view = $WorldView
@onready var _cam = $Camera
@onready var _date: Label = %DateLabel
@onready var _info: Label = %InfoLabel
@onready var _status: Label = %StatusLabel


func _ready() -> void:
	if not World.has_world():
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return
	_view.setup(World.data, Defs)
	_cam.setup(Vector2(World.data.width, World.data.height))
	_cam.tapped.connect(_on_tapped)
	%SaveButton.pressed.connect(_on_save)
	%MenuButton.pressed.connect(_on_menu)
	%HomeButton.pressed.connect(_cam.show_all)
	GameClock.day_passed.connect(func(_d): _refresh_date())
	GameClock.paused_changed.connect(func(_p): _refresh_date())
	_refresh_date()
	var gen := " · создан за %d мс" % World.gen_ms if World.gen_ms > 0.0 else ""
	_status.text = "%s · %d×%d · сид %s%s · картинка %d мс" % [
		World.world_name, World.data.width, World.data.height,
		str(World.params.get("seed", "?")), gen, _view.last_build_ms]
	_info.text = "Тап по карте — сведения о клетке. Два пальца — сдвиг и масштаб."


func _refresh_date() -> void:
	_date.text = GameClock.get_date_string() + ("  (пауза)" if GameClock.paused else "")


func _on_tapped(p: Vector2) -> void:
	var c := Vector2i(floori(p.x), floori(p.y))
	var w = World.data
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
	if cell["deposit"] >= 0:
		parts.append("жила: " + Defs.resources[Defs.resource_ids[cell["deposit"]]]["name"])
	_info.text = " · ".join(parts)


func _on_save() -> void:
	var err := SaveLoad.save_game(World.slot_name())
	_status.text = ("Сохранено: %s, %s" % [World.world_name, GameClock.get_date_string()]) if err == "" else "Ошибка: " + err


func _on_menu() -> void:
	GameClock.set_paused(true)
	get_tree().change_scene_to_file(MENU_SCENE)
