extends RefCounted
## Тесты слоёв мира: индексы, соседи, зоны, чанки, пометки изменений.

const WorldData = preload("res://sim/world_data.gd")


func test_size_and_defaults(t) -> void:
	var w := WorldData.new(100, 70)
	t.eq(w.cell_count(), 7000, "клеток")
	t.eq(w.heights.size(), 7000, "слой высот")
	t.eq(w.biomes[0], WorldData.NONE, "биом пустой")
	t.eq(w.owners[6999], WorldData.NONE, "владельца нет")
	t.eq(w.floras[10], WorldData.NONE, "флоры нет")
	t.eq(w.resources[10], WorldData.NONE, "жилы нет")
	t.eq(w.building_ids[10], WorldData.NONE, "здания нет")
	t.eq(w.flags[10], 0, "флагов нет")
	t.eq(WorldData.LAYERS.size(), 8, "7 слоёв правила 3 + flags")
	t.eq(w.chunks_x, 2, "чанков по x (100/64 вверх)")
	t.eq(w.zones_y, 9, "зон по y (70/8 вверх)")


func test_index_and_pos(t) -> void:
	var w := WorldData.new(50, 40)
	t.eq(w.index(3, 2), 103, "x + y × ширина")
	t.eq(w.pos_of(103), Vector2i(3, 2), "обратно")
	t.ok(w.in_bounds(49, 39) and not w.in_bounds(50, 0) and not w.in_bounds(0, -1), "границы")


func test_neighbors(t) -> void:
	var w := WorldData.new(10, 10)
	t.eq(w.neighbors4(0, 0).size(), 2, "угол: 2 соседа по сторонам")
	t.eq(w.neighbors8(0, 0).size(), 3, "угол: 3 соседа вокруг")
	t.eq(w.neighbors4(5, 5).size(), 4, "середина: 4")
	t.eq(w.neighbors8(5, 0).size(), 5, "край: 5")
	t.eq(w.neighbor_indices4(w.index(9, 9)), PackedInt32Array([w.index(9, 8), w.index(8, 9)]), "индексы соседей угла")


func test_zones(t) -> void:
	var w := WorldData.new(20, 20)
	t.eq(w.zone_count(), 9, "зон 3×3")
	t.eq(w.zone_of(9, 17), 1 + 2 * 3, "зона клетки")
	t.eq(w.zone_rect(8), Rect2i(16, 16, 4, 4), "последняя зона обрезана краем")


func test_set_value_and_get_cell(t) -> void:
	var w := WorldData.new(16, 16)
	w.set_value("height", 3, 4, 5000)
	w.set_value("biome", 3, 4, 2)
	t.eq(w.get_height(3, 4), WorldData.HEIGHT_MAX, "высота ограничена")
	var c := w.get_cell(3, 4)
	t.eq(c["biome"], 2, "биом в get_cell")
	t.eq(w.get_value("biome", 3, 4), 2, "get_value")


func test_dirty_chunks(t) -> void:
	var w := WorldData.new(200, 130)
	t.eq(w.take_dirty_chunks().size(), w.chunk_count(), "новый мир весь «грязный»")
	t.ok(not w.has_dirty_chunks(), "пометки сняты")
	w.set_value("height", 10, 10, 5)
	t.eq(w.take_dirty_chunks(), PackedInt32Array([0]), "правка внутри чанка — только он")
	w.set_value("height", 64, 10, 5)
	t.eq(w.take_dirty_chunks(), PackedInt32Array([0, 1]), "правка на краю — и сосед (тень и кромка)")
	w.mark_all_dirty()
	t.eq(w.take_dirty_chunks(4).size(), 4, "за раз не больше 4 чанков")
	t.ok(w.has_dirty_chunks(), "остальные ждут следующего кадра")
	t.eq(w.take_dirty_chunks().size(), w.chunk_count() - 4, "потом отдаются остальные")
	t.eq(w.chunk_rect(w.chunk_count() - 1), Rect2i(192, 128, 8, 2), "последний чанк обрезан")


func test_dict_roundtrip_and_errors(t) -> void:
	var a := WorldData.new(12, 9)
	a.set_value("resource", 1, 1, 3)
	a.set_value("flora", 5, 5, 1)
	a.set_value("building_id", 6, 6, 7)
	a.set_value("flags", 2, 2, WorldData.FLAG_RIVER)
	var b := WorldData.new()
	t.eq(b.from_dict(a.to_dict()), "", "загрузка без ошибки")
	t.ok(a.equals(b), "миры совпали")
	t.ok(b.is_river(2, 2), "река на месте")
	var bad := a.to_dict()
	bad["layers"]["height"] = PackedInt32Array([1, 2])
	t.has_text(b.from_dict(bad), "world.layers.height", "неверный размер слоя")


func test_old_save_without_layers_opens(t) -> void:
	# Как старое сохранение, где слоёв flora и building_id ещё не было (правило 12).
	var a := WorldData.new(10, 10)
	a.set_value("height", 2, 3, 400)
	var d := a.to_dict()
	d["layers"].erase("flora")
	d["layers"].erase("building_id")
	var b := WorldData.new()
	t.eq(b.from_dict(d), "", "загрузка без ошибки")
	t.eq(b.get_height(2, 3), 400, "высота на месте")
	t.eq(b.floras[0], WorldData.NONE, "flora по умолчанию -1")
	t.eq(b.building_ids[99], WorldData.NONE, "building_id по умолчанию -1")
