class_name Player extends CharacterBody3D

@export_group("Movement")
@export var walking_speed: float = 5.0
@export var sprinting_speed: float = 8.0
@export var crouching_speed: float = 3.0
@export var jump_velocity: float = 5.0
@export var lerp_speed: float = 20.0

@export_group("Camera")
@export_range(0.0, 10.0, 0.1) var mouse_sensitivity: float = 2.0
@export_range(0.0, 2.0, 0.1) var crouching_depth: float = -0.5

@export_group("HeadBobbing")
@export var head_bobbing_enabled: bool = true
@export var head_bobbing_walking_speed: float = 14.0
@export var head_bobbing_sprinting_speed: float = 22.0
@export var head_bobbing_crouching_speed: float = 10.0
@export var head_bobbing_walking_intensity: float = 0.05
@export var head_bobbing_sprinting_intensity: float = 0.1
@export var head_bobbing_crouching_intensity: float = 0.025
var _head_bobbing_index: float = 0.0
var _head_bobbing_current_intensity: float = 0.0
var _head_bobbing_vector = Vector2.ZERO

@onready var _head: Node3D = $head
@onready var _eyes: Node3D = $head/eyes
@onready var _camera: Camera3D = $head/eyes/camera_3d
@onready var _ray_cast: RayCast3D = $ray_cast_3d

@onready var _standing_collision_shape: CollisionShape3D = $standing_collision_shape
@onready var _crouching_collision_shape: CollisionShape3D = $crouching_collision_shape

var _direction: Vector3 = Vector3.ZERO
var _current_speed: float = 5.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") # defaukt: 9.8 -> 14.7

func _ready() -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * (mouse_sensitivity / 10)))
		_head.rotate_x(deg_to_rad(-event.relative.y * (mouse_sensitivity / 10)))
		_head.rotation.x = clamp(_head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	var _input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_pressed("crouch"): ##Crouching
		_current_speed = crouching_speed
		_head.position.y = lerp(_head.position.y, 1.8 + crouching_depth, delta * lerp_speed)
		_head_bobbing_current_intensity = head_bobbing_crouching_intensity #TESTING
		_head_bobbing_index += head_bobbing_crouching_speed * delta #TESTING
		
		_standing_collision_shape.disabled = true
		_crouching_collision_shape.disabled = false
	elif !_ray_cast.is_colliding(): ##Standing
		_crouching_collision_shape.disabled = true
		_standing_collision_shape.disabled = false
		
		_head.position.y = lerp(_head.position.y, 1.8, delta * lerp_speed)
		if Input.is_action_pressed("sprint"): ##Sprinting
			_current_speed = sprinting_speed
			
			_head_bobbing_current_intensity = head_bobbing_sprinting_intensity #TESTING
			_head_bobbing_index += head_bobbing_sprinting_speed * delta #TESTING
		else:
			_current_speed = walking_speed
			_head_bobbing_current_intensity = head_bobbing_walking_intensity #TESTING
			_head_bobbing_index += head_bobbing_walking_speed * delta #TESTING
		
	
	if head_bobbing_enabled:
		if is_on_floor() && _input_dir != Vector2.ZERO:
			_head_bobbing_vector.y = sin(_head_bobbing_index)
			_head_bobbing_vector.x = sin(_head_bobbing_index / 2) + 0.5
			
			_eyes.position.y = lerp(_eyes.position.y, _head_bobbing_vector.y * (_head_bobbing_current_intensity / 4.0), delta * lerp_speed)
			_eyes.position.x = lerp(_eyes.position.x, _head_bobbing_vector.x * (_head_bobbing_current_intensity / 2.0), delta * lerp_speed)
		else:
			_eyes.position.y = lerp(_eyes.position.y, 0.0, delta * lerp_speed)
			_eyes.position.x = lerp(_eyes.position.x, 0.0 , delta * lerp_speed)
	
	if not is_on_floor(): ##Gravity
		velocity.y -= _gravity * delta
	
	if Input.is_action_just_pressed("jump") and is_on_floor(): ##Jumping
		velocity.y = jump_velocity
	
	_direction = lerp(_direction, (transform.basis * Vector3(_input_dir.x, 0, _input_dir.y)).normalized(), lerp_speed * delta)
	
	if _direction:
		velocity.x = _direction.x * _current_speed
		velocity.z = _direction.z * _current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, _current_speed)
		velocity.z = move_toward(velocity.z, 0, _current_speed)
	
	move_and_slide()

#@export_group("Movement")
#@export var move_speed: float = 8.0
#@export var acceleration: float = 20.0
#@export var rotation_speed: float = 12.0
#@export var jump_strength: float = 12.0
#
#@export_group("Camera")
#@export_range(0.0, 10.0, 0.1) var mouse_sensitivity: float = 5.0
#@export var min_vertical_angle: float = -PI / 3.0  # -30 Grad
#@export var max_vertical_angle: float = PI / 3.0   # 60 Grad
#
#@onready var _camera_pivot: Node3D = %CameraPivot
#@onready var _camera: Camera3D = %Camera3D
#
#@onready var player_mesh: MeshInstance3D = $PlayerMesh #TODO: TEMPORARY NEEDS TO BE CHANGED TESTING.
#
#var _gravity: float = -30.0
#var _camera_input_direction: Vector2 = Vector2.ZERO
#var _last_movement_direction := Vector3.BACK
#
#func _input(event: InputEvent) -> void:
	#if event.is_action_pressed("left_click"):
		#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	#if event.is_action_pressed("ui_cancel"):
		#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
#
#func _unhandled_input(event: InputEvent) -> void:
	#var is_camera_motion: bool = (
		#event is InputEventMouseMotion and
		#Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	#)
	#
	#if is_camera_motion:
		#_camera_input_direction += event.screen_relative * (mouse_sensitivity / 1000)
#
#func _physics_process(delta: float) -> void:
	#_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x - _camera_input_direction.y, min_vertical_angle, max_vertical_angle)
	#_camera_pivot.rotation.y -= _camera_input_direction.x 
	#
	#_camera_input_direction = Vector2.ZERO
	#
	#var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	#var forward := _camera.global_basis.z
	#var right := _camera.global_basis.x
	#
	#var move_direction := forward * raw_input.y + right * raw_input.x
	#move_direction.y = 0.0
	#move_direction = move_direction.normalized()
	#
	#var y_velocity: float = velocity.y
	#velocity.y = 0.0
	#velocity = velocity.move_toward(move_direction * move_speed, acceleration * delta)
	#velocity.y = y_velocity + _gravity * delta
	#
	#var can_jump: bool = Input.is_action_just_pressed("jump") and is_on_floor()
	#if can_jump:
		#velocity.y += jump_strength
	#
	#move_and_slide()
	#
	#if move_direction.length() > 0.2:
		#_last_movement_direction = move_direction
	#var target_angle := Vector3.BACK.signed_angle_to(_last_movement_direction, Vector3.UP)
	#player_mesh.global_rotation.y = lerp_angle(player_mesh.rotation.y, target_angle, rotation_speed * delta)
