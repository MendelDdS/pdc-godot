extends CanvasLayer
class_name PlayerResourcesUI

@onready var health_bar: ProgressBar = $Root/Bars/HealthBar
@onready var stamina_bar: ProgressBar = $Root/Bars/StaminaBar
@onready var mana_bar: ProgressBar = $Root/Bars/ManaBar

func setup_for_class(is_mage: bool) -> void:
	stamina_bar.visible = not is_mage
	mana_bar.visible = is_mage

func set_health(value: float, max_value: float) -> void:
	_set_bar(health_bar, value, max_value)

func set_stamina(value: float, max_value: float) -> void:
	_set_bar(stamina_bar, value, max_value)

func set_mana(value: float, max_value: float) -> void:
	_set_bar(mana_bar, value, max_value)

func _set_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value = clampf(value, 0.0, max_value)
