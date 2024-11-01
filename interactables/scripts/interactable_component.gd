class_name InteractableComponent extends Node

var characters_hovering: Dictionary = {}

signal interacted
signal interacted_by_character(character: CharacterBody3D)

func interact_with(character: CharacterBody3D):
	interacted.emit()
	interacted_by_character.emit(character)

func _process(delta: float) -> void:
	for c in characters_hovering.keys():
		if Engine.get_process_frames() - characters_hovering[c] > 1:
			characters_hovering.erase(c)

func hover_cursor(character: CharacterBody3D):
	characters_hovering[character] = Engine.get_process_frames()

func get_character_hovered_by_current_camera() -> CharacterBody3D:
	for c in characters_hovering.keys():
		var current_camera = get_viewport().get_camera_3d() if get_viewport() else null
		if current_camera != null and c.is_ancestor_of(current_camera):
			return c
	return null
