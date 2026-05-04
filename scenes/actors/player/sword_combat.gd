extends Node
class_name SwordCombat

const STANCE_TRANSITION_DURATION: float = 0.22
const DEFENSE_TRANSITION_SPEED: float = 28.0
const STANCE_ROTATE_SPEED: float = 12.0
const BOTTOM_CROSS_TRANSITION_DURATION: float = 0.45
const BOTTOM_CROSS_ARC_HEIGHT: float = 0.85
const DEFENSE_READY_DISTANCE: float = 0.04
const DEFENSE_READY_ROT_DOT: float = 0.995
const STANCES = {
	0: {"pos": Vector3(0.5, -0.3, -1), "rot": Vector3(0, -90, 90)},
	1: {"pos": Vector3(0, 0.7, -1), "rot": Vector3(0, -90, 0)},
	2: {"pos": Vector3(1, 0.5, -1), "rot": Vector3(-45, -90, 0)},
	3: {"pos": Vector3(0.6, -0.5, -1), "rot": Vector3(-135, -90, 0)},
	4: {"pos": Vector3(-0.6, -0.5, -1), "rot": Vector3(135, -90, 0)},
	5: {"pos": Vector3(-1, 0.5, -1), "rot": Vector3(45, -90, 0)}
}

var combat_ui: CombatUI
var weapon_pivot: Node3D
var camera: Camera3D

var current_stance_index: int = 0
var target_stance_pos: Vector3 = STANCES[0]["pos"]
var target_stance_rot: Vector3 = STANCES[0]["rot"]
var stance_transitioning: bool = false
var stance_from_index: int = 0
var stance_to_index: int = 0
var stance_actual_start_pos: Vector3 = Vector3.ZERO
var stance_actual_start_quat: Quaternion = Quaternion.IDENTITY
var stance_transition_elapsed: float = 0.0

func setup(ui: CombatUI, pivot: Node3D, player_camera: Camera3D) -> void:
	combat_ui = ui
	weapon_pivot = pivot
	camera = player_camera

func reset() -> void:
	current_stance_index = 0
	target_stance_pos = STANCES[0]["pos"]
	target_stance_rot = STANCES[0]["rot"]
	stance_transitioning = false
	stance_transition_elapsed = 0.0

func update_weapon_stance(delta: float, is_defending: bool, defense_stance: Dictionary) -> Dictionary:
	var base_target_pos: Vector3 = target_stance_pos
	var base_target_quat := _degrees_to_quat(target_stance_rot)

	if is_defending:
		base_target_pos = defense_stance["pos"]
		base_target_quat = _degrees_to_quat(defense_stance["rot"])
		stance_transitioning = false

	if stance_transitioning:
		var is_arc := _is_bottom_cross_transition(stance_from_index, stance_to_index) and not is_defending
		var duration := BOTTOM_CROSS_TRANSITION_DURATION if is_arc else STANCE_TRANSITION_DURATION
		stance_transition_elapsed += delta
		var progress := clampf(stance_transition_elapsed / duration, 0.0, 1.0)
		var eased_progress := _smooth_step(progress)

		if is_arc:
			var control: Vector3 = (STANCES[stance_from_index]["pos"] + STANCES[stance_to_index]["pos"]) * 0.5 + Vector3(0.0, BOTTOM_CROSS_ARC_HEIGHT, 0.0)
			weapon_pivot.position = _quadratic_bezier(stance_actual_start_pos, control, base_target_pos, eased_progress)

			var mid_quat := _degrees_to_quat(STANCES[1]["rot"])
			if eased_progress < 0.5:
				weapon_pivot.quaternion = _slerp_short(stance_actual_start_quat, mid_quat, eased_progress * 2.0)
			else:
				weapon_pivot.quaternion = _slerp_short(mid_quat, base_target_quat, (eased_progress - 0.5) * 2.0)
		else:
			weapon_pivot.position = stance_actual_start_pos.lerp(base_target_pos, eased_progress)
			weapon_pivot.quaternion = _slerp_short(stance_actual_start_quat, base_target_quat, eased_progress)

		if progress >= 1.0:
			stance_transitioning = false
	else:
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

func handle_direction_changed(dir_index: int, is_attacking: bool, ui_locked: bool) -> void:
	if is_attacking or ui_locked:
		return

	stance_from_index = current_stance_index
	stance_to_index = dir_index
	stance_actual_start_pos = weapon_pivot.position
	stance_actual_start_quat = weapon_pivot.quaternion
	stance_transitioning = true
	stance_transition_elapsed = 0.0
	current_stance_index = dir_index
	target_stance_pos = STANCES[dir_index]["pos"]
	target_stance_rot = STANCES[dir_index]["rot"]

func build_attack_data(active_critical: bool) -> Dictionary:
	var attack_from_stance := current_stance_index
	var next_stance := _get_next_stance_after_attack(attack_from_stance)
	if combat_ui != null:
		combat_ui.set_direction(next_stance)

	var original_pos: Vector3 = STANCES[attack_from_stance]["pos"]
	var original_quat := _degrees_to_quat(STANCES[attack_from_stance]["rot"])
	var final_pos: Vector3 = STANCES[next_stance]["pos"]
	var final_quat := _degrees_to_quat(STANCES[next_stance]["rot"])
	var pose := _build_attack_pose(attack_from_stance, original_pos, original_quat)
	var camera_kick_dir := _get_camera_kick_dir(attack_from_stance)
	var is_thrust := attack_from_stance == 0

	var windup_pos: Vector3 = pose["windup_pos"]
	var attack_pos: Vector3 = pose["attack_pos"]
	windup_pos.z = min(windup_pos.z, original_pos.z + 0.08)
	attack_pos.z = min(attack_pos.z, original_pos.z - (2.5 if is_thrust else 0.35))
	if active_critical:
		attack_pos.z -= 0.45
		camera_kick_dir *= 1.6

	return {
		"next_stance": next_stance,
		"original_pos": original_pos,
		"original_quat": original_quat,
		"windup_pos": windup_pos,
		"windup_quat": pose["windup_quat"],
		"attack_pos": attack_pos,
		"attack_quat": pose["attack_quat"],
		"final_pos": final_pos,
		"final_quat": final_quat,
		"camera_kick_dir": camera_kick_dir
	}

func on_attack_finished(next_stance: int) -> void:
	current_stance_index = next_stance
	target_stance_pos = STANCES[next_stance]["pos"]
	target_stance_rot = STANCES[next_stance]["rot"]
	stance_transitioning = false

func _build_attack_pose(from_stance: int, original_pos: Vector3, original_quat: Quaternion) -> Dictionary:
	match from_stance:
		0:
			return {
				"windup_pos": original_pos,
				"windup_quat": original_quat * _local_quat(Vector3(8.0, 0.0, 0.0)),
				"attack_pos": original_pos,
				"attack_quat": original_quat
			}
		1:
			return {
				"windup_pos": original_pos + Vector3(0.0, 0.16, -1.20),
				"windup_quat": original_quat * _local_quat(Vector3(0, 0.0, -5.0)),
				"attack_pos": original_pos + Vector3(0.0, -2.10, -0.95),
				"attack_quat": original_quat * _local_quat(Vector3(0, 0.0, 150.0))
			}
		2:
			return {
				"windup_pos": original_pos + Vector3(0.14, 0.10, 0.18),
				"windup_quat": original_quat * _local_quat(Vector3(-10.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(-2.30, -2.0, -0.95),
				"attack_quat": original_quat * _local_quat(Vector3(12.0, 0.0, 150.0))
			}
		3:
			return {
				"windup_pos": original_pos + Vector3(0.12, -0.06, 0.14),
				"windup_quat": original_quat * _local_quat(Vector3(-12.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(-2.30, 0.76, -0.76),
				"attack_quat": original_quat * _local_quat(Vector3(18.0, 0.0, 150.0))
			}
		4:
			return {
				"windup_pos": original_pos + Vector3(-0.12, -0.06, 0.14),
				"windup_quat": original_quat * _local_quat(Vector3(5.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(2.0, 1.5, -0.76),
				"attack_quat": original_quat * _local_quat(Vector3(-18.0, 0.0, 150.0))
			}
		5:
			return {
				"windup_pos": original_pos + Vector3(-0.14, 0.10, 0.18),
				"windup_quat": original_quat * _local_quat(Vector3(12.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(2.30, -2.0, -0.95),
				"attack_quat": original_quat * _local_quat(Vector3(18.0, 0.0, 150.0))
			}
		_:
			return {
				"windup_pos": original_pos + Vector3(0.0, 0.05, 0.15),
				"windup_quat": original_quat,
				"attack_pos": original_pos + Vector3(0.0, 0.0, -0.75),
				"attack_quat": original_quat
			}

func _get_next_stance_after_attack(current: int) -> int:
	match current:
		1:
			return 3 if randf() > 0.5 else 4
		2:
			return 4
		3:
			return 5
		4:
			return 2
		5:
			return 3
		_:
			return current

func _get_camera_kick_dir(stance: int) -> Vector3:
	match stance:
		1:
			return Vector3(1.2, 0.2, 0.0)
		2, 3:
			return Vector3(0.0, 1.0, -0.5)
		4, 5:
			return Vector3(0.0, -1.0, 0.5)
		_:
			return Vector3(0.8, 0.0, 0.0)

func _smooth_step(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return (u * u * p0) + (2.0 * u * t * p1) + (t * t * p2)

func _slerp_short(from: Quaternion, to: Quaternion, weight: float) -> Quaternion:
	if from.dot(to) < 0.0:
		to = -to
	return from.slerp(to, weight)

func _is_bottom_cross_transition(from_index: int, to_index: int) -> bool:
	return (
		(from_index == 4 and to_index == 3) or
		(from_index == 3 and to_index == 4)
	)

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
