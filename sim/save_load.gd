extends Node
## Сохранение и загрузка (автозагрузка SaveLoad).
##
## Один файл user://save.json. Внутри словарь:
##   {"version": 1, "game_version": "0.1.0", "saved_at": "...", "clock": {...}}
## Поле version — версия формата сохранения. Если формат меняется,
## увеличь SAVE_VERSION и допиши перенос старых данных в _migrate().
##
## Новые системы добавляют свои данные так: в build_save_dict() — ключ
## со словарём от system.to_dict(), в apply_save_dict() — вызов from_dict().

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://save.json"


func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


## Сохраняет игру. Возвращает текст ошибки или "" если всё хорошо.
func save_game(path: String = DEFAULT_PATH, clock: Node = null) -> String:
	var data := build_save_dict(clock if clock else GameClock)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Не удалось открыть файл %s для записи: %s" % [tmp, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# Сначала пишем во временный файл, потом подменяем: если игра упадёт
	# посреди записи, старое сохранение останется целым.
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "Не удалось записать %s: %s" % [path, error_string(err)]
	return ""


## Загружает игру. Возвращает текст ошибки или "" если всё хорошо.
func load_game(path: String = DEFAULT_PATH, clock: Node = null) -> String:
	if not FileAccess.file_exists(path):
		return "Сохранение не найдено: %s" % path
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return "%s, строка %d: файл повреждён — %s" % [path, json.get_error_line() + 1, json.get_error_message()]
	if not json.data is Dictionary:
		return "%s: ожидается объект {...} в корне файла" % path
	return apply_save_dict(json.data, clock if clock else GameClock)


func build_save_dict(clock: Node) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"saved_at": Time.get_datetime_string_from_system(),
		"clock": clock.to_dict(),
	}


## Применяет словарь сохранения. Возвращает текст ошибки или "".
func apply_save_dict(data: Dictionary, clock: Node) -> String:
	var v = data.get("version")
	if not (v is int or v is float):
		return "В сохранении нет поля version"
	var version := int(v)
	if version > SAVE_VERSION:
		return "Сохранение из более новой версии игры (формат %d, эта версия понимает до %d)" % [version, SAVE_VERSION]
	if version < 1:
		return "Неверная версия сохранения: %d" % version
	data = _migrate(data, version)
	if not data.get("clock") is Dictionary:
		return "В сохранении нет раздела clock"
	return clock.from_dict(data["clock"])


## Перенос старых форматов в текущий. Пока формат один — ничего не делает.
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data
