extends Node3D

# IRON VEIL - lightweight native Quest prototype.
# Left thumbstick: smooth movement. Right thumbstick: smooth turning.
# Uses Godot's default OpenXR action map ("primary" Vector2 action).

@export var move_speed: float = 2.5
@export var turn_speed: float = 1.8
@export var stick_deadzone: float = 0.18

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $XROrigin3D/LeftController
@onready var right_controller: XRController3D = $XROrigin3D/RightController

func _ready() -> void:
    _start_openxr()
    _build_training_range()
    _build_controller_markers()

func _process(delta: float) -> void:
    if not _xr_is_active():
        return
    _update_smooth_movement(delta)
    _update_smooth_turn(delta)

func _xr_is_active() -> bool:
    var xr_interface := XRServer.find_interface("OpenXR")
    return xr_interface != null and xr_interface.is_initialized()

func _update_smooth_movement(delta: float) -> void:
    # OpenXR's default action map exposes each controller's thumbstick as "primary".
    var stick: Vector2 = left_controller.get_vector2("primary")
    if stick.length() < stick_deadzone:
        return

    var input_vector := Vector2(stick.x, -stick.y)
    if input_vector.length() > 1.0:
        input_vector = input_vector.normalized()

    # Move in the direction the headset faces, ignoring head pitch.
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

    # Rotate around the user's current head position, not the origin point.
    var head_position_before: Vector3 = xr_camera.global_position
    xr_origin.rotate_y(-stick.x * turn_speed * delta)
    var head_position_after: Vector3 = xr_camera.global_position
    xr_origin.global_position += head_position_before - head_position_after

func _start_openxr() -> void:
    var xr_interface := XRServer.find_interface("OpenXR")
    if xr_interface and xr_interface.is_initialized():
        get_viewport().use_xr = true
        print("IRON VEIL: OpenXR initialized.")
    else:
        push_warning("IRON VEIL: OpenXR is not initialized. Check the XR settings and launch on the headset.")

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

func _build_controller_markers() -> void:
    _add_controller_marker(left_controller, Color(0.15, 0.45, 0.95))
    _add_controller_marker(right_controller, Color(0.15, 0.85, 0.45))

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
