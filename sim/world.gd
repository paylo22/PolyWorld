extends RefCounted
## Состояние мира: данные клеток (WorldData), настройки генерации, название.
##
## Текущий мир лежит в статической переменной WorldState.current — так он
## переживает смену сцен без отдельного узла-автозагрузки (правило 1 CLAUDE.md:
## в sim/ только RefCounted). Использование:
##   const WorldState = preload("res://sim/world.gd")
##   WorldState.current = WorldState.new(data, params, "Мир 1")

const WorldData = preload("res://sim/world_data.gd")
const GodPalette = preload("res://sim/god_palette.gd")
const FloraGrowth = preload("res://sim/flora_growth.gd")

## Мир, который сейчас открыт, или null.
static var current = null

var data: WorldData = null
## Настройки, с которыми мир был создан (seed, size, water, mountains, islands).
var params: Dictionary = {}
var world_name: String = ""
## Сколько мс заняла генерация (0 для загруженного мира).
var gen_ms: float = 0.0
## Случайность живого мира (рост леса и всё, что будет дальше). Правило 8:
## сид — от сида мира, состояние пишется в сохранение.
var rng := RandomNumberGenerator.new()
## Команды палитры бога и рост леса. Создаются в start_sim().
var palette: GodPalette = null
var growth: FloraGrowth = null


func _init(p_data: WorldData = null, p_params: Dictionary = {}, p_name: String = "", p_gen_ms: float = 0.0) -> void:
	data = p_data
	params = p_params.duplicate()
	world_name = p_name
	gen_ms = p_gen_ms
	_seed_rng()


## Готовит системы, которые меняют мир: палитру бога и рост леса.
func start_sim(defs) -> void:
	palette = GodPalette.new(data, defs)
	growth = FloraGrowth.new(data, defs, rng)


## Один шаг симуляции (подключается к GameClock.step).
func step(step_index: int) -> void:
	if growth:
		growth.on_step(step_index)


func _seed_rng() -> void:
	rng.seed = hash("sim:%s" % str(params.get("seed", 0)))


func has_world() -> bool:
	return data != null


## Имя файла сохранения для этого мира.
func slot_name() -> String:
	return slot_for_name(world_name)


static func slot_for_name(n: String) -> String:
	var s := n.strip_edges().validate_filename().replace(" ", "_")
	return s if s != "" else "world"


## Биом и жила хранятся в слоях номерами. Вместе с ними сохраняем списки id,
## чтобы мир правильно загрузился, даже если в data/*.json поменяли порядок.
func to_dict(defs) -> Dictionary:
	return {
		"name": world_name,
		"params": params,
		"biome_ids": Array(defs.biome_ids),
		"resource_ids": Array(defs.resource_ids),
		"flora_ids": Array(defs.flora_ids),
		"rng_seed": rng.seed,
		"rng_state": rng.state,
		"cells": data.to_dict(),
	}


## Заполняет состояние из словаря. Возвращает текст ошибки или "".
## Отсутствующие поля получают значения по умолчанию (правило 12).
func from_dict(d: Dictionary, defs) -> String:
	if not d.get("cells") is Dictionary:
		return "world: нет раздела cells"
	var wd := WorldData.new()
	var err := wd.from_dict(d["cells"])
	if err != "":
		return err
	err = _remap(wd.biomes, d.get("biome_ids", defs.biome_ids), defs.biome_ids, "биом")
	if err != "":
		return err
	err = _remap(wd.resources, d.get("resource_ids", defs.resource_ids), defs.resource_ids, "ресурс")
	if err != "":
		return err
	err = _remap(wd.floras, d.get("flora_ids", defs.flora_ids), defs.flora_ids, "растение")
	if err != "":
		return err
	data = wd
	var p = d.get("params", {})
	params = p if p is Dictionary else {}
	world_name = str(d.get("name", "Мир"))
	gen_ms = 0.0
	palette = null
	growth = null
	# Старое сохранение без состояния случайности: сид от сида мира (правило 12).
	_seed_rng()
	if d.get("rng_seed") is int and d.get("rng_state") is int:
		rng.seed = d["rng_seed"]
		rng.state = d["rng_state"]
	return ""


## Переводит номера из сохранённого списка id в номера текущего.
static func _remap(layer: PackedInt32Array, saved_ids, current_ids: PackedStringArray, what: String) -> String:
	var saved := PackedStringArray(saved_ids)
	if saved == current_ids:
		return ""
	var map := PackedInt32Array()
	for id in saved:
		var j := current_ids.find(id)
		if j < 0:
			return "В сохранении есть %s \"%s\", которого больше нет в data/" % [what, id]
		map.append(j)
	for i in layer.size():
		var v := layer[i]
		if v >= 0:
			if v >= map.size():
				return "Слой мира ссылается на %s №%d, а в сохранении их %d" % [what, v, map.size()]
			layer[i] = map[v]
	return ""
