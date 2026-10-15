class_name Minimap
extends Control
## The island from above, in the HUD's corner: land and sea from the tiles,
## settlements as dots sized by what they've grown into, the person you're
## following, and a marker for where the camera looks. Click to look there.
## The land image is redrawn slowly (tiles change: woods, floods, felling);
## the markers every frame. Reads the world, never writes it.

const SIZE := 176.0
const REDRAW_SECONDS := 6.0

var main: Node
var _tex: ImageTexture
var _redraw := 0.0
var _world_ref: WeakRef

func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "The island (M to hide) · click to look there"

func _process(delta: float) -> void:
	if not visible or main == null or main.world == null:
		return
	_redraw -= delta
	if _tex == null or _redraw <= 0.0 or _world_ref == null or _world_ref.get_ref() != main.world:
		_redraw = REDRAW_SECONDS
		_world_ref = weakref(main.world)
		_paint()
	queue_redraw()

## The land, one pixel per tile, coloured as the look colours the ground.
func _paint() -> void:
	var w: World = main.world
	var img := Image.create(w.width, w.height, false, Image.FORMAT_RGBA8)
	for z in w.height:
		for x in w.width:
			img.set_pixel(x, z, colour_of(w.tiles[z][x]))
	if _tex == null:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)

static func colour_of(tile: Dictionary) -> Color:
	var c: Color
	match int(tile["type"]):
		World.TileType.DEEP_WATER: c = Color(0.16, 0.30, 0.52)
		World.TileType.WATER: c = Color(0.30, 0.55, 0.70)
		World.TileType.BEACH: c = LookStyle.SAND
		World.TileType.GRASS: c = LookStyle.MEADOW
		World.TileType.WOODLAND: c = LookStyle.WOOD
		World.TileType.FOREST: c = LookStyle.FOREST
		World.TileType.STONE, World.TileType.MOUNTAIN: c = LookStyle.ROCK
		World.TileType.GLACIER: c = LookStyle.SNOW
		World.TileType.LAVA: c = LookStyle.LAVA
		_: c = LookStyle.DESERT
	if bool(tile.get("river", false)):
		c = Color(0.30, 0.55, 0.70)
	if bool(tile.get("flooded", false)):
		c = c.lerp(Color(0.30, 0.55, 0.70), 0.7)
	if bool(tile.get("tree_cut", false)) or float(tile.get("burnt", 0.0)) > 0.0:
		c = c.lerp(LookStyle.BARREN, 0.5)
	return LookStyle.g(c)

func _draw() -> void:
	if _tex == null or main == null or main.world == null:
		return
	var w: World = main.world
	var k := SIZE / float(w.width)
	var ink := UiTheme.c("ink") if UiTheme.style == "storybook" else UiTheme.c("border")
	var sb := UiTheme.panel_box()
	draw_style_box(sb, Rect2(Vector2(-6, -6), Vector2(SIZE + 12, SIZE + 12)))
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)
	# Settlements: bigger dots for hamlets and towns.
	for st in main.settlement_system.get_settlements():
		var r := 2.5 + 1.5 * int(st.tier)
		draw_circle(st.centre * k, r + 1.2, ink)
		draw_circle(st.centre * k, r, UiTheme.c("accent"))
	# Whoever you're following.
	var sel = main.selected_agent
	if sel and not sel.is_dead:
		draw_circle(sel.pos * k, 3.0, UiTheme.c("select"))
		draw_arc(sel.pos * k, 5.0, 0, TAU, 16, ink, 1.5)
	# Where the eye is: a ring, sized by how far out the camera is.
	var f: Vector2 = main._focus_tile()
	var view_r := clampf(main._view_distance() / World.TILE_SIZE * 0.6, 3.0, SIZE * 0.4 / k) * k
	draw_arc(f * k, view_r, 0, TAU, 32, Color(1, 1, 1, 0.9), 2.0)
	draw_arc(f * k, view_r + 1.5, 0, TAU, 32, Color(ink, 0.6), 1.0)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and main and main.world:
		var tile := (ev as InputEventMouseButton).position / (SIZE / float(main.world.width))
		main.look_at_tile(tile)
		accept_event()
