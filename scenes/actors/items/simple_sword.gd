extends Node3D

const TEXTURE_PATH := "res://assets/weapons/knight_texture.png"

func _ready() -> void:
	var mesh_instance := _find_first_mesh_instance(self)
	if mesh_instance == null:
		return

	var texture := load(TEXTURE_PATH) as Texture2D
	if texture == null:
		push_warning("SimpleSword: nao foi possivel carregar a textura em %s" % TEXTURE_PATH)
		return

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.metallic = 0.0
	material.roughness = 0.5
	mesh_instance.material_override = material

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D

	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found

	return null
