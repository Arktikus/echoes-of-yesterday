class_name Player extends CharacterBody3D

@export_group("Movement")
@export var move_speed: float = 8.0
@export var acceleration: float = 20.0
@export var rotation_speed: float = 12.0
@export var jump_strength: float = 12.0

@export_group("Camera")
@export_range(0.0, 10.0, 0.1) var mouse_sensitivity: float = 5.0
@export var min_vertical_angle: float = -PI / 3.0  # -30 Grad
@export var max_vertical_angle: float = PI / 3.0   # 60 Grad

@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %Camera3D

@onready var player_mesh: MeshInstance3D = $PlayerMesh #TODO: TEMPORARY NEEDS TO BE CHANGED TESTING.

var _gravity: float = -30.0
var _camera_input_direction: Vector2 = Vector2.ZERO
var _last_movement_direction := Vector3.BACK

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	var is_camera_motion: bool = (
		event is InputEventMouseMotion and
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)
	
	if is_camera_motion:
		_camera_input_direction += event.screen_relative * (mouse_sensitivity / 1000)

func _physics_process(delta: float) -> void:
	_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x - _camera_input_direction.y, min_vertical_angle, max_vertical_angle)
	_camera_pivot.rotation.y -= _camera_input_direction.x 
	
	_camera_input_direction = Vector2.ZERO
	
	var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := _camera.global_basis.z
	var right := _camera.global_basis.x
	
	var move_direction := forward * raw_input.y + right * raw_input.x
	move_direction.y = 0.0
	move_direction = move_direction.normalized()
	
	var y_velocity: float = velocity.y
	velocity.y = 0.0
	velocity = velocity.move_toward(move_direction * move_speed, acceleration * delta)
	velocity.y = y_velocity + _gravity * delta
	
	var can_jump: bool = Input.is_action_just_pressed("jump") and is_on_floor()
	if can_jump:
		velocity.y += jump_strength
	
	move_and_slide()
	
	if move_direction.length() > 0.2:
		_last_movement_direction = move_direction
	var target_angle := Vector3.BACK.signed_angle_to(_last_movement_direction, Vector3.UP)
	player_mesh.global_rotation.y = lerp_angle(player_mesh.rotation.y, target_angle, rotation_speed * delta)
