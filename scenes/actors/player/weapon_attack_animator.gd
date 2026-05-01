extends Node
class_name WeaponAttackAnimator

const WEAPON_POSITION_TRACK := NodePath("../CameraPivot/Camera3D/WeaponPivot:position")
const WEAPON_ROTATION_TRACK := NodePath("../CameraPivot/Camera3D/WeaponPivot:quaternion")
const SELF_METHOD_TRACK := NodePath(".")
const LIBRARY_NAME := StringName("runtime")
const ANIMATION_NAME := StringName("weapon_attack_runtime")
const ATTACK_SPEED_SCALE := 2

var _animation_player: AnimationPlayer
var _impact_callback: Callable
var _finish_callback: Callable
var _impact_dir: Vector3 = Vector3.ZERO
var _next_stance: int = 0
var _final_pos: Vector3 = Vector3.ZERO
var _final_rot: Vector3 = Vector3.ZERO

func _ready() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)

func play_attack(
	original_pos: Vector3,
	original_rot_quat: Quaternion,
	windup_pos: Vector3,
	windup_rot_quat: Quaternion,
	attack_pos: Vector3,
	attack_rot_quat: Quaternion,
	final_pos: Vector3,
	final_rot_quat: Quaternion,
	next_stance: int,
	impact_dir: Vector3,
	on_impact: Callable,
	on_finish: Callable
) -> void:
	_impact_callback = on_impact
	_finish_callback = on_finish
	_impact_dir = impact_dir
	_next_stance = next_stance
	_final_pos = final_pos
	_final_rot = final_rot_quat.get_euler() * (180.0 / PI)

	if not _animation_player.has_animation_library(LIBRARY_NAME):
		_animation_player.add_animation_library(LIBRARY_NAME, AnimationLibrary.new())
	var animation_library := _animation_player.get_animation_library(LIBRARY_NAME)
	if animation_library.has_animation(ANIMATION_NAME):
		animation_library.remove_animation(ANIMATION_NAME)

	var anim := Animation.new()
	anim.length = 0.90

	var position_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(position_track, WEAPON_POSITION_TRACK)
	anim.track_set_interpolation_type(position_track, Animation.INTERPOLATION_CUBIC)
	anim.track_insert_key(position_track, 0.0, original_pos)
	anim.track_insert_key(position_track, 0.18, windup_pos)
	anim.track_insert_key(position_track, 0.32, attack_pos)
	# Pequeno follow-through para passar sensacao de peso.
	anim.track_insert_key(position_track, 0.42, attack_pos.lerp(final_pos, 0.35))
	anim.track_insert_key(position_track, 0.75, final_pos + Vector3(0.0, -0.02, 0.03))
	anim.track_insert_key(position_track, 0.90, final_pos)

	var rotation_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rotation_track, WEAPON_ROTATION_TRACK)
	anim.track_set_interpolation_type(rotation_track, Animation.INTERPOLATION_CUBIC)
	anim.track_insert_key(rotation_track, 0.0, original_rot_quat)
	anim.track_insert_key(rotation_track, 0.18, windup_rot_quat)
	anim.track_insert_key(rotation_track, 0.32, attack_rot_quat)
	anim.track_insert_key(rotation_track, 0.42, attack_rot_quat.slerp(final_rot_quat, 0.35))
	anim.track_insert_key(rotation_track, 0.75, final_rot_quat)
	anim.track_insert_key(rotation_track, 0.90, final_rot_quat)

	var method_track := anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(method_track, SELF_METHOD_TRACK)
	anim.track_insert_key(method_track, 0.32, {"method": "_emit_impact", "args": []})
	anim.track_insert_key(method_track, 0.90, {"method": "_emit_finish", "args": []})

	animation_library.add_animation(ANIMATION_NAME, anim)
	_animation_player.play(StringName("runtime/weapon_attack_runtime"))
	_animation_player.speed_scale = ATTACK_SPEED_SCALE

func _emit_impact() -> void:
	if _impact_callback.is_valid():
		_impact_callback.call(_impact_dir)

func _emit_finish() -> void:
	if _finish_callback.is_valid():
		_finish_callback.call(_next_stance, _final_pos, _final_rot)
