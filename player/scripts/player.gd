class_name Player extends CharacterBody3D

@export_group("Movement")
@export var jump_velocity: float = 6.0
@export var walk_speed: float = 7.0
@export var sprint_speed: float = 8.5
@export var swim_up_speed: float = 10.0
@export var auto_bhop: bool = true
@export_subgroup("Ground")
@export var ground_accel: float = 14.0
@export var ground_decel: float = 10.0
@export var ground_friction: float = 6.0
@export_subgroup("Air")
@export var air_move_speed: float = 500.0
@export var air_cap: float = 0.85
@export var air_accel: float = 800.0
@export_subgroup("Noclip")
@export var noclip_speed_mult: float = 3.0
@export_group("Camera")
@export_range(0.0, 10.0, 0.1) var mouse_sensitivity: float = 6.0
@export_range(0.0, 10.0, 0.1) var controller_sensitivity: float = 5.5

@onready var world_model: Node3D = $world_model
@onready var head: Node3D = $head_original_position/head
@onready var camera: Camera3D = $head_original_position/head/camera_smooth/camera_3d
@onready var camera_smooth: Node3D = $head_original_position/head/camera_smooth

@onready var standing_collision_shape: CollisionShape3D = $standing_collision_shape

@onready var interact_shape_cast: ShapeCast3D = $head_original_position/head/camera_smooth/camera_3d/interact_shape_cast_3d

@onready var stairs_ahead_ray_cast_3d: RayCast3D = $stairs_ahead_ray_cast_3d
@onready var stairs_below_ray_cast_3d: RayCast3D = $stairs_below_ray_cast_3d

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var noclip: bool = false
var wish_dir: Vector3 = Vector3.ZERO
var cam_aligned_wish_dir: Vector3 = Vector3.ZERO

const CROUCH_TRANSLATE: float = 0.7
const CROUCH_JUMP_ADD: float = CROUCH_TRANSLATE * 0.9 # 0.9 for sourcelike camera jitter in air on crouch
var is_crouched: bool = false

const MAX_STEP_HEIGHT: float = 0.5
var _snapped_to_stairs_last_frame: bool = false
var _last_frame_was_on_floor = -INF

const HEADBOB_MOVE_AMOUNT: float = 0.06
const HEADBOB_FREQUENCY: float = 2.4
var headbob_time: float = 0.0

func _ready() -> void:
	for c in world_model.find_children("*", "VisualInstance3D"):
		c.set_layer_mask_value(1, false)
		c.set_layer_mask_value(2, true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * mouse_sensitivity / 1000)
			camera.rotate_x(-event.relative.y * mouse_sensitivity / 1000)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _process(delta: float) -> void:
	_handle_controller_look_input(delta)
	
	if get_interactable_component_at_shapecast():
		get_interactable_component_at_shapecast().hover_cursor(self)
		if Input.is_action_just_pressed("interact"):
			get_interactable_component_at_shapecast().interact_with(self)

func _handle_ground_physics(delta) -> void:
	var current_speed_in_wish_dir = self.velocity.dot(wish_dir)
	var add_speed_till_cap = get_move_speed() - current_speed_in_wish_dir
	if add_speed_till_cap > 0:
		var accel_speed = ground_accel * delta * get_move_speed()
		accel_speed = min(accel_speed, add_speed_till_cap)
		self.velocity += accel_speed * wish_dir
	
	# Apply friction
	var control = max(self.velocity.length(), ground_decel)
	var drop = control * ground_friction * delta
	var new_speed = max(self.velocity.length() - drop, 0.0)
	if self.velocity.length() > 0:
		new_speed /= self.velocity.length()
	self.velocity *= new_speed
	
	_headbob_effect(delta)

@onready var _original_capsule_height = standing_collision_shape.shape.height
func _handle_crouch_physics(delta) -> void:
	var was_crouched_last_frame = is_crouched
	if Input.is_action_pressed("crouch"):
		is_crouched = true
	elif is_crouched and not self.test_move(self.global_transform, Vector3(0, CROUCH_TRANSLATE, 0)):
		is_crouched = false
	
	# Allow for crouch to heighten/extend a jump
	var translate_y_if_possible: float = 0.0
	if was_crouched_last_frame != is_crouched and not is_on_floor() and not _snapped_to_stairs_last_frame:
		translate_y_if_possible = CROUCH_JUMP_ADD if is_crouched else -CROUCH_JUMP_ADD
	# Make sure not to get player stuck in floor/ceiling during crouch jumps
	if translate_y_if_possible != 0.0:
		var result = KinematicCollision3D.new()
		self.test_move(self.global_transform, Vector3(0, translate_y_if_possible, 0), result)
		self.position.y += result.get_travel().y
		head.position.y -= result.get_travel().y
		head.position.y = clampf(head.position.y, -CROUCH_TRANSLATE, 0)
	
	head.position.y = move_toward(head.position.y, -CROUCH_TRANSLATE if is_crouched else 0, 7.0 * delta)
	standing_collision_shape.shape.height = _original_capsule_height - CROUCH_TRANSLATE if is_crouched else _original_capsule_height
	standing_collision_shape.position.y = standing_collision_shape.shape.height / 2

func _handle_air_physics(delta) -> void:
	self.velocity.y -= gravity * delta
	
	# Classic battle tested & fan favorite source/quake air movement recipe.
	# CSS players gonna feel their gamer instincts kick in with this one
	var current_speed_in_wish_dir = self.velocity.dot(wish_dir)
	# Wish speed (if wish_dir > 0 length) capped to air_cap
	var capped_speed = min((air_move_speed * wish_dir).length(), air_cap)
	# How much to get to the speed the player wishes (in the new dir)
	# Notice this allows for infinite speed. If wish_dir is perpendicular, we always need to add velocity
	#  no matter how fast we're going. This is what allows for things like bhop in CSS & Quake.
	# Also happens to just give some very nice feeling movement & responsiveness when in the air.
	var add_speed_till_cap = capped_speed - current_speed_in_wish_dir
	if add_speed_till_cap > 0:
		var accel_speed = air_accel * air_move_speed * delta # Usually is adding this one.
		accel_speed = min(accel_speed, add_speed_till_cap) # Works ok without this but sticking to the recipe
		self.velocity += accel_speed * wish_dir
	
	if is_on_wall():
		# The floating mode is much better and less jittery for surf
		# This bit of code is tricky. Will toggle floating mode in air
		# is_on_floor() never triggers in floating mode, and instead is_on_wall() does.
		if is_surface_too_steep(get_wall_normal()):
			self.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		else:
			self.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		clip_velocity(get_wall_normal(), 1, delta) # Allows surf

func _handle_water_physics(delta) -> bool:
	if get_tree().get_nodes_in_group("water_area").all(func(area): return !area.overlaps_body(self)):
		return false
	
	if not is_on_floor():
		velocity.y -= gravity * 0.1 * delta
	
	self.velocity += cam_aligned_wish_dir * get_move_speed() * delta
	
	if Input.is_action_pressed("jump"):
		self.velocity.y += swim_up_speed * delta
	
	self.velocity = self.velocity.lerp(Vector3.ZERO, 2 * delta)
	
	return true

func get_interactable_component_at_shapecast() -> InteractableComponent:
	for i in interact_shape_cast.get_collision_count():
		if i> 0 and interact_shape_cast.get_collider(0) != $".":
			return null
		if interact_shape_cast.get_collider(i).get_node_or_null("interactable_component") is InteractableComponent:
			return interact_shape_cast.get_collider(i).get_node_or_null("interactable_component") #TESTING TODO MAYBE CHANGE
	return null

func _push_away_rigid_bodies():
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			var push_dir = -c.get_normal()
			# How much velocity the object needs to increase to match player velocity in the push direction
			var velocity_diff_in_push_dir = self.velocity.dot(push_dir) - c.get_collider().linear_velocity.dot(push_dir)
			# Only count velocity towards push dir, away from character
			velocity_diff_in_push_dir = max(0., velocity_diff_in_push_dir)
			# Objects with more mass than us should be harder to push. But doesn't really make sense to push faster than we are going
			const MY_APPROX_MASS_KG = 80.0
			var mass_ratio = min(1., MY_APPROX_MASS_KG / c.get_collider().mass)
			# Optional add: Don't push object at all if it's 4x heavier or more
			if mass_ratio < 0.25:
				continue
			# Don't push object from above/below
			push_dir.y = 0
			# 5.0 is a magic number, adjust to your needs
			var push_force = mass_ratio * 5.0
			c.get_collider().apply_impulse(push_dir * velocity_diff_in_push_dir * push_force, c.get_position() - c.get_collider().global_position)

func _snap_up_to_stairs_check(delta) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	var expected_move_motion = self.velocity * Vector3(1,0,1) * delta
	var step_pos_with_clearance = self.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	# Run a body_test_motion slightly above the pos we expect to move to, towards the floor.
	#  We give some clearance above to ensure there's ample room for the player.
	#  If it hits a step <= MAX_STEP_HEIGHT, we can teleport the player on top of the step
	#  along with their intended motion forward.
	var down_check_result = PhysicsTestMotionResult3D.new()
	if (_run_body_test_motion(step_pos_with_clearance, Vector3(0,-MAX_STEP_HEIGHT*2,0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))):
		var step_height = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y
		# Note I put the step_height <= 0.01 in just because I noticed it prevented some physics glitchiness
		# 0.02 was found with trial and error. Too much and sometimes get stuck on a stair. Too little and can jitter if running into a ceiling.
		# The normal character controller (both jolt & default) seems to be able to handled steps up of 0.1 anyway
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_collision_point() - self.global_position).y > MAX_STEP_HEIGHT: return false
		stairs_ahead_ray_cast_3d.global_position = down_check_result.get_collision_point() + Vector3(0,MAX_STEP_HEIGHT,0) + expected_move_motion.normalized() * 0.1
		stairs_ahead_ray_cast_3d.force_raycast_update()
		if stairs_ahead_ray_cast_3d.is_colliding() and not is_surface_too_steep(stairs_ahead_ray_cast_3d.get_collision_normal()):
			_save_camera_pos_for_smoothing()
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true
	return false

var _saved_camera_global_pos = null
func _save_camera_pos_for_smoothing():
	if _saved_camera_global_pos == null:
		_saved_camera_global_pos = camera_smooth.global_position

func _slide_camera_smooth_back_to_origin(delta):
	if _saved_camera_global_pos == null: return
	camera_smooth.global_position.y = _saved_camera_global_pos.y
	camera_smooth.position.y = clampf(camera_smooth.position.y, -0.7, 0.7) # Clamp incase teleported
	var move_amount = max(self.velocity.length() * delta, walk_speed/2 * delta)
	camera_smooth.position.y = move_toward(camera_smooth.position.y, 0.0, move_amount)
	_saved_camera_global_pos = camera_smooth.global_position
	if camera_smooth.position.y == 0:
		_saved_camera_global_pos = null # Stop smoothing camera

func _snap_down_to_stairs_check() -> void:
	var did_snap: bool = false
	stairs_below_ray_cast_3d.force_raycast_update()
	var floor_below: bool = stairs_below_ray_cast_3d.is_colliding() and not is_surface_too_steep(stairs_below_ray_cast_3d.get_collision_normal())
	var was_on_floor_last_frame = Engine.get_physics_frames() == 1
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = PhysicsTestMotionResult3D.new()
		if _run_body_test_motion(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			_save_camera_pos_for_smoothing()
			var translate_y = body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	_snapped_to_stairs_last_frame = did_snap

func _handle_noclip(delta: float) -> bool:
	if Input.is_action_just_pressed("noclip") and OS.has_feature("debug"): #DEBUG means noclip only available while in editor? debug
		noclip = !noclip
	
	standing_collision_shape.disabled = noclip
	
	if not noclip:
		return false
	
	var speed: float = get_move_speed() * noclip_speed_mult
	if Input.is_action_pressed("sprint"):
		speed *= 3.0
	
	self.velocity = cam_aligned_wish_dir * speed
	global_position += self.velocity * delta
	
	if Input.is_action_pressed("jump"):
		global_position += Vector3(0, 1 * speed, 0) * delta
	
	return true

func _physics_process(delta: float) -> void:
	if is_on_floor(): _last_frame_was_on_floor = Engine.get_physics_frames()
	
	var _input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down").normalized()
	wish_dir = self.global_transform.basis * Vector3(_input_dir.x, 0., _input_dir.y)
	cam_aligned_wish_dir = camera.global_transform.basis * Vector3(_input_dir.x, 0., _input_dir.y)
	
	_handle_crouch_physics(delta)
	
	if not _handle_noclip(delta):
		if not _handle_water_physics(delta):
			if is_on_floor() or _snapped_to_stairs_last_frame:
				if Input.is_action_just_pressed("jump") or (auto_bhop and Input.is_action_pressed("jump")):
					self.velocity.y = jump_velocity
				_handle_ground_physics(delta)
			else:
				_handle_air_physics(delta)
			
		if not _snap_up_to_stairs_check(delta):
			_push_away_rigid_bodies()
			move_and_slide()
			_snap_down_to_stairs_check()
	_slide_camera_smooth_back_to_origin(delta)

var _current_controller_look: Vector2 = Vector2()
func _handle_controller_look_input(delta):
	var target_look = Input.get_vector("look_left", "look_right", "look_down", "look_up").normalized()
	
	if target_look.length() < _current_controller_look.length():
		_current_controller_look = target_look
	else:
		_current_controller_look = _current_controller_look.lerp(target_look, 5.0 * delta)
	
	rotate_y(-_current_controller_look.x * controller_sensitivity / 100) # turn left and right
	camera.rotate_x(_current_controller_look.y * controller_sensitivity / 100) # look up and down
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90)) # clamp up and down range

func clip_velocity(normal: Vector3, overbounce : float, delta : float) -> void:
	# When strafing into wall, + gravity, velocity will be pointing much in the opposite direction of the normal
	# So with this code, we will back up and off of the wall, cancelling out our strafe + gravity, allowing surf.
	var backoff := self.velocity.dot(normal) * overbounce
	# Not in original recipe. Maybe because of the ordering of the loop, in original source it
	# shouldn't be the case that velocity can be away away from plane while also colliding.
	# Without this, it's possible to get stuck in ceilings
	if backoff >= 0: return
	
	var change := normal * backoff
	self.velocity -= change
	
	# Second iteration to make sure not still moving through plane
	# Not sure why this is necessary but it was in the original recipe so keeping it.
	var adjust := self.velocity.dot(normal)
	if adjust < 0.0:
		self.velocity -= normal * adjust

func is_surface_too_steep(normal : Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle
	#var max_slope_ang_dot = Vector3(0,1,0).rotated(Vector3(1.0,0,0), self.floor_max_angle).dot(Vector3(0,1,0))
	#if normal.dot(Vector3(0,1,0)) < max_slope_ang_dot:
		#return true
	#return false

func _run_body_test_motion(from: Transform3D, motion: Vector3, result = null) -> bool:
	if not result: result = PhysicsTestMotionResult3D.new()
	var params = PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	return PhysicsServer3D.body_test_motion(self.get_rid(), params, result)

func _headbob_effect(delta):
	headbob_time += delta * self.velocity.length()
	camera.transform.origin = Vector3(
		cos(headbob_time * HEADBOB_FREQUENCY * 0.5) * HEADBOB_MOVE_AMOUNT,
		sin(headbob_time * HEADBOB_FREQUENCY) * HEADBOB_MOVE_AMOUNT,
		0
	)

func get_move_speed() -> float:
	if is_crouched:
		return walk_speed * 0.8 #TESTING TODO: CHANGE?
	return sprint_speed if Input.is_action_pressed("sprint") else walk_speed

#@export_group("Movement")
#@export var walking_speed: float = 5.0 # 5
#@export var sprinting_speed: float = 10.0 # 8
#@export var crouching_speed: float = 2.0 # 3
#@export var jump_velocity: float = 5.0 # 5
#@export var lerp_speed: float = 20.0 # 20
#@export var air_lerp_speed: float = 2.0
#
#@export_group("Camera")
#@export_range(0.0, 10.0, 0.1) var mouse_sensitivity: float = 2.0
#@export_range(0.0, 2.0, 0.1) var crouching_depth: float = -0.5
#
#@export_group("HeadBobbing")
#@export var head_bobbing_enabled: bool = true
#@export var head_bobbing_walking_speed: float = 14.0
#@export var head_bobbing_sprinting_speed: float = 22.0
#@export var head_bobbing_crouching_speed: float = 10.0
#@export var head_bobbing_walking_intensity: float = 0.05
#@export var head_bobbing_sprinting_intensity: float = 0.1
#@export var head_bobbing_crouching_intensity: float = 0.025
#var _head_bobbing_index: float = 0.0
#var _head_bobbing_current_intensity: float = 0.0
#var _head_bobbing_vector = Vector2.ZERO
#
#@onready var _head: Node3D = $head
#@onready var _eyes: Node3D = $head/eyes
#@onready var _camera: Camera3D = $head/eyes/camera_3d
#@onready var _ray_cast: RayCast3D = $ray_cast_3d
#
#@onready var _standing_collision_shape: CollisionShape3D = $standing_collision_shape
#@onready var _crouching_collision_shape: CollisionShape3D = $crouching_collision_shape
#
#var _direction: Vector3 = Vector3.ZERO
#var _current_speed: float = 5.0
#var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") # defaukt: 9.8 -> 14.7
#
#func _ready() -> void:
	#pass
#
#func _input(event: InputEvent) -> void:
	#if event is InputEventMouseMotion:
		#rotate_y(deg_to_rad(-event.relative.x * (mouse_sensitivity / 10)))
		#_head.rotate_x(deg_to_rad(-event.relative.y * (mouse_sensitivity / 10)))
		#_head.rotation.x = clamp(_head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	#
	#if event.is_action_pressed("left_click"):
		#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	#if event.is_action_pressed("ui_cancel"):
		#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
#
#func _physics_process(delta: float) -> void:
	#var _input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	#if Input.is_action_pressed("crouch"): ##Crouching
		#_current_speed = crouching_speed
		#_head.position.y = lerp(_head.position.y, 1.8 + crouching_depth, delta * lerp_speed)
		#_head_bobbing_current_intensity = head_bobbing_crouching_intensity #TESTING
		#_head_bobbing_index += head_bobbing_crouching_speed * delta #TESTING
		#
		#_standing_collision_shape.disabled = true
		#_crouching_collision_shape.disabled = false
	#elif !_ray_cast.is_colliding(): ##Standing
		#_crouching_collision_shape.disabled = true
		#_standing_collision_shape.disabled = false
		#
		#_head.position.y = lerp(_head.position.y, 1.8, delta * lerp_speed)
		#if Input.is_action_pressed("sprint"): ##Sprinting
			#_current_speed = sprinting_speed
			#
			#_head_bobbing_current_intensity = head_bobbing_sprinting_intensity #TESTING
			#_head_bobbing_index += head_bobbing_sprinting_speed * delta #TESTING
		#else:
			#_current_speed = walking_speed
			#_head_bobbing_current_intensity = head_bobbing_walking_intensity #TESTING
			#_head_bobbing_index += head_bobbing_walking_speed * delta #TESTING
		#
	#
	#if head_bobbing_enabled:
		#if is_on_floor() && _input_dir != Vector2.ZERO:
			#_head_bobbing_vector.y = sin(_head_bobbing_index)
			#_head_bobbing_vector.x = sin(_head_bobbing_index / 2) + 0.5
			#
			#_eyes.position.y = lerp(_eyes.position.y, _head_bobbing_vector.y * (_head_bobbing_current_intensity / 4.0), delta * lerp_speed)
			#_eyes.position.x = lerp(_eyes.position.x, _head_bobbing_vector.x * (_head_bobbing_current_intensity / 2.0), delta * lerp_speed)
		#else:
			#_eyes.position.y = lerp(_eyes.position.y, 0.0, delta * lerp_speed)
			#_eyes.position.x = lerp(_eyes.position.x, 0.0 , delta * lerp_speed)
	#
	#if not is_on_floor(): ##Gravity
		#velocity.y -= _gravity * delta
	#
	#if Input.is_action_just_pressed("jump") and is_on_floor(): ##Jumping
		#velocity.y = jump_velocity
	#
	#if is_on_floor():
		#_direction = lerp(_direction, (transform.basis * Vector3(_input_dir.x, 0, _input_dir.y)).normalized(), lerp_speed * delta)
	#else:
		#if _input_dir != Vector2.ZERO:
			#_direction = lerp(_direction, (transform.basis * Vector3(_input_dir.x, 0, _input_dir.y)).normalized(), air_lerp_speed * delta)
	#
	#if _direction:
		#velocity.x = _direction.x * _current_speed
		#velocity.z = _direction.z * _current_speed
	#else:
		#velocity.x = move_toward(velocity.x, 0, _current_speed)
		#velocity.z = move_toward(velocity.z, 0, _current_speed)
	#
	#move_and_slide()
