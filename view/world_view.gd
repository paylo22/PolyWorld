extends Node2D
## Рисует землю: 1 клетка мира = 1 пиксель (docs/RESEARCH.md, «Визуал и камера»).
##
## Мир разбит на чанки 64×64, у каждого своя Image + ImageTexture + Sprite2D
## (фильтр Nearest). Когда WorldData помечает чанк изменённым, перерисовывается
## и заново загружается в видеопамять только он, и не больше
## MAX_CHUNKS_PER_FRAME за кадр (правило 4 CLAUDE.md) — остальные в следующих кадрах.
##
## Цвет клетки:
##   вода — от светлой отмели к тёмной глубине, у берега светлая кромка (пена);
##   река — свой цвет;
##   суша — цвет биома из biomes.json, выше — светлее, пики со снегом;
##     если северный сосед выше — клетка в тени (тёмная южная сторона гор),
##     если ниже — подсвечена; у воды — светлая песчаная кромка;
##   жила — смешивается с map_color ресурса.

const WorldData = preload("res://sim/world_data.gd")

const WATER_SHALLOW := Color("#3d7cb4")
const WATER_DEEP := Color("#163861")
const FOAM := Color("#a6d0e4")
const RIVER := Color("#4b8cc8")
const SNOW := Color("#efefe8")
const SAND_RIM := Color("#efe3b8")
const UNKNOWN := Color("#ff00ff")

const MAX_CHUNKS_PER_FRAME := 4
const SNOW_HEIGHT := 930
const SHADOW_PER_UNIT := 0.012
const SHADOW_MAX := 0.45
const LIGHT_PER_UNIT := 0.006
const LIGHT_MAX := 0.15

var world: WorldData

var _sprites: Array[Sprite2D] = []
var _textures: Array[ImageTexture] = []
var _biome_rgb := PackedFloat32Array()
var _deposit_rgb := PackedFloat32Array()  # r,g,b,есть ли цвет — на каждый ресурс

## Сколько миллисекунд заняла последняя полная отрисовка.
var last_build_ms: float = 0.0


func setup(p_world: WorldData, defs) -> void:
	world = p_world
	_build_palette(defs)
	var t0 := Time.get_ticks_usec()
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	_textures.clear()
	var full := Rect2i(0, 0, world.width, world.height)
	var img := Image.create_from_data(world.width, world.height, false, Image.FORMAT_RGB8, paint_rect(full))
	for c in world.chunk_count():
		var r := world.chunk_rect(c)
		var tex := ImageTexture.create_from_image(img.get_region(r))
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(r.position)
		add_child(s)
		_sprites.append(s)
		_textures.append(tex)
	world.take_dirty_chunks()
	last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _process(_delta: float) -> void:
	if world and world.has_dirty_chunks():
		for c in world.take_dirty_chunks(MAX_CHUNKS_PER_FRAME):
			var r := world.chunk_rect(c)
			_textures[c].update(Image.create_from_data(r.size.x, r.size.y, false, Image.FORMAT_RGB8, paint_rect(r)))


func _build_palette(defs) -> void:
	_biome_rgb = PackedFloat32Array()
	for id in defs.biome_ids:
		var c: Color = defs.biomes[id]["color"]
		_biome_rgb.append_array([c.r, c.g, c.b])
	_deposit_rgb = PackedFloat32Array()
	for id in defs.resource_ids:
		var r: Dictionary = defs.resources[id]
		if r.has("map_color"):
			var c: Color = r["map_color"]
			_deposit_rgb.append_array([c.r, c.g, c.b, 1.0])
		else:
			_deposit_rgb.append_array([0.0, 0.0, 0.0, 0.0])


## Цвета клеток прямоугольника в формате RGB8 (по 3 байта на клетку).
func paint_rect(rect: Rect2i) -> PackedByteArray:
	var w := world.width
	var h := world.height
	var heights := world.heights
	var biomes := world.biomes
	var flags := world.flags
	var resources := world.resources
	var out := PackedByteArray()
	out.resize(rect.size.x * rect.size.y * 3)
	var o := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := x + y * w
			var hv := heights[i]
			var hn := heights[i - w] if y > 0 else hv
			var hs := heights[i + w] if y < h - 1 else hv
			var hw := heights[i - 1] if x > 0 else hv
			var he := heights[i + 1] if x < w - 1 else hv
			var r: float
			var g: float
			var b: float
			if hv < 0:
				var t := clampf(-hv / 700.0, 0.0, 1.0)
				r = lerpf(WATER_SHALLOW.r, WATER_DEEP.r, t)
				g = lerpf(WATER_SHALLOW.g, WATER_DEEP.g, t)
				b = lerpf(WATER_SHALLOW.b, WATER_DEEP.b, t)
				if hn >= 0 or hs >= 0 or hw >= 0 or he >= 0:
					r = lerpf(r, FOAM.r, 0.55)
					g = lerpf(g, FOAM.g, 0.55)
					b = lerpf(b, FOAM.b, 0.55)
			elif flags[i] & WorldData.FLAG_RIVER:
				var dark := 1.0 - clampf((hn - hv) * SHADOW_PER_UNIT, 0.0, 0.25)
				r = RIVER.r * dark
				g = RIVER.g * dark
				b = RIVER.b * dark
			else:
				var bi := biomes[i]
				if bi >= 0:
					r = _biome_rgb[bi * 3]
					g = _biome_rgb[bi * 3 + 1]
					b = _biome_rgb[bi * 3 + 2]
				else:
					r = UNKNOWN.r
					g = UNKNOWN.g
					b = UNKNOWN.b
				# Выше — светлее; пики под снегом.
				var bright := 0.88 + 0.24 * hv / 1000.0
				if hv > SNOW_HEIGHT:
					var s := (hv - SNOW_HEIGHT) / float(1000 - SNOW_HEIGHT) * 0.8
					r = lerpf(r, SNOW.r, s)
					g = lerpf(g, SNOW.g, s)
					b = lerpf(b, SNOW.b, s)
				# Свет с севера: северный сосед выше — тень (южный склон тёмный).
				var dn := maxi(hn, 0) - hv
				var shade: float
				if dn > 0:
					shade = 1.0 - minf(dn * SHADOW_PER_UNIT, SHADOW_MAX)
				else:
					shade = 1.0 + minf(-dn * LIGHT_PER_UNIT, LIGHT_MAX)
				shade *= 1.0 - clampf((maxi(hw, 0) - hv) * 0.004, -0.06, 0.1)
				var k := bright * shade
				r *= k
				g *= k
				b *= k
				var dep := resources[i]
				if dep >= 0 and _deposit_rgb[dep * 4 + 3] > 0.0:
					r = lerpf(r, _deposit_rgb[dep * 4], 0.65)
					g = lerpf(g, _deposit_rgb[dep * 4 + 1], 0.65)
					b = lerpf(b, _deposit_rgb[dep * 4 + 2], 0.65)
				if hn < 0 or hs < 0 or hw < 0 or he < 0:
					r = lerpf(r, SAND_RIM.r, 0.35)
					g = lerpf(g, SAND_RIM.g, 0.35)
					b = lerpf(b, SAND_RIM.b, 0.35)
			out[o] = clampi(int(r * 255.0), 0, 255)
			out[o + 1] = clampi(int(g * 255.0), 0, 255)
			out[o + 2] = clampi(int(b * 255.0), 0, 255)
			o += 3
	return out
