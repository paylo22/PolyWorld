extends Node
## Текущий мир (автозагрузка World): данные клеток, настройки генерации, имя.
## Экран мира рисует World.data, SaveLoad сохраняет и загружает World.

const WorldData = preload("res://sim/world_data.gd")

signal world_changed

var data: WorldData = null
## Настройки, с которыми мир был создан (seed, size, water, mountains, islands).
var params: Dictionary = {}
var world_name: String = ""
## Сколько мс заняла генерация (0 для загруженного мира).
var gen_ms: float = 0.0


func has_world() -> bool:
	return data != null


func set_world(p_data: WorldData, p_params: Dictionary, p_name: String, p_gen_ms: float = 0.0) -> void:
	data = p_data
	params = p_params.duplicate()
	world_name = p_name
	gen_ms = p_gen_ms
	world_changed.emit()


func clear() -> void:
	data = null
	params = {}
	world_name = ""
	world_changed.emit()


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
		"cells": data.to_dict(),
	}


## Возвращает текст ошибки или "".
func from_dict(d: Dictionary, defs) -> String:
	if not d.get("cells") is Dictionary:
		return "world: нет раздела cells"
	var wd := WorldData.new()
	var err := wd.from_dict(d["cells"])
	if err != "":
		return err
	err = _remap(wd.biomes, d.get("biome_ids", []), defs.biome_ids, "биом")
	if err != "":
		return err
	err = _remap(wd.deposits, d.get("resource_ids", []), defs.resource_ids, "ресурс")
	if err != "":
		return err
	var p = d.get("params", {})
	set_world(wd, p if p is Dictionary else {}, str(d.get("name", "Мир")))
	return ""


## Переводит номера из старого списка id в номера текущего.
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
