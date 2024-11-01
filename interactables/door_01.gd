extends AnimatableBody3D

@export var open: bool = false :
	set(v):
		if v != open:
			open = v
			update_door()

@onready var animation_player: AnimationPlayer = $animation_player

func update_door() -> void:
	if open:
		animation_player.play("opening")
	else:
		animation_player.play_backwards("opening")
	animation_player.set_active(true)

func toggle_open() -> void:
	open = !open
