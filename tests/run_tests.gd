extends SceneTree
## Запуск всех тестов без окна:
##   godot --headless --path . -s res://tests/run_tests.gd
## Выход с кодом 0, если всё прошло, и 1, если есть падения.
##
## Тест-файл — tests/test_*.gd, наследник RefCounted. Каждый метод test_*
## получает объект T с проверками: t.eq(a, b, "что проверяем"), t.ok(cond, "...").

const TESTS_DIR := "res://tests"


class T:
	var failures: PackedStringArray = []

	func ok(cond: bool, what: String) -> void:
		if not cond:
			failures.append(what)

	func eq(got: Variant, expected: Variant, what: String) -> void:
		if typeof(got) != typeof(expected) or got != expected:
			failures.append("%s: ожидалось %s, получено %s" % [what, var_to_str(expected), var_to_str(got)])

	func has_text(text: String, part: String, what: String) -> void:
		if not text.contains(part):
			failures.append("%s: в тексте нет «%s». Текст: %s" % [what, part, text])


var _started := false
var _finished := false


# Тесты запускаются в первом кадре. Если прогон оборвётся из-за ошибки
# скрипта, во втором кадре раннер всё равно выйдет с кодом 1, а не зависнет.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_all()
		return _finished
	if not _finished:
		print("\nПрогон оборвался из-за ошибки скрипта (см. SCRIPT ERROR выше).")
		quit(1)
	return true


func _run_all() -> void:
	var passed := 0
	var failed := 0
	var files := DirAccess.get_files_at(TESTS_DIR)
	files.sort()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(TESTS_DIR.path_join(file))
		if script == null or not script.can_instantiate():
			print("  FAIL %s: скрипт не загрузился (ошибка разбора, см. выше)" % file)
			failed += 1
			continue
		var suite = script.new()
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var t := T.new()
			suite.call(name, t)
			if t.failures.is_empty():
				passed += 1
				print("  ok   %s :: %s" % [file, name])
			else:
				failed += 1
				print("  FAIL %s :: %s" % [file, name])
				for f in t.failures:
					print("         - " + f)
		if suite.has_method("cleanup"):
			suite.cleanup()
	print("")
	print("Итого: %d прошло, %d упало" % [passed, failed])
	_finished = true
	quit(1 if failed > 0 else 0)
