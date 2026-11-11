extends Control
## Заглушка игрового экрана до этапа «Мир»: здесь будет карта.
## Сейчас показывает дату и даёт сохранить игру и выйти в меню.

const MENU_SCENE := "res://ui/main_menu.tscn"

@onready var _date: Label = %DateLabel
@onready var _status: Label = %StatusLabel


func _ready() -> void:
	%SaveButton.pressed.connect(_on_save)
	%MenuButton.pressed.connect(_on_menu)
	GameClock.tick.connect(_on_tick)
	GameClock.paused_changed.connect(func(_p): _refresh())
	_refresh()


func _on_tick(_t: int) -> void:
	_refresh()


func _refresh() -> void:
	_date.text = GameClock.get_date_string() + ("  (пауза)" if GameClock.paused else "")


func _on_save() -> void:
	var err := SaveLoad.save_game()
	_status.text = "Сохранено: %s" % GameClock.get_date_string() if err == "" else "Ошибка: " + err


func _on_menu() -> void:
	GameClock.set_paused(true)
	get_tree().change_scene_to_file(MENU_SCENE)
