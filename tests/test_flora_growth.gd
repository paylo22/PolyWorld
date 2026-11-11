extends RefCounted
## Тесты роста леса: порция клеток, куда лес не идёт, луг зарастает за годы.

const DefsScript = preload("res://sim/defs.gd")
const WorldData = preload("res://sim/world_data.gd")
const FloraGrowth = preload("res://sim/flora_growth.gd")
const Clock = preload("res://sim/game_clock.gd")

const TICKS_PER_YEAR := Clock.TICKS_PER_DAY * Clock.DAYS_PER_YEAR

var _defs: Node


func _init() -> void:
	_defs = DefsScript.new()
	_defs.load_dir("res://data")


func cleanup() -> void:
	_defs.free()


## Луг размером size; в нём поляна (x0..x1, y0..y1), остальное — лес.
func _clearing(size: int, clearing: Rect2i, biome: String = "meadow") -> WorldData:
	var w := WorldData.new(size, size)
	w.heights.fill(100)
	w.biomes.fill(_defs.biome_index(biome))
	w.floras.fill(_defs.flora_index("broadleaf"))
	for y in range(clearing.position.y, clearing.end.y):
		for x in range(clearing.position.x, clearing.end.x):
			w.floras[w.index(x, y)] = -1
	return w


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _overgrown(w: WorldData, r: Rect2i) -> float:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if w.floras[w.index(x, y)] >= 0:
				n += 1
	return float(n) / r.get_area()


func test_portion_not_whole_world(t) -> void:
	for size in [128, 256, 576]:
		var g := FloraGrowth.new(WorldData.new(size, size), _defs, _rng(1))
		t.ok(g.cells_per_tick > 0, "%d: порция больше нуля" % size)
		t.ok(g.cells_per_tick * 20 < size * size, "%d: за тик проверяется меньше 5%% мира (%d)" % [size, g.cells_per_tick])
	# Шаги тика вместе дают ровно порцию тика.
	var w := WorldData.new(64, 64)
	var g := FloraGrowth.new(w, _defs, _rng(1))
	var r1 := _rng(5)
	var r2 := _rng(5)
	g.rng = r1
	for s in range(1, Clock.STEPS_PER_TICK + 1):
		g.on_step(s)
	g.rng = r2
	g.run_tick()
	t.eq(r1.state, r2.state, "10 шагов = один тик")


func test_meadow_overgrows_in_few_years(t) -> void:
	# Поляна 16×16 в лесу. На ×5 игровой год идёт 144 секунды.
	var clearing := Rect2i(24, 24, 16, 16)
	var w := _clearing(64, clearing)
	var g := FloraGrowth.new(w, _defs, _rng(7))
	var years := 0
	var share := 0.0
	var after_one := 0.0
	while years < 10 and share < 0.95:
		for k in TICKS_PER_YEAR:
			g.run_tick()
		years += 1
		share = _overgrown(w, clearing)
		if years == 1:
			after_one = share
	t.ok(after_one > 0.05 and after_one < 0.9, "за год луг зарастает заметно, но не сразу (%.2f)" % after_one)
	t.ok(share >= 0.95, "луг зарос за %d лет (%.2f)" % [years, share])
	t.ok(years >= 2 and years <= 6, "зарастание заняло несколько лет: %d" % years)


func test_forest_does_not_go_everywhere(t) -> void:
	var w := _clearing(32, Rect2i(8, 0, 24, 32))
	var bush: int = _defs.flora_index("bush")
	for y in 32:
		w.heights[w.index(10, y)] = -100          # пролив
		w.biomes[w.index(10, y)] = -1
		w.flags[w.index(9, y)] = WorldData.FLAG_RIVER  # река
		w.floras[w.index(8, y)] = bush              # кусты
		w.building_ids[w.index(11, y)] = 3          # здания (на будущее)
	var g := FloraGrowth.new(w, _defs, _rng(3))
	for k in TICKS_PER_YEAR * 5:
		g.run_tick()
	for y in 32:
		t.eq(w.floras[w.index(8, y)], bush, "кусты не вытеснены")
		t.eq(w.floras[w.index(9, y)], -1, "в реку лес не идёт")
		t.eq(w.floras[w.index(10, y)], -1, "в воду лес не идёт")
		t.eq(w.floras[w.index(11, y)], -1, "на здание лес не идёт")
	t.eq(_overgrown(w, Rect2i(12, 0, 20, 32)), 0.0, "за преградой лес не появился")


func test_spread_speed_from_biomes_json(t) -> void:
	# В степи лиственный лес идёт куда медленнее, чем на лугу.
	var r := Rect2i(24, 24, 16, 16)
	var meadow := _clearing(64, r, "meadow")
	var steppe := _clearing(64, r, "steppe")
	var gm := FloraGrowth.new(meadow, _defs, _rng(11))
	var gs := FloraGrowth.new(steppe, _defs, _rng(11))
	for k in TICKS_PER_YEAR:
		gm.run_tick()
		gs.run_tick()
	t.ok(_overgrown(meadow, r) > _overgrown(steppe, r) * 3, "луг %.2f, степь %.2f" % [_overgrown(meadow, r), _overgrown(steppe, r)])


func test_same_seed_same_forest(t) -> void:
	var a := _clearing(64, Rect2i(10, 10, 40, 40))
	var b := _clearing(64, Rect2i(10, 10, 40, 40))
	var ga := FloraGrowth.new(a, _defs, _rng(99))
	var gb := FloraGrowth.new(b, _defs, _rng(99))
	for k in 2000:
		ga.run_tick()
		gb.run_tick()
	t.ok(a.equals(b), "один сид — один лес")


func test_growth_writes_flora_log(t) -> void:
	var w := _clearing(64, Rect2i(10, 10, 40, 40))
	var g := FloraGrowth.new(w, _defs, _rng(4))
	w.take_dirty_chunks()
	var grown := 0
	for k in 500:
		grown += g.run(g.cells_per_tick)
	t.ok(grown > 0, "лес вырос")
	t.eq(w.flora_log_end, grown, "каждое изменение флоры записано в журнал")
	t.ok(not w.has_dirty_chunks(), "рост не заставляет перерисовывать землю")
