extends SceneTree
## Замер: рисование большой кистью по миру 576×576 на настоящем экране мира.
##   godot --headless --path . -s res://tools/bench_brush.gd
## Создаёт мир, открывает экран мира, проводит пальцем (события касания)
## каждой кистью размера 9 и печатает время кадра (скрипты + перерисовка).
## Без окна видеокарта не работает, поэтому это время только процессора.

const WorldGen = preload("res://sim/world_gen.gd")
const WorldState = preload("res://sim/world.gd")

const SIZE := 576
const FRAMES_PER_TOOL := 120

var _screen: Node
var _frame := 0
var _tools := [["raise", ""], ["water", ""], ["river", ""], ["biome", "taiga"], ["flora", "conifer"], ["erase", ""],
	["zoom5", ""], ["flora", "broadleaf"], ["raise", ""], ["erase", ""]]
var _zoom := 0.0
var _tool_i := 0
var _times := PackedFloat32Array()
var _report: PackedStringArray = []
var _t_prev := 0
var _end: EndMark


## Узел, который обрабатывается последним в кадре и запоминает время.
class EndMark extends Node:
	var t := 0
	func _ready() -> void:
		process_priority = 100000
	func _process(_d: float) -> void:
		t = Time.get_ticks_usec()


func _setup() -> void:
	var defs = root.get_node("Defs")
	var gen = WorldGen.new(defs, {"seed": 7, "size": SIZE})
	var t0 := Time.get_ticks_msec()
	WorldState.current = WorldState.new(gen.generate(), gen.params, "Замер", Time.get_ticks_msec() - t0)
	_screen = load("res://view/world_screen.tscn").instantiate()
	root.add_child(_screen)
	_end = EndMark.new()
	root.add_child(_end)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_setup()  # автозагрузки готовы только к первому кадру
	if _frame < 5:
		return false  # даём экрану построиться
	if _frame > 6:
		# Работа прошлого кадра: от начала кадра (здесь) до узла-замыкающего,
		# который обрабатывается последним. Паузы между кадрами не считаются.
		_times.append((_end.t - _t_prev) / 1000.0)
	_t_prev = Time.get_ticks_usec()
	var k := _frame - 5
	var pal = _screen.get("_palette")
	if k % FRAMES_PER_TOOL == 0:
		if _tool_i > 0:
			_finish_tool()
		if _tool_i >= _tools.size():
			print("\n".join(_report))
			var gc = root.get_node("GameClock")
			gc.set_paused(false)
			gc.set_speed(5)
			return _bench_growth()
		var t = _tools[_tool_i]
		if t[0] == "zoom5":
			# Второй проход: зум ×5 — видны спрайты флоры.
			var cam = _screen.get("_cam")
			cam.zoom_at(Vector2(640, 400), 5.0)
			_zoom = 5.0
			_report.append("--- зум ×5, спрайты флоры видны ---")
			_tool_i += 1
			return false
		pal.tool = t[0]
		pal.arg = t[1]
		pal.brush_size = 9
		_touch(true, Vector2(200, 200))
		_tool_i += 1
		return false
	# Быстрый палец: зигзаг по экрану, ~30 пикселей за кадр.
	var p := Vector2(100 + (k % FRAMES_PER_TOOL) * 8.0, 400 + 300 * sin(k * 0.1))
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = p
	root.push_input(e, true)
	return false


func _finish_tool() -> void:
	_touch(false, Vector2.ZERO)
	var arr := Array(_times)
	arr.sort()
	var avg := 0.0
	for v in arr:
		avg += v
	avg /= maxf(arr.size(), 1)
	if _tools[_tool_i - 1][0] == "zoom5":
		return
	_report.append("%-8s кисть 9: кадр в среднем %.2f мс, худший %.2f мс, мазков в истории %d" % [
		_tools[_tool_i - 1][0], avg, arr.back() if not arr.is_empty() else 0.0, WorldState.current.palette.undo_count()])
	_times = PackedFloat32Array()


func _touch(pressed: bool, p: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = p
	root.push_input(e, true)


func _bench_growth() -> bool:
	# Шаг симуляции с ростом леса на ×5.
	var gc = root.get_node("GameClock")
	var w = WorldState.current
	var forest: int = root.get_node("Defs").flora_index("broadleaf")
	for i in range(0, w.data.cell_count(), 3):
		if w.data.heights[i] >= 0:
			w.data.set_flora(i, forest)
	var t0 := Time.get_ticks_usec()
	for s in 1000:
		w.step(s)
	print("Рост леса, мир %d: %.3f мс на шаг (порция %d клеток за тик)" % [SIZE, (Time.get_ticks_usec() - t0) / 1000000.0, w.growth.cells_per_tick])
	quit(0)
	return true
