extends RefCounted
## Данные мира: клетки, зоны 8×8, чанки 64×64.
##
## Каждый слой — PackedInt32Array размером width × height, клетка (x, y)
## лежит по индексу x + y × width (docs/RESEARCH.md, «Архитектура»).
## Слои:
##   height   — высота: -1000..-1 вода, 0 уровень моря, 1..1000 суша;
##   moisture — влажность 0..1000;
##   biome    — номер биома в Defs.biome_ids, -1 для воды;
##   deposit  — номер ресурса жилы в Defs.resource_ids, -1 если жилы нет;
##   flags    — битовые флаги (FLAG_RIVER — река);
##   owner    — номер королевства-владельца, -1 если ничьё.
##
## Любая правка через set_* помечает чанк «грязным», а WorldView
## перерисовывает только такие чанки.

const CHUNK_SIZE := 64
const ZONE_SIZE := 8

const LAYERS: Array[String] = ["height", "moisture", "biome", "deposit", "flags", "owner"]
const FLAG_RIVER := 1
const NONE := -1

const HEIGHT_MIN := -1000
const HEIGHT_MAX := 1000

var width: int = 0
var height: int = 0

var heights := PackedInt32Array()
var moistures := PackedInt32Array()
var biomes := PackedInt32Array()
var deposits := PackedInt32Array()
var flags := PackedInt32Array()
var owners := PackedInt32Array()

var chunks_x: int = 0
var chunks_y: int = 0
var zones_x: int = 0
var zones_y: int = 0

var _dirty := PackedByteArray()
var _dirty_count: int = 0


func _init(w: int = 0, h: int = 0) -> void:
	if w > 0 and h > 0:
		resize(w, h)


## Создаёт пустой мир: всё вода глубиной 0, без биомов, жил и владельцев.
func resize(w: int, h: int) -> void:
	width = w
	height = h
	var n := w * h
	heights = PackedInt32Array()
	heights.resize(n)
	moistures = PackedInt32Array()
	moistures.resize(n)
	biomes = _filled(n, NONE)
	deposits = _filled(n, NONE)
	flags = PackedInt32Array()
	flags.resize(n)
	owners = _filled(n, NONE)
	chunks_x = ceili(float(w) / CHUNK_SIZE)
	chunks_y = ceili(float(h) / CHUNK_SIZE)
	zones_x = ceili(float(w) / ZONE_SIZE)
	zones_y = ceili(float(h) / ZONE_SIZE)
	_dirty = PackedByteArray()
	_dirty.resize(chunks_x * chunks_y)
	_dirty_count = 0
	mark_all_dirty()


func cell_count() -> int:
	return width * height


# --- Клетки ---------------------------------------------------------------

func index(x: int, y: int) -> int:
	return x + y * width


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func pos_of(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func get_height(x: int, y: int) -> int:
	return heights[x + y * width]


func get_biome(x: int, y: int) -> int:
	return biomes[x + y * width]


func is_water(x: int, y: int) -> bool:
	return heights[x + y * width] < 0


func is_river(x: int, y: int) -> bool:
	return flags[x + y * width] & FLAG_RIVER != 0


## Все слои клетки одним словарём (для лупы и отладки).
func get_cell(x: int, y: int) -> Dictionary:
	var i := index(x, y)
	return {
		"x": x, "y": y,
		"height": heights[i], "moisture": moistures[i], "biome": biomes[i],
		"deposit": deposits[i], "flags": flags[i], "owner": owners[i],
	}


## Меняет один слой клетки по имени ("height", "biome", ...) и помечает чанк.
func set_value(layer: String, x: int, y: int, value: int) -> void:
	var i := index(x, y)
	match layer:
		"height": heights[i] = clampi(value, HEIGHT_MIN, HEIGHT_MAX)
		"moisture": moistures[i] = value
		"biome": biomes[i] = value
		"deposit": deposits[i] = value
		"flags": flags[i] = value
		"owner": owners[i] = value
		_:
			push_error("WorldData.set_value: нет слоя \"%s\"" % layer)
			return
	mark_dirty(x, y)


func get_value(layer: String, x: int, y: int) -> int:
	var i := index(x, y)
	match layer:
		"height": return heights[i]
		"moisture": return moistures[i]
		"biome": return biomes[i]
		"deposit": return deposits[i]
		"flags": return flags[i]
		"owner": return owners[i]
	push_error("WorldData.get_value: нет слоя \"%s\"" % layer)
	return 0


# --- Соседи ---------------------------------------------------------------

const DIRS4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRS8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


## Соседи по сторонам (север, восток, юг, запад), только внутри мира.
func neighbors4(x: int, y: int) -> Array[Vector2i]:
	return _neighbors(x, y, DIRS4)


## Соседи по сторонам и диагоналям, только внутри мира.
func neighbors8(x: int, y: int) -> Array[Vector2i]:
	return _neighbors(x, y, DIRS8)


## Индексы соседей по сторонам (для быстрых циклов).
func neighbor_indices4(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := i % width
	var y := i / width
	if y > 0: out.append(i - width)
	if x < width - 1: out.append(i + 1)
	if y < height - 1: out.append(i + width)
	if x > 0: out.append(i - 1)
	return out


func _neighbors(x: int, y: int, dirs: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in dirs:
		var nx := x + d.x
		var ny := y + d.y
		if nx >= 0 and ny >= 0 and nx < width and ny < height:
			out.append(Vector2i(nx, ny))
	return out


# --- Зоны 8×8 (из них складываются территории королевств) -----------------

func zone_count() -> int:
	return zones_x * zones_y


func zone_of(x: int, y: int) -> int:
	return (x / ZONE_SIZE) + (y / ZONE_SIZE) * zones_x


func zone_rect(zone: int) -> Rect2i:
	var zx := (zone % zones_x) * ZONE_SIZE
	var zy := (zone / zones_x) * ZONE_SIZE
	return Rect2i(zx, zy, mini(ZONE_SIZE, width - zx), mini(ZONE_SIZE, height - zy))


# --- Чанки 64×64 (перерисовка и сохранение) -------------------------------

func chunk_count() -> int:
	return chunks_x * chunks_y


func chunk_of(x: int, y: int) -> int:
	return (x / CHUNK_SIZE) + (y / CHUNK_SIZE) * chunks_x


func chunk_rect(chunk: int) -> Rect2i:
	var cx := (chunk % chunks_x) * CHUNK_SIZE
	var cy := (chunk / chunks_x) * CHUNK_SIZE
	return Rect2i(cx, cy, mini(CHUNK_SIZE, width - cx), mini(CHUNK_SIZE, height - cy))


## Помечает чанк клетки (x, y). Клетки на краю чанка меняют тень и кромку
## у соседей, поэтому помечаются и соседние чанки.
func mark_dirty(x: int, y: int) -> void:
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if in_bounds(nx, ny):
			_mark_chunk(chunk_of(nx, ny))


func mark_all_dirty() -> void:
	for c in chunk_count():
		_mark_chunk(c)


func has_dirty_chunks() -> bool:
	return _dirty_count > 0


## Отдаёт список изменённых чанков и снимает пометки.
func take_dirty_chunks() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _dirty_count == 0:
		return out
	for c in _dirty.size():
		if _dirty[c] != 0:
			out.append(c)
			_dirty[c] = 0
	_dirty_count = 0
	return out


func _mark_chunk(c: int) -> void:
	if _dirty[c] == 0:
		_dirty[c] = 1
		_dirty_count += 1


# --- Сравнение и сохранение -----------------------------------------------

func equals(other) -> bool:
	return other != null and width == other.width and height == other.height \
		and heights == other.heights and moistures == other.moistures \
		and biomes == other.biomes and deposits == other.deposits \
		and flags == other.flags and owners == other.owners


func to_dict() -> Dictionary:
	return {
		"width": width, "height": height,
		"layers": {
			"height": heights, "moisture": moistures, "biome": biomes,
			"deposit": deposits, "flags": flags, "owner": owners,
		},
	}


## Заполняет мир из словаря. Возвращает текст ошибки или "".
func from_dict(data: Dictionary) -> String:
	var w = data.get("width")
	var h = data.get("height")
	if not (w is int and h is int) or w <= 0 or h <= 0:
		return "world: неверный размер мира %s × %s" % [str(w), str(h)]
	var layers = data.get("layers")
	if not layers is Dictionary:
		return "world: нет раздела layers"
	for name in LAYERS:
		var arr = layers.get(name)
		if not arr is PackedInt32Array:
			return "world.layers.%s: слой отсутствует или не того типа" % name
		if arr.size() != w * h:
			return "world.layers.%s: размер %d, а должен быть %d" % [name, arr.size(), w * h]
	resize(w, h)
	heights = layers["height"]
	moistures = layers["moisture"]
	biomes = layers["biome"]
	deposits = layers["deposit"]
	flags = layers["flags"]
	owners = layers["owner"]
	mark_all_dirty()
	return ""


static func _filled(n: int, v: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	a.fill(v)
	return a
