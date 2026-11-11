extends RefCounted
## Тесты палитры бога: кисти всех размеров, река без разрывов, отмена.

const DefsScript = preload("res://sim/defs.gd")
const WorldData = preload("res://sim/world_data.gd")
const GodPalette = preload("res://sim/god_palette.gd")

## Сколько клеток в круге кисти каждого размера.
const DISC := {1: 1, 3: 9, 5: 21, 9: 69}

var _defs: Node


func _init() -> void:
	_defs = DefsScript.new()
	_defs.load_dir("res://data")


func cleanup() -> void:
	_defs.free()


## Ровный луг на высоте 100.
func _world(size: int = 128) -> WorldData:
	var w := WorldData.new(size, size)
	w.heights.fill(100)
	w.biomes.fill(_defs.biome_index("meadow"))
	w.moistures.fill(500)
	w.take_dirty_chunks()
	return w


func _snapshot(w: WorldData) -> Array:
	return [w.heights.duplicate(), w.biomes.duplicate(), w.floras.duplicate(), w.resources.duplicate(), w.flags.duplicate()]


func _count_changed(a: Array, b: Array) -> int:
	var n := 0
	for i in (a[0] as PackedInt32Array).size():
		for l in a.size():
			if a[l][i] != b[l][i]:
				n += 1
				break
	return n


func _dab(p: GodPalette, tool: String, size: int, arg: String, x: int, y: int) -> String:
	var err := p.begin_stroke(tool, size, arg)
	if err == "":
		p.stroke_to(x, y)
		p.end_stroke()
	return err


func test_every_brush_every_size(t) -> void:
	var cases := {
		"raise": "", "lower": "", "level": "", "water": "", "river": "",
		"biome": "forest", "vein": "gold", "flora": "conifer",
	}
	for tool in cases:
		for size in DISC:
			var w := _world()
			if tool == "level":
				w.heights[w.index(30, 30)] = 300  # центр мазка выше — ровняем по нему
			var p := GodPalette.new(w, _defs)
			var before := _snapshot(w)
			t.eq(_dab(p, tool, size, cases[tool], 30, 30), "", "%s %d: мазок начат" % [tool, size])
			var changed := _count_changed(before, _snapshot(w))
			var expected: int = DISC[size] - (1 if tool == "level" else 0)
			t.eq(changed, expected, "%s размер %d: изменено клеток" % [tool, size])
			var none: bool = tool == "flora" or expected == 0
			t.eq(w.take_dirty_chunks(), PackedInt32Array() if none else PackedInt32Array([0]),
				"%s размер %d: помечен только тронутый чанк" % [tool, size])
	# ластик: сначала ставим, потом стираем
	for size in DISC:
		var w := _world()
		var p := GodPalette.new(w, _defs)
		_dab(p, "flora", 9, "bush", 60, 60)
		_dab(p, "vein", 9, "coal", 60, 60)
		_dab(p, "erase", size, "", 60, 60)
		var left := 0
		for i in w.cell_count():
			if w.floras[i] >= 0:
				left += 1
		t.eq(left, DISC[9] - DISC[size], "ластик размер %d стёр свой круг" % size)


func test_dirty_rect_is_small(t) -> void:
	var w := _world(576)
	var p := GodPalette.new(w, _defs)
	_dab(p, "raise", 9, "", 100, 100)
	var rects := w.take_dirty_rects()
	t.eq(rects.size(), 1, "один чанк")
	t.eq(rects[0], Rect2i(95, 95, 11, 11), "перерисуется только круг кисти и кромка вокруг")


func test_raise_lower_water_level(t) -> void:
	var w := _world()
	var p := GodPalette.new(w, _defs)
	var step: int = _defs.palette["raise_step"]
	var i := w.index(30, 30)
	_dab(p, "raise", 1, "", 30, 30)
	t.eq(w.heights[i], 100 + step, "поднять")
	# Мазок туда-сюда по одной клетке поднимает её один раз.
	p.begin_stroke("raise", 1)
	for k in 5:
		p.stroke_to(30, 30)
		p.stroke_to(31, 30)
	p.end_stroke()
	t.eq(w.heights[i], 100 + 2 * step, "клетка меняется раз за мазок")
	_dab(p, "flora", 1, "broadleaf", 40, 40)
	_dab(p, "vein", 1, "iron_ore", 40, 40)
	_dab(p, "water", 1, "", 40, 40)
	var j := w.index(40, 40)
	t.ok(w.heights[j] < 0, "залить водой")
	t.eq([w.biomes[j], w.floras[j], w.resources[j]], [-1, -1, -1], "под водой нет биома, флоры и жилы")
	# Подняли со дна — биом от соседней суши.
	for k in 3:
		_dab(p, "raise", 1, "", 40, 40)
	t.ok(w.heights[j] >= 0, "снова суша")
	t.eq(w.biomes[j], _defs.biome_index("meadow"), "биом взят у соседей")
	# Выровнять: по высоте клетки, где мазок начался.
	w.heights[w.index(10, 10)] = 250
	p.begin_stroke("level", 3)
	p.stroke_to(10, 10)
	p.stroke_to(20, 10)
	p.end_stroke()
	for x in range(9, 22):
		t.eq(w.heights[w.index(x, 10)], 250, "выровнено (%d, 10)" % x)
	_dab(p, "lower", 1, "", 70, 70)
	t.eq(w.heights[w.index(70, 70)], 100 - int(_defs.palette["lower_step"]), "опустить")


func test_river_is_continuous(t) -> void:
	var w := _world()
	var p := GodPalette.new(w, _defs)
	# Быстрый палец: между событиями касания большие прыжки.
	var pts := [Vector2i(3, 5), Vector2i(40, 21), Vector2i(41, 90), Vector2i(120, 100), Vector2i(60, 3)]
	p.begin_stroke("river", 1)
	for q in pts:
		p.stroke_to(q.x, q.y)
	p.end_stroke()
	var river := 0
	for i in w.cell_count():
		if w.flags[i] & WorldData.FLAG_RIVER:
			river += 1
	# Все клетки реки связаны по сторонам с началом.
	var seen := {}
	var queue: Array[Vector2i] = [pts[0]]
	seen[pts[0]] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for n in w.neighbors4(c.x, c.y):
			if not seen.has(n) and w.is_river(n.x, n.y):
				seen[n] = true
				queue.append(n)
	t.ok(river > 200, "река проведена (%d клеток)" % river)
	t.eq(seen.size(), river, "река непрерывна по сторонам клеток")
	for q in pts:
		t.ok(seen.has(q), "точка %s на реке" % q)
	# Широкая кисть тоже без разрывов.
	var w2 := _world()
	var p2 := GodPalette.new(w2, _defs)
	p2.begin_stroke("river", 5)
	p2.stroke_to(10, 10)
	p2.stroke_to(110, 60)
	p2.end_stroke()
	for x in range(10, 111):
		var y := 10 + int(round((x - 10) * 0.5))
		t.ok(w2.is_river(x, y), "широкая река: клетка (%d, %d)" % [x, y])


func test_river_stops_at_sea(t) -> void:
	var w := _world()
	for x in range(64, 128):
		for y in 128:
			w.heights[w.index(x, y)] = -200
			w.biomes[w.index(x, y)] = -1
	var p := GodPalette.new(w, _defs)
	_dab(p, "river", 3, "", 64, 64)
	t.ok(not w.is_river(65, 64), "в море реки нет")
	t.eq(w.heights[w.index(65, 64)], -200, "море не тронуто")
	t.ok(w.is_river(63, 64), "на суше река есть")


func test_reed_on_river_trees_not(t) -> void:
	var w := _world()
	var p := GodPalette.new(w, _defs)
	_dab(p, "flora", 5, "broadleaf", 50, 50)
	_dab(p, "river", 1, "", 50, 50)
	t.eq(w.floras[w.index(50, 50)], -1, "река смыла дерево")
	_dab(p, "flora", 1, "broadleaf", 50, 50)
	t.eq(w.floras[w.index(50, 50)], -1, "дерево в реку не сажается")
	_dab(p, "flora", 1, "reed", 50, 50)
	t.eq(w.floras[w.index(50, 50)], _defs.flora_index("reed"), "камыш в реке растёт")


func test_bad_arguments(t) -> void:
	var p := GodPalette.new(_world(), _defs)
	t.has_text(p.begin_stroke("dig", 3), "Нет инструмента", "неизвестный инструмент")
	t.has_text(p.begin_stroke("raise", 4), "Размер кисти", "размер не из списка")
	t.has_text(p.begin_stroke("vein", 3, "wood"), "Неизвестный вариант", "дерево — не жила")
	t.has_text(p.begin_stroke("flora", 3, "oak"), "Неизвестный вариант", "нет такого растения")
	t.ok(not p.is_stroking(), "мазок не начат")


func test_undo_restores_land_and_flora(t) -> void:
	var w := _world()
	w.floras[w.index(5, 5)] = 0
	var p := GodPalette.new(w, _defs)
	var start := _snapshot(w)
	var tools := [["raise", ""], ["flora", "berries"], ["water", ""], ["river", ""], ["biome", "swamp"],
		["vein", "sulfur"], ["lower", ""], ["level", ""], ["erase", ""], ["flora", "conifer"]]
	for k in tools.size():
		p.begin_stroke(tools[k][0], [1, 3, 5, 9][k % 4], tools[k][1])
		p.stroke_to(5 + k * 7, 5)
		p.stroke_to(5 + k * 9, 60)
		p.stroke_to(4, 4)
		p.end_stroke()
	t.eq(p.undo_count(), 10, "10 мазков в истории")
	t.ok(_count_changed(start, _snapshot(w)) > 0, "мир изменён")
	for k in 10:
		t.ok(p.undo(), "отмена %d" % (k + 1))
	t.ok(not p.undo(), "больше отменять нечего")
	t.eq(_count_changed(start, _snapshot(w)), 0, "земля и флора вернулись как были")


func test_undo_keeps_last_ten(t) -> void:
	var w := _world()
	var p := GodPalette.new(w, _defs)
	for k in 12:
		_dab(p, "raise", 1, "", 10 + k, 10)
	t.eq(p.undo_count(), int(_defs.palette["undo_strokes"]), "хранится не больше 10")
	while p.undo():
		pass
	t.ok(w.heights[w.index(10, 10)] > 100 and w.heights[w.index(11, 10)] > 100, "первые два мазка остались")
	t.eq(w.heights[w.index(12, 10)], 100, "третий отменён")
	# Пустой мазок (биом на воде) не занимает место в истории.
	w.heights[w.index(90, 90)] = -50
	_dab(p, "biome", 1, "forest", 90, 90)
	t.eq(p.undo_count(), 0, "пустой мазок не записан")


func test_cancel_stroke(t) -> void:
	var w := _world()
	var p := GodPalette.new(w, _defs)
	var start := _snapshot(w)
	p.begin_stroke("water", 9)
	p.stroke_to(20, 20)
	p.stroke_to(80, 70)
	p.cancel_stroke()
	t.eq(_count_changed(start, _snapshot(w)), 0, "отменённый мазок ничего не оставил")
	t.eq(p.undo_count(), 0, "и в историю не попал")


func test_same_commands_same_world(t) -> void:
	var a := _world()
	var b := _world()
	for w in [a, b]:
		var p := GodPalette.new(w, _defs)
		p.begin_stroke("raise", 5)
		p.stroke_to(3, 3)
		p.stroke_to(90, 40)
		p.end_stroke()
		_dab(p, "flora", 9, "wild_grain", 30, 80)
		p.undo()
		_dab(p, "river", 3, "", 100, 100)
	t.ok(a.equals(b), "одни команды — один мир")
