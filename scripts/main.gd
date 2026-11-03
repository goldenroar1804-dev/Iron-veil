extends Node3D

# IRON VEIL - first native Quest scene.
# This is a lightweight greybox so we can validate OpenXR before adding systems.

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var left_controller: XRController3D = $XROrigin3D/LeftController
@onready var right_controller: XRController3D = $XROrigin3D/RightController

func _ready() -> void:
    _start_openxr()
    _build_training_range()
    _build_controller_markers()

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
