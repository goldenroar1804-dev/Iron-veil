extends Node3D

# IRON VEIL - Quest prototype.
# Left thumbstick: smooth movement. Right thumbstick: smooth turning.
# Right trigger: fire the rifle.

@export var move_speed: float = 2.5
@export var turn_speed: float = 1.8
@export var stick_deadzone: float = 0.18
@export var fire_interval: float = 0.22
@export var shot_range: float = 100.0

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $XROrigin3D/LeftController
@onready var right_controller: XRController3D = $XROrigin3D/RightController

var rifle: Node3D
var fire_cooldown := 0.0
var trigger_was_pressed := false

func _ready() -> void:
    _start_openxr()
    _build_training_range()
    _build_controller_markers()
    _build_rifle()

func _process(delta: float) -> void:
    if not _xr_is_active():
        return
    _update_smooth_movement(delta)
    _update_smooth_turn(delta)
    fire_cooldown = maxf(0.0, fire_cooldown - delta)
    _update_firing()

func _xr_is_active() -> bool:
    var xr_interface := XRServer.find_interface("OpenXR")
    return xr_interface != null and xr_interface.is_initialized()

func _update_smooth_movement(delta: float) -> void:
    var stick: Vector2 = left_controller.get_vector2("primary")
    if stick.length() < stick_deadzone:
        return
    var input_vector := Vector2(stick.x, stick.y)
    if input_vector.length() > 1.0:
        input_vector = input_vector.normalized()
    var head_forward := -xr_camera.global_transform.basis.z
    head_forward.y = 0.0
    head_forward = head_forward.normalized()
    var head_right := xr_camera.global_transform.basis.x
    head_right.y = 0.0
    head_right = head_right.normalized()
    var move_direction := head_right * input_vector.x + head_forward * input_vector.y
    xr_origin.global_position += move_direction * move_speed * delta

func _update_smooth_turn(delta: float) -> void:
    var stick: Vector2 = right_controller.get_vector2("primary")
    if absf(stick.x) < stick_deadzone:
        return
    var head_position_before: Vector3 = xr_camera.global_position
    xr_origin.rotate_y(-stick.x * turn_speed * delta)
    var head_position_after: Vector3 = xr_camera.global_position
    xr_origin.global_position += head_position_before - head_position_after

func _build_rifle() -> void:
    rifle = Node3D.new()
    rifle.name = "VR_Rifle"
    right_controller.add_child(rifle)
    # Positioned in front of the right hand, with the barrel pointing along -Z.
    _add_weapon_box(rifle, "Receiver", Vector3(0.13, 0.13, 0.34), Vector3(0, -0.055, -0.22), Color(0.12, 0.13, 0.12))
    _add_weapon_box(rifle, "Barrel", Vector3(0.045, 0.045, 0.48), Vector3(0, -0.025, -0.61), Color(0.075, 0.08, 0.075))
    _add_weapon_box(rifle, "Handguard", Vector3(0.09, 0.09, 0.28), Vector3(0, -0.025, -0.48), Color(0.17, 0.18, 0.16))
    _add_weapon_box(rifle, "Stock", Vector3(0.085, 0.11, 0.28), Vector3(0, -0.04, 0.09), Color(0.10, 0.11, 0.10))
    _add_weapon_box(rifle, "Grip", Vector3(0.07, 0.17, 0.09), Vector3(0, -0.17, -0.13), Color(0.08, 0.085, 0.08))
    _add_weapon_box(rifle, "Magazine", Vector3(0.075, 0.22, 0.11), Vector3(0, -0.22, -0.24), Color(0.09, 0.10, 0.09))
    _add_weapon_box(rifle, "Sight", Vector3(0.045, 0.07, 0.07), Vector3(0, 0.07, -0.29), Color(0.035, 0.04, 0.035))

func _add_weapon_box(parent: Node3D, label: String, dimensions: Vector3, location: Vector3, tint: Color) -> void:
    var part := MeshInstance3D.new()
    part.name = label
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    part.mesh = mesh
    part.position = location
    part.material_override = _material(tint)
    parent.add_child(part)

func _update_firing() -> void:
    # OpenXR trigger is exposed as the controller's "trigger" button.
    var pressed := right_controller.is_button_pressed("trigger")
    if pressed and not trigger_was_pressed and fire_cooldown <= 0.0:
        _fire_rifle()
        fire_cooldown = fire_interval
    trigger_was_pressed = pressed

func _fire_rifle() -> void:
    if rifle == null:
        return
    var muzzle := rifle.global_position + (-rifle.global_transform.basis.z * 0.82)
    var direction := -rifle.global_transform.basis.z.normalized()
    var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + direction * shot_range)
    query.collide_with_areas = true
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        _spawn_bullet_impact(hit.position, hit.normal)
        print("IRON VEIL: hit ", hit.collider.name)

func _spawn_bullet_impact(point: Vector3, normal: Vector3) -> void:
    var impact := MeshInstance3D.new()
    impact.name = "BulletImpact"
    var sphere := SphereMesh.new()
    sphere.radius = 0.025
    sphere.height = 0.05
    impact.mesh = sphere
    impact.material_override = _material(Color(0.025, 0.022, 0.018))
    add_child(impact)
    impact.global_position = point + normal * 0.012
    get_tree().create_timer(8.0).timeout.connect(impact.queue_free)

func _start_openxr() -> void:
    var xr_interface := XRServer.find_interface("OpenXR")
    if xr_interface and xr_interface.is_initialized():
        get_viewport().use_xr = true
        print("IRON VEIL: OpenXR initialized.")
    else:
        push_warning("IRON VEIL: OpenXR is not initialized. Check XR settings and launch on the headset.")

func _build_training_range() -> void:
    var floor_mesh := BoxMesh.new()
    floor_mesh.size = Vector3(18.0, 0.2, 18.0)
    var floor := MeshInstance3D.new()
    floor.name = "TrainingFloor"
    floor.mesh = floor_mesh
    floor.position = Vector3(0, -0.12, -5)
    floor.material_override = _material(Color(0.16, 0.18, 0.17))
    add_child(floor)

    _add_box("BackWall", Vector3(18, 4, 0.25), Vector3(0, 2, -14), Color(0.22, 0.24, 0.23))
    _add_box("LeftWall", Vector3(0.25, 4, 18), Vector3(-9, 2, -5), Color(0.19, 0.21, 0.20))
    _add_box("RightWall", Vector3(0.25, 4, 18), Vector3(9, 2, -5), Color(0.19, 0.21, 0.20))

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -25, 0)
    light.light_energy = 1.0
    add_child(light)

    _add_box("TargetStand", Vector3(0.18, 1.1, 0.18), Vector3(0, 0.55, -7), Color(0.28, 0.29, 0.27))
    _add_box("TargetPlate", Vector3(0.9, 1.2, 0.12), Vector3(0, 1.75, -7), Color(0.72, 0.12, 0.08))

    # Give the target a real physics shape so ray-fired shots can hit it.
    var target_body := StaticBody3D.new()
    target_body.name = "TargetHitbox"
    target_body.position = Vector3(0, 1.75, -7)
    var target_shape := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(0.9, 1.2, 0.12)
    target_shape.shape = shape
    target_body.add_child(target_shape)
    add_child(target_body)

func _build_controller_markers() -> void:
    _add_controller_marker(left_controller, Color(0.15, 0.45, 0.95))

func _add_controller_marker(controller: XRController3D, tint: Color) -> void:
    var marker := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.08, 0.08, 0.16)
    marker.mesh = mesh
    marker.material_override = _material(tint)
    controller.add_child(marker)

func _add_box(label: String, dimensions: Vector3, location: Vector3, tint: Color) -> void:
    var box := MeshInstance3D.new()
    box.name = label
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    box.mesh = mesh
    box.position = location
    box.material_override = _material(tint)
    add_child(box)

func _material(tint: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = tint
    mat.roughness = 0.9
    return mat
