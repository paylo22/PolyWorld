extends RefCounted
## Лес растёт сам (docs/RESEARCH.md, «Мир и палитра бога»).
##
## Мир целиком не обходится никогда. За тик проверяется случайная порция
## клеток: cells_per_tick = клеток мира × checks_per_cell_per_year / тиков в году
## (data/biomes.json, flora_growth). Порция тика делится на 10 шагов, чтобы
## не было одного тяжёлого шага.
##
## Проверка клетки: если на ней лес, выбирается случайный из 8 соседей.
## Сосед подходит, если это суша без реки, растений и зданий. Лес переходит
## на него с шансом forest_spread[вид леса] биома соседа (data/biomes.json).
## Случайность — только из RandomNumberGenerator мира (правило 8).

const WorldData = preload("res://sim/world_data.gd")
const Clock = preload("res://sim/game_clock.gd")

var world: WorldData
var rng: RandomNumberGenerator
## Сколько клеток проверяется за один тик.
var cells_per_tick: int = 0

var _nflora: int = 0
var _forest := PackedByteArray()
## Шанс перехода: [биом × число видов флоры + вид].
var _spread := PackedFloat32Array()
var _dx := PackedInt32Array()
var _dy := PackedInt32Array()


func _init(p_world: WorldData, defs, p_rng: RandomNumberGenerator) -> void:
	world = p_world
	rng = p_rng
	_nflora = defs.flora_ids.size()
	for id in defs.flora_ids:
		_forest.append(1 if defs.flora[id]["forest"] else 0)
	for bid in defs.biome_ids:
		var sp: Dictionary = defs.biomes[bid]["forest_spread"]
		for fid in defs.flora_ids:
			_spread.append(float(sp.get(fid, 0.0)))
	for d in WorldData.DIRS8:
		_dx.append(d.x)
		_dy.append(d.y)
	var per_year: float = defs.flora_growth["checks_per_cell_per_year"]
	var ticks_per_year := Clock.TICKS_PER_DAY * Clock.DAYS_PER_YEAR
	cells_per_tick = ceili(world.cell_count() * per_year / ticks_per_year)


## Вызывается на каждом шаге часов: делает свою долю порции тика.
func on_step(step_index: int) -> void:
	var s := Clock.STEPS_PER_TICK
	var k := step_index % s
	run(cells_per_tick * (k + 1) / s - cells_per_tick * k / s)


## Целый тик сразу (для тестов и замеров).
func run_tick() -> void:
	run(cells_per_tick)


## Проверяет n случайных клеток. Возвращает, сколько клеток заросло.
func run(n: int) -> int:
	var w := world.width
	var h := world.height
	var total := w * h
	var floras := world.floras
	var heights := world.heights
	var biomes := world.biomes
	var flags := world.flags
	var buildings := world.building_ids
	var grown := 0
	for _k in n:
		var i := rng.randi_range(0, total - 1)
		var f := floras[i]
		if f < 0 or _forest[f] == 0:
			continue
		var d := rng.randi_range(0, 7)
		var x := i % w + _dx[d]
		var y := i / w + _dy[d]
		if x < 0 or y < 0 or x >= w or y >= h:
			continue
		var j := x + y * w
		if floras[j] >= 0 or heights[j] < 0 or buildings[j] >= 0 or flags[j] & WorldData.FLAG_RIVER:
			continue
		var b := biomes[j]
		if b < 0:
			continue
		var chance := _spread[b * _nflora + f]
		if chance > 0.0 and rng.randf() < chance:
			world.set_flora(j, f)
			grown += 1
	return grown
