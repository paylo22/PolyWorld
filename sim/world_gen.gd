extends RefCounted
## Генерация мира из сида (docs/RESEARCH.md, «Мир и палитра бога»).
##
## Этапы (их можно запускать по одному, чтобы показывать прогресс):
##   0 Рельеф   — шум FastNoiseLite + маска островов → «сырая» высота;
##   1 Высоты   — доля воды и гор задаётся точно через сортировку;
##   2 Реки     — сток к морю (priority flood), реки от холмов и гор по стоку;
##   3 Влажность — второй шум + бонус у рек и моря;
##   4 Биомы    — по паре «высота + влажность», правила в data/worldgen.json;
##   5 Жилы     — руда, уголь, сера, золото в горах; глина у рек.
##
## Все случайности — от одного RandomNumberGenerator с заданным сидом,
## поэтому один сид и одни настройки всегда дают один и тот же мир.
## Все числа — из Defs.worldgen (data/worldgen.json).

const WorldData = preload("res://sim/world_data.gd")

const STAGES: Array[String] = ["Рельеф", "Высоты", "Реки", "Влажность", "Биомы", "Жилы"]

var world: WorldData
var params: Dictionary
## Сколько миллисекунд занял каждый этап (для отладки и замеров).
var stage_ms: Dictionary = {}

var _defs
var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _noise_h := FastNoiseLite.new()
var _noise_ridge := FastNoiseLite.new()
var _noise_m := FastNoiseLite.new()
var _raw := PackedFloat32Array()
var _sea_dist := PackedInt32Array()
var _river_dist := PackedInt32Array()
var _down := PackedInt32Array()
var _land_count := 0


## defs — автозагрузка Defs (или её копия в тестах), p — настройки мира.
func _init(defs, p: Dictionary) -> void:
	_defs = defs
	_cfg = defs.worldgen
	params = normalize_params(p, _cfg)
	var size: int = params["size"]
	world = WorldData.new(size, size)


## Настройки по умолчанию из data/worldgen.json.
static func default_params(cfg: Dictionary) -> Dictionary:
	var d: Dictionary = cfg["defaults"]
	return {"seed": 1, "size": cfg["size_default"], "water": d["water"],
		"mountains": d["mountains"], "islands": d["islands"]}


## Приводит настройки к допустимым: размер кратен шагу, проценты в пределах.
static func normalize_params(p: Dictionary, cfg: Dictionary) -> Dictionary:
	var out := default_params(cfg)
	for k in p:
		if out.has(k):
			out[k] = int(p[k])
	var lim: Dictionary = cfg["limits"]
	var smin: int = cfg["size_min"]
	var step: int = cfg["size_step"]
	var size := clampi(out["size"], smin, cfg["size_max"])
	out["size"] = smin + int(round(float(size - smin) / step)) * step
	out["water"] = clampi(out["water"], lim["water_min"], lim["water_max"])
	out["mountains"] = clampi(out["mountains"], 0, 100)
	out["islands"] = clampi(out["islands"], lim["islands_min"], lim["islands_max"])
	return out


## Сид из текста: число берётся как есть, любой другой текст — по хешу.
static func seed_from_text(text: String) -> int:
	var s := text.strip_edges()
	if s.is_valid_int():
		return s.to_int()
	return s.hash()


## Выполняет все этапы и возвращает готовый мир.
func generate() -> WorldData:
	for i in STAGES.size():
		run_stage(i)
	return world


func run_stage(i: int) -> void:
	var t0 := Time.get_ticks_usec()
	match i:
		0: _stage_relief()
		1: _stage_heights()
		2: _stage_rivers()
		3: _stage_moisture()
		4: _stage_biomes()
		5: _stage_deposits()
	stage_ms[STAGES[i]] = (Time.get_ticks_usec() - t0) / 1000.0
	if i == STAGES.size() - 1:
		_raw = PackedFloat32Array()
		_down = PackedInt32Array()
		world.mark_all_dirty()


func total_ms() -> float:
	var s := 0.0
	for v in stage_ms.values():
		s += v
	return s


# --- 0. Рельеф ------------------------------------------------------------

func _stage_relief() -> void:
	_rng.seed = params["seed"]
	_setup_noise(_noise_h, _rng.randi(), FastNoiseLite.FRACTAL_FBM, _cfg["height_frequency"], _cfg["height_octaves"])
	_setup_noise(_noise_ridge, _rng.randi(), FastNoiseLite.FRACTAL_RIDGED, _cfg["ridge_frequency"], 4)
	_setup_noise(_noise_m, _rng.randi(), FastNoiseLite.FRACTAL_FBM, _cfg["moisture_frequency"], 4)

	var w := world.width
	var h := world.height
	# Маска островов считается на грубой сетке (шаг 8) и сглаживается —
	# так в десятки раз быстрее, чем считать расстояние до центров в каждой клетке.
	var step := 8
	var gw := w / step + 2
	var gh := h / step + 2
	var n_isl: int = params["islands"]
	var centers: Array[Vector2] = []
	var radii: Array[float] = []
	for k in n_isl:
		centers.append(Vector2(_rng.randf_range(0.18, 0.82) * w, _rng.randf_range(0.18, 0.82) * h))
		radii.append(w * 0.5 / sqrt(n_isl) * _rng.randf_range(0.95, 1.3))
	var edge_band := w * 0.08
	var grid := PackedFloat32Array()
	grid.resize(gw * gh)
	for gy in gh:
		for gx in gw:
			var p := Vector2(gx * step, gy * step)
			var m := -1.0
			for k in n_isl:
				m = maxf(m, 1.0 - p.distance_to(centers[k]) / radii[k])
			var edge := minf(minf(p.x, p.y), minf(w - 1 - p.x, h - 1 - p.y))
			m -= (1.0 - clampf(edge / edge_band, 0.0, 1.0)) * 1.5
			grid[gx + gy * gw] = m

	var nw: float = _cfg["noise_weight"]
	var iw: float = _cfg["island_weight"]
	_raw.resize(w * h)
	var inv := 1.0 / step
	for y in h:
		var fy := y * inv
		var gy0 := int(fy)
		var ty := fy - gy0
		for x in w:
			var fx := x * inv
			var gx0 := int(fx)
			var tx := fx - gx0
			var a := gx0 + gy0 * gw
			var top := lerpf(grid[a], grid[a + 1], tx)
			var bot := lerpf(grid[a + gw], grid[a + gw + 1], tx)
			_raw[x + y * w] = _noise_h.get_noise_2d(x, y) * nw + lerpf(top, bot, ty) * iw


func _setup_noise(n: FastNoiseLite, s: int, fractal: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = fractal
	n.frequency = freq
	n.fractal_octaves = octaves


# --- 1. Высоты ------------------------------------------------------------

func _stage_heights() -> void:
	var w := world.width
	var n := world.cell_count()
	var heights := PackedInt32Array()
	heights.resize(n)

	# Вода: самые низкие water% клеток. Глубина растёт к самым низким.
	var order := _sorted_indices(_raw, PackedInt32Array())
	var water_k := int(round(n * params["water"] / 100.0))
	for r in water_k:
		heights[order[r]] = -1000 + int(999.0 * r / water_k)
	var sea_level: float = _raw[order[water_k]] if water_k < n else 1e9

	# Суша: «сырая» высота над водой + горные хребты (ridged-шум), которые
	# растут вглубь суши. Потом ранги раскладываются по поясам равнина/холмы/горы
	# так, чтобы доля гор точно соответствовала ползунку «Гористость».
	var land := PackedInt32Array()
	for r in range(water_k, n):
		land.append(order[r])
	_land_count = land.size()
	var mountains: int = params["mountains"]
	var ridge_w: float = _cfg["ridge_strength"] * (0.5 + mountains / 100.0)
	var e := PackedFloat32Array()
	e.resize(land.size())
	for j in land.size():
		var i := land[j]
		var above := _raw[i] - sea_level
		var ridge := (_noise_ridge.get_noise_2d(i % w, i / w) + 1.0) * 0.5
		e[j] = above + ridge * ridge_w * smoothstep(0.0, 0.12, above)
	var land_order := _sorted_indices(e, land)

	var hills_h: int = _cfg["hills_height"]
	var mount_h: int = _cfg["mountain_height"]
	var pm: float = lerpf(_cfg["mountain_share_min"], _cfg["mountain_share_max"], mountains / 100.0)
	var ph: float = pm * _cfg["hills_ratio"]
	var q_h := 1.0 - pm - ph
	var q_m := 1.0 - pm
	var last := maxi(1, land_order.size() - 1)
	for r in land_order.size():
		var q := float(r) / last
		var hv: int
		if q < q_h:
			hv = 1 + int((hills_h - 2) * q / q_h)
		elif q < q_m:
			hv = hills_h + int((mount_h - hills_h - 1) * (q - q_h) / maxf(ph, 1e-6))
		else:
			hv = mount_h + int((1000 - mount_h) * (q - q_m) / maxf(pm, 1e-6))
		heights[land_order[r]] = hv
	world.heights = heights


## Индексы, отсортированные по значению (по возрастанию). Если ids пуст —
## values[k] относится к клетке k, иначе к клетке ids[k].
## Сортировка упакованных в int64 ключей (значение << 20 | индекс) — быстрая.
func _sorted_indices(values: PackedFloat32Array, ids: PackedInt32Array) -> PackedInt32Array:
	var count := values.size()
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var scale := float(1 << 40) / maxf(hi - lo, 1e-9)
	var keys := PackedInt64Array()
	keys.resize(count)
	var use_ids := not ids.is_empty()
	for k in count:
		var cell: int = ids[k] if use_ids else k
		keys[k] = (int((values[k] - lo) * scale) << 20) | cell
	keys.sort()
	var out := PackedInt32Array()
	out.resize(count)
	for k in count:
		out[k] = keys[k] & 0xFFFFF
	return out


# --- 2. Реки ----------------------------------------------------------------

func _stage_rivers() -> void:
	var w := world.width
	var n := world.cell_count()
	var heights := world.heights
	var flags := world.flags
	_sea_dist = _bfs_distance(heights, PackedInt32Array(), -1)

	_down = _drainage(heights)

	var hills_h: int = _cfg["hills_height"]
	var sources := PackedInt32Array()
	for i in n:
		if heights[i] >= hills_h:
			sources.append(i)
	var want := clampi(_land_count / int(_cfg["land_cells_per_river"]), _cfg["rivers_min"], _cfg["rivers_max"])
	var min_len: int = _cfg["river_min_length"]
	var made := 0
	var tries := 0
	while made < want and tries < want * 10 and not sources.is_empty():
		tries += 1
		var src := sources[_rng.randi_range(0, sources.size() - 1)]
		if flags[src] & WorldData.FLAG_RIVER:
			continue
		# Исток не вплотную к другой реке — иначе две реки бегут рядом.
		var near := false
		for nb in world.neighbor_indices4(src):
			if flags[nb] & WorldData.FLAG_RIVER:
				near = true
		if near:
			continue
		var path := _trace_river(src, heights, flags)
		if path.size() < min_len:
			continue
		made += 1
		var prev := heights[path[0]]
		for i in path:
			flags[i] |= WorldData.FLAG_RIVER
			# Русло прорезает рельеф: вниз по течению высота не растёт.
			prev = clampi(mini(heights[i], prev), 1, 1000)
			heights[i] = prev
	world.heights = heights
	world.flags = flags
	_river_dist = _bfs_distance(heights, flags, maxi(_cfg["river_moisture_radius"], _cfg["clay_radius"]))


## Сток воды (priority flood): «заливаем» сушу от берега по возрастанию
## высоты. Каждая клетка суши запоминает соседа, из которого до неё дошла
## заливка, — это и есть направление течения к морю. Впадины по пути
## заливаются, поэтому из любой клетки сток гарантированно доходит до моря.
## Очередь — корзины по высоте 0..1000, это быстрее кучи.
func _drainage(heights: PackedInt32Array) -> PackedInt32Array:
	var w := world.width
	var n := world.cell_count()
	var down := PackedInt32Array()
	down.resize(n)
	down.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(1001)
	for b in 1001:
		buckets[b] = PackedInt32Array()
	# Начало — клетки воды у берега.
	for i in n:
		if heights[i] < 0:
			done[i] = 1
	for i in n:
		if heights[i] < 0:
			continue
		for nb in world.neighbor_indices4(i):
			if heights[nb] < 0:
				done[i] = 1
				down[i] = nb
				buckets[heights[i]].append(i)
				break
	var dirs := PackedInt32Array([-w, 1, w, -1])
	var level := 0
	while level <= 1000:
		var bucket := buckets[level]
		if bucket.is_empty():
			level += 1
			continue
		var cur := bucket[bucket.size() - 1]
		bucket.resize(bucket.size() - 1)
		buckets[level] = bucket
		var x := cur % w
		# Случайный порядок соседей — чтобы на ровных местах русла не шли по линейке.
		var start := _rng.randi_range(0, 3)
		for k in 4:
			var dk := (start + k) % 4
			if (dk == 1 and x == w - 1) or (dk == 3 and x == 0):
				continue
			var nb := cur + dirs[dk]
			if nb < 0 or nb >= n or done[nb]:
				continue
			done[nb] = 1
			down[nb] = cur
			var lv := maxi(heights[nb], level)
			buckets[lv].append(nb)
	return down


## Путь реки от истока по стоку до моря или до другой реки.
func _trace_river(src: int, heights: PackedInt32Array, flags: PackedInt32Array) -> PackedInt32Array:
	var path := PackedInt32Array()
	var cur := src
	var max_len := world.cell_count()
	while cur >= 0 and path.size() < max_len:
		if heights[cur] < 0 or (cur != src and flags[cur] & WorldData.FLAG_RIVER):
			return path  # дошла до воды или влилась в другую реку
		path.append(cur)
		cur = _down[cur]
	return path


## Расстояние (шаги по 4 сторонам) до ближайшей воды; если передан flags —
## до ближайшей реки. limit < 0 — без ограничения, иначе дальше не считает (-1).
func _bfs_distance(heights: PackedInt32Array, river_flags: PackedInt32Array, limit: int) -> PackedInt32Array:
	var w := world.width
	var h := world.height
	var n := w * h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n)
	var tail := 0
	var rivers := not river_flags.is_empty()
	for i in n:
		var src := (river_flags[i] & WorldData.FLAG_RIVER) != 0 if rivers else heights[i] < 0
		if src:
			dist[i] = 0
			queue[tail] = i
			tail += 1
	var head := 0
	while head < tail:
		var i := queue[head]
		head += 1
		var nd := dist[i] + 1
		if limit >= 0 and nd > limit:
			continue
		var x := i % w
		if i >= w and dist[i - w] < 0:
			dist[i - w] = nd; queue[tail] = i - w; tail += 1
		if i < n - w and dist[i + w] < 0:
			dist[i + w] = nd; queue[tail] = i + w; tail += 1
		if x > 0 and dist[i - 1] < 0:
			dist[i - 1] = nd; queue[tail] = i - 1; tail += 1
		if x < w - 1 and dist[i + 1] < 0:
			dist[i + 1] = nd; queue[tail] = i + 1; tail += 1
	if not rivers:
		for i in n:
			if dist[i] < 0:
				dist[i] = w + h  # воды нет вовсе
	return dist


# --- 3. Влажность -----------------------------------------------------------

func _stage_moisture() -> void:
	var w := world.width
	var n := world.cell_count()
	var heights := world.heights
	var moist := PackedInt32Array()
	moist.resize(n)
	moist.fill(1000)
	var land := PackedInt32Array()
	var vals := PackedFloat32Array()
	for i in n:
		if heights[i] >= 0:
			land.append(i)
			vals.append(_noise_m.get_noise_2d(i % w, i / w))
	# Ранги шума → равномерная влажность 0..1000: каждого биома будет примерно
	# одинаково при любом сиде.
	var order := _sorted_indices(vals, land)
	var last := maxi(1, order.size() - 1)
	for r in order.size():
		moist[order[r]] = int(1000.0 * r / last)

	var rr: int = _cfg["river_moisture_radius"]
	var rb: int = _cfg["river_moisture_bonus"]
	var wr: int = _cfg["water_moisture_radius"]
	var wb: int = _cfg["water_moisture_bonus"]
	for i in land:
		var m := moist[i]
		var dr := _river_dist[i]
		if dr >= 0 and dr <= rr:
			m += int(rb * (1.0 - float(dr) / (rr + 1)))
		var ds := _sea_dist[i]
		if ds <= wr:
			m += int(wb * (1.0 - float(ds) / (wr + 1)))
		moist[i] = mini(m, 1000)
	world.moistures = moist


# --- 4. Биомы ---------------------------------------------------------------

func _stage_biomes() -> void:
	var n := world.cell_count()
	var heights := world.heights
	var moist := world.moistures
	var rules: Array = _cfg["biome_rules"]
	var rc := rules.size()
	var r_b := PackedInt32Array()
	var r_hmin := PackedInt32Array()
	var r_hmax := PackedInt32Array()
	var r_mmin := PackedInt32Array()
	var r_mmax := PackedInt32Array()
	var r_sd := PackedInt32Array()
	for r in rules:
		r_b.append(_defs.biome_index(r["biome"]))
		r_hmin.append(r.get("height_min", 0))
		r_hmax.append(r.get("height_max", 1000))
		r_mmin.append(r.get("moisture_min", 0))
		r_mmax.append(r.get("moisture_max", 1000))
		r_sd.append(r.get("max_sea_distance", 1 << 30))
	var biomes := PackedInt32Array()
	biomes.resize(n)
	for i in n:
		var hv := heights[i]
		if hv < 0:
			biomes[i] = WorldData.NONE
			continue
		var mv := moist[i]
		var sd := _sea_dist[i]
		var b := r_b[rc - 1]
		for k in rc:
			if hv >= r_hmin[k] and hv <= r_hmax[k] and mv >= r_mmin[k] and mv <= r_mmax[k] and sd <= r_sd[k]:
				b = r_b[k]
				break
		biomes[i] = b
	world.biomes = biomes


# --- 5. Жилы ----------------------------------------------------------------

func _stage_deposits() -> void:
	var w := world.width
	var h := world.height
	var n := world.cell_count()
	var heights := world.heights
	var flags := world.flags
	var deposits := world.deposits
	var mount_h: int = _cfg["mountain_height"]
	var hills_h: int = _cfg["hills_height"]

	var mountain_cells := PackedInt32Array()
	for i in n:
		if heights[i] >= mount_h:
			mountain_cells.append(i)
	var veins: Array = _cfg["veins"]
	var total_w := 0.0
	for v in veins:
		total_w += v["weight"]
	var count := maxi(veins.size(), int(round(mountain_cells.size() * float(_cfg["veins_per_1000_mountain"]) / 1000.0)))
	for k in count:
		if mountain_cells.is_empty() or total_w <= 0.0:
			break
		# Сначала по одной жиле каждого вида (чтобы в мире было всё), дальше — по весам.
		var res_id: String = veins[veins.size() - 1]["resource"]
		if k < veins.size():
			res_id = veins[k]["resource"]
		else:
			var pick := _rng.randf() * total_w
			for v in veins:
				pick -= v["weight"]
				if pick < 0.0:
					res_id = v["resource"]
					break
		var res: int = _defs.resource_index(res_id)
		var cur := mountain_cells[_rng.randi_range(0, mountain_cells.size() - 1)]
		var size := _rng.randi_range(_cfg["vein_size_min"], _cfg["vein_size_max"])
		for s in size:
			deposits[cur] = res
			var d: Vector2i = WorldData.DIRS8[_rng.randi_range(0, 7)]
			var nx := cur % w + d.x
			var ny := cur / w + d.y
			if nx >= 0 and ny >= 0 and nx < w and ny < h and heights[nx + ny * w] >= hills_h:
				cur = nx + ny * w

	# Глина: на суше рядом с реками (не в горах и не в самом русле).
	var clay: int = _defs.resource_index("clay")
	var cr: int = _cfg["clay_radius"]
	var chance: float = _cfg["clay_chance"]
	if clay >= 0:
		for i in n:
			var dr := _river_dist[i]
			if dr > 0 and dr <= cr and heights[i] >= 0 and heights[i] < hills_h and deposits[i] < 0:
				if _rng.randf() < chance:
					deposits[i] = clay
	world.deposits = deposits
	world.flags = flags
