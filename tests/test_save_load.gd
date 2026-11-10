extends RefCounted
## Тесты сохранения: запись и чтение файла, поле version.

const Clock = preload("res://sim/game_clock.gd")
const SaveLoadScript = preload("res://sim/save_load.gd")
const PATH := "user://test_save.json"

var _made: Array = []


func _new(script: Script) -> Node:
	var n: Node = script.new()
	_made.append(n)
	return n


func cleanup() -> void:
	for n in _made:
		n.free()
	_made.clear()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_roundtrip_file(t) -> void:
	var sl := _new(SaveLoadScript)
	var a := _new(Clock)
	a.set_paused(false)
	a.set_speed(5)
	for i in 100:
		a.advance(1.0)
	t.eq(sl.save_game(PATH, a), "", "сохранение без ошибки")
	t.ok(sl.has_save(PATH), "файл появился")
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	t.eq(int(data["version"]), SaveLoadScript.SAVE_VERSION, "в файле есть version")
	var b := _new(Clock)
	t.eq(sl.load_game(PATH, b), "", "загрузка без ошибки")
	t.eq(b.total_steps, a.total_steps, "время восстановлено")
	t.eq(b.speed, 5, "скорость восстановлена")


func test_newer_version_rejected(t) -> void:
	var sl := _new(SaveLoadScript)
	var c := _new(Clock)
	var err: String = sl.apply_save_dict({"version": 999, "clock": c.to_dict()}, c)
	t.has_text(err, "более новой версии", "новая версия")


func test_missing_version_rejected(t) -> void:
	var sl := _new(SaveLoadScript)
	var c := _new(Clock)
	t.has_text(sl.apply_save_dict({"clock": c.to_dict()}, c), "version", "нет version")


func test_missing_file(t) -> void:
	var sl := _new(SaveLoadScript)
	var c := _new(Clock)
	t.has_text(sl.load_game("user://no_such_save.json", c), "не найдено", "нет файла")
