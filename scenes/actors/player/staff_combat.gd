extends Node
class_name StaffCombat

const STAFF_IDLE_STANCE = {"pos": Vector3(0.72, -0.12, -1.0), "rot": Vector3(10, -90, 25)}
const STAFF_DRAW_DISTANCE: float = 0.18
const STAFF_DRAW_DURATION: float = 0.16
const DEFENSE_TRANSITION_SPEED: float = 28.0
const STANCE_ROTATE_SPEED: float = 12.0
const DEFENSE_READY_DISTANCE: float = 0.04
const DEFENSE_READY_ROT_DOT: float = 0.995
const BREATH_FREQ: float = 1.3
const BREATH_POS_AMOUNT: Vector3 = Vector3(0.014, 0.024, 0.01)
const BREATH_ROT_AMOUNT: Vector3 = Vector3(0.65, 0.25, 0.55)

var combat_ui: CombatUI
var weapon_pivot: Node3D
var camera: Camera3D
var spells: Array[SpellData] = []

var drawing: bool = false
var draw_invalid: bool = false
var draw_closed: bool = false
var sequence: Array[int] = []
var sequence_times: Array[int] = []
var drawn_edges: Dictionary = {}
var breath_time: float = 0.0

func setup(ui: CombatUI, pivot: Node3D, player_camera: Camera3D) -> void:
	combat_ui = ui
	weapon_pivot = pivot
	camera = player_camera

func set_spells(value: Array[SpellData]) -> void:
	spells = value.duplicate()

func is_drawing() -> bool:
	return drawing

func start_draw(start_direction: int) -> void:
	drawing = true
	draw_invalid = false
	draw_closed = false
	sequence.clear()
	sequence_times.clear()
	drawn_edges.clear()
	record_direction(start_direction)

func finish_draw() -> Dictionary:
	drawing = false
	if sequence.is_empty():
		_clear_draw()
		_return_staff_to_idle()
		return {"valid": false, "critical": false}

	var released_msec := Time.get_ticks_msec()
	var spell_match := _get_matched_spell_info()
	var spell: SpellData = spell_match["spell"]
	var matched_pattern_start: int = spell_match["start"]
	var valid_cast := spell != null and not draw_invalid
	var cast_duration := _sequence_duration_from(matched_pattern_start, released_msec) if valid_cast else 999.0
	var critical := valid_cast and cast_duration <= spell.critical_max_time
	print("Magic sequence drawn: ", sequence, " spell: ", spell.spell_name if spell != null else "none", " duration: ", cast_duration, " critical: ", critical)

	_clear_draw()
	if not valid_cast:
		_return_staff_to_idle()
		_play_fizzle_feedback()

	return {
		"valid": valid_cast,
		"critical": critical,
		"spell": spell,
		"mana_cost": spell.mana_cost if spell != null else 0.0
	}

func record_direction(dir_index: int) -> void:
	if not drawing:
		return

	var now := Time.get_ticks_msec()
	if sequence.size() > 0 and sequence[-1] == dir_index:
		return

	if sequence.size() > 1 and sequence[-2] == dir_index:
		_remove_edge(sequence[-2], sequence[-1])
		sequence.pop_back()
		sequence_times.pop_back()
		draw_closed = _is_sequence_closed()
		combat_ui.set_magic_trace(sequence)
		_play_draw_motion(dir_index)
		return

	if draw_closed:
		_invalidate_draw()
		return

	if sequence.size() > 0 and _has_edge(sequence[-1], dir_index):
		_invalidate_draw()
		return

	if sequence.size() > 0 and _edge_crosses_existing(sequence[-1], dir_index):
		_invalidate_draw()
		return

	if sequence.size() > 0:
		_add_edge(sequence[-1], dir_index)

	var closes_symbol := sequence.has(dir_index)
	sequence.append(dir_index)
	sequence_times.append(now)
	if closes_symbol:
		draw_closed = true

	combat_ui.set_magic_trace(sequence)
	_play_draw_motion(dir_index)

func reset() -> void:
	drawing = false
	draw_invalid = false
	draw_closed = false
	_clear_draw()
	breath_time = randf() * TAU

func update_weapon_stance(delta: float, is_defending: bool, defense_stance: Dictionary, is_idle: bool = false) -> Dictionary:
	if drawing:
		return {"defense_ready": false}

	var base_target_pos: Vector3 = STAFF_IDLE_STANCE["pos"]
	var base_target_quat := _degrees_to_quat(STAFF_IDLE_STANCE["rot"])
	if is_defending:
		base_target_pos = defense_stance["pos"]
		base_target_quat = _degrees_to_quat(defense_stance["rot"])
	elif is_idle:
		var breath := _get_breath_offset(delta)
		base_target_pos += breath["pos"]
		base_target_quat *= _local_quat(breath["rot"])

	var rotate_speed := DEFENSE_TRANSITION_SPEED if is_defending else STANCE_ROTATE_SPEED
	var weight := clampf(delta * rotate_speed, 0.0, 1.0)
	weapon_pivot.position = weapon_pivot.position.lerp(base_target_pos, weight)
	weapon_pivot.quaternion = _slerp_short(weapon_pivot.quaternion, base_target_quat, weight)

	var defense_ready := false
	if is_defending:
		var position_ready := weapon_pivot.position.distance_to(base_target_pos) <= DEFENSE_READY_DISTANCE
		var rotation_ready := absf(weapon_pivot.quaternion.dot(base_target_quat)) >= DEFENSE_READY_ROT_DOT
		defense_ready = position_ready and rotation_ready

	return {"defense_ready": defense_ready}

func _get_breath_offset(delta: float) -> Dictionary:
	breath_time += delta * BREATH_FREQ
	var wave := sin(breath_time)
	var side_wave := sin(breath_time * 0.57 + 1.0)
	return {
		"pos": Vector3(BREATH_POS_AMOUNT.x * side_wave, BREATH_POS_AMOUNT.y * wave, BREATH_POS_AMOUNT.z * wave),
		"rot": Vector3(BREATH_ROT_AMOUNT.x * wave, BREATH_ROT_AMOUNT.y * side_wave, BREATH_ROT_AMOUNT.z * side_wave)
	}

func handle_direction_changed(dir_index: int, is_attacking: bool, ui_locked: bool) -> void:
	if is_attacking or ui_locked:
		return

	record_direction(dir_index)

func build_attack_data(active_critical: bool) -> Dictionary:
	var original_pos: Vector3 = STAFF_IDLE_STANCE["pos"]
	var original_quat := _degrees_to_quat(STAFF_IDLE_STANCE["rot"])
	var final_pos := original_pos
	var final_quat := original_quat
	var windup_pos := original_pos + Vector3(0.0, 0.04, 0.12)
	var windup_quat := original_quat * _local_quat(Vector3(-6.0, 0.0, 0.0))
	var attack_pos := original_pos + Vector3(0.0, 0.02, -1.45)
	var attack_quat := original_quat * _local_quat(Vector3(14.0, 0.0, 0.0))
	var camera_kick_dir := Vector3(0.56, 0.0, 0.0)

	windup_pos.z = min(windup_pos.z, original_pos.z + 0.08)
	attack_pos.z = min(attack_pos.z, original_pos.z - 1.45)
	if active_critical:
		attack_pos.z -= 0.45
		camera_kick_dir *= 1.6

	return {
		"weapon_kind": "Staff",
		"attack_direction": -1,
		"next_stance": 0,
		"original_pos": original_pos,
		"original_quat": original_quat,
		"windup_pos": windup_pos,
		"windup_quat": windup_quat,
		"attack_pos": attack_pos,
		"attack_quat": attack_quat,
		"final_pos": final_pos,
		"final_quat": final_quat,
		"camera_kick_dir": camera_kick_dir
	}

func on_attack_finished(_next_stance: int) -> void:
	pass

func _clear_draw() -> void:
	sequence.clear()
	sequence_times.clear()
	drawn_edges.clear()
	if combat_ui != null:
		combat_ui.clear_magic_trace()

func _invalidate_draw() -> void:
	draw_invalid = true
	drawing = false
	_clear_draw()
	_return_staff_to_idle()
	_play_fizzle_feedback()

func _is_sequence_closed() -> bool:
	return sequence.size() > 2 and sequence[0] == sequence[-1]

func _edge_key(from_dir: int, to_dir: int) -> String:
	return "%s:%s" % [min(from_dir, to_dir), max(from_dir, to_dir)]

func _has_edge(from_dir: int, to_dir: int) -> bool:
	return drawn_edges.has(_edge_key(from_dir, to_dir))

func _add_edge(from_dir: int, to_dir: int) -> void:
	drawn_edges[_edge_key(from_dir, to_dir)] = true

func _remove_edge(from_dir: int, to_dir: int) -> void:
	drawn_edges.erase(_edge_key(from_dir, to_dir))

func _edge_crosses_existing(from_dir: int, to_dir: int) -> bool:
	var a := _magic_point(from_dir)
	var b := _magic_point(to_dir)

	for edge_key in drawn_edges.keys():
		var parts := String(edge_key).split(":")
		var c_dir := int(parts[0])
		var d_dir := int(parts[1])
		if from_dir == c_dir or from_dir == d_dir or to_dir == c_dir or to_dir == d_dir:
			continue
		if _segments_intersect(a, b, _magic_point(c_dir), _magic_point(d_dir)):
			return true

	return false

func _magic_point(dir: int) -> Vector2:
	match dir:
		1:
			return Vector2(0.0, -1.0)
		2:
			return Vector2(0.95, -0.31)
		3:
			return Vector2(0.59, 0.81)
		4:
			return Vector2(-0.59, 0.81)
		5:
			return Vector2(-0.95, -0.31)
		_:
			return Vector2.ZERO

func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab := b - a
	var ac := c - a
	var ad := d - a
	var cd := d - c
	var ca := a - c
	var cb := b - c
	return signf(ab.cross(ac)) != signf(ab.cross(ad)) and signf(cd.cross(ca)) != signf(cd.cross(cb))

func _slerp_short(from: Quaternion, to: Quaternion, weight: float) -> Quaternion:
	if from.dot(to) < 0.0:
		to = -to
	return from.slerp(to, weight)

func _play_draw_motion(dir_index: int) -> void:
	if weapon_pivot == null:
		return

	var direction := _direction_offset(dir_index)
	var target_pos: Vector3 = STAFF_IDLE_STANCE["pos"] + Vector3(direction.x, direction.y, 0.0) * STAFF_DRAW_DISTANCE
	var target_quat := _degrees_to_quat(STAFF_IDLE_STANCE["rot"]) * _local_quat(Vector3(-direction.y * 6.0, 0.0, direction.x * 8.0))

	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon_pivot, "position", target_pos, STAFF_DRAW_DURATION)
	tween.tween_property(weapon_pivot, "quaternion", target_quat, STAFF_DRAW_DURATION)

func _return_staff_to_idle() -> void:
	if weapon_pivot == null:
		return

	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon_pivot, "position", STAFF_IDLE_STANCE["pos"], 0.12)
	tween.tween_property(weapon_pivot, "quaternion", _degrees_to_quat(STAFF_IDLE_STANCE["rot"]), 0.12)

func _direction_offset(dir_index: int) -> Vector2:
	match dir_index:
		1:
			return Vector2(0.0, 1.0)
		2:
			return Vector2(0.85, 0.55)
		3:
			return Vector2(0.85, -0.55)
		4:
			return Vector2(-0.85, -0.55)
		5:
			return Vector2(-0.85, 0.55)
		_:
			return Vector2.ZERO

func _get_matched_spell_info() -> Dictionary:
	for spell in spells:
		var pattern := spell.pattern
		if sequence.size() < pattern.size():
			continue
		var offset := sequence.size() - pattern.size()
		var matches := true
		for i in pattern.size():
			if sequence[offset + i] != pattern[i]:
				matches = false
				break
		if matches:
			return {"spell": spell, "start": offset}
	return {"spell": null, "start": -1}

func _sequence_duration_from(start_index: int, released_msec: int) -> float:
	if start_index < 0 or sequence_times.size() < start_index + 1:
		return 999.0
	return float(released_msec - sequence_times[start_index]) / 1000.0

func _play_fizzle_feedback() -> void:
	if camera == null or weapon_pivot == null:
		return

	var fizzle := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	fizzle.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.45, 0.5, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fizzle.material_override = material

	get_tree().current_scene.add_child(fizzle)
	fizzle.global_position = weapon_pivot.global_position + (-camera.global_transform.basis.z.normalized() * 0.5)

	var tween := create_tween()
	tween.tween_property(fizzle, "scale", Vector3(2.0, 2.0, 2.0), 0.18)
	tween.parallel().tween_property(material, "albedo_color", Color(0.45, 0.45, 0.5, 0.0), 0.18)
	tween.tween_callback(fizzle.queue_free)

func _local_quat(rot_degrees: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(
		deg_to_rad(rot_degrees.x),
		deg_to_rad(rot_degrees.y),
		deg_to_rad(rot_degrees.z)
	))

func _degrees_to_quat(rot_degrees: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(
		deg_to_rad(rot_degrees.x),
		deg_to_rad(rot_degrees.y),
		deg_to_rad(rot_degrees.z)
	))
