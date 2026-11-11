extends Control
## Главное меню: «Новый мир», «Загрузить», номер версии.
## Если в data/*.json ошибка, показывает её и не пускает в игру.

const WORLD_SCENE := "res://view/world_placeholder.tscn"

@onready var _new_btn: Button = %NewWorldButton
@onready var _load_btn: Button = %LoadButton
@onready var _error: Label = %ErrorLabel
@onready var _version: Label = %VersionLabel


func _ready() -> void:
	_version.text = "версия %s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	_new_btn.pressed.connect(_on_new_world)
	_load_btn.pressed.connect(_on_load)
	GameClock.reset()
	_error.visible = false
	if not Defs.is_ok():
		_show_error("Ошибка в файлах данных:\n" + Defs.get_error_text())
		_new_btn.disabled = true
		_load_btn.disabled = true
		return
	_load_btn.disabled = not SaveLoad.has_save()


func _on_new_world() -> void:
	GameClock.reset()
	GameClock.set_paused(false)
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_load() -> void:
	var err := SaveLoad.load_game()
	if err != "":
		_show_error("Не удалось загрузить:\n" + err)
		return
	get_tree().change_scene_to_file(WORLD_SCENE)


func _show_error(text: String) -> void:
	_error.text = text
	_error.visible = true
	push_error(text)
