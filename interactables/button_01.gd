extends StaticBody3D

@onready var interactable_component: InteractableComponent = $interactable_component
@onready var interact_outline: MeshInstance3D = $interact_outline

func _process(delta: float) -> void:
	interact_outline.visible = !!interactable_component.get_character_hovered_by_current_camera()
