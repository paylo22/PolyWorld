extends Camera2D
## Камера карты.
## Планшет: два пальца — сдвиг и щипок (зум вокруг точки между пальцами),
##   после отпускания карта плавно докатывается по инерции; тап одним пальцем — сигнал tapped.
## Компьютер: колесо — плавный зум к курсору, правая (или средняя) кнопка — сдвиг,
##   левый клик — tapped.
## Зум от «вся карта на экране» до MAX_ZOOM (1 клетка = 16 пикселей),
## камера не уезжает за края мира.

signal tapped(world_pos: Vector2)

const MAX_ZOOM := 16.0
const WHEEL_FACTOR := 1.25
const ZOOM_SMOOTH := 14.0
const FRICTION := 5.0
const TAP_MAX_MOVE := 14.0
const TAP_MAX_MS := 350

var world_size := Vector2(256, 256)
var min_zoom := 1.0

var _target_zoom := 1.0
var _zoom_anchor := Vector2.ZERO
var _touches := {}
var _prev_center := Vector2.ZERO
var _prev_dist := 0.0
var _prev_time := 0
var _velocity := Vector2.ZERO
var _last_move_ms := 0
var _mouse_pan := false
var _tap_index := -1
var _tap_pos := Vector2.ZERO
var _tap_time := 0


func _ready() -> void:
	get_viewport().size_changed.connect(_on_resize)


func setup(size: Vector2) -> void:
	world_size = size
	_update_min_zoom()
	show_all()


## Вся карта на экране, по центру.
func show_all() -> void:
	_set_zoom(min_zoom)
	_target_zoom = min_zoom
	position = world_size / 2.0
	_velocity = Vector2.ZERO


func screen_to_world(p: Vector2) -> Vector2:
	return position + (p - get_viewport_rect().size / 2.0) / zoom.x


## Меняет зум так, чтобы точка экрана screen_p осталась над той же точкой мира.
func zoom_at(screen_p: Vector2, new_zoom: float) -> void:
	_zoom_at(screen_p, new_zoom)
	_target_zoom = zoom.x


func _zoom_at(screen_p: Vector2, new_zoom: float) -> void:
	var before := screen_to_world(screen_p)
	_set_zoom(new_zoom)
	position = before - (screen_p - get_viewport_rect().size / 2.0) / zoom.x
	_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return  # палец, касание которого мы не видели
		_touches[event.index] = event.position
		if event.index == _tap_index and event.position.distance_to(_tap_pos) > TAP_MAX_MOVE:
			_tap_index = -1
		if _touches.size() == 2:
			_two_finger_move()
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return  # клик, придуманный движком из касания, — касания уже обработаны
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and _mouse_pan:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var d: Vector2 = event.relative / zoom.x
		position -= d
		_clamp()
		_track_velocity(-d)
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, zoom.x * event.factor)
	elif event is InputEventPanGesture:
		position += event.delta * 6.0 / zoom.x
		_clamp()


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		_velocity = Vector2.ZERO
		if _touches.size() == 1:
			_tap_index = event.index
			_tap_pos = event.position
			_tap_time = Time.get_ticks_msec()
		else:
			_tap_index = -1
	else:
		_touches.erase(event.index)
		if event.index == _tap_index and _touches.is_empty() \
				and Time.get_ticks_msec() - _tap_time <= TAP_MAX_MS:
			tapped.emit(screen_to_world(event.position))
		_tap_index = -1
		if Time.get_ticks_msec() - _last_move_ms > 80:
			_velocity = Vector2.ZERO  # пальцы стояли — без инерции
	_prev_dist = 0.0  # число пальцев изменилось — жест начинается заново


func _two_finger_move() -> void:
	var pts := _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var center := (a + b) / 2.0
	var dist := maxf(a.distance_to(b), 1.0)
	var now := Time.get_ticks_msec()
	if _prev_dist > 0.0:
		var old_pos := position
		var anchor := screen_to_world(_prev_center)
		_set_zoom(zoom.x * dist / _prev_dist)
		_target_zoom = zoom.x
		position = anchor - (center - get_viewport_rect().size / 2.0) / zoom.x
		_clamp()
		_track_velocity(position - old_pos)
	_prev_center = center
	_prev_dist = dist
	_prev_time = now


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var f := WHEEL_FACTOR if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_FACTOR
				_target_zoom = clampf(_target_zoom * f, min_zoom, MAX_ZOOM)
				_zoom_anchor = event.position
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_mouse_pan = event.pressed
			_velocity = Vector2.ZERO
			if not event.pressed and Time.get_ticks_msec() - _last_move_ms > 80:
				_velocity = Vector2.ZERO
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_tap_pos = event.position
				_tap_time = Time.get_ticks_msec()
			elif event.position.distance_to(_tap_pos) <= TAP_MAX_MOVE and Time.get_ticks_msec() - _tap_time <= TAP_MAX_MS:
				tapped.emit(screen_to_world(event.position))


func _process(delta: float) -> void:
	# Плавный зум колесом: в логарифмах, чтобы скорость не зависела от масштаба.
	if absf(_target_zoom - zoom.x) > 0.0005 * zoom.x:
		var k := 1.0 - exp(-ZOOM_SMOOTH * delta)
		var z := exp(lerpf(log(zoom.x), log(_target_zoom), k))
		_zoom_at(_zoom_anchor, z)
	# Инерция после сдвига.
	var moving := _touches.size() >= 2 or _mouse_pan
	if not moving and _velocity.length_squared() > 1.0:
		position += _velocity * delta
		_velocity *= exp(-FRICTION * delta)
		_clamp()


func _track_velocity(world_delta: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var dt := maxf((now - _last_move_ms) / 1000.0, 1.0 / 120.0)
	if now - _last_move_ms > 100:
		_velocity = Vector2.ZERO
	_velocity = _velocity.lerp(world_delta / dt, 0.4)
	_last_move_ms = now


func _set_zoom(z: float) -> void:
	z = clampf(z, min_zoom, MAX_ZOOM)
	zoom = Vector2(z, z)


func _clamp() -> void:
	var half := get_viewport_rect().size / (2.0 * zoom.x)
	for axis in 2:
		if world_size[axis] <= half[axis] * 2.0:
			position[axis] = world_size[axis] / 2.0
		else:
			position[axis] = clampf(position[axis], half[axis], world_size[axis] - half[axis])


func _update_min_zoom() -> void:
	var vp := get_viewport_rect().size
	min_zoom = minf(vp.x / world_size.x, vp.y / world_size.y) * 0.95
	_target_zoom = clampf(_target_zoom, min_zoom, MAX_ZOOM)


func _on_resize() -> void:
	_update_min_zoom()
	_set_zoom(zoom.x)
	_clamp()
