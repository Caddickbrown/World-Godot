class_name SyntyMaterial
extends RefCounted

# Shared helper: loads the Synty flat-colour palette and creates a
# StandardMaterial3D that can be applied to any Synty mesh.
# Call make() once and reuse the result.

const PALETTE_PATH := "res://assets/textures/PolygonFantasyKingdom_01_A.png"
const GENERIC_PALETTE_PATH := "res://assets/textures/Generic_01_A.png"

static func make() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := load(PALETTE_PATH)
	if tex is Texture2D:
		mat.albedo_texture = tex as Texture2D
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # crisp flat-poly look
	return mat

static func make_generic() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := load(GENERIC_PALETTE_PATH)
	if tex is Texture2D:
		mat.albedo_texture = tex as Texture2D
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat

# Apply mat to every MeshInstance3D in a subtree.
# Skips surfaces that already have a valid albedo texture (they've resolved
# their own material correctly from the FBX import).
static func apply_to(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var existing := mi.get_active_material(s)
				var needs_apply := true
				if existing is StandardMaterial3D:
					if (existing as StandardMaterial3D).albedo_texture != null:
						needs_apply = false
				if needs_apply:
					mi.set_surface_override_material(s, mat)
	for child in node.get_children():
		apply_to(child, mat)
