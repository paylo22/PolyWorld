extends RefCounted
## Тесты загрузки и проверки данных. Ошибки должны называть файл и поле.

const DefsScript = preload("res://sim/defs.gd")

var _made: Array = []


func _defs() -> Node:
	var d: Node = DefsScript.new()
	_made.append(d)
	return d


func cleanup() -> void:
	for d in _made:
		d.free()
	_made.clear()


func _real_texts() -> Dictionary:
	return {
		"resources.json": FileAccess.get_file_as_string("res://data/resources.json"),
		"biomes.json": FileAccess.get_file_as_string("res://data/biomes.json"),
		"worldgen.json": FileAccess.get_file_as_string("res://data/worldgen.json"),
	}


## Берёт настоящие данные, меняет их функцией и возвращает тексты.
func _patched(file: String, change: Callable) -> Dictionary:
	var texts := _real_texts()
	var data = JSON.parse_string(texts[file])
	change.call(data)
	texts[file] = JSON.stringify(data)
	return texts


func _all_errors(d: Node) -> String:
	return "\n".join(d.errors)


func test_real_data_loads(t) -> void:
	var d := _defs()
	var ok: bool = d.load_dir("res://data")
	t.ok(ok, "data/ без ошибок:\n" + _all_errors(d))
	t.eq(d.resources.size(), 27, "ресурсов в таблице")
	t.eq(d.biomes.size(), 8, "биомов в таблице")
	t.eq(d.get_resource("gunpowder")["storage"], "powder_magazine", "порох в погребе")
	t.eq(d.storages["granary"]["capacity"], 400, "амбар 400")
	t.eq(d.get_resource("meat").get("spoils"), true, "мясо портится")
	t.ok(d.get_biome("mountains")["resources"].has("sulfur"), "сера в горах")
	t.ok(d.get_biome("forest")["color"] is Color, "цвет биома превращён в Color")
	t.eq(d.resource_ids[0], "grain", "порядок как в файле")


func test_syntax_error_names_file_and_line(t) -> void:
	var d := _defs()
	var texts := _real_texts()
	texts["biomes.json"] = '{\n  "materials": [\n    { "id": "wood" "name": "Дерево" }\n  ]\n}'
	t.ok(not d.load_from_texts(texts), "загрузка провалилась")
	var e := _all_errors(d)
	t.has_text(e, "data/biomes.json", "имя файла")
	t.has_text(e, "строка 3", "номер строки")
	t.ok(not d.is_ok(), "is_ok() == false")
	t.eq(d.resources.size(), 0, "при ошибке данные не загружаются")


func test_wrong_type_names_field(t) -> void:
	var d := _defs()
	var texts := _patched("resources.json", func(data): data["storages"][0]["capacity"] = "много")
	d.load_from_texts(texts)
	var e := _all_errors(d)
	t.has_text(e, "data/resources.json", "имя файла")
	t.has_text(e, "storages[0] «granary».capacity", "путь к полю")
	t.has_text(e, "ожидается целое число", "что не так")
	t.has_text(e, "строка \"много\"", "что получено")


func test_missing_field(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("resources.json", func(data): data["resources"][2].erase("name")))
	t.has_text(_all_errors(d), "resources[2] «bread».name — нет обязательного поля", "нет поля name")


func test_unknown_field_is_typo(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("resources.json", func(data): data["resources"][0]["stroage"] = "granary"))
	var e := _all_errors(d)
	t.has_text(e, "resources[0] «grain».stroage — неизвестное поле", "опечатка в имени")


func test_comment_keys_are_allowed(t) -> void:
	var d := _defs()
	t.ok(d.load_from_texts(_patched("biomes.json", func(data): data["biomes"][0]["_todo"] = "x")), "ключи с _ пропускаются")


func test_bad_enum(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("resources.json", func(data): data["resources"][1]["type"] = "foood"))
	t.has_text(_all_errors(d), "resources[1] «flour».type — ожидается одно из", "неверный тип ресурса")


func test_bad_id_format(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("resources.json", func(data): data["resources"][0]["id"] = "Iron Ore"))
	t.has_text(_all_errors(d), "resources[0] «Iron Ore».id — ожидается id", "id с пробелом")


func test_duplicate_id(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("resources.json", func(data): data["resources"][1]["id"] = "grain"))
	t.has_text(_all_errors(d), "id \"grain\" повторяется", "повтор id")


func test_unknown_storage_reference(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("resources.json", func(data): data["resources"][0]["storage"] = "barn"))
	t.has_text(_all_errors(d), "resources[0] «grain».storage — нет хранилища \"barn\"", "ссылка на хранилище")


func test_biome_unknown_resource(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("biomes.json", func(data): data["biomes"][3]["resources"].append("mithril")))
	var e := _all_errors(d)
	t.has_text(e, "data/biomes.json", "имя файла")
	t.has_text(e, "biomes[3] «mountains».resources[5] — нет ресурса \"mithril\"", "ссылка на ресурс")


func test_bad_color(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("biomes.json", func(data): data["biomes"][0]["color"] = "зелёный"))
	t.has_text(_all_errors(d), "biomes[0] «forest».color — ожидается цвет", "цвет")


func test_missing_file(t) -> void:
	var d := _defs()
	var texts := _real_texts()
	texts.erase("biomes.json")
	d.load_from_texts(texts)
	t.has_text(_all_errors(d), "data/biomes.json: файл не найден", "нет файла")


func test_reload_clears_old_errors(t) -> void:
	var d := _defs()
	d.load_from_texts({})
	t.ok(not d.is_ok(), "сначала ошибки")
	t.ok(d.load_dir("res://data"), "потом нормальная загрузка")
	t.ok(d.is_ok(), "ошибки очищены")


func test_worldgen_loaded(t) -> void:
	var d := _defs()
	d.load_dir("res://data")
	t.eq(d.worldgen["size_default"], 256, "размер по умолчанию")
	t.eq(d.biome_index("coast"), 7, "индекс побережья")
	t.ok(d.get_resource("coal")["map_color"] is Color, "цвет жилы угля")


func test_worldgen_bad_rule_biome(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("worldgen.json", func(data): data["biome_rules"][1]["biome"] = "volcano"))
	t.has_text(_all_errors(d), "data/worldgen.json: biome_rules[1].biome — нет биома \"volcano\"", "правило с неизвестным биомом")


func test_worldgen_bad_vein(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("worldgen.json", func(data): data["veins"][0]["resource"] = "mithril"))
	t.has_text(_all_errors(d), "veins[0].resource — нет ресурса \"mithril\"", "жила неизвестного ресурса")


func test_flora_and_palette_loaded(t) -> void:
	var d := _defs()
	t.ok(d.load_from_texts(_real_texts()), "данные без ошибок")
	t.eq(d.flora_ids, PackedStringArray(["broadleaf", "conifer", "bush", "berries", "reed", "wild_grain"]), "6 видов флоры")
	t.ok(d.flora["conifer"]["forest"] and not d.flora["bush"]["forest"], "лес отмечен")
	t.ok(d.flora["reed"]["on_river"], "камыш растёт в реке")
	t.ok(d.biomes["meadow"]["forest_spread"]["broadleaf"] > 0.0, "скорость леса на лугу")
	t.eq(d.palette["brush_sizes"], [1, 3, 5, 9], "размеры кисти")
	t.eq(d.palette["undo_strokes"], 10, "отмена 10 мазков")


func test_flora_errors_name_field(t) -> void:
	var d := _defs()
	d.load_from_texts(_patched("biomes.json", func(x): x["biomes"][1]["forest_spread"]["oak"] = 0.5))
	t.has_text(_all_errors(d), "biomes[1] «meadow».forest_spread", "неизвестная флора в скорости леса")
	d.load_from_texts(_patched("biomes.json", func(x): x["biomes"][0]["forest_spread"]["conifer"] = 2))
	t.has_text(_all_errors(d), "forest_spread.conifer — значение должно быть не больше 1", "шанс больше 1")
	d.load_from_texts(_patched("biomes.json", func(x): x["flora"][2]["sprite"] = "nope.png"))
	t.has_text(_all_errors(d), "flora[2] «bush».sprite — нет картинки", "нет картинки")
	d.load_from_texts(_patched("biomes.json", func(x): x["palette"]["veins"].append("mithril")))
	t.has_text(_all_errors(d), "data/biomes.json: palette.veins[4] — нет ресурса \"mithril\"", "жила из неизвестного ресурса")
	d.load_from_texts(_patched("biomes.json", func(x): x["palette"]["veins"].append("bread")))
	t.has_text(_all_errors(d), "palette.veins[4] — у ресурса \"bread\" нет map_color", "хлеб — не жила")
	d.load_from_texts(_patched("biomes.json", func(x): x["palette"].erase("raise_step")))
	t.has_text(_all_errors(d), "palette.raise_step — нет обязательного поля", "нет поля палитры")
