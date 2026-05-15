# res://.../player.gd

extends CharacterBody3D
class_name Player

enum PlayerClass { WARRIOR, MAGE }

const BASE_STAT_VALUE: int = 10
const DEFAULT_MAGE_SPELLS: Array[SpellData] = [
	preload("res://resources/spells/spark.tres"),
	preload("res://resources/spells/arcane_bolt.tres"),
	preload("res://resources/spells/stone_hook.tres")
]

@export_group("Setup")
@export var class_data: ClassData
@export var player_class: PlayerClass = PlayerClass.MAGE
@export var warrior_starting_weapon_scene: PackedScene
@export var mage_starting_weapon_scene: PackedScene
@export var mage_spells: Array[SpellData] = []

@export_group("Progression")
@export var level: int = 1
@export var experience: int = 0
@export var experience_to_next_level: int = 100
@export var experience_to_next_level_growth: float = 1.35
@export var level_up_strength_gain: int = 1
@export var level_up_dexterity_gain: int = 1
@export var level_up_vigor_gain: int = 1
@export var level_up_intelligence_gain: int = 1

@export_group("Primary Stats")
@export var strength: int = BASE_STAT_VALUE
@export var dexterity: int = BASE_STAT_VALUE
@export var vigor: int = BASE_STAT_VALUE
@export var intelligence: int = BASE_STAT_VALUE

@export_group("Resource Stats")
@export var base_max_stamina: float = 100.0
@export var stamina_per_vigor: float = 4.0
@export var base_stamina_regen_per_second: float = 10.0
@export var stamina_regen_per_vigor: float = 0.25
@export var base_max_mana: float = 100.0
@export var mana_per_intelligence: float = 4.0
@export var base_mana_regen_per_second: float = 10.0
@export var mana_regen_per_intelligence: float = 0.25
@export var resource_regen_delay: float = 0.65

@export_group("Combat Stats")
@export var sword_attack_stamina_cost: float = 18.0
@export var block_stamina_cost: float = 14.0
@export var spell_mana_cost: float = 22.0
@export_range(0.2, 3.0, 0.05) var base_sword_attack_speed_rate: float = 1.0
@export var attack_speed_per_dexterity: float = 0.02
@export var base_damage_bonus: int = 0
@export var physical_damage_bonus_per_strength: float = 0.5
@export var magic_damage_bonus_per_intelligence: float = 0.5

const MOVE_DURATION: float = 0.35
const ROTATE_DURATION: float = 0.3
const HEAD_BOB_FREQ: float = 8.0
const HEAD_BOB_AMP: float = 0.08
const TILT_AMOUNT: float = 2.5
const PERFECT_BLOCK_WINDOW: float = 0.22
const CRITICAL_ATTACK_WINDOW: float = 1.2
const DEFAULT_ATTACK_DAMAGE: int = 20
const DEFAULT_CRITICAL_ATTACK_DAMAGE: int = 60

const COMBAT_SCRIPT_BY_WEAPON_KIND = {
	"Sword": preload("res://scenes/actors/player/sword_combat.gd"),
	"Staff": preload("res://scenes/actors/player/staff_combat.gd")
}
const DEFENSE_STANCE = {"pos": Vector3(0.5, 0.3, -0.8), "rot": Vector3(180, 0, 45)}

@onready var health_component: HealthComponent = $HealthComponent
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var weapon_pivot: Node3D = $CameraPivot/Camera3D/WeaponPivot
@onready var combat_ui: CombatUI = $CombatUI/Control
@onready var forward_ray: RayCast3D = $ForwardRay
@onready var back_ray: RayCast3D = $BackRay
@onready var left_ray: RayCast3D = $LeftRay
@onready var right_ray: RayCast3D = $RightRay
@onready var melee_ray: RayCast3D = $CameraPivot/Camera3D/MeleeRay
@onready var weapon_attack_animator: WeaponAttackAnimator = $WeaponAttackAnimator
@onready var resources_ui: CanvasLayer = $PlayerResourcesUI

var player_name: String = "Mendel"
var is_moving: bool = false
var moving_from_cell: Vector2i
var moving_target_cell: Vector2i
var is_rotating: bool = false
var bob_time: float = 0.0
var base_camera_y: float = 0.0

var current_weapon: Node3D = null
var current_weapon_scene: PackedScene = null
var active_weapon_combat: Node = null
var is_attacking: bool = false
var is_defending: bool = false
var block_started_msec: int = -100000
var block_ready_msec: int = -100000
var defense_pose_ready: bool = false
var critical_attack_until_msec: int = -100000
var active_attack_is_critical: bool = false
var active_attack_context: Dictionary = {}
var queued_magic_is_critical: bool = false
var queued_magic_spell: SpellData = null
var active_magic_spell: SpellData = null
var can_attack: bool = true
var stamina: float = 100.0
var mana: float = 100.0
var max_stamina: float = 100.0
var stamina_regen_per_second: float = 18.0
var max_mana: float = 100.0
var mana_regen_per_second: float = 10.0
var sword_attack_speed_rate: float = 1.0
var physical_damage_bonus: int = 0
var magic_damage_bonus: int = 0
var stamina_regen_delay_timer: float = 0.0
var mana_regen_delay_timer: float = 0.0

func _ready() -> void:
	print("Character created: " + player_name)
	base_camera_y = camera.position.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	health_component.entity_died.connect(_on_died)
	health_component.healing.connect(_on_health_changed)
	health_component.damage_taken.connect(_on_take_damage)

	combat_ui.direction_changed.connect(_on_combat_direction_changed)
	_apply_class_data()
	_recalculate_stats()
	stamina = max_stamina
	mana = max_mana
	resources_ui.setup_for_class(player_class == PlayerClass.MAGE)
	_update_resources_ui()

	var starting_weapon_scene := _get_starting_weapon_scene()
	if starting_weapon_scene != null:
		equip_weapon(starting_weapon_scene, false, global_position)
	else:
		push_warning("Player sem arma inicial configurada.")
	melee_ray.add_exception(self)

func _process(delta: float) -> void:
	handle_head_bob(delta)
	handle_movement_input()
	handle_combat_input()
	_update_resources(delta)
	update_weapon_stance(delta)
	_update_attack_availability()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		combat_ui.handle_mouse_movement(event.relative)

	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()

func handle_combat_input() -> void:
	if Input.is_action_just_pressed("Item Passive"):
		block_started_msec = Time.get_ticks_msec()
		block_ready_msec = -100000
		defense_pose_ready = false

	is_defending = Input.is_action_pressed("Item Passive") and _can_defend()
	if not is_defending:
		defense_pose_ready = false

	if active_weapon_combat == null:
		return

	if _is_using_staff():
		if Input.is_action_just_pressed("Item Action") and _can_start_attack_input() and not is_defending:
			active_weapon_combat.start_draw(combat_ui.current_direction)
		elif Input.is_action_just_released("Item Action") and active_weapon_combat.is_drawing():
			var cast_result: Dictionary = active_weapon_combat.finish_draw()
			if cast_result["valid"] and _consume_mana(float(cast_result["mana_cost"])):
				queued_magic_is_critical = cast_result["critical"]
				queued_magic_spell = cast_result["spell"]
				perform_attack()
			elif cast_result["valid"]:
				_flash_mana_denied()
	elif Input.is_action_just_pressed("Item Action") and _can_start_attack_input() and not is_defending:
		perform_attack()

func is_blocking() -> bool:
	return is_defending and _can_defend()

func is_perfect_blocking() -> bool:
	if not is_defending or not defense_pose_ready:
		return false

	var elapsed := float(Time.get_ticks_msec() - block_ready_msec) / 1000.0
	return elapsed <= PERFECT_BLOCK_WINDOW

func open_critical_attack_window() -> void:
	critical_attack_until_msec = Time.get_ticks_msec() + int(CRITICAL_ATTACK_WINDOW * 1000.0)

func _has_critical_attack_window() -> bool:
	return Time.get_ticks_msec() <= critical_attack_until_msec

func _consume_critical_attack_window() -> bool:
	if not _has_critical_attack_window():
		return false

	critical_attack_until_msec = -100000
	return true

func _get_starting_weapon_scene() -> PackedScene:
	return mage_starting_weapon_scene if player_class == PlayerClass.MAGE else warrior_starting_weapon_scene

func _is_using_staff() -> bool:
	return current_weapon != null and current_weapon.has_method("is_staff") and current_weapon.is_staff()

func _is_using_sword() -> bool:
	return current_weapon != null and not _is_using_staff()

func play_block_impact_feedback() -> bool:
	if _is_using_sword() and not _consume_stamina(block_stamina_cost):
		return false

	var original_pos := weapon_pivot.position
	var original_quat := weapon_pivot.quaternion
	var recoil_pos := original_pos + Vector3(0.04, 0.05, 0.24)
	var recoil_quat := original_quat * _local_quat(Vector3(-12.0, 4.0, 9.0))
	var rattle_pos_a := original_pos + Vector3(-0.03, 0.03, 0.14)
	var rattle_quat_a := original_quat * _local_quat(Vector3(-6.0, -3.0, -7.0))
	var rattle_pos_b := original_pos + Vector3(0.02, 0.01, 0.10)
	var rattle_quat_b := original_quat * _local_quat(Vector3(4.0, 2.0, 5.0))

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon_pivot, "position", recoil_pos, 0.055)
	tween.parallel().tween_property(weapon_pivot, "quaternion", recoil_quat, 0.055)
	tween.tween_property(weapon_pivot, "position", rattle_pos_a, 0.045)
	tween.parallel().tween_property(weapon_pivot, "quaternion", rattle_quat_a, 0.045)
	tween.tween_property(weapon_pivot, "position", rattle_pos_b, 0.04)
	tween.parallel().tween_property(weapon_pivot, "quaternion", rattle_quat_b, 0.04)
	tween.tween_property(weapon_pivot, "position", original_pos, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return true

func play_perfect_block_impact_feedback() -> void:
	var original_pos := weapon_pivot.position
	var original_quat := weapon_pivot.quaternion
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(weapon_pivot, "position", original_pos + Vector3(0.03, 0.01, 0.08), 0.025)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat * _local_quat(Vector3(-4.0, 0.0, 8.0)), 0.025)
	tween.tween_property(weapon_pivot, "position", original_pos + Vector3(-0.03, -0.01, 0.06), 0.025)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat * _local_quat(Vector3(4.0, 0.0, -8.0)), 0.025)
	tween.tween_property(weapon_pivot, "position", original_pos + Vector3(0.02, 0.02, 0.04), 0.025)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat * _local_quat(Vector3(-2.0, 0.0, 5.0)), 0.025)
	tween.tween_property(weapon_pivot, "position", original_pos, 0.06)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat, 0.06)

func _update_resources(delta: float) -> void:
	if stamina_regen_delay_timer > 0.0:
		stamina_regen_delay_timer -= delta
	if mana_regen_delay_timer > 0.0:
		mana_regen_delay_timer -= delta

	if _is_using_sword() and not is_attacking and stamina_regen_delay_timer <= 0.0:
		stamina = minf(stamina + stamina_regen_per_second * delta, max_stamina)
	if _is_using_staff() and not is_attacking and mana_regen_delay_timer <= 0.0:
		mana = minf(mana + mana_regen_per_second * delta, max_mana)
	_update_resources_ui()

func _update_resources_ui() -> void:
	if resources_ui == null:
		return

	resources_ui.set_health(health_component.current_health, health_component.max_health)
	resources_ui.set_stamina(stamina, max_stamina)
	resources_ui.set_mana(mana, max_mana)
	if resources_ui.has_method("set_level"):
		resources_ui.set_level(level)
	if resources_ui.has_method("set_experience"):
		resources_ui.set_experience(experience, experience_to_next_level)

func _can_defend() -> bool:
	return not _is_using_sword() or stamina > 0.0

func _has_mana_for_spell() -> bool:
	return mana >= spell_mana_cost

func _consume_stamina(amount: float) -> bool:
	if stamina < amount:
		_flash_stamina_denied()
		return false

	stamina -= amount
	stamina_regen_delay_timer = resource_regen_delay
	_update_resources_ui()
	return true

func _consume_mana(amount: float) -> bool:
	if mana < amount:
		_flash_mana_denied()
		return false

	mana -= amount
	mana_regen_delay_timer = resource_regen_delay
	_update_resources_ui()
	return true

func _apply_class_data() -> void:
	if class_data == null:
		return

	player_class = PlayerClass.MAGE if class_data.class_kind == "Mage" else PlayerClass.WARRIOR
	strength = class_data.strength
	dexterity = class_data.dexterity
	vigor = class_data.vigor
	intelligence = class_data.intelligence
	if class_data.starting_weapon_scene != null:
		if player_class == PlayerClass.MAGE:
			mage_starting_weapon_scene = class_data.starting_weapon_scene
		else:
			warrior_starting_weapon_scene = class_data.starting_weapon_scene

func apply_level_up(
	strength_gain: int = 0,
	dexterity_gain: int = 0,
	vigor_gain: int = 0,
	intelligence_gain: int = 0
) -> void:
	level += 1
	strength += max(0, strength_gain)
	dexterity += max(0, dexterity_gain)
	vigor += max(0, vigor_gain)
	intelligence += max(0, intelligence_gain)
	_recalculate_stats(true)
	if resources_ui != null and resources_ui.has_method("flash_level_up"):
		resources_ui.flash_level_up()
	print("Level up! Level: ", level, " STR: ", strength, " DEX: ", dexterity, " VIG: ", vigor, " INT: ", intelligence)

func add_experience(amount: int) -> void:
	if amount <= 0:
		return

	experience += amount
	print("XP +", amount, " (", experience, "/", experience_to_next_level, ")")
	while experience >= experience_to_next_level:
		experience -= experience_to_next_level
		experience_to_next_level = max(1, roundi(experience_to_next_level * experience_to_next_level_growth))
		_apply_automatic_level_up()
	_update_resources_ui()

func _apply_automatic_level_up() -> void:
	apply_level_up(
		level_up_strength_gain,
		level_up_dexterity_gain,
		level_up_vigor_gain,
		level_up_intelligence_gain
	)

func _recalculate_stats(fill_resources: bool = false) -> void:
	var stamina_percent := 1.0 if max_stamina <= 0.0 else stamina / max_stamina
	var mana_percent := 1.0 if max_mana <= 0.0 else mana / max_mana
	var vigor_bonus := vigor - BASE_STAT_VALUE
	var intelligence_bonus := intelligence - BASE_STAT_VALUE
	var dexterity_bonus := dexterity - BASE_STAT_VALUE
	var strength_bonus := strength - BASE_STAT_VALUE

	max_stamina = maxf(1.0, base_max_stamina + vigor_bonus * stamina_per_vigor)
	stamina_regen_per_second = maxf(0.0, base_stamina_regen_per_second + vigor_bonus * stamina_regen_per_vigor)
	max_mana = maxf(1.0, base_max_mana + intelligence_bonus * mana_per_intelligence)
	mana_regen_per_second = maxf(0.0, base_mana_regen_per_second + intelligence_bonus * mana_regen_per_intelligence)
	sword_attack_speed_rate = clampf(base_sword_attack_speed_rate + dexterity_bonus * attack_speed_per_dexterity, 0.2, 3.0)
	physical_damage_bonus = base_damage_bonus + roundi(strength_bonus * physical_damage_bonus_per_strength)
	magic_damage_bonus = base_damage_bonus + roundi(intelligence_bonus * magic_damage_bonus_per_intelligence)

	if fill_resources:
		stamina = max_stamina
		mana = max_mana
	else:
		stamina = clampf(stamina_percent * max_stamina, 0.0, max_stamina)
		mana = clampf(mana_percent * max_mana, 0.0, max_mana)

	_apply_player_combat_stats()
	_update_resources_ui()

func _flash_stamina_denied() -> void:
	if resources_ui != null and resources_ui.has_method("flash_stamina_denied"):
		resources_ui.flash_stamina_denied()

func _flash_mana_denied() -> void:
	if resources_ui != null and resources_ui.has_method("flash_mana_denied"):
		resources_ui.flash_mana_denied()

func update_weapon_stance(delta: float) -> void:
	if active_weapon_combat == null or is_attacking:
		return

	var result: Dictionary = active_weapon_combat.update_weapon_stance(delta, is_defending, DEFENSE_STANCE, not is_moving and not is_rotating)
	if is_defending and not defense_pose_ready and result.get("defense_ready", false):
		defense_pose_ready = true
		block_ready_msec = Time.get_ticks_msec()

func perform_attack() -> void:
	if not _can_start_attack_input() or active_weapon_combat == null:
		return
	if _is_using_sword() and not _consume_stamina(_get_current_sword_attack_stamina_cost()):
		return
		
	is_attacking = true
	can_attack = false
	active_attack_is_critical = _consume_critical_attack_window() or _consume_weapon_combo_critical() or (queued_magic_is_critical if _is_using_staff() else false)
	active_magic_spell = queued_magic_spell if _is_using_staff() else null
	queued_magic_is_critical = false
	queued_magic_spell = null
	melee_ray.enabled = true

	var attack_data: Dictionary = active_weapon_combat.build_attack_data(active_attack_is_critical)
	active_attack_context = attack_data.duplicate()
	active_attack_context["critical"] = active_attack_is_critical
	weapon_pivot.position = attack_data["original_pos"]
	weapon_pivot.quaternion = attack_data["original_quat"]

	weapon_attack_animator.play_attack(
		attack_data["original_pos"],
		attack_data["original_quat"],
		attack_data["windup_pos"],
		attack_data["windup_quat"],
		attack_data["attack_pos"],
		attack_data["attack_quat"],
		attack_data["final_pos"],
		attack_data["final_quat"],
		attack_data["next_stance"],
		attack_data["camera_kick_dir"],
		float(attack_data.get("attack_speed_rate", 1.0)),
		Callable(self, "_on_attack_impact_event"),
		Callable(self, "_on_attack_animation_finished_event")
	)

func _local_quat(rot_degrees: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(
		deg_to_rad(rot_degrees.x),
		deg_to_rad(rot_degrees.y),
		deg_to_rad(rot_degrees.z)
	))

func _apply_camera_feedback(dir: Vector3) -> void:
	var kick_strength = 2.0
	var original_rot = camera.rotation_degrees
	var target_rot = original_rot + dir * kick_strength

	var tween = create_tween()
	tween.tween_property(camera, "rotation_degrees", target_rot, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "rotation_degrees", original_rot, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_attack_impact_event(camera_kick_dir: Vector3) -> void:
	_apply_camera_feedback(camera_kick_dir)
	if active_attack_is_critical:
		_play_critical_attack_feedback()
	if _is_using_staff():
		_check_magic_hit()
	else:
		_check_hit()

func _on_attack_animation_finished_event(next_stance: int, _final_pos: Vector3, _final_rot: Vector3) -> void:
	is_attacking = false
	melee_ray.enabled = false
	active_attack_is_critical = false
	active_magic_spell = null
	active_attack_context.clear()
	if active_weapon_combat != null:
		active_weapon_combat.on_attack_finished(next_stance)
	can_attack = not _is_using_sword()

func _can_start_attack_input() -> bool:
	if is_attacking:
		return false
	if _is_using_sword():
		return active_weapon_combat != null and active_weapon_combat.has_method("is_ready_for_attack") and active_weapon_combat.is_ready_for_attack()

	return can_attack

func _update_attack_availability() -> void:
	if not _is_using_sword() or is_attacking or active_weapon_combat == null:
		return
	if active_weapon_combat.has_method("is_ready_for_attack"):
		can_attack = active_weapon_combat.is_ready_for_attack()

func _get_current_sword_attack_stamina_cost() -> float:
	if active_weapon_combat != null and active_weapon_combat.has_method("get_current_attack_stamina_cost"):
		return active_weapon_combat.get_current_attack_stamina_cost()

	return sword_attack_stamina_cost

func _consume_weapon_combo_critical() -> bool:
	if active_weapon_combat != null and active_weapon_combat.has_method("consume_combo_critical_for_current_attack"):
		return active_weapon_combat.consume_combo_critical_for_current_attack()

	return false

func _check_hit() -> void:
	melee_ray.force_raycast_update()
	if melee_ray.is_colliding():
		var target = melee_ray.get_collider()
		print("Hit something: ", target.name)

		var health = target.get_node_or_null("HealthComponent")
		if not health and target.get_parent():
			health = target.get_parent().get_node_or_null("HealthComponent")

		if health:
			print("Dealing damage to ", target.name)
			var hit_owner = health.get_parent()
			if hit_owner and hit_owner.has_method("try_avoid_player_attack") and hit_owner.try_avoid_player_attack(self, active_attack_context):
				return
			if active_attack_is_critical and hit_owner and hit_owner.has_method("on_critical_hit_by_player"):
				hit_owner.on_critical_hit_by_player(self)
			elif hit_owner and hit_owner.has_method("on_hit_by_player"):
				hit_owner.on_hit_by_player(self)
			var damage := _get_current_attack_damage()
			if hit_owner and hit_owner.has_method("show_damage_number"):
				hit_owner.show_damage_number(damage, active_attack_is_critical)
			health.take_damage(damage)

func _check_magic_hit() -> void:
	var start := camera.global_position
	var end := start + (-camera.global_transform.basis.z.normalized() * _get_current_magic_range())
	var query := PhysicsRayQueryParameters3D.create(start, end, 2)
	query.exclude = [self]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_pos: Vector3 = hit.get("position", end)
	_spawn_magic_projectile(hit_pos, active_attack_is_critical)
	if hit.is_empty():
		return

	var target = hit.get("collider")
	var health = target.get_node_or_null("HealthComponent")
	if not health and target.get_parent():
		health = target.get_parent().get_node_or_null("HealthComponent")

	if health:
		var hit_owner = health.get_parent()
		if hit_owner and hit_owner.has_method("try_avoid_player_attack") and hit_owner.try_avoid_player_attack(self, active_attack_context):
			return
		if active_attack_is_critical and hit_owner and hit_owner.has_method("on_critical_hit_by_player"):
			hit_owner.on_critical_hit_by_player(self)
		elif hit_owner and hit_owner.has_method("on_hit_by_player"):
			hit_owner.on_hit_by_player(self)
		var damage := _get_current_attack_damage()
		if hit_owner and hit_owner.has_method("show_damage_number"):
			hit_owner.show_damage_number(damage, active_attack_is_critical)
		health.take_damage(damage)

func _get_current_magic_range() -> float:
	if active_magic_spell != null:
		return active_magic_spell.spell_range

	if current_weapon != null and current_weapon.has_method("get_magic_range"):
		return current_weapon.get_magic_range()

	return 18.0

func _get_current_attack_damage() -> int:
	var damage: int
	if _is_using_staff() and active_magic_spell != null:
		damage = active_magic_spell.roll_damage(active_attack_is_critical)
		return max(0, damage + _get_current_damage_bonus())

	if current_weapon == null:
		damage = DEFAULT_CRITICAL_ATTACK_DAMAGE if active_attack_is_critical else DEFAULT_ATTACK_DAMAGE
		return max(0, damage + _get_current_damage_bonus())

	if active_attack_is_critical and current_weapon.has_method("roll_critical_attack_damage"):
		damage = current_weapon.roll_critical_attack_damage()
		return max(0, damage + _get_current_damage_bonus())

	if current_weapon.has_method("roll_attack_damage"):
		damage = current_weapon.roll_attack_damage()
		return max(0, damage + _get_current_damage_bonus())

	damage = DEFAULT_CRITICAL_ATTACK_DAMAGE if active_attack_is_critical else DEFAULT_ATTACK_DAMAGE
	return max(0, damage + _get_current_damage_bonus())

func _get_current_damage_bonus() -> int:
	return magic_damage_bonus if _is_using_staff() else physical_damage_bonus

func equip_weapon(weapon_scene: PackedScene, drop_current: bool, drop_position: Vector3) -> void:
	var next_weapon := weapon_scene.instantiate()
	if not _can_equip_weapon(next_weapon):
		next_weapon.queue_free()
		return

	if drop_current and current_weapon_scene != null:
		_drop_current_weapon(drop_position)

	if current_weapon:
		current_weapon.queue_free()

	current_weapon = next_weapon
	current_weapon_scene = weapon_scene
	if current_weapon.has_method("set_pickup_enabled"):
		current_weapon.set_pickup_enabled(false)
	weapon_pivot.add_child(current_weapon)
	current_weapon.position = Vector3.ZERO
	current_weapon.rotation = Vector3.ZERO
	_refresh_weapon_combat()
	_on_combat_direction_changed(0)

func _can_equip_weapon(weapon: Node) -> bool:
	if player_class == PlayerClass.WARRIOR:
		return weapon.has_method("is_sword") and weapon.is_sword()

	return weapon.has_method("is_staff") and weapon.is_staff()

func _drop_current_weapon(drop_position: Vector3) -> void:
	var dropped_weapon := current_weapon_scene.instantiate()
	var drop_parent := _get_weapon_drop_parent()
	drop_parent.add_child(dropped_weapon)
	dropped_weapon.global_position = Vector3(drop_position.x, drop_position.y, drop_position.z)
	dropped_weapon.rotation = Vector3.ZERO
	if dropped_weapon.has_method("set_pickup_enabled"):
		dropped_weapon.set_pickup_enabled(true)

func _get_weapon_drop_parent() -> Node:
	var level_container := get_parent().get_node_or_null("LevelContainer")
	if level_container and level_container.get_child_count() > 0:
		return level_container.get_child(0)

	return get_tree().current_scene

func _refresh_weapon_combat() -> void:
	if active_weapon_combat != null:
		active_weapon_combat.queue_free()
		active_weapon_combat = null

	var weapon_kind := _get_current_weapon_kind()
	if not COMBAT_SCRIPT_BY_WEAPON_KIND.has(weapon_kind):
		push_error("Sem combat configurado para arma do tipo: %s" % weapon_kind)
		return

	var combat_script: Script = COMBAT_SCRIPT_BY_WEAPON_KIND[weapon_kind]
	active_weapon_combat = combat_script.new()
	active_weapon_combat.name = "%sCombat" % weapon_kind
	add_child(active_weapon_combat)
	active_weapon_combat.setup(combat_ui, weapon_pivot, camera)
	_apply_player_combat_stats()
	active_weapon_combat.reset()

func _apply_player_combat_stats() -> void:
	if active_weapon_combat == null:
		return
	if _get_current_weapon_kind() == "Sword" and "attack_speed_rate" in active_weapon_combat:
		active_weapon_combat.attack_speed_rate = sword_attack_speed_rate
	if _get_current_weapon_kind() == "Staff" and active_weapon_combat.has_method("set_spells"):
		active_weapon_combat.set_spells(mage_spells if not mage_spells.is_empty() else DEFAULT_MAGE_SPELLS)

func _get_current_weapon_kind() -> String:
	if current_weapon != null and current_weapon.has_method("get_weapon_kind"):
		return current_weapon.get_weapon_kind()

	return ""

func _on_combat_direction_changed(dir_index: int) -> void:
	if active_weapon_combat == null:
		return

	active_weapon_combat.handle_direction_changed(dir_index, is_attacking, false)

func handle_movement_input() -> void:
	if is_moving or is_rotating or is_attacking:
		return

	if Input.is_action_pressed("Foward"):
		move_in_direction(-transform.basis.z, forward_ray)
	elif Input.is_action_pressed("Back"):
		move_in_direction(transform.basis.z, back_ray)
	elif Input.is_action_pressed("Left strafe"):
		move_in_direction(-transform.basis.x, left_ray, true, -1)
	elif Input.is_action_pressed("Right strafe"):
		move_in_direction(transform.basis.x, right_ray, true, 1)
	elif Input.is_action_pressed("Turn Left"):
		turn(90)
	elif Input.is_action_pressed("Turn Right"):
		turn(-90)

func move_in_direction(direction: Vector3, ray: RayCast3D, is_strafe: bool = false, strafe_dir: int = 0) -> void:
	var previous_pos := global_position
	var target_pos = global_position + direction.normalized() * Constants.TILE_SIZE
	ray.force_raycast_update()

	if ray.is_colliding() || _has_enemy_on_tile(target_pos):
		play_wall_bump_animation(direction)
		return

	is_moving = true
	moving_from_cell = _world_to_cell(previous_pos)
	moving_target_cell = _world_to_cell(target_pos)

	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(self, "global_position", target_pos, MOVE_DURATION)

	if is_strafe:
		var target_tilt = deg_to_rad(-strafe_dir * TILT_AMOUNT)
		tween.tween_property(camera, "rotation:z", target_tilt, MOVE_DURATION * 0.5)
		tween.chain().tween_property(camera, "rotation:z", 0.0, MOVE_DURATION * 0.5)

	tween.chain().tween_callback(func():
		is_moving = false
		_try_pickup_weapon_current_tile(previous_pos)
	)

func _try_pickup_weapon_current_tile(drop_position: Vector3) -> void:
	var current_cell := _world_to_cell(global_position)
	for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
		if not pickup is Node3D:
			continue
		if _world_to_cell(pickup.global_position) != current_cell:
			continue
		if not pickup.has_method("get_weapon_scene"):
			continue

		var weapon_scene: PackedScene = pickup.get_weapon_scene()
		if _try_equip_pickup_weapon(weapon_scene, pickup, drop_position):
			return

func _try_equip_pickup_weapon(weapon_scene: PackedScene, pickup: Node, drop_position: Vector3) -> bool:
	var test_weapon := weapon_scene.instantiate()
	var can_equip := _can_equip_weapon(test_weapon)
	test_weapon.queue_free()
	if not can_equip:
		return false

	pickup.queue_free()
	equip_weapon(weapon_scene, true, drop_position)
	return true

func _has_enemy_on_tile(target_pos: Vector3) -> bool:
	var target_cell := _world_to_cell(target_pos)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("blocks_player_cell") and enemy.blocks_player_cell(target_cell):
			return true
		if enemy.has_method("occupies_cell") and enemy.occupies_cell(target_cell):
			return true
		if enemy.has_method("get_current_cell") and enemy.get_current_cell() == target_cell:
			return true

	return false

func occupies_cell(cell: Vector2i) -> bool:
	if _world_to_cell(global_position) == cell:
		return true

	return is_moving and (moving_from_cell == cell or moving_target_cell == cell)

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / Constants.TILE_SIZE),
		floori(world_pos.z / Constants.TILE_SIZE)
	)

func turn(angle_degrees: float) -> void:
	is_rotating = true
	var target_rot = rotation.y + deg_to_rad(angle_degrees)

	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(self, "rotation:y", target_rot, ROTATE_DURATION)

	var tilt_dir = 1 if angle_degrees > 0 else -1
	var target_tilt = deg_to_rad(tilt_dir * TILT_AMOUNT)
	tween.tween_property(camera, "rotation:z", target_tilt, ROTATE_DURATION * 0.5)
	tween.chain().tween_property(camera, "rotation:z", 0.0, ROTATE_DURATION * 0.5)

	tween.chain().tween_callback(func(): is_rotating = false)

func play_wall_bump_animation(direction: Vector3) -> void:
	is_moving = true
	var original_pos = global_position
	var bump_pos = original_pos + direction.normalized() * (Constants.TILE_SIZE * 0.1)

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", bump_pos, 0.1)
	tween.tween_property(self, "global_position", original_pos, 0.1)
	tween.tween_callback(func(): is_moving = false)

func handle_head_bob(delta: float) -> void:
	if is_moving:
		bob_time += delta * HEAD_BOB_FREQ
	else:
		bob_time = lerp(bob_time, 0.0, delta * 10.0)

	var target_y = base_camera_y + sin(bob_time) * HEAD_BOB_AMP
	camera.position.y = lerp(camera.position.y, target_y, delta * 20.0)

	var target_x = cos(bob_time * 0.5) * (HEAD_BOB_AMP * 0.5)
	camera.position.x = lerp(camera.position.x, target_x, delta * 20.0)

func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_died() -> void:
	print(player_name + " died!")
	_update_resources_ui()
	#queue_free()

func _on_health_changed() -> void:
	print("Cura recebida! HP: ", health_component.current_health)
	_update_resources_ui()

func _on_take_damage() -> void:
	_update_resources_ui()
	_play_damage_camera_shake()

func _play_damage_camera_shake() -> void:
	var original_rot := camera.rotation_degrees
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-2.0, 1.4, -1.2), 0.035)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(1.5, -1.0, 1.0), 0.04)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-0.8, 0.5, -0.5), 0.035)
	tween.tween_property(camera, "rotation_degrees", original_rot, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _play_critical_attack_feedback() -> void:
	var original_rot := camera.rotation_degrees
	var original_fov := camera.fov
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-5.0, 3.8, -3.2), 0.025)
	tween.parallel().tween_property(camera, "fov", original_fov + 6.0, 0.025)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(4.2, -3.0, 2.8), 0.035)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-2.4, 1.6, -1.6), 0.03)
	tween.tween_property(camera, "rotation_degrees", original_rot, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(camera, "fov", original_fov, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _spawn_magic_projectile(target_pos: Vector3, critical: bool) -> void:
	var projectile := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08 if not critical else 0.13
	mesh.height = mesh.radius * 2.0
	projectile.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.75, 1.0, 1.0) if not critical else Color(1.0, 0.85, 0.25, 1.0)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.5 if not critical else 5.0
	projectile.material_override = material

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = weapon_pivot.global_position

	var tween := create_tween()
	tween.tween_property(projectile, "global_position", target_pos, 0.16 if not critical else 0.1)
	tween.tween_property(projectile, "scale", Vector3.ZERO, 0.08)
	tween.tween_callback(projectile.queue_free)
