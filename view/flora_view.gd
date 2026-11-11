extends Node2D
## Рисует флору поверх земли (docs/RESEARCH.md, «Визуал и камера»).
##
## Два слоя:
##   1) «Подлесок» — на каждый чанк картинка 64×64, 1 пиксель на клетку,
##      цвет растения map_color (data/biomes.json). Виден всегда: на мелком
##      масштабе по нему видно, где лес.
##   2) Спрайты — на каждый чанк один MultiMeshInstance2D (правило 5: ни
##      одного узла на растение). Строится только для чанков в видимой области
##      и только при зуме от SPRITE_ZOOM, не больше BUILDS_PER_FRAME за кадр.
##      У чанка 64×64 = 4096 мест, место = клетка; пустая клетка — экземпляр
##      нулевого размера. Так смена одной клетки — правка 12 чисел буфера.
##
## Все спрайты лежат в одной полосе-атласе (собирается при запуске из
## assets/sprites/flora). Какой кусок атласа брать, говорит INSTANCE_CUSTOM.x
## в шейдере flora.gdshader, яркость — INSTANCE_CUSTOM.y.
##
## Изменения флоры берутся из журнала WorldData (flora_log): FloraView только
## читает его со своего места и обновляет изменённые клетки.

const WorldData = preload("res://sim/world_data.gd")
const FloraShader = preload("res://view/flora.gdshader")
const SPRITE_DIR := "res://assets/sprites/flora"

## С какого зума видны спрайты растений (1 клетка = столько пикселей экрана).
const SPRITE_ZOOM := 4.0
const BUILDS_PER_FRAME := 2
## Сколько записей журнала обрабатывать за кадр (остальное — в следующих кадрах).
const LOG_PER_FRAME := 4000
## Размер спрайта: 16 пикселей картинки = 2 клетки мира. Низ — на нижнем крае клетки.
const SPRITE_CELLS := 2.0
const FLOATS := 12  # 8 на Transform2D + 4 на custom data

var world: WorldData
var camera: Camera2D

var _n_types: int = 0
var _colors := PackedByteArray()  # RGBA на каждый вид флоры
var _atlas: ImageTexture
var _mesh: ArrayMesh
var _material: ShaderMaterial

var _under_imgs: Array[Image] = []
var _under_texs: Array[ImageTexture] = []
var _under_dirty := PackedByteArray()
var _mmis: Array = []                   # MultiMeshInstance2D или null на чанк
var _bufs: Array[PackedFloat32Array] = []
var _buf_dirty := PackedByteArray()
var _templates := {}                     # размер чанка → буфер с позициями
var _cursor: int = 0
var _sprites_on := false
var _sprite_root: Node2D


func setup(p_world: WorldData, defs, p_camera: Camera2D) -> void:
	world = p_world
	camera = p_camera
	for ch in get_children():
		ch.queue_free()
	_build_palette(defs)
	_build_mesh()
	_under_imgs.clear()
	_under_texs.clear()
	_mmis.clear()
	_bufs.clear()
	var n := world.chunk_count()
	_under_dirty = PackedByteArray()
	_under_dirty.resize(n)
	_buf_dirty = PackedByteArray()
	_buf_dirty.resize(n)
	var under := Node2D.new()
	under.name = "Undergrowth"
	add_child(under)
	# Спрайты — после подлеска; чанки сортируются по Y, чтобы нижний ряд
	# чанков рисовался поверх верхнего (кроны заходят на соседа сверху).
	_sprite_root = Node2D.new()
	_sprite_root.name = "Sprites"
	_sprite_root.y_sort_enabled = true
	add_child(_sprite_root)
	for c in n:
		var r := world.chunk_rect(c)
		var img := Image.create_from_data(r.size.x, r.size.y, false, Image.FORMAT_RGBA8, _paint_under(r))
		var tex := ImageTexture.create_from_image(img)
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(r.position)
		under.add_child(s)
		_under_imgs.append(img)
		_under_texs.append(tex)
		_mmis.append(null)
		_bufs.append(PackedFloat32Array())
	_cursor = world.flora_log_end


func _process(_delta: float) -> void:
	if world == null:
		return
	_read_log()
	_update_sprites()
	for c in _under_dirty.size():
		if _under_dirty[c] != 0:
			_under_dirty[c] = 0
			_under_texs[c].update(_under_imgs[c])
		if _buf_dirty[c] != 0:
			_buf_dirty[c] = 0
			if _mmis[c] != null:
				(_mmis[c] as MultiMeshInstance2D).multimesh.buffer = _bufs[c]


# --- Журнал изменений -----------------------------------------------------

func _read_log() -> void:
	var end := world.flora_log_end
	if end == _cursor:
		return
	if end - _cursor > WorldData.FLORA_LOG_SIZE:
		_rebuild_all()
		return
	var stop := mini(end, _cursor + LOG_PER_FRAME)
	var log := world.flora_log
	var mask := WorldData.FLORA_LOG_SIZE - 1
	var w := world.width
	var cs := WorldData.CHUNK_SIZE
	for n in range(_cursor, stop):
		var i := log[n & mask]
		var x := i % w
		var y := i / w
		var c := (x / cs) + (y / cs) * world.chunks_x
		var lx := x - (x / cs) * cs
		var ly := y - (y / cs) * cs
		var f := world.floras[i]
		var col := Color(0, 0, 0, 0)
		if f >= 0:
			col = Color8(_colors[f * 4], _colors[f * 4 + 1], _colors[f * 4 + 2], _colors[f * 4 + 3])
		_under_imgs[c].set_pixel(lx, ly, col)
		_under_dirty[c] = 1
		if _mmis[c] != null:
			_write_instance(_bufs[c], lx + ly * world.chunk_rect(c).size.x, i, f)
			_buf_dirty[c] = 1
	_cursor = stop


## Журнал переполнился (очень много изменений сразу) — перечитываем всё.
func _rebuild_all() -> void:
	for c in world.chunk_count():
		var r := world.chunk_rect(c)
		_under_imgs[c].set_data(r.size.x, r.size.y, false, Image.FORMAT_RGBA8, _paint_under(r))
		_under_dirty[c] = 1
		if _mmis[c] != null:
			(_mmis[c] as Node).queue_free()
			_mmis[c] = null
			_bufs[c] = PackedFloat32Array()
	_cursor = world.flora_log_end


# --- Спрайты --------------------------------------------------------------

func _update_sprites() -> void:
	var on := camera != null and camera.zoom.x >= SPRITE_ZOOM
	var vis := _visible_chunks() if on else Rect2i()
	var builds := 0
	for c in _mmis.size():
		var cx := c % world.chunks_x
		var cy := c / world.chunks_x
		var want := on and vis.has_point(Vector2i(cx, cy))
		if _mmis[c] != null:
			(_mmis[c] as Node2D).visible = want
		elif want and builds < BUILDS_PER_FRAME:
			_build_chunk(c)
			builds += 1
	_sprites_on = on


## Прямоугольник чанков, которые видны на экране (с запасом в один чанк).
func _visible_chunks() -> Rect2i:
	var half := get_viewport_rect().size / (2.0 * camera.zoom.x)
	var a := camera.position - half
	var b := camera.position + half
	var cs := float(WorldData.CHUNK_SIZE)
	var x0 := clampi(floori(a.x / cs) - 1, 0, world.chunks_x - 1)
	var y0 := clampi(floori(a.y / cs) - 1, 0, world.chunks_y - 1)
	var x1 := clampi(floori(b.x / cs) + 1, 0, world.chunks_x - 1)
	var y1 := clampi(floori((b.y + SPRITE_CELLS) / cs), 0, world.chunks_y - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _build_chunk(c: int) -> void:
	var r := world.chunk_rect(c)
	var count := r.size.x * r.size.y
	var buf := _template(r.size).duplicate()
	var floras := world.floras
	var w := world.width
	var k := 0
	for y in range(r.position.y, r.end.y):
		var row := y * w
		for x in range(r.position.x, r.end.x):
			var f := floras[x + row]
			if f >= 0:
				_write_instance(buf, k, x + row, f)
			k += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = count
	mm.buffer = buf
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = _atlas
	mmi.material = _material
	mmi.position = Vector2(r.position)
	_sprite_root.add_child(mmi)
	_mmis[c] = mmi
	_bufs[c] = buf


## Буфер чанка, где все места пустые (нулевой размер), но позиции уже стоят:
## центр низа клетки плюс небольшой сдвиг, чтобы лес не стоял ровными рядами.
func _template(size: Vector2i) -> PackedFloat32Array:
	if _templates.has(size):
		return _templates[size]
	var buf := PackedFloat32Array()
	buf.resize(size.x * size.y * FLOATS)
	var k := 0
	for y in size.y:
		for x in size.x:
			var o := k * FLOATS
			var hsh := _hash(x * 7919 + y * 104729)
			buf[o + 3] = x + 0.5 + ((hsh & 15) / 15.0 - 0.5) * 0.4
			buf[o + 7] = y + 1.0 - ((hsh >> 4) & 15) / 15.0 * 0.25
			k += 1
	_templates[size] = buf
	return buf


## Пишет место k буфера: вид f в клетке мира i (или пусто, если f < 0).
func _write_instance(buf: PackedFloat32Array, k: int, i: int, f: int) -> void:
	var o := k * FLOATS
	if f < 0:
		buf[o] = 0.0
		buf[o + 5] = 0.0
		return
	var hsh := _hash(i)
	var s := 0.82 + ((hsh >> 8) & 15) / 15.0 * 0.26
	var flip := -1.0 if (hsh >> 12) & 1 else 1.0
	buf[o] = s * flip
	buf[o + 5] = s
	buf[o + 8] = float(f)
	buf[o + 9] = 0.86 + ((hsh >> 16) & 15) / 15.0 * 0.24


static func _hash(v: int) -> int:
	v = ((v >> 16) ^ v) * 0x45d9f3b
	v = ((v >> 16) ^ v) * 0x45d9f3b
	return ((v >> 16) ^ v) & 0x7fffffff


# --- Подготовка -----------------------------------------------------------

func _build_palette(defs) -> void:
	_n_types = defs.flora_ids.size()
	_colors = PackedByteArray()
	var atlas := Image.create_empty(16 * _n_types, 16, false, Image.FORMAT_RGBA8)
	for n in _n_types:
		var f: Dictionary = defs.flora[defs.flora_ids[n]]
		var c: Color = f["map_color"]
		_colors.append_array([c.r8, c.g8, c.b8, 255])
		var tex := load(SPRITE_DIR.path_join(f["sprite"])) as Texture2D
		if tex == null:
			push_error("FloraView: нет картинки %s" % f["sprite"])
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_size() != Vector2i(16, 16):
			img.resize(16, 16, Image.INTERPOLATE_NEAREST)
		atlas.blit_rect(img, Rect2i(0, 0, 16, 16), Vector2i(16 * n, 0))
	_atlas = ImageTexture.create_from_image(atlas)
	_material = ShaderMaterial.new()
	_material.shader = FloraShader
	_material.set_shader_parameter("slots", float(maxi(_n_types, 1)))


## Квадрат 2×2 клетки, низ по центру — в точке экземпляра.
func _build_mesh() -> void:
	var h := SPRITE_CELLS
	var verts := PackedVector2Array([Vector2(-h / 2, -h), Vector2(h / 2, -h), Vector2(h / 2, 0), Vector2(-h / 2, 0)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Подлесок прямоугольника: RGBA по 4 байта на клетку, пусто — прозрачно.
func _paint_under(r: Rect2i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(r.size.x * r.size.y * 4)
	var floras := world.floras
	var w := world.width
	var o := 0
	for y in range(r.position.y, r.end.y):
		var row := y * w
		for x in range(r.position.x, r.end.x):
			var f := floras[x + row]
			if f >= 0:
				out[o] = _colors[f * 4]
				out[o + 1] = _colors[f * 4 + 1]
				out[o + 2] = _colors[f * 4 + 2]
				out[o + 3] = _colors[f * 4 + 3]
			o += 4
	return out
