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


func _world(seed_value: int) -> RefCounted:
	var gen = WorldGen.new(_defs, {"seed": seed_value, "size": 128})
	return WorldScript.new(gen.generate(), gen.params, "Тестовый мир %d" % seed_value)


func cleanup() -> void:
	for n in _made:
		if n is Node:
			n.free()
	_made.clear()
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		DirAccess.remove_absolute(DIR)


func test_world_roundtrip(t) -> void:
	var sl := _saveload()
	var a = _world(31)
	var ca := _new(Clock)
	ca.set_paused(false)
	ca.set_speed(5)
	for i in 100:
		ca.advance(1.0)
	t.eq(sl.save_game("roundtrip", ca, a, _defs), "", "сохранение без ошибки")
	var b = WorldScript.new()
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
	var w2 = _world(2)
	t.eq(sl.save_game("same", c, w2, _defs), "", "перезапись")
	var back = WorldScript.new()
	sl.load_game("same", c, back, _defs)
	t.ok(back.data.equals(w2.data), "в файле новый мир")


func test_remap_when_biome_order_changes(t) -> void:
	var a = _world(4)
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
	var b = WorldScript.new()
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
	t.has_text(sl.load_game("nope", c, WorldScript.new(), _defs), "не найдено", "нет файла")


func test_no_world_to_save(t) -> void:
	var sl := _saveload()
	t.has_text(sl.save_game("x", _new(Clock), WorldScript.new(), _defs), "Нет мира", "пустой мир")


func test_load_sets_current_world(t) -> void:
	var sl := _saveload()
	var c := _new(Clock)
	sl.save_game("cur", c, _world(8), _defs)
	var before = WorldScript.current
	t.eq(sl.load_game("cur", c, null, _defs), "", "загрузка в текущий мир")
	t.ok(WorldScript.current != null and WorldScript.current.world_name == "Тестовый мир 8", "текущий мир — загруженный")
	t.has_text(sl.load_game("nope", c, null, _defs), "не найдено", "ошибка")
	t.eq(WorldScript.current.world_name, "Тестовый мир 8", "при ошибке текущий мир не тронут")
	WorldScript.current = before


func test_palette_and_forest_go_to_save(t) -> void:
	# Мазки палитры и выросший лес попадают в сохранение, и после загрузки
	# лес растёт дальше так же, как рос бы без сохранения (правила 8 и 12).
	var sl := _saveload()
	var c := _new(Clock)
	var a = _world(12)
	a.start_sim(_defs)
	a.palette.begin_stroke("flora", 9, "broadleaf")
	a.palette.stroke_to(30, 30)
	a.palette.stroke_to(90, 40)
	a.palette.end_stroke()
	a.palette.begin_stroke("raise", 5)
	a.palette.stroke_to(60, 60)
	a.palette.end_stroke()
	a.palette.begin_stroke("river", 1)
	a.palette.stroke_to(10, 100)
	a.palette.stroke_to(100, 110)
	a.palette.end_stroke()
	for s in 3000:
		a.step(s)
	t.eq(sl.save_game("palette", c, a, _defs), "", "сохранение")
	var b = WorldScript.new()
	t.eq(sl.load_game("palette", c, b, _defs), "", "загрузка")
	t.ok(a.data.equals(b.data), "земля, флора и реки совпали")
	b.start_sim(_defs)
	for s in range(3000, 6000):
		a.step(s)
		b.step(s)
	t.ok(a.data.equals(b.data), "после загрузки лес растёт так же")


func test_old_save_without_flora_ids_and_rng(t) -> void:
	var a = _world(13)
	var d: Dictionary = a.to_dict(_defs)
	d.erase("flora_ids")
	d.erase("rng_seed")
	d.erase("rng_state")
	var b = WorldScript.new()
	t.eq(b.from_dict(d, _defs), "", "старое сохранение открывается")
	t.eq(b.rng.seed, a.rng.seed, "сид случайности — от сида мира")


func test_remap_when_flora_order_changes(t) -> void:
	var a = _world(14)
	a.data.floras[5] = 0
	a.data.floras[6] = 1
	var d: Dictionary = a.to_dict(_defs)
	var ids: Array = d["flora_ids"].duplicate()
	ids.reverse()
	var layer: PackedInt32Array = d["cells"]["layers"]["flora"].duplicate()
	for i in layer.size():
		if layer[i] >= 0:
			layer[i] = ids.size() - 1 - layer[i]
	d["cells"]["layers"]["flora"] = layer
	d["flora_ids"] = ids
	var b = WorldScript.new()
	t.eq(b.from_dict(d, _defs), "", "загрузка")
	t.eq(b.data.floras, a.data.floras, "номера растений переведены")
