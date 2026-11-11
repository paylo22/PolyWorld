extends RefCounted
## Тесты часов. Каждый тест создаёт свои часы, автозагрузка не трогается.

const Clock = preload("res://sim/game_clock.gd")

var _made: Array = []


func _clock() -> Node:
	var c: Node = Clock.new()
	c.set_paused(false)
	_made.append(c)
	return c


func cleanup() -> void:
	for c in _made:
		c.free()
	_made.clear()


## Продвигает часы по секунде (один большой кадр обрезался бы MAX_STEPS_PER_FRAME).
func _run_seconds(c: Node, seconds: int) -> void:
	for i in seconds:
		c.advance(1.0)


func _counter(sig: Signal) -> Array:
	var calls := []
	sig.connect(func(v): calls.append(v))
	return calls


func test_starts_at_year_one_spring_day_one(t) -> void:
	var c := _clock()
	t.eq(c.get_year(), 1, "год")
	t.eq(c.get_season(), 0, "сезон")
	t.eq(c.get_day_of_season(), 1, "день сезона")
	t.eq(c.get_date_string(), "Год 1, Весна, день 1", "дата строкой")


func test_new_clock_is_paused(t) -> void:
	var c: Node = Clock.new()
	_made.append(c)
	t.eq(c.paused, true, "новые часы на паузе")
	t.eq(c.advance(1.0), 0, "на паузе шаги не идут")


func test_one_second_is_one_tick_at_x1(t) -> void:
	var c := _clock()
	var ticks := _counter(c.tick)
	var steps: int = c.advance(1.0)
	t.eq(steps, Clock.STEPS_PER_TICK, "шагов за секунду")
	t.eq(ticks, [1], "сигнал tick")
	t.eq(c.get_total_ticks(), 1, "тиков всего")


func test_fractional_frames_accumulate(t) -> void:
	var c := _clock()
	var total := 0
	for i in 40:
		total += c.advance(0.025)  # 40 кадров по 25 мс = 1 секунда
	t.eq(total, Clock.STEPS_PER_TICK, "сумма шагов по маленьким кадрам")


func test_day_after_60_ticks(t) -> void:
	var c := _clock()
	var days := _counter(c.day_passed)
	_run_seconds(c, 59)
	t.eq(days, [], "до 60 тиков дня нет")
	c.advance(1.0)
	t.eq(days, [1], "через 60 тиков — день 1")
	t.eq(c.get_day_of_season(), 2, "второй день сезона")


func test_seasons_and_year(t) -> void:
	var c := _clock()
	var seasons := _counter(c.season_changed)
	var years := _counter(c.year_passed)
	_run_seconds(c, 12 * 60)
	t.eq(seasons, [1, 2, 3, 0], "смена сезонов за год")
	t.eq(years, [2], "наступил год 2")
	t.eq(c.get_date_string(), "Год 2, Весна, день 1", "дата после года")


func test_pause_stops_time(t) -> void:
	var c := _clock()
	c.advance(1.0)
	c.set_paused(true)
	t.eq(c.advance(10.0), 0, "на паузе 0 шагов")
	t.eq(c.get_total_ticks(), 1, "тики не изменились")
	c.toggle_pause()
	t.eq(c.paused, false, "toggle снимает паузу")


func test_speed_x5(t) -> void:
	var c := _clock()
	t.ok(c.set_speed(5), "скорость 5 принята")
	c.advance(1.0)
	t.eq(c.get_total_ticks(), 5, "×5: 5 тиков за секунду")


func test_invalid_speed_rejected(t) -> void:
	var c := _clock()
	t.ok(not c.set_speed(3), "скорость 3 отклонена")
	t.eq(c.speed, 1, "скорость не изменилась")


func test_long_frame_is_capped(t) -> void:
	var c := _clock()
	t.eq(c.advance(1000.0), Clock.MAX_STEPS_PER_FRAME, "долгий кадр обрезан")
	t.eq(c.advance(0.05), 0, "остаток времени отброшен")


func test_signals_paused_and_speed(t) -> void:
	var c := _clock()
	var p := _counter(c.paused_changed)
	var s := _counter(c.speed_changed)
	c.set_paused(true)
	c.set_paused(true)
	c.set_speed(2)
	c.set_speed(2)
	t.eq(p, [true], "paused_changed один раз")
	t.eq(s, [2], "speed_changed один раз")


func test_reset(t) -> void:
	var c := _clock()
	c.set_speed(5)
	_run_seconds(c, 100)
	c.reset()
	t.eq(c.total_steps, 0, "шаги сброшены")
	t.eq(c.speed, 1, "скорость ×1")
	t.eq(c.paused, true, "на паузе")


func test_save_roundtrip(t) -> void:
	var a := _clock()
	a.set_speed(2)
	_run_seconds(a, 30)
	var b := _clock()
	t.eq(b.from_dict(a.to_dict()), "", "загрузка без ошибки")
	t.eq(b.total_steps, a.total_steps, "шаги совпали")
	t.eq(b.speed, 2, "скорость совпала")


func test_from_dict_rejects_bad_data(t) -> void:
	var c := _clock()
	t.has_text(c.from_dict({"total_steps": -5}), "total_steps", "отрицательные шаги")
	t.has_text(c.from_dict({"total_steps": 10, "speed": 3}), "speed", "неверная скорость")
	t.eq(c.total_steps, 0, "состояние не испорчено")
