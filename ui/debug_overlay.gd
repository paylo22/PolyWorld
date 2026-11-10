extends CanvasLayer
## Отладочная панель (автозагрузка DebugOverlay).
## Открывается и закрывается касанием тремя пальцами (на ПК — клавиша F3).
## Показывает FPS, мс на шаг симуляции, дату и сезон; кнопки паузы и скоростей.

const REFRESH_SEC := 0.25

@onready var _panel: PanelContainer = %Panel
@onready var _fps: Label = %FpsLabel
@onready var _step: Label = %StepLabel
@onready var _date: Label = %DateLabel
@onready var _state: Label = %StateLabel
@onready var _pause_btn: Button = %PauseButton
@onready var _speed_btns := {1: %Speed1Button, 2: %Speed2Button, 5: %Speed5Button}

var _touches := {}
var _gesture_used := false
var _refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	_pause_btn.pressed.connect(GameClock.toggle_pause)
	for s in _speed_btns:
		(_speed_btns[s] as Button).pressed.connect(_on_speed.bind(s))
	GameClock.paused_changed.connect(func(_p): _update())
	GameClock.speed_changed.connect(func(_s): _update())
	GameClock.day_passed.connect(func(_d): _update())


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
			if _touches.size() >= 3 and not _gesture_used:
				_gesture_used = true
				toggle()
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_gesture_used = false
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle()


func toggle() -> void:
	_panel.visible = not _panel.visible
	_update()


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_refresh += delta
	if _refresh >= REFRESH_SEC:
		_refresh = 0.0
		_update()


func _on_speed(s: int) -> void:
	GameClock.set_speed(s)
	GameClock.set_paused(false)
	_update()


func _update() -> void:
	if not is_node_ready() or not _panel.visible:
		return
	_fps.text = "FPS: %d" % Engine.get_frames_per_second()
	_step.text = "Шаг симуляции: %.3f мс  (%d шаг/с)" % [GameClock.step_ms_avg, GameClock.steps_last_second]
	_date.text = "%s  (тик %d)" % [GameClock.get_date_string(), GameClock.get_total_ticks()]
	_state.text = "ПАУЗА" if GameClock.paused else "Скорость ×%d" % GameClock.speed
	_pause_btn.text = "Пуск" if GameClock.paused else "Пауза"
	for s in _speed_btns:
		(_speed_btns[s] as Button).button_pressed = (not GameClock.paused and GameClock.speed == s)
