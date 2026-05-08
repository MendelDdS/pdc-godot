extends CanvasLayer
class_name PlayerResourcesUI

@onready var health_bar: ProgressBar = $Root/Bars/HealthBar
@onready var stamina_bar: ProgressBar = $Root/Bars/StaminaBar
@onready var mana_bar: ProgressBar = $Root/Bars/ManaBar

var _bar_tweens: Dictionary = {}
var _last_values: Dictionary = {}

func setup_for_class(is_mage: bool) -> void:
	stamina_bar.visible = not is_mage
	mana_bar.visible = is_mage

func set_health(value: float, max_value: float) -> void:
	_set_bar(health_bar, value, max_value, Color(1.0, 0.25, 0.2), Color(0.35, 1.0, 0.45))

func set_stamina(value: float, max_value: float) -> void:
	_set_bar(stamina_bar, value, max_value, Color(1.0, 0.92, 0.35), Color(0.5, 1.0, 0.55))

func set_mana(value: float, max_value: float) -> void:
	_set_bar(mana_bar, value, max_value, Color(0.55, 0.9, 1.0), Color(0.75, 0.85, 1.0))

func flash_stamina_denied() -> void:
	_flash_bar(stamina_bar, Color(1.0, 0.25, 0.12), 1.12)

func flash_mana_denied() -> void:
	_flash_bar(mana_bar, Color(0.75, 0.3, 1.0), 1.12)

func _set_bar(bar: ProgressBar, value: float, max_value: float, spend_color: Color, gain_color: Color) -> void:
	var previous := float(_last_values.get(bar, value))
	bar.max_value = max_value
	bar.value = clampf(value, 0.0, max_value)
	_last_values[bar] = bar.value

	if is_equal_approx(previous, bar.value):
		return

	if bar.value < previous - 0.01:
		_flash_bar(bar, spend_color, 1.08)
	elif bar == health_bar and bar.value > previous + 0.01:
		_flash_bar(bar, gain_color, 1.04)

func _flash_bar(bar: ProgressBar, color: Color, scale_amount: float) -> void:
	if bar == null or not bar.visible:
		return

	if _bar_tweens.has(bar) and _bar_tweens[bar]:
		_bar_tweens[bar].kill()

	bar.pivot_offset = bar.size * 0.5
	bar.modulate = color
	bar.scale = Vector2(scale_amount, scale_amount)

	var tween := create_tween()
	_bar_tweens[bar] = tween
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(bar, "scale", Vector2.ONE, 0.16)
	tween.parallel().tween_property(bar, "modulate", Color.WHITE, 0.16)
