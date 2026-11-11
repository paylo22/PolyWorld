extends RefCounted
## Проверка данных из JSON по простому описанию схемы.
##
## Описание поля — словарь:
##   {"type": "string" | "id" | "int" | "number" | "bool" | "color" | "enum" | "array" | "object" | "map",
##    "optional": true,             — поле можно не указывать
##    "min": 0, "max": 10,          — для int/number
##    "values": [...],              — для enum
##    "item": {...}, "min_items": 1 — для array
##    "fields": {...}}              — для object
##    "value": {...}                — для map: объект, где ключи — любые id,
##                                    а значения проверяются по value
##
## Ключи объекта, начинающиеся с "_" (например "_comment"), пропускаются —
## ими можно писать пояснения прямо в JSON. Любой другой лишний ключ — ошибка
## (так ловятся опечатки в названиях полей).
##
## Ошибки дописываются в массив errors строками вида
##   resources[3] «flour».storage — ожидается id ..., получено число 5

const ID_HINT := "id (строчные латинские буквы, цифры и _, например iron_ore)"


static func check(value: Variant, spec: Dictionary, path: String, errors: PackedStringArray) -> void:
	var t: String = spec.get("type", "any")
	match t:
		"any":
			pass
		"string":
			if not value is String:
				_err(errors, path, "ожидается строка", value)
			elif (value as String).strip_edges() == "":
				_err(errors, path, "строка не должна быть пустой", value)
		"id":
			if not (value is String and is_valid_id(value)):
				_err(errors, path, "ожидается " + ID_HINT, value)
		"int":
			if not is_int(value):
				_err(errors, path, "ожидается целое число", value)
			else:
				_check_range(value, spec, path, errors)
		"number":
			if not (value is int or value is float):
				_err(errors, path, "ожидается число", value)
			else:
				_check_range(value, spec, path, errors)
		"bool":
			if not value is bool:
				_err(errors, path, "ожидается true или false", value)
		"color":
			if not (value is String and (value as String).begins_with("#") and Color.html_is_valid(value)):
				_err(errors, path, "ожидается цвет вида \"#5a8f3c\"", value)
		"enum":
			var values: Array = spec.get("values", [])
			if not (value is String and values.has(value)):
				_err(errors, path, "ожидается одно из: %s" % ", ".join(PackedStringArray(values)), value)
		"array":
			if not value is Array:
				_err(errors, path, "ожидается массив [...]", value)
				return
			var arr: Array = value
			var min_items: int = spec.get("min_items", 0)
			if arr.size() < min_items:
				_err(errors, path, "в массиве должно быть хотя бы %d элемент(ов)" % min_items, value)
			var item_spec: Dictionary = spec.get("item", {})
			for i in arr.size():
				check(arr[i], item_spec, item_path(path, i, arr[i]), errors)
		"object":
			if not value is Dictionary:
				_err(errors, path, "ожидается объект {...}", value)
				return
			var obj: Dictionary = value
			var fields: Dictionary = spec.get("fields", {})
			for key in fields:
				var fspec: Dictionary = fields[key]
				if not obj.has(key):
					if not fspec.get("optional", false):
						errors.append("%s — нет обязательного поля" % join_path(path, key))
					continue
				check(obj[key], fspec, join_path(path, key), errors)
			for key in obj:
				if str(key).begins_with("_"):
					continue
				if not fields.has(key):
					errors.append("%s — неизвестное поле (опечатка?). Допустимые поля: %s"
						% [join_path(path, str(key)), ", ".join(PackedStringArray(fields.keys()))])
		"map":
			if not value is Dictionary:
				_err(errors, path, "ожидается объект {\"id\": значение, ...}", value)
				return
			var m: Dictionary = value
			var vspec: Dictionary = spec.get("value", {})
			for key in m:
				if str(key).begins_with("_"):
					continue
				if not is_valid_id(str(key)):
					errors.append("%s — ключ должен быть %s" % [join_path(path, str(key)), ID_HINT])
					continue
				check(m[key], vspec, join_path(path, str(key)), errors)
		_:
			errors.append("%s — внутренняя ошибка схемы: неизвестный тип \"%s\"" % [path, t])


## Приводит проверенные данные к нужным типам: поля "int" из float (так их
## читает JSON) превращаются в int. Вызывать только после check() без ошибок.
static func normalize(value: Variant, spec: Dictionary) -> Variant:
	match spec.get("type", "any"):
		"int":
			return int(value)
		"array":
			var item_spec: Dictionary = spec.get("item", {})
			var out := []
			for v in value:
				out.append(normalize(v, item_spec))
			return out
		"map":
			var vspec: Dictionary = spec.get("value", {})
			var m := {}
			for key in value:
				if not str(key).begins_with("_"):
					m[key] = normalize(value[key], vspec)
			return m
		"object":
			var fields: Dictionary = spec.get("fields", {})
			var obj := {}
			for key in value:
				obj[key] = normalize(value[key], fields[key]) if fields.has(key) else value[key]
			return obj
	return value


static func is_valid_id(s: String) -> bool:
	if s.is_empty():
		return false
	for c in s:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


## JSON читает все числа как float, поэтому 5.0 тоже считается целым.
static func is_int(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v) and floor(v) == v)


static func join_path(path: String, key: String) -> String:
	return key if path.is_empty() else "%s.%s" % [path, key]


## Путь к элементу массива; если у элемента есть id, он добавляется для понятности.
static func item_path(path: String, index: int, item: Variant) -> String:
	var p := "%s[%d]" % [path, index]
	if item is Dictionary and item.get("id") is String:
		p += " «%s»" % item["id"]
	return p


static func describe(v: Variant) -> String:
	if v == null:
		return "null"
	if v is String:
		return "строка \"%s\"" % v
	if v is bool:
		return "true" if v else "false"
	if v is int or v is float:
		return "число %s" % (str(int(v)) if is_int(v) else str(v))
	if v is Array:
		return "массив"
	if v is Dictionary:
		return "объект"
	return type_string(typeof(v))


static func _check_range(v: Variant, spec: Dictionary, path: String, errors: PackedStringArray) -> void:
	if spec.has("min") and v < spec["min"]:
		_err(errors, path, "значение должно быть не меньше %s" % spec["min"], v)
	if spec.has("max") and v > spec["max"]:
		_err(errors, path, "значение должно быть не больше %s" % spec["max"], v)


static func _err(errors: PackedStringArray, path: String, what: String, got: Variant) -> void:
	errors.append("%s — %s, получено: %s" % [path if path != "" else "(корень файла)", what, describe(got)])
