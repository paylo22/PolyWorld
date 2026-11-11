extends RefCounted
## Тесты сохранения: мир и часы после записи и чтения совпадают, список, версия.

const Clock = preload("res://sim/game_clock.gd")
const SaveLoadScript = preload("res://sim/save_load.gd")
const WorldScript = preload("res://sim/world.gd")
const WorldGen = preload("res://sim/world_gen.gd")
const DefsScript = preload("res://sim/defs.gd")
const DIR := "user://test_saves"

var _made: Array = []
var _defs: Node


func _init() -> void:
	_defs = _new(DefsScript)
	_defs.load_dir("res://data")


func _new(script: Script) -> Node:
	var n: Node = script.new()
	_made.append(n)
	return n


func _saveload() -> Node:
	var sl := _new(SaveLoadScript)
	sl.saves_dir = DIR
	return sl


func _world(seed_value: int) -> Node:
	var w := _new(WorldScript)
	var gen = WorldGen.new(_defs, {"seed": seed_value, "size": 128})
	w.set_world(gen.generate(), gen.params, "Тестовый мир %d" % seed_value)
	return w


func cleanup() -> void:
	for n in _made:
		n.free()
	_made.clear()
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		DirAccess.remove_absolute(DIR)


func test_world_roundtrip(t) -> void:
	var sl := _saveload()
	var a := _world(31)
	var ca := _new(Clock)
	ca.set_paused(false)
	ca.set_speed(5)
	for i in 100:
		ca.advance(1.0)
	t.eq(sl.save_game("roundtrip", ca, a, _defs), "", "сохранение без ошибки")
	var b := _new(WorldScript)
	var cb := _new(Clock)
	t.eq(sl.load_game("roundtrip", cb, b, _defs), "", "загрузка без ошибки")
	t.ok(a.data.equals(b.data), "все слои мира совпали")
	t.eq(b.params, a.params, "настройки совпали")
	t.eq(b.world_name, "Тестовый мир 31", "название")
	t.eq(cb.total_steps, ca.total_steps, "время совпало")
	t.eq(cb.speed, 5, "скорость совпала")


func test_list_and_delete(t) -> void:
	var sl := _saveload()
	var c := _new(Clock)
	t.eq(sl.save_game("one", c, _world(1), _defs), "", "первое")
	t.eq(sl.save_game("two", c, _world(2), _defs), "", "второе")
	var list: Array = sl.list_saves()
	var slots := list.map(func(s): return s["slot"])
	t.ok(slots.has("one") and slots.has("two"), "оба в списке")
	var one: Dictionary = list[slots.find("one")]
	t.eq(one["name"], "Тестовый мир 1", "имя в шапке")
	t.eq(int(one["size"]), 128, "размер в шапке")
	t.eq(sl.delete_save("one"), "", "удаление")
	t.ok(not sl.list_saves().map(func(s): return s["slot"]).has("one"), "удалён из списка")


func test_overwrite_same_slot(t) -> void:
	var sl := _saveload()
	var c := _new(Clock)
	sl.save_game("same", c, _world(1), _defs)
	var w2 := _world(2)
	t.eq(sl.save_game("same", c, w2, _defs), "", "перезапись")
	var back := _new(WorldScript)
	sl.load_game("same", c, back, _defs)
	t.ok(back.data.equals(w2.data), "в файле новый мир")


func test_remap_when_biome_order_changes(t) -> void:
	var a := _world(4)
	var d: Dictionary = a.to_dict(_defs)
	# Как будто в старой версии биомы шли в обратном порядке.
	var ids: Array = d["biome_ids"].duplicate()
	ids.reverse()
	var cells: Dictionary = d["cells"]
	var layer: PackedInt32Array = cells["layers"]["biome"].duplicate()
	var n := ids.size()
	for i in layer.size():
		if layer[i] >= 0:
			layer[i] = n - 1 - layer[i]
	cells["layers"]["biome"] = layer
	d["biome_ids"] = ids
	var b := _new(WorldScript)
	t.eq(b.from_dict(d, _defs), "", "загрузка")
	t.eq(b.data.biomes, a.data.biomes, "номера биомов переведены")


func test_bad_versions(t) -> void:
	var sl := _saveload()
	t.has_text(sl.check_header({"version": 999}), "более новой версии", "новее")
	t.has_text(sl.check_header({"version": 1}), "старого формата", "старый формат этапа 0")
	t.has_text(sl.check_header({}), "version", "нет version")
	t.has_text(sl.check_header("мусор"), "не похож", "не словарь")


func test_missing_slot(t) -> void:
	var sl := _saveload()
	var c := _new(Clock)
	t.has_text(sl.load_game("nope", c, _new(WorldScript), _defs), "не найдено", "нет файла")


func test_no_world_to_save(t) -> void:
	var sl := _saveload()
	t.has_text(sl.save_game("x", _new(Clock), _new(WorldScript), _defs), "Нет мира", "пустой мир")
