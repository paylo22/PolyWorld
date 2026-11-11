extends Node
## Часы симуляции (автозагрузка GameClock).
##
## Единицы времени (docs/RESEARCH.md, раздел «Ресурсы»):
##   шаг  — минимальный шаг симуляции, STEPS_PER_TICK шагов = 1 тик;
##   тик  — 1 секунда игрового времени при скорости ×1;
##   день — 60 тиков; сезон — 3 дня; год — 12 дней (4 сезона).
##
## Всё время хранится одним числом total_steps, остальное вычисляется из него.
## Системы симуляции подписываются на сигналы step/tick/day_passed и не
## считают время сами. Логика продвижения — в advance(), чтобы её можно было
## проверять в тестах без дерева сцен.

signal step(step_index: int)
signal tick(tick_index: int)
signal day_passed(day_index: int)
signal season_changed(season: int)
signal year_passed(year: int)
signal paused_changed(paused: bool)
signal speed_changed(speed: int)

const STEPS_PER_TICK := 10
const TICKS_PER_DAY := 60
const DAYS_PER_SEASON := 3
const SEASONS_PER_YEAR := 4
const DAYS_PER_YEAR := DAYS_PER_SEASON * SEASONS_PER_YEAR
const SPEEDS: Array[int] = [1, 2, 5]
## Сколько шагов максимум за один кадр. Если кадр был очень долгим,
## лишнее время отбрасывается: игра замедляется, а не зависает.
const MAX_STEPS_PER_FRAME := 100

const SEASON_NAMES: Array[String] = ["Весна", "Лето", "Осень", "Зима"]

var total_steps: int = 0
var paused: bool = true
var speed: int = 1

## Среднее время одного шага симуляции (обработчики сигнала step и tick), мс.
var step_ms_avg: float = 0.0
## Сколько шагов было выполнено за последнюю реальную секунду.
var steps_last_second: int = 0

var _accum: float = 0.0
var _second_timer: float = 0.0
var _steps_this_second: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	advance(delta)
	_second_timer += delta
	if _second_timer >= 1.0:
		steps_last_second = _steps_this_second
		_steps_this_second = 0
		_second_timer = fmod(_second_timer, 1.0)


## Продвигает время на real_delta реальных секунд. Возвращает число шагов.
func advance(real_delta: float) -> int:
	if paused or real_delta <= 0.0:
		return 0
	_accum += real_delta * speed * STEPS_PER_TICK
	var n := int(floor(_accum))
	if n > MAX_STEPS_PER_FRAME:
		n = MAX_STEPS_PER_FRAME
		_accum = 0.0
	else:
		_accum -= n
	for i in n:
		_do_step()
	return n


## Сбрасывает часы на начало мира: год 1, весна, день 1, пауза, ×1.
func reset() -> void:
	total_steps = 0
	_accum = 0.0
	step_ms_avg = 0.0
	set_speed(1)
	set_paused(true)


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	paused_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


## Ставит скорость из SPEEDS (1, 2, 5). Другие значения отклоняются.
func set_speed(value: int) -> bool:
	if not SPEEDS.has(value):
		push_error("GameClock.set_speed: недопустимая скорость %d, можно %s" % [value, SPEEDS])
		return false
	if speed != value:
		speed = value
		speed_changed.emit(speed)
	return true


# --- Производные величины -------------------------------------------------

func get_total_ticks() -> int:
	return total_steps / STEPS_PER_TICK


## Номер дня с начала мира, с нуля.
func get_day_index() -> int:
	return get_total_ticks() / TICKS_PER_DAY


## Год, начиная с 1.
func get_year() -> int:
	return get_day_index() / DAYS_PER_YEAR + 1


## День внутри года, с нуля (0..11).
func get_day_of_year() -> int:
	return get_day_index() % DAYS_PER_YEAR


## Сезон: 0 весна, 1 лето, 2 осень, 3 зима.
func get_season() -> int:
	return get_day_of_year() / DAYS_PER_SEASON


## День внутри сезона, с 1 (1..3).
func get_day_of_season() -> int:
	return get_day_of_year() % DAYS_PER_SEASON + 1


## Доля текущего дня, 0..1 (для смены освещения и т. п.).
func get_day_progress() -> float:
	return float(get_total_ticks() % TICKS_PER_DAY) / TICKS_PER_DAY


func get_season_name() -> String:
	return SEASON_NAMES[get_season()]


## Например: «Год 3, Лето, день 2».
func get_date_string() -> String:
	return "Год %d, %s, день %d" % [get_year(), get_season_name(), get_day_of_season()]


# --- Сохранение -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {"total_steps": total_steps, "speed": speed, "paused": paused}


## Восстанавливает состояние. Возвращает текст ошибки или "" если всё хорошо.
func from_dict(data: Dictionary) -> String:
	var steps = data.get("total_steps")
	if not (steps is int or steps is float) or steps < 0 or floor(steps) != steps:
		return "clock.total_steps: ожидается целое число ≥ 0, получено %s" % [str(steps)]
	var spd = data.get("speed", 1)
	if not (spd is int or spd is float) or not SPEEDS.has(int(spd)):
		return "clock.speed: ожидается одно из %s, получено %s" % [SPEEDS, str(spd)]
	total_steps = int(steps)
	_accum = 0.0
	set_speed(int(spd))
	set_paused(bool(data.get("paused", true)))
	return ""


# --- Внутреннее -----------------------------------------------------------

func _do_step() -> void:
	var t0 := Time.get_ticks_usec()
	var old_day := get_day_index()
	var old_season := get_season()
	total_steps += 1
	step.emit(total_steps)
	if total_steps % STEPS_PER_TICK == 0:
		tick.emit(get_total_ticks())
		var day := get_day_index()
		if day != old_day:
			day_passed.emit(day)
			var season := get_season()
			if season != old_season:
				season_changed.emit(season)
			if get_day_of_year() == 0:
				year_passed.emit(get_year())
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	step_ms_avg = ms if step_ms_avg == 0.0 else lerpf(step_ms_avg, ms, 0.05)
	_steps_this_second += 1
