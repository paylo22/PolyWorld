extends RefCounted
## Данные мира: клетки, зоны 8×8, чанки 64×64.
##
## Каждый слой — PackedInt32Array размером width × height, клетка (x, y)
## лежит по индексу x + y × width (docs/RESEARCH.md, «Архитектура»).
## Слои:
##   height   — высота: -1000..-1 вода, 0 уровень моря, 1..1000 суша;
##   moisture — влажность 0..1000;
##   biome    — номер биома в Defs.biome_ids, -1 для воды;
##   flora    — растение на клетке, -1 если пусто (заполняется с этапа 2);
##   resource — номер ресурса жилы в Defs.resource_ids, -1 если жилы нет;
##   owner    — номер королевства-владельца, -1 если ничьё;
##   building_id — номер здания на клетке, -1 если нет (с этапа 4);
##   flags    — битовые флаги (FLAG_RIVER — река).
## Слои по правилу 3 CLAUDE.md; flags — дополнительно, для рек.
##
## Любая правка через set_* помечает чанк «грязным», а WorldView
## перерисовывает только такие чанки.

const CHUNK_SIZE := 64
const ZONE_SIZE := 8

const LAYERS: Array[String] = ["height", "moisture", "biome", "flora", "resource", "owner", "building_id", "flags"]
## Чем заполняется слой в новом мире и в старом сохранении, где слоя ещё не было.
const LAYER_DEFAULTS := {"height": 0, "moisture": 0, "biome": -1, "flora": -1, "resource": -1, "owner": -1, "building_id": -1, "flags": 0}
const FLAG_RIVER := 1
const NONE := -1

const HEIGHT_MIN := -1000
const HEIGHT_MAX := 1000

var width: int = 0
var height: int = 0

var heights := PackedInt32Array()
var moistures := PackedInt32Array()
var biomes := PackedInt32Array()
var floras := PackedInt32Array()
var resources := PackedInt32Array()
var owners := PackedInt32Array()
var building_ids := PackedInt32Array()
var flags := PackedInt32Array()

var chunks_x: int = 0
var chunks_y: int = 0
var zones_x: int = 0
var zones_y: int = 0

var _dirty := PackedByteArray()
var _dirty_count: int = 0


func _init(w: int = 0, h: int = 0) -> void:
	if w > 0 and h > 0:
		resize(w, h)


## Создаёт пустой мир: все слои заполнены значениями из LAYER_DEFAULTS.
func resize(w: int, h: int) -> void:
	width = w
	height = h
	var n := w * h
	for name in LAYERS:
		_set_layer(name, _filled(n, LAYER_DEFAULTS[name]))
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
	var out := {"x": x, "y": y}
	for name in LAYERS:
		out[name] = get_layer(name)[i]
	return out


## Меняет один слой клетки по имени ("height", "biome", ...) и помечает чанк.
func set_value(layer: String, x: int, y: int, value: int) -> void:
	if not LAYER_DEFAULTS.has(layer):
		push_error("WorldData.set_value: нет слоя \"%s\"" % layer)
		return
	if layer == "height":
		value = clampi(value, HEIGHT_MIN, HEIGHT_MAX)
	get_layer(layer)[index(x, y)] = value
	mark_dirty(x, y)


func get_value(layer: String, x: int, y: int) -> int:
	if not LAYER_DEFAULTS.has(layer):
		push_error("WorldData.get_value: нет слоя \"%s\"" % layer)
		return 0
	return get_layer(layer)[index(x, y)]


## Массив слоя по имени. Packed-массивы передаются по ссылке: запись в него
## меняет мир (но не помечает чанки — для этого set_value или mark_dirty).
func get_layer(layer: String) -> PackedInt32Array:
	match layer:
		"height": return heights
		"moisture": return moistures
		"biome": return biomes
		"flora": return floras
		"resource": return resources
		"owner": return owners
		"building_id": return building_ids
		"flags": return flags
	push_error("WorldData.get_layer: нет слоя \"%s\"" % layer)
	return PackedInt32Array()


func _set_layer(layer: String, arr: PackedInt32Array) -> void:
	match layer:
		"height": heights = arr
		"moisture": moistures = arr
		"biome": biomes = arr
		"flora": floras = arr
		"resource": resources = arr
		"owner": owners = arr
		"building_id": building_ids = arr
		"flags": flags = arr


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


## Отдаёт изменённые чанки (не больше limit, если limit > 0) и снимает
## с них пометку. Остальные остаются помеченными до следующего вызова.
func take_dirty_chunks(limit: int = 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _dirty_count == 0:
		return out
	for c in _dirty.size():
		if _dirty[c] != 0:
			out.append(c)
			_dirty[c] = 0
			_dirty_count -= 1
			if limit > 0 and out.size() >= limit:
				break
	return out


func _mark_chunk(c: int) -> void:
	if _dirty[c] == 0:
		_dirty[c] = 1
		_dirty_count += 1


# --- Сравнение и сохранение -----------------------------------------------

func equals(other) -> bool:
	if other == null or width != other.width or height != other.height:
		return false
	for name in LAYERS:
		if get_layer(name) != other.get_layer(name):
			return false
	return true


func to_dict() -> Dictionary:
	var layers := {}
	for name in LAYERS:
		layers[name] = get_layer(name)
	return {"width": width, "height": height, "layers": layers}


## Заполняет мир из словаря. Возвращает текст ошибки или "".
## Слой, которого нет в словаре (старое сохранение), заполняется значением
## по умолчанию — так старые сохранения открываются (правило 12).
func from_dict(data: Dictionary) -> String:
	var w = data.get("width")
	var h = data.get("height")
	if not (w is int and h is int) or w <= 0 or h <= 0:
		return "world: неверный размер мира %s × %s" % [str(w), str(h)]
	var layers = data.get("layers", {})
	if not layers is Dictionary:
		return "world: раздел layers не того типа"
	for name in LAYERS:
		if not layers.has(name):
			continue
		var arr = layers[name]
		if not arr is PackedInt32Array:
			return "world.layers.%s: слой не того типа" % name
		if arr.size() != w * h:
			return "world.layers.%s: размер %d, а должен быть %d" % [name, arr.size(), w * h]
	resize(w, h)
	for name in LAYERS:
		if layers.has(name):
			_set_layer(name, layers[name])
	mark_all_dirty()
	return ""


static func _filled(n: int, v: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	a.fill(v)
	return a
