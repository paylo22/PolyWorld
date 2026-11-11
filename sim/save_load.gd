extends Node
## Сохранение и загрузка (автозагрузка SaveLoad).
##
## Каждый мир — отдельный файл user://saves/<имя>.save, сжатый ZSTD.
## Внутри две записи store_var подряд:
##   1) шапка {"version", "game_version", "saved_at", "name", "seed", "size", "date"} —
##      её одну читает список сохранений, не распаковывая весь мир;
##   2) тело {"clock": {...}, "world": {...}} — слои мира как PackedInt32Array.
## Поле version — версия формата. Сменил формат — увеличь SAVE_VERSION
## и допиши перенос в _migrate().
##
## Версия 1 (этап 0) была одним JSON без мира; такие файлы не читаются.

const WorldState = preload("res://sim/world.gd")

const SAVE_VERSION := 2
const EXT := ".save"

var saves_dir := "user://saves"


func has_saves() -> bool:
	return not list_saves().is_empty()


## Список сохранений, новые сверху. Каждый элемент — шапка файла плюс
## "slot" (имя файла без расширения) и "modified" (время файла, unix).
## Если файл не читается, в элементе есть "error".
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(saves_dir):
		return out
	for f in DirAccess.get_files_at(saves_dir):
		if not f.ends_with(EXT):
			continue
		var path := saves_dir.path_join(f)
		var header := _read_header(path)
		header["slot"] = f.get_basename()
		header["modified"] = FileAccess.get_modified_time(path)
		out.append(header)
	out.sort_custom(func(a, b): return a["modified"] > b["modified"])
	return out


## Сохраняет мир и часы в слот. Возвращает текст ошибки или "".
## clock, world, defs — для тестов; по умолчанию GameClock, WorldState.current, Defs.
func save_game(slot: String, clock: Node = null, world = null, defs: Node = null) -> String:
	clock = clock if clock else GameClock
	world = world if world else WorldState.current
	defs = defs if defs else Defs
	if world == null or not world.has_world():
		return "Нет мира для сохранения"
	DirAccess.make_dir_recursive_absolute(saves_dir)
	var path := saves_dir.path_join(slot + EXT)
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "Не удалось открыть %s для записи: %s" % [tmp, error_string(FileAccess.get_open_error())]
	f.store_var({
		"version": SAVE_VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"name": world.world_name,
		"seed": world.params.get("seed", 0),
		"size": world.data.width,
		"date": clock.get_date_string(),
	})
	f.store_var({"clock": clock.to_dict(), "world": world.to_dict(defs)})
	f.close()
	# Сначала пишем во временный файл, потом подменяем: если игра упадёт
	# посреди записи, старое сохранение останется целым.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "Не удалось записать %s: %s" % [path, error_string(err)]
	return ""


## Загружает слот и делает его текущим миром (WorldState.current).
## Возвращает текст ошибки или "" — при ошибке текущий мир не меняется.
## clock, defs — для тестов; если передан world, загрузка идёт в него.
func load_game(slot: String, clock: Node = null, world = null, defs: Node = null) -> String:
	clock = clock if clock else GameClock
	defs = defs if defs else Defs
	var make_current: bool = world == null
	world = world if world else WorldState.new()
	var path := saves_dir.path_join(slot + EXT)
	if not FileAccess.file_exists(path):
		return "Сохранение не найдено: %s" % path
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "Не удалось открыть %s: %s" % [path, error_string(FileAccess.get_open_error())]
	var header = f.get_var()
	var err := check_header(header)
	if err != "":
		return err
	var body = f.get_var()
	f.close()
	if not body is Dictionary:
		return "%s: файл повреждён (нет данных мира)" % path
	body = _migrate(body, int(header["version"]))
	if not body.get("clock") is Dictionary or not body.get("world") is Dictionary:
		return "%s: файл повреждён (нет раздела clock или world)" % path
	err = world.from_dict(body["world"], defs)
	if err != "":
		return err
	err = clock.from_dict(body["clock"])
	if err != "":
		return err
	if make_current:
		WorldState.current = world
	return ""


func delete_save(slot: String) -> String:
	var path := saves_dir.path_join(slot + EXT)
	if not FileAccess.file_exists(path):
		return "Сохранение не найдено: %s" % path
	var err := DirAccess.remove_absolute(path)
	return "" if err == OK else "Не удалось удалить %s: %s" % [path, error_string(err)]


## Проверяет шапку. Возвращает текст ошибки или "".
func check_header(header) -> String:
	if not header is Dictionary:
		return "Файл не похож на сохранение PolyWorld"
	var v = header.get("version")
	if not (v is int or v is float):
		return "В сохранении нет поля version"
	if int(v) > SAVE_VERSION:
		return "Сохранение из более новой версии игры (формат %d, эта версия понимает до %d)" % [int(v), SAVE_VERSION]
	if int(v) < SAVE_VERSION:
		return "Сохранение старого формата %d, его нельзя загрузить (нужен %d)" % [int(v), SAVE_VERSION]
	return ""


func _read_header(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {"error": "файл не открывается"}
	var header = f.get_var()
	var err := check_header(header)
	if err != "":
		return {"error": err}
	return header


## Перенос старых форматов в текущий. Пока перенос не нужен.
func _migrate(body: Dictionary, _from_version: int) -> Dictionary:
	return body
