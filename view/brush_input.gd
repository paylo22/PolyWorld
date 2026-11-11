extends Node
## Ввод для кистей: один палец рисует, два пальца — камера (её ведёт WorldCamera).
##
## Сигналы дают клетку мира под пальцем:
##   started → moved (много раз) → finished, или cancelled.
## Мазок не начинается, если палец опустился на панель (blockers).
## Если второй палец пришёл в первые CANCEL_MS мазка — это начало жеста
## камеры, и мазок отменяется целиком; если позже — мазок просто заканчивается.
## На компьютере: левая кнопка мыши рисует.

signal started(cell: Vector2i)
signal moved(cell: Vector2i)
signal finished
signal cancelled

const CANCEL_MS := 250

var camera: Camera2D
## Элементы интерфейса, над которыми мазок не начинается.
var blockers: Array[Control] = []

var _fingers := {}
var _stroke_finger := -1  # -1 нет мазка, -2 мышь
var _stroke_start_ms := 0
var _last_cell := Vector2i(-99999, -99999)


func is_stroking() -> bool:
	return _stroke_finger != -1


## Прерывает мазок (например, при смене инструмента).
func finish() -> void:
	if _stroke_finger != -1:
		_stroke_finger = -1
		finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_fingers[event.index] = true
			if _fingers.size() == 1:
				if not _over_ui(event.position):
					_begin(event.index, event.position)
			elif _stroke_finger != -1:
				_stroke_finger = -1
				if Time.get_ticks_msec() - _stroke_start_ms < CANCEL_MS:
					cancelled.emit()
				else:
					finished.emit()
		else:
			_fingers.erase(event.index)
			if event.index == _stroke_finger:
				_stroke_finger = -1
				finished.emit()
	elif event is InputEventScreenDrag:
		if event.index == _stroke_finger:
			_move(event.position)
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT:
			return  # клик, придуманный движком из касания, — касания уже обработаны
		if event.pressed:
			if _stroke_finger == -1 and not _over_ui(event.position):
				_begin(-2, event.position)
		elif _stroke_finger == -2:
			_stroke_finger = -1
			finished.emit()
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and _stroke_finger == -2:
			_move(event.position)


func _begin(finger: int, pos: Vector2) -> void:
	_stroke_finger = finger
	_stroke_start_ms = Time.get_ticks_msec()
	_last_cell = _cell(pos)
	started.emit(_last_cell)


func _move(pos: Vector2) -> void:
	var c := _cell(pos)
	if c != _last_cell:
		_last_cell = c
		moved.emit(c)


func _cell(pos: Vector2) -> Vector2i:
	var p: Vector2 = camera.screen_to_world(pos)
	return Vector2i(floori(p.x), floori(p.y))


func _over_ui(pos: Vector2) -> bool:
	for b in blockers:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return true
	return false
