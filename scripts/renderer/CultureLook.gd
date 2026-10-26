class_name CultureLook
extends RefCounted
## How a camp's culture shows on its buildings (SettlementRenderer calls these,
## drawing into the place's one PropKit mesh). Colours come from the Culture
## (seeded per settlement), never from the global RNG. docs/features/cultures.md.

## Dwelling colours: [wall/tent, roof] for a tier, from the culture.
static func dwelling_colours(cul: Culture, tier: int, base_tent: Color, base_roof: Color) -> Array:
	if cul == null:
		return [base_tent, base_roof]
	match tier:
		0:
			# Hide tents take a wash of the camp's dye; a dyeing camp's are bright.
			return [base_tent.lerp(cul.dye(), 0.7 if cul.dyed else 0.6), base_roof]
		1:
			return [base_tent, cul.hut_roof()]
		_:
			return [base_tent, cul.town_roof()]

## The roof's top, above the ground at a dwelling, by tier.
static func _top(tier: int) -> float:
	return [2.6, 3.1, 3.1][clampi(tier, 0, 2)]

## A camp's mark on one home (xf: the dwelling, +z its door). i: which home.
static func dwelling_deco(k: PropKit, xf: Transform3D, cul: Culture, tier: int, i: int) -> void:
	if cul == null:
		return
	var dye := LookStyle.g(cul.dye())
	var wood := LookStyle.g(Color(0.42, 0.30, 0.20))
	var bone := LookStyle.g(Color(0.94, 0.90, 0.80))
	var door_z := 1.45 if tier > 0 else 1.0
	match cul.deco():
		"pennants":
			# A tall pole beside the door with a flag in the camp's colour.
			var px := 1.3 if i % 2 == 0 else -1.3
			k.cyl(0.05, 0.06, 4.2, xf * PropKit.at(Vector3(px, 0, door_z * 0.6)), wood, 5)
			k.box(Vector3(1.2, 0.65, 0.05), xf * PropKit.at(Vector3(px + signf(px) * 0.62, 3.75, door_z * 0.6)), dye)
		"antlers":
			# Big antlers over the door, and a band of the dye under them.
			var ay: float = [1.7, 1.9, 2.3][clampi(tier, 0, 2)]
			for side in [-1.0, 1.0]:
				var b := Basis(Vector3.FORWARD, side * 0.6)
				k.box(Vector3(0.12, 1.3, 0.12), xf * Transform3D(b, Vector3(side * 0.4, ay, door_z + 0.08)), bone)
				k.box(Vector3(0.1, 0.6, 0.1), xf * Transform3D(Basis(Vector3.FORWARD, side * 1.2), Vector3(side * 0.75, ay + 0.4, door_z + 0.08)), bone)
			k.box(Vector3(1.2, 0.22, 0.08), xf * PropKit.at(Vector3(0, ay - 0.55, door_z + 0.06)), dye)
		"lanterns":
			# A post by the door with a lantern; a dyed cloth hangs below it.
			k.cyl(0.05, 0.06, 1.9, xf * PropKit.at(Vector3(0.95, 0, door_z)), wood, 5)
			k.ball(0.22, xf * PropKit.at(Vector3(0.95, 2.0, door_z)), LookStyle.g(Color(1.0, 0.84, 0.42)))
			k.box(Vector3(0.36, 0.5, 0.04), xf * PropKit.at(Vector3(0.95, 1.5, door_z + 0.06)), dye)
		"painted bands":
			# A broad painted band round the home (tents low, huts at the eaves).
			var y := 0.45 if tier == 0 else 1.15
			var r := 1.25 if tier == 0 else 1.62
			if tier >= 2:
				k.box(Vector3(3.08, 0.34, 2.48), xf * PropKit.at(Vector3(0, 1.45, 0)), dye)
			else:
				k.cyl(r * 0.97, r, 0.36, xf * PropKit.at(Vector3(0, y, 0)), dye, 10)
		"bunting":
			# A string of little flags from the roof to a pole out front.
			var top := _top(tier) - 0.3
			var pole := Vector3(0, 0, door_z + 2.2)
			k.cyl(0.04, 0.05, 2.4, xf * PropKit.at(pole), wood, 4)
			var from := Vector3(0, top, 0)
			var to := pole + Vector3(0, 2.3, 0)
			for f in 5:
				var t := (f + 0.5) / 5.0
				var p := from.lerp(to, t) - Vector3(0, sin(t * PI) * 0.35, 0)
				var col := dye if f % 2 == 0 else bone
				k.cyl(0.0, 0.2, 0.38, xf * Transform3D(Basis(Vector3.RIGHT, PI), p + Vector3(0, 0.02, 0)), col, 3)
		"carved posts":
			# Two carved posts at the door with dyed caps.
			for side in [-1.0, 1.0]:
				var at := Vector3(side * 0.75, 0, door_z + 0.45)
				k.cyl(0.1, 0.13, 1.5, xf * PropKit.at(at), wood, 6)
				k.ball(0.2, xf * PropKit.at(at + Vector3(0, 1.6, 0)), dye)

## The camp's pole by the hearth: a tall banner in its colour, readable from the sky.
## at: local position (metres from the hearth), on the ground.
static func hearth_banner(k: PropKit, at: Vector3, cul: Culture) -> void:
	if cul == null:
		return
	var dye := LookStyle.g(cul.dye())
	var wood := LookStyle.g(Color(0.40, 0.28, 0.18))
	# A drum of dyed cloth round the pole reads from any side (a flat flag
	# vanishes edge-on), with a pale hem and a gilded knob.
	k.cyl(0.1, 0.12, 7.2, PropKit.at(at), wood, 6)
	k.cyl(0.8, 0.8, 2.0, PropKit.at(at + Vector3(0, 4.6, 0)), dye, 10)
	k.cyl(0.84, 0.84, 0.3, PropKit.at(at + Vector3(0, 4.45, 0)), LookStyle.g(Color(0.95, 0.92, 0.84)), 10)
	k.ball(0.26, PropKit.at(at + Vector3(0, 7.3, 0)), LookStyle.g(Color(0.95, 0.84, 0.40)))
