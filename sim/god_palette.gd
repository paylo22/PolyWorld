extends RefCounted
## Палитра бога: кисти земли и флоры, ластик, отмена мазков
## (docs/RESEARCH.md, «Мир и палитра бога»).
##
## Это команды sim: интерфейс меняет мир только через них.
## Мазок — от касания пальцем до отпускания:
##   begin_stroke(инструмент, размер, вариант) → stroke_to(x, y) много раз → end_stroke().
## stroke_to проводит линию от прошлой точки до новой и ставит вдоль неё
## «печати» кисти — круг диаметром size. Каждая клетка меняется не больше
## одного раза за мазок: держать палец на месте безопасно, а «поднять» за один
## мазок поднимает землю ровно на raise_step.
##
## Для отмены мазок запоминает старые значения всех клеток, которые он менял
## (высота, биом, флора, жила, флаги). Хранятся последние palette.undo_strokes мазков.
## Все числа — из Defs.palette (data/biomes.json).

const WorldData = preload("res://sim/world_data.gd")

## Инструменты-кисти. Лупа — не кисть: она только читает клетку.
const TOOLS: Array[String] = ["raise", "lower", "level", "water", "river", "biome", "vein", "flora", "erase"]
## Каким инструментам нужен вариант (id биома, жилы или растения).
const ARG_TOOLS := {"biome": "биом", "vein": "жила", "flora": "растение"}

## Сколько чисел хранится на клетку для отмены: высота, биом, флора, жила, флаги.
const SAVED := 5

var world: WorldData

var _defs
var _cfg: Dictionary
var _flora_on_river := PackedByteArray()
var _new_land_biome: int = -1

var _undo: Array[Dictionary] = []
var _touched := PackedByteArray()

var _active := false
var _tool := ""
var _arg: int = -1
var _radius: int = 0
var _last := Vector2i.ZERO
var _has_last := false
var _level_h: int = 0
var _cells := PackedInt32Array()
var _old := PackedInt32Array()


func _init(p_world: WorldData, defs) -> void:
	world = p_world
	_defs = defs
	_cfg = defs.palette
	_new_land_biome = defs.biome_index(_cfg["new_land_biome"])
	for id in defs.flora_ids:
		_flora_on_river.append(1 if defs.flora[id]["on_river"] else 0)
	_touched.resize(world.cell_count())


func is_stroking() -> bool:
	return _active


## Сколько мазков можно отменить.
func undo_count() -> int:
	return _undo.size()


## Начинает мазок. arg — id биома (для "biome"), жилы ("vein") или растения ("flora").
## Возвращает текст ошибки или "".
func begin_stroke(tool: String, size: int, arg: String = "") -> String:
	if _active:
		end_stroke()
	if not TOOLS.has(tool):
		return "Нет инструмента \"%s\"" % tool
	var sizes: Array = _cfg["brush_sizes"]
	if not sizes.has(size):
		return "Размер кисти %d недопустим, можно: %s" % [size, str(sizes)]
	var a := -1
	match tool:
		"biome":
			a = _defs.biome_index(arg)
		"vein":
			a = _defs.resource_index(arg) if (_cfg["veins"] as Array).has(arg) else -1
		"flora":
			a = _defs.flora_index(arg)
	if ARG_TOOLS.has(tool) and a < 0:
		return "Неизвестный вариант \"%s\" для инструмента %s (%s)" % [arg, tool, ARG_TOOLS[tool]]
	_active = true
	_tool = tool
	_arg = a
	_radius = (size - 1) / 2
	_has_last = false
	_cells = PackedInt32Array()
	_old = PackedInt32Array()
	return ""


## Ведёт мазок в клетку (x, y): от прошлой точки до этой без пропусков.
func stroke_to(x: int, y: int) -> void:
	if not _active:
		return
	if not _has_last:
		_has_last = true
		_last = Vector2i(x, y)
		if world.in_bounds(x, y):
			_level_h = world.heights[world.index(x, y)]
		else:
			_level_h = world.heights[world.index(clampi(x, 0, world.width - 1), clampi(y, 0, world.height - 1))]
		_stamp(x, y)
		return
	if _last == Vector2i(x, y):
		return
	# Линия по сторонам клеток (без шагов по диагонали): река из кисти 1
	# получается непрерывной. Печати — через каждые radius клеток: круги
	# радиуса r с центрами не дальше r друг от друга сливаются в сплошную полосу.
	var spacing := maxi(1, _radius)
	var x0 := _last.x
	var y0 := _last.y
	var dx := absi(x - x0)
	var dy := absi(y - y0)
	var sx := 1 if x > x0 else -1
	var sy := 1 if y > y0 else -1
	var ix := 0
	var iy := 0
	var cx := x0
	var cy := y0
	var since := 0
	for k in dx + dy:
		if dy == 0 or (dx != 0 and (2 * ix + 1) * dy < (2 * iy + 1) * dx):
			cx += sx
			ix += 1
		else:
			cy += sy
			iy += 1
		since += 1
		if since >= spacing or k == dx + dy - 1:
			_stamp(cx, cy)
			since = 0
	_last = Vector2i(x, y)


## Заканчивает мазок и кладёт его в историю отмены (если он что-то изменил).
func end_stroke() -> void:
	if not _active:
		return
	_active = false
	for i in _cells:
		_touched[i] = 0
	# Оставляем только клетки, которые на самом деле изменились.
	var cells := PackedInt32Array()
	var old := PackedInt32Array()
	for n in _cells.size():
		var i := _cells[n]
		var o := n * SAVED
		if _old[o] != world.heights[i] or _old[o + 1] != world.biomes[i] or _old[o + 2] != world.floras[i] \
				or _old[o + 3] != world.resources[i] or _old[o + 4] != world.flags[i]:
			cells.append(i)
			old.append_array(_old.slice(o, o + SAVED))
	_cells = PackedInt32Array()
	_old = PackedInt32Array()
	if cells.is_empty():
		return
	_undo.append({"cells": cells, "old": old})
	while _undo.size() > int(_cfg["undo_strokes"]):
		_undo.pop_front()


## Отменяет текущий мазок, не кладя его в историю (например, если вторым
## пальцем начали двигать камеру).
func cancel_stroke() -> void:
	if not _active:
		return
	_active = false
	for i in _cells:
		_touched[i] = 0
	_restore(_cells, _old)
	_cells = PackedInt32Array()
	_old = PackedInt32Array()


## Отменяет последний законченный мазок. Возвращает false, если отменять нечего.
func undo() -> bool:
	if _active:
		end_stroke()
	if _undo.is_empty():
		return false
	var u: Dictionary = _undo.pop_back()
	_restore(u["cells"], u["old"])
	return true


# --- Внутреннее -----------------------------------------------------------

func _restore(cells: PackedInt32Array, old: PackedInt32Array) -> void:
	var w := world.width
	for n in cells.size():
		var i := cells[n]
		var o := n * SAVED
		world.heights[i] = old[o]
		world.biomes[i] = old[o + 1]
		world.set_flora(i, old[o + 2])
		world.resources[i] = old[o + 3]
		world.flags[i] = old[o + 4]
		world.mark_dirty(i % w, i / w)


## Круг диаметром size с центром (cx, cy).
func _stamp(cx: int, cy: int) -> void:
	var r := _radius
	var rr := r * r + r
	var w := world.width
	for dy in range(-r, r + 1):
		var y := cy + dy
		if y < 0 or y >= world.height:
			continue
		for dx in range(-r, r + 1):
			var x := cx + dx
			if x < 0 or x >= w or dx * dx + dy * dy > rr:
				continue
			var i := x + y * w
			if _touched[i] != 0:
				continue
			_touched[i] = 1
			_cells.append(i)
			_old.append(world.heights[i])
			_old.append(world.biomes[i])
			_old.append(world.floras[i])
			_old.append(world.resources[i])
			_old.append(world.flags[i])
			_apply(i, x, y)


func _apply(i: int, x: int, y: int) -> void:
	var h := world.heights[i]
	match _tool:
		"raise":
			_set_height(i, x, y, h + int(_cfg["raise_step"]))
		"lower":
			_set_height(i, x, y, h - int(_cfg["lower_step"]))
		"level":
			_set_height(i, x, y, _level_h)
		"water":
			_set_height(i, x, y, mini(h, -int(_cfg["water_depth"])))
		"river":
			if h < 0:
				return  # река кончается у моря или озера
			world.heights[i] = maxi(0, h - int(_cfg["river_cut"]))
			world.flags[i] |= WorldData.FLAG_RIVER
			var f := world.floras[i]
			if f >= 0 and _flora_on_river[f] == 0:
				world.set_flora(i, -1)
			world.mark_dirty(x, y)
		"biome":
			if h >= 0 and world.biomes[i] != _arg:
				world.biomes[i] = _arg
				world.mark_dirty(x, y)
		"vein":
			if h >= 0 and world.resources[i] != _arg:
				world.resources[i] = _arg
				world.mark_dirty(x, y)
		"flora":
			if h < 0:
				return
			if world.flags[i] & WorldData.FLAG_RIVER and _flora_on_river[_arg] == 0:
				return
			world.set_flora(i, _arg)
		"erase":
			world.set_flora(i, -1)
			if world.resources[i] >= 0 or world.flags[i] & WorldData.FLAG_RIVER:
				world.resources[i] = -1
				world.flags[i] &= ~WorldData.FLAG_RIVER
				world.mark_dirty(x, y)


## Меняет высоту. Суша ушла под воду — на клетке не остаётся биома, растений,
## жилы и реки. Вода стала сушей — биом берётся у соседней суши.
func _set_height(i: int, x: int, y: int, new_h: int) -> void:
	new_h = clampi(new_h, WorldData.HEIGHT_MIN, WorldData.HEIGHT_MAX)
	var old_h := world.heights[i]
	if new_h == old_h:
		return
	world.heights[i] = new_h
	if old_h >= 0 and new_h < 0:
		world.biomes[i] = -1
		world.set_flora(i, -1)
		world.resources[i] = -1
		world.flags[i] &= ~WorldData.FLAG_RIVER
	elif old_h < 0 and new_h >= 0:
		world.biomes[i] = _land_biome_near(x, y)
	world.mark_dirty(x, y)


func _land_biome_near(x: int, y: int) -> int:
	for d in WorldData.DIRS8:
		var nx := x + d.x
		var ny := y + d.y
		if world.in_bounds(nx, ny):
			var j := nx + ny * world.width
			if world.heights[j] >= 0 and world.biomes[j] >= 0:
				return world.biomes[j]
	return _new_land_biome
