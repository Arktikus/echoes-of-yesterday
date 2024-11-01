extends CanvasLayer

@onready var underwater_effect: ColorRect = $underwater_effect

var is_underwater = false

func set_underwater_effect(active: bool):
	if active != is_underwater:
		underwater_effect.visible = active
		is_underwater = active
