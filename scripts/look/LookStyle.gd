class_name LookStyle
extends RefCounted
## World colours for the two looks in docs/ART_DIRECTION.md. The UI style
## picks the world style: storybook UI -> storybook world, field notes UI ->
## naturalist world (the cartoon turned down).

static func naturalist() -> bool:
	return UiTheme.style == "fieldnotes"

const SAND := Color(0.90, 0.80, 0.58)
const WET_SAND := Color(0.72, 0.62, 0.45)
const MEADOW := Color(0.42, 0.62, 0.26)
const MEADOW_DRY := Color(0.62, 0.64, 0.32)
const WOOD := Color(0.30, 0.52, 0.22)
const FOREST := Color(0.18, 0.38, 0.17)
const ASH := Color(0.20, 0.18, 0.16)
const DESERT := Color(0.86, 0.68, 0.42)
const ROCK := Color(0.55, 0.52, 0.50)
const ROCK_DARK := Color(0.40, 0.38, 0.38)
const SNOW := Color(0.95, 0.97, 1.0)
const BARREN := Color(0.62, 0.52, 0.36)
const TRAMPLED := Color(0.60, 0.50, 0.35)
const RIVER := Color(0.30, 0.62, 0.70)
const LAVA := Color(0.55, 0.16, 0.08)

const TRIBES := [Color(0.80, 0.42, 0.22), Color(0.88, 0.70, 0.30), Color(0.62, 0.30, 0.24),
	Color(0.92, 0.86, 0.70), Color(0.30, 0.55, 0.62), Color(0.55, 0.62, 0.30)]
const TRIBES_NAT := [Color(0.48, 0.38, 0.28), Color(0.58, 0.50, 0.38), Color(0.42, 0.30, 0.24),
	Color(0.62, 0.58, 0.48), Color(0.38, 0.44, 0.44), Color(0.46, 0.48, 0.34)]
const SKIN := [Color(0.93, 0.76, 0.60), Color(0.78, 0.56, 0.40), Color(0.55, 0.37, 0.26), Color(0.98, 0.84, 0.70)]
const HAIR := [Color(0.16, 0.11, 0.08), Color(0.36, 0.22, 0.12), Color(0.62, 0.42, 0.22), Color(0.85, 0.82, 0.78)]

## Colour grade: the naturalist look pulls toward a warm olive grey and darkens.
static func g(c: Color) -> Color:
	if not naturalist():
		return c
	var grey := c.get_luminance()
	return c.lerp(Color(grey * 1.04, grey, grey * 0.80), 0.32).darkened(0.14)

static func tribe(i: int) -> Color:
	var list: Array = TRIBES_NAT if naturalist() else TRIBES
	return list[posmod(i, list.size())]

## Ground colour from the continuous biome field, then the tile's own state.
static func ground(nv: float, h: float, nrm: Vector3, tile: Dictionary, wobble: float) -> Color:
	var c := MEADOW
	c = c.lerp(MEADOW_DRY, wobble * 0.45)
	c = c.lerp(WOOD, smoothstep(0.14, 0.22, nv))
	c = c.lerp(FOREST, smoothstep(0.27, 0.35, nv))
	c = c.lerp(ROCK, smoothstep(0.50, 0.58, nv))
	if not tile.is_empty():
		match int(tile["type"]):
			World.TileType.DESERT: c = c.lerp(DESERT, 0.85)
			World.TileType.GLACIER: c = SNOW.lerp(Color(0.75, 0.86, 0.95), 0.3)
			World.TileType.LAVA: c = LAVA
		if float(tile.get("depletion_level", 0.0)) > 0.0:
			c = c.lerp(BARREN, clampf(float(tile["depletion_level"]), 0.0, 1.0) * 0.7)
		if bool(tile.get("tree_cut", false)):
			c = c.lerp(BARREN, 0.35)
		if float(tile.get("burnt", 0.0)) > 0.0:
			c = c.lerp(ASH, 0.75)
		if bool(tile.get("river", false)):
			c = c.lerp(RIVER, 0.75)
	# Sand is a height band (smooth), never the tile type (which steps).
	if h > -2.5:
		c = c.lerp(SAND, (1.0 - smoothstep(0.45, 1.1, h)) * (0.85 if h > 0.0 else 0.4))
	if h <= 0.0:
		c = c.lerp(WET_SAND, clampf(-h / 2.0, 0.0, 1.0))
	var slope := 1.0 - nrm.y
	c = c.lerp(ROCK_DARK, smoothstep(0.25, 0.55, slope))
	c = c.lerp(SNOW, smoothstep(13.0, 17.0, h) * (1.0 - smoothstep(0.35, 0.6, slope)))
	return g(c)
