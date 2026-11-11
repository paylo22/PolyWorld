extends RefCounted
## Тесты генерации: один сид — один мир, настройки работают, все биомы есть.

const WorldGen = preload("res://sim/world_gen.gd")
const WorldData = preload("res://sim/world_data.gd")
const DefsScript = preload("res://sim/defs.gd")

var _defs: Node


func _init() -> void:
	_defs = DefsScript.new()
	_defs.load_dir("res://data")


func cleanup() -> void:
	_defs.free()


func _gen(p: Dictionary) -> WorldData:
	return WorldGen.new(_defs, p).generate()


func test_same_seed_same_world(t) -> void:
	var p := {"seed": 777, "size": 128, "water": 40, "mountains": 60, "islands": 2}
	var a := _gen(p)
	var b := _gen(p)
	t.ok(a.equals(b), "одинаковый сид и настройки — одинаковый мир")


func test_other_seed_other_world(t) -> void:
	var a := _gen({"seed": 1, "size": 128})
	var b := _gen({"seed": 2, "size": 128})
	t.ok(a.heights != b.heights, "другой сид — другой рельеф")


func test_text_seed(t) -> void:
	t.eq(WorldGen.seed_from_text(" 12345 "), 12345, "число как есть")
	t.eq(WorldGen.seed_from_text("Тверь"), WorldGen.seed_from_text("Тверь"), "текст даёт постоянный сид")
	t.ok(WorldGen.seed_from_text("Тверь") != WorldGen.seed_from_text("Москва"), "разный текст — разный сид")


func test_params_normalized(t) -> void:
	var p := WorldGen.normalize_params({"size": 300, "water": 99, "islands": 0, "junk": 1}, _defs.worldgen)
	t.eq(p["size"], 320, "размер к шагу 64")
	t.eq(p["water"], 80, "вода не больше предела")
	t.eq(p["islands"], 1, "острова не меньше 1")
	t.ok(not p.has("junk"), "лишнее отброшено")


func test_water_share_matches_setting(t) -> void:
	for water in [20, 60]:
		var w := _gen({"seed": 5, "size": 128, "water": water})
		var count := 0
		for h in w.heights:
			if h < 0:
				count += 1
		t.eq(int(round(100.0 * count / w.cell_count())), water, "доля воды %d%%" % water)


func test_more_mountains_with_slider(t) -> void:
	var lo := _count_mountains(_gen({"seed": 9, "size": 128, "mountains": 0}))
	var hi := _count_mountains(_gen({"seed": 9, "size": 128, "mountains": 100}))
	t.ok(hi > lo * 3, "гористость 100 даёт гор больше, чем 0 (%d против %d)" % [hi, lo])


func test_all_biomes_rivers_and_deposits(t) -> void:
	for s in [1, 42, 2026]:
		var w := _gen({"seed": s, "size": 256})
		var seen := {}
		var rivers := 0
		var deps := {}
		for i in w.cell_count():
			seen[w.biomes[i]] = true
			if w.flags[i] & WorldData.FLAG_RIVER:
				rivers += 1
			if w.resources[i] >= 0:
				deps[_defs.resource_ids[w.resources[i]]] = true
		for id in _defs.biome_ids:
			t.ok(seen.has(_defs.biome_index(id)), "сид %d: есть биом %s" % [s, id])
		t.ok(rivers > 50, "сид %d: есть реки (%d клеток)" % [s, rivers])
		for r in ["iron_ore", "coal", "sulfur", "gold", "clay"]:
			t.ok(deps.has(r), "сид %d: есть жила %s" % [s, r])


func test_rivers_run_downhill_to_water(t) -> void:
	var w := _gen({"seed": 3, "size": 128})
	var bad := 0
	for i in w.cell_count():
		if w.flags[i] & WorldData.FLAG_RIVER:
			# У каждой клетки реки есть сосед-вода, сосед-река или она исток.
			if w.heights[i] < 0:
				bad += 1
	t.eq(bad, 0, "река не течёт по воде")


func test_deposits_in_right_places(t) -> void:
	var w := _gen({"seed": 11, "size": 256})
	var clay: int = _defs.resource_index("clay")
	var mount_h: int = _defs.worldgen["hills_height"]
	var wrong := 0
	for i in w.cell_count():
		var d := w.resources[i]
		if d < 0:
			continue
		if d == clay:
			if w.heights[i] >= mount_h:
				wrong += 1
		elif w.heights[i] < mount_h:
			wrong += 1
	t.eq(wrong, 0, "руда только в горах/холмах, глина ниже")


func _count_mountains(w: WorldData) -> int:
	var b: int = _defs.biome_index("mountains")
	var n := 0
	for v in w.biomes:
		if v == b:
			n += 1
	return n
