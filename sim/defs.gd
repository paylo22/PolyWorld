extends Node
## Данные баланса (автозагрузка Defs).
##
## Читает JSON из data/, проверяет по схемам ниже и складывает в словари.
## Все числа баланса живут в data/*.json, а не в коде (CLAUDE.md).
## Если в данных есть ошибка, is_ok() == false, а errors содержит понятные
## сообщения вида
##   data/resources.json: resources[4] «bread».storage — ...
## Главное меню показывает их на экране.

const Schema = preload("res://sim/schema.gd")

const DATA_DIR := "res://data"
const FILES: Array[String] = ["resources.json", "biomes.json"]

const RESOURCE_TYPES: Array[String] = [
	"food_raw",      # еда-сырьё (зерно)
	"intermediate",  # полуфабрикат (мука)
	"food",          # еда (хлеб, мясо, рыба)
	"raw",           # сырьё
	"luxury",        # роскошь
	"material",      # материал
	"fuel",          # топливо
	"goods",         # товар
	"military",      # военное
	"living",        # живое (лошади)
	"money",         # деньги
]

const SCHEMAS := {
	"resources.json": {
		"type": "object",
		"fields": {
			"storages": {"type": "array", "min_items": 1, "item": {
				"type": "object",
				"fields": {
					"id": {"type": "id"},
					"name": {"type": "string"},
					# -1 = без предела; поле можно не указывать, если вместимость задаёт здание.
					"capacity": {"type": "int", "min": -1, "optional": true},
					"note": {"type": "string", "optional": true},
				},
			}},
			"resources": {"type": "array", "min_items": 1, "item": {
				"type": "object",
				"fields": {
					"id": {"type": "id"},
					"name": {"type": "string"},
					"type": {"type": "enum", "values": RESOURCE_TYPES},
					"storage": {"type": "id"},
					"spoils": {"type": "bool", "optional": true},
					"source": {"type": "string"},
					"uses": {"type": "string"},
				},
			}},
		},
	},
	"biomes.json": {
		"type": "object",
		"fields": {
			"materials": {"type": "array", "min_items": 1, "item": {
				"type": "object",
				"fields": {"id": {"type": "id"}, "name": {"type": "string"}},
			}},
			"features": {"type": "array", "item": {
				"type": "object",
				"fields": {"id": {"type": "id"}, "name": {"type": "string"}},
			}},
			"biomes": {"type": "array", "min_items": 1, "item": {
				"type": "object",
				"fields": {
					"id": {"type": "id"},
					"name": {"type": "string"},
					"color": {"type": "color"},
					"resources": {"type": "array", "item": {"type": "id"}},
					"features": {"type": "array", "item": {"type": "id"}},
					"materials": {"type": "array", "min_items": 1, "item": {"type": "id"}},
					"note": {"type": "string", "optional": true},
				},
			}},
		},
	},
}

var errors: PackedStringArray = []

## id → словарь записи. *_ids хранят порядок как в файле.
var storages: Dictionary = {}
var resources: Dictionary = {}
var resource_ids: PackedStringArray = []
var materials: Dictionary = {}
var features: Dictionary = {}
var biomes: Dictionary = {}
var biome_ids: PackedStringArray = []


func _ready() -> void:
	if not load_dir(DATA_DIR):
		for e in errors:
			push_error(e)


func is_ok() -> bool:
	return errors.is_empty()


## Короткий текст всех ошибок для показа на экране.
func get_error_text() -> String:
	return "\n".join(errors)


func get_resource(id: String) -> Dictionary:
	if not resources.has(id):
		push_error("Defs.get_resource: нет ресурса \"%s\"" % id)
		return {}
	return resources[id]


func get_biome(id: String) -> Dictionary:
	if not biomes.has(id):
		push_error("Defs.get_biome: нет биома \"%s\"" % id)
		return {}
	return biomes[id]


## Читает все файлы из папки. Возвращает true, если ошибок нет.
func load_dir(dir: String) -> bool:
	var texts := {}
	for f in FILES:
		var p := dir.path_join(f)
		texts[f] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
	return load_from_texts(texts, dir)


## Разбирает и проверяет тексты файлов {имя: текст}. Нужна и тестам.
## Если хоть в одном файле ошибка, данные не загружаются вовсе.
func load_from_texts(texts: Dictionary, dir: String = DATA_DIR) -> bool:
	_clear()
	var label_dir := dir.trim_prefix("res://").trim_prefix("user://")
	var parsed := {}
	for f in FILES:
		var label := label_dir.path_join(f)
		var text = texts.get(f)
		if text == null:
			errors.append("%s: файл не найден" % label)
			continue
		var json := JSON.new()
		if json.parse(text) != OK:
			errors.append("%s, строка %d: ошибка синтаксиса JSON — %s (проверь запятые, кавычки и скобки)"
				% [label, json.get_error_line() + 1, json.get_error_message()])
			continue
		var file_errors: PackedStringArray = []
		Schema.check(json.data, SCHEMAS[f], "", file_errors)
		for e in file_errors:
			errors.append("%s: %s" % [label, e])
		if file_errors.is_empty():
			parsed[f] = Schema.normalize(json.data, SCHEMAS[f])

	if parsed.has("resources.json"):
		_cross_check_resources(parsed["resources.json"], label_dir.path_join("resources.json"))
	if parsed.has("biomes.json"):
		var res_ids := []
		if parsed.has("resources.json"):
			for r in parsed["resources.json"]["resources"]:
				res_ids.append(r["id"])
		_cross_check_biomes(parsed["biomes.json"], label_dir.path_join("biomes.json"),
			res_ids, parsed.has("resources.json"))

	if not errors.is_empty():
		return false
	_fill(parsed)
	return true


func _clear() -> void:
	errors = []
	storages = {}
	resources = {}
	resource_ids = []
	materials = {}
	features = {}
	biomes = {}
	biome_ids = []


func _cross_check_resources(data: Dictionary, label: String) -> void:
	var storage_ids := _unique_ids(data["storages"], "storages", label)
	_unique_ids(data["resources"], "resources", label)
	var list: Array = data["resources"]
	for i in list.size():
		var r: Dictionary = list[i]
		if not storage_ids.has(r["storage"]):
			errors.append("%s: %s.storage — нет хранилища \"%s\" в списке storages (есть: %s)"
				% [label, Schema.item_path("resources", i, r), r["storage"], ", ".join(PackedStringArray(storage_ids))])


func _cross_check_biomes(data: Dictionary, label: String, res_ids: Array, check_res: bool) -> void:
	var mat_ids := _unique_ids(data["materials"], "materials", label)
	var feat_ids := _unique_ids(data["features"], "features", label)
	_unique_ids(data["biomes"], "biomes", label)
	var list: Array = data["biomes"]
	for i in list.size():
		var b: Dictionary = list[i]
		var p := Schema.item_path("biomes", i, b)
		if check_res:
			_check_refs(b["resources"], res_ids, label, p + ".resources", "ресурса", "data/resources.json")
		_check_refs(b["features"], feat_ids, label, p + ".features", "особенности", "features")
		_check_refs(b["materials"], mat_ids, label, p + ".materials", "материала", "materials")


func _check_refs(values: Array, known: Array, label: String, path: String, what: String, where: String) -> void:
	for j in values.size():
		if not known.has(values[j]):
			errors.append("%s: %s[%d] — нет %s \"%s\" (смотри %s)" % [label, path, j, what, values[j], where])


## Проверяет, что id в списке не повторяются. Возвращает список id.
func _unique_ids(list: Array, list_name: String, label: String) -> Array:
	var seen := []
	for i in list.size():
		var id: String = list[i]["id"]
		if seen.has(id):
			errors.append("%s: %s — id \"%s\" повторяется" % [label, Schema.item_path(list_name, i, list[i]), id])
		else:
			seen.append(id)
	return seen


func _fill(parsed: Dictionary) -> void:
	var rdata: Dictionary = parsed["resources.json"]
	for s in rdata["storages"]:
		storages[s["id"]] = s
	for r in rdata["resources"]:
		resources[r["id"]] = r
		resource_ids.append(r["id"])
	var bdata: Dictionary = parsed["biomes.json"]
	for m in bdata["materials"]:
		materials[m["id"]] = m
	for f in bdata["features"]:
		features[f["id"]] = f
	for b in bdata["biomes"]:
		b["color"] = Color.html(b["color"])
		biomes[b["id"]] = b
		biome_ids.append(b["id"])
