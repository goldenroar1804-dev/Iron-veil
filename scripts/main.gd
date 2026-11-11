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
var rifle_held := false
var grip_was_pressed := false
var footstep_timer := 0.0
var muzzle_flash: MeshInstance3D
var muzzle_light: OmniLight3D
var gun_audio: AudioStreamPlayer3D
var footstep_audio: AudioStreamPlayer3D
var gun_download: HTTPRequest
var step_download: HTTPRequest
var detail_texture: ImageTexture
var left_hand_root: Node3D
var right_hand_root: Node3D
var left_hand_fingers: Array[Node3D] = []
var right_hand_fingers: Array[Node3D] = []
var left_hand_thumb: Node3D
var right_hand_thumb: Node3D
var interactive_doors: Array[Node3D] = []
var held_door: Node3D
var held_door_controller: XRController3D
var door_grab_start_vector := Vector2.ZERO
var door_grab_start_rotation := 0.0
var door_right_grip_was_pressed := false
var left_grip_was_pressed := false
var left_hand_grip_was_pressed := false
var right_hand_grip_was_pressed := false
var left_trigger_was_pressed := false
var rifle_ammo := 30
var rifle_reserve_ammo := 90
var mission_director: Node

func _ready() -> void:
    _start_openxr()
    _setup_visual_quality()
    var paint_thinner_map := preload("res://scripts/paint_thinner_map.gd").new()
    add_child(paint_thinner_map)
    paint_thinner_map.build_map(self)
    _build_hands()
    _build_rifle()
    _build_audio()

func _process(delta: float) -> void:
    if not _xr_is_active():
        return
    _update_smooth_movement(delta)
    _update_smooth_turn(delta)
    _update_hand_pose()
    var door_consumed_grip := _update_door_interaction()
    _animate_doors(delta)
    _update_weapon_grab(door_consumed_grip)
    _update_two_hand_support()
    _update_weapon_reload()
    _update_footsteps()
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
    var displacement := move_direction * move_speed * delta
    # XR origin movement is manual, so subdivide large frame steps and test
    # the standing capsule at each step. This prevents tunnelling through thin
    # walls/fences during a frame hitch while preserving axis-based wall sliding.
    var max_step := 0.12
    var steps := maxi(1, ceili(displacement.length() / max_step))
    var step_motion := displacement / float(steps)
    for _step in range(steps):
        if not _player_space_blocked(step_motion):
            xr_origin.global_position += step_motion
            continue
        var slide_x := Vector3(step_motion.x, 0.0, 0.0)
        var slide_z := Vector3(0.0, 0.0, step_motion.z)
        if not _player_space_blocked(slide_x):
            xr_origin.global_position += slide_x
        if not _player_space_blocked(slide_z):
            xr_origin.global_position += slide_z

func _player_space_blocked(displacement: Vector3) -> bool:
    if displacement.length_squared() < 0.000001:
        return false
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.28
    capsule.height = 1.55
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = capsule
    query.transform = Transform3D(Basis.IDENTITY, xr_origin.global_position + Vector3(0.0, 0.95, 0.0) + displacement)
    query.collision_mask = 1
    query.collide_with_bodies = true
    query.collide_with_areas = false
    query.margin = 0.02
    var hits := get_world_3d().direct_space_state.intersect_shape(query, 8)
    return not hits.is_empty()

func _update_smooth_turn(delta: float) -> void:
    var stick: Vector2 = right_controller.get_vector2("primary")
    if absf(stick.x) < stick_deadzone:
        return
    var head_position_before: Vector3 = xr_camera.global_position
    xr_origin.rotate_y(-stick.x * turn_speed * delta)
    var head_position_after: Vector3 = xr_camera.global_position
    xr_origin.global_position += head_position_before - head_position_after

# ---------------------------------------------------------------------------
# VR hands and weapon
# ---------------------------------------------------------------------------

func _build_hands() -> void:
    _make_human_hand(left_controller, "LeftHumanHand")
    _make_human_hand(right_controller, "RightHumanHand")

func _make_human_hand(parent: Node3D, hand_name: String) -> void:
    # A more anatomical tactical-glove silhouette. The palm lies flat in the
    # X/Z plane, with the fingers extending forward along controller -Z.
    var is_left := hand_name.begins_with("Left")
    var hand := Node3D.new()
    hand.name = hand_name
    hand.position = Vector3(0.0, -0.018, -0.075)
    hand.quaternion = Quaternion.IDENTITY
    parent.add_child(hand)
    if is_left:
        left_hand_root = hand
    else:
        right_hand_root = hand

    var glove := Color(0.105, 0.12, 0.105)
    var fabric := Color(0.19, 0.21, 0.17)
    var rubber := Color(0.045, 0.052, 0.047)
    var seam := Color(0.27, 0.28, 0.23)

    # Palm and dorsal padding: wide across X, long along Z, thin along Y.
    _add_hand_sphere(hand, "Palm", Vector3(0.073, 0.027, 0.088), Vector3(0, 0, -0.035), glove)
    _add_hand_sphere(hand, "DorsalPadding", Vector3(0.060, 0.012, 0.057), Vector3(0, 0.023, -0.044), fabric)
    _add_hand_sphere(hand, "HeelPadding", Vector3(0.061, 0.022, 0.029), Vector3(0, 0, 0.025), rubber)

    # Four individually articulated fingers with visible knuckle guards.
    var finger_array: Array[Node3D] = []
    for i in range(4):
        var x := (float(i) - 1.5) * 0.034
        var finger := Node3D.new()
        finger.name = "Finger_%d_Pivot" % i
        finger.position = Vector3(x, 0.0, -0.092)
        hand.add_child(finger)

        var proximal := _add_hand_capsule(finger, "Proximal", 0.0115, 0.067, Vector3(0, 0, -0.033), glove)
        proximal.rotation_degrees.x = 90.0
        _add_hand_sphere(finger, "KnuckleGuard", Vector3(0.014, 0.009, 0.018), Vector3(0, 0.018, -0.012), fabric)

        var distal := Node3D.new()
        distal.name = "DistalJoint"
        distal.position = Vector3(0, 0, -0.064)
        finger.add_child(distal)
        var distal_mesh := _add_hand_capsule(distal, "Distal", 0.010, 0.054, Vector3(0, 0, -0.027), glove)
        distal_mesh.rotation_degrees.x = 90.0
        _add_hand_sphere(distal, "Fingertip", Vector3(0.010, 0.010, 0.012), Vector3(0, 0, -0.049), fabric)
        finger.set_meta("distal_joint", distal)
        finger_array.append(finger)

    # Thumb angles inward across the palm instead of sticking straight out.
    var thumb := Node3D.new()
    thumb.name = "ThumbPivot"
    thumb.position = Vector3(0.068 if not is_left else -0.068, 0.0, -0.018)
    thumb.rotation_degrees.y = 38.0 if not is_left else -38.0
    hand.add_child(thumb)
    var thumb_base := _add_hand_capsule(thumb, "ThumbBase", 0.014, 0.070, Vector3(0, 0, -0.035), glove)
    thumb_base.rotation_degrees.x = 90.0
    var thumb_tip := Node3D.new()
    thumb_tip.name = "ThumbTipJoint"
    thumb_tip.position = Vector3(0, 0, -0.064)
    thumb.add_child(thumb_tip)
    var thumb_tip_mesh := _add_hand_capsule(thumb_tip, "ThumbTip", 0.0115, 0.047, Vector3(0, 0, -0.023), glove)
    thumb_tip_mesh.rotation_degrees.x = 90.0

    # Reinforced wrist cuff and a narrow seam ring.
    var cuff := _add_hand_capsule(hand, "WristCuff", 0.041, 0.092, Vector3(0, 0, 0.105), rubber)
    cuff.rotation_degrees.x = 90.0
    var cuff_band := _add_hand_capsule(hand, "CuffBand", 0.043, 0.018, Vector3(0, 0, 0.075), seam)
    cuff_band.rotation_degrees.x = 90.0

    if is_left:
        left_hand_fingers = finger_array
        left_hand_thumb = thumb
    else:
        right_hand_fingers = finger_array
        right_hand_thumb = thumb

func _update_hand_pose() -> void:
    var left_pressed := left_controller.is_button_pressed("grip") or left_controller.get_float("grip") > 0.12
    var right_pressed := right_controller.is_button_pressed("grip") or right_controller.get_float("grip") > 0.12
    if left_pressed and not left_hand_grip_was_pressed:
        left_controller.trigger_haptic_pulse("haptic", 0.22, 0.35, 0.045, 0.0)
    if right_pressed and not right_hand_grip_was_pressed and not rifle_held:
        right_controller.trigger_haptic_pulse("haptic", 0.22, 0.35, 0.045, 0.0)
    left_hand_grip_was_pressed = left_pressed
    right_hand_grip_was_pressed = right_pressed
    _pose_one_hand(left_controller, left_hand_fingers, left_hand_thumb)
    _pose_one_hand(right_controller, right_hand_fingers, right_hand_thumb)

func _pose_one_hand(controller: XRController3D, fingers: Array[Node3D], thumb: Node3D) -> void:
    if controller == null:
        return
    var grip := maxf(controller.get_float("grip"), 1.0 if controller.is_button_pressed("grip") else 0.0)
    var trigger := maxf(controller.get_float("trigger"), 1.0 if controller.is_button_pressed("trigger") else 0.0)
    for i in range(fingers.size()):
        var finger := fingers[i]
        var curl := grip * 1.18
        var index_finger_index := 3 if controller == right_controller else 0
        if i == index_finger_index:
            curl = maxf(curl, trigger * 1.18)
        finger.rotation.x = curl
        var distal := finger.get_meta("distal_joint") as Node3D
        if distal != null:
            distal.rotation.x = curl * 0.82
    if thumb != null:
        thumb.rotation.y = grip * (0.72 if controller == right_controller else -0.72)
        thumb.rotation.x = grip * 0.48


func _add_hand_sphere(parent: Node3D, label: String, dimensions: Vector3, location: Vector3, tint: Color) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = label
    var mesh := SphereMesh.new()
    part.mesh = mesh
    part.scale = dimensions * 2.0
    part.position = location
    part.material_override = _material(tint)
    parent.add_child(part)
    return part

func _add_hand_capsule(parent: Node3D, label: String, radius: float, length: float, location: Vector3, tint: Color) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = label
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = length
    part.mesh = mesh
    part.position = location
    part.material_override = _material(tint)
    parent.add_child(part)
    return part

func _build_rifle() -> void:
    rifle = Node3D.new()
    rifle.name = "M4A1_Carbine"
    rifle.position = Vector3(0.025, -0.11, -0.22)
    rifle.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
    add_child(rifle)
    var forward := -xr_camera.global_transform.basis.z
    forward.y = 0.0
    rifle.global_position = xr_camera.global_position + forward.normalized() * 0.72 + Vector3(0, -0.78, 0)
    rifle.global_rotation = xr_camera.global_rotation
    _add_box("WeaponPickupStand_Top", Vector3(0.55, 0.06, 0.42), rifle.global_position + Vector3(0, -0.42, 0), Color(0.18, 0.19, 0.17))
    _add_box("WeaponPickupStand_LegA", Vector3(0.06, 0.42, 0.06), rifle.global_position + Vector3(-0.20, -0.66, 0), Color(0.12, 0.13, 0.12))
    _add_box("WeaponPickupStand_LegB", Vector3(0.06, 0.42, 0.06), rifle.global_position + Vector3(0.20, -0.66, 0), Color(0.12, 0.13, 0.12))

    # Prefer a real imported GLB when one is installed; retain the Quest-friendly
    # procedural rifle as a fallback so the project remains runnable out of the box.
    var has_imported_rifle := _try_add_imported_model(
        rifle,
        "res://assets/models/weapons/m4_carbine.glb",
        "ImportedM4Carbine"
    )
    if not has_imported_rifle:
        var black := Color(0.045, 0.052, 0.048)
        var receiver := Color(0.105, 0.115, 0.105)
        var polymer := Color(0.15, 0.16, 0.14)
        var steel := Color(0.23, 0.24, 0.22)
        var glass := Color(0.025, 0.075, 0.065)

        # M4-style silhouette: adjustable stock, buffer tube, split receiver,
        # curved magazine, quad-rail handguard, front sight and muzzle device.
        _add_weapon_cylinder(rifle, "BufferTube", 0.027, 0.23, Vector3(0, 0.0, 0.19), steel)
        _add_weapon_box(rifle, "AdjustableStock", Vector3(0.105, 0.14, 0.26), Vector3(0, -0.005, 0.31), polymer)
        _add_weapon_box(rifle, "RubberButtPad", Vector3(0.11, 0.15, 0.025), Vector3(0, -0.005, 0.445), black)
        _add_weapon_box(rifle, "LowerReceiver", Vector3(0.105, 0.13, 0.24), Vector3(0, -0.075, -0.13), receiver)
        _add_weapon_box(rifle, "UpperReceiver", Vector3(0.105, 0.095, 0.34), Vector3(0, 0.015, -0.20), steel)
        _add_weapon_box(rifle, "EjectionPort", Vector3(0.008, 0.042, 0.105), Vector3(0.056, -0.005, -0.19), black)
        _add_weapon_box(rifle, "ForwardAssist", Vector3(0.025, 0.035, 0.035), Vector3(0.06, 0.035, -0.31), black)
        _add_weapon_box(rifle, "QuadRailHandguard", Vector3(0.115, 0.12, 0.37), Vector3(0, 0.01, -0.53), polymer)
        _add_weapon_cylinder(rifle, "OuterBarrel", 0.018, 0.58, Vector3(0, 0.01, -0.99), black)
        _add_weapon_cylinder(rifle, "FrontBarrelCollar", 0.027, 0.045, Vector3(0, 0.01, -0.78), steel)
        _add_weapon_cylinder(rifle, "A2BirdcageFlashHider", 0.026, 0.075, Vector3(0, 0.01, -1.30), steel)
        _add_weapon_box(rifle, "TopPicatinnyRail", Vector3(0.045, 0.025, 0.76), Vector3(0, 0.08, -0.50), black)
        _add_weapon_box(rifle, "CarryHandleOpticMount", Vector3(0.09, 0.06, 0.13), Vector3(0, 0.13, -0.28), black)
        _add_weapon_box(rifle, "RedDotOptic", Vector3(0.075, 0.085, 0.12), Vector3(0, 0.19, -0.29), black)
        _add_weapon_box(rifle, "OpticLens", Vector3(0.065, 0.062, 0.006), Vector3(0, 0.19, -0.354), glass)
        _add_weapon_box(rifle, "FrontSightPost", Vector3(0.022, 0.075, 0.025), Vector3(0, 0.13, -0.69), steel)
        _add_weapon_box(rifle, "FrontSightWings", Vector3(0.10, 0.018, 0.025), Vector3(0, 0.12, -0.69), steel)
        _add_weapon_box(rifle, "PistolGrip", Vector3(0.065, 0.18, 0.09), Vector3(0, -0.19, -0.09), black)
        _add_weapon_box(rifle, "TriggerGuard", Vector3(0.075, 0.018, 0.095), Vector3(0, -0.155, -0.11), steel)
        _add_weapon_box(rifle, "Trigger", Vector3(0.012, 0.045, 0.018), Vector3(0, -0.15, -0.12), steel)
        _add_weapon_box(rifle, "MagazineWell", Vector3(0.09, 0.07, 0.11), Vector3(0, -0.15, -0.19), black)
        _add_weapon_box(rifle, "STANAGMagazine", Vector3(0.075, 0.25, 0.105), Vector3(0, -0.29, -0.20), black)
        _add_weapon_box(rifle, "MagazineFloorplate", Vector3(0.08, 0.025, 0.11), Vector3(0, -0.425, -0.20), steel)
        # Rail slots and fasteners add detail without high-cost geometry.
        for i in range(8):
            var z := -0.39 - float(i) * 0.039
            _add_weapon_box(rifle, "RailSlot_%d" % i, Vector3(0.122, 0.012, 0.012), Vector3(0, 0.075, z), black)
        for side in [-1.0, 1.0]:
            _add_weapon_box(rifle, "SideRail_%s" % side, Vector3(0.018, 0.045, 0.27), Vector3(side * 0.064, 0.01, -0.53), black)
            _add_weapon_box(rifle, "HandStop_%s" % side, Vector3(0.035, 0.06, 0.045), Vector3(side * 0.073, -0.01, -0.64), steel)


    # Three offset, crossed transparent flame cards create a broad layered burst
    # directly at the muzzle rather than a thin line.
    var flash_textures: Array[Texture2D] = [
        _create_muzzle_flash_png(Color(1.0, 0.58, 0.10), 1.0),
        _create_muzzle_flash_png(Color(1.0, 0.24, 0.025), 0.78),
        _create_muzzle_flash_png(Color(1.0, 0.88, 0.48), 0.48)
    ]
    for i in range(3):
        var card := MeshInstance3D.new()
        card.name = "MuzzleFlash_Layer_%d" % i
        var quad := QuadMesh.new()
        quad.size = Vector2(0.34 + float(i) * 0.15, 0.20 + float(i) * 0.07)
        card.mesh = quad
        card.position = Vector3(0, 0.01, -1.36 - float(i) * 0.012)
        card.rotation_degrees.y = float(i) * 27.0
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
        mat.albedo_texture = flash_textures[i]
        mat.emission_enabled = true
        mat.emission = Color(1.0, 0.42, 0.08)
        mat.emission_energy_multiplier = 2.5
        card.material_override = mat
        card.visible = false
        rifle.add_child(card)
        if i == 0:
            muzzle_flash = card
    muzzle_light = OmniLight3D.new()
    muzzle_light.light_color = Color(1.0, 0.48, 0.12)
    muzzle_light.light_energy = 0.0
    muzzle_light.omni_range = 4.5
    muzzle_light.position = Vector3(0, 0.01, -1.38)
    rifle.add_child(muzzle_light)

func _add_weapon_box(parent: Node3D, label: String, dimensions: Vector3, location: Vector3, tint: Color) -> void:
    var part := MeshInstance3D.new()
    part.name = label
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    part.mesh = mesh
    part.position = location
    part.material_override = _material(tint)
    parent.add_child(part)

func _add_weapon_cylinder(parent: Node3D, label: String, radius: float, length: float, location: Vector3, tint: Color) -> void:
    var part := MeshInstance3D.new()
    part.name = label
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = length
    mesh.radial_segments = 16
    part.mesh = mesh
    part.position = location
    part.rotation_degrees.x = 90.0
    part.material_override = _material(tint)
    parent.add_child(part)

func _update_weapon_grab(door_consumed_grip: bool = false) -> void:
    var right_grip := right_controller.is_button_pressed("grip") or right_controller.get_float("grip") > 0.55
    if not door_consumed_grip and not rifle_held and right_grip and right_controller.global_position.distance_to(rifle.global_position) < 0.65:
        rifle.reparent(right_controller, false)
        rifle.position = Vector3(0.025, -0.11, -0.22)
        rifle.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
        rifle_held = true
        right_controller.trigger_haptic_pulse("haptic", 0.85, 0.9, 0.16, 0.0)
        print("IRON VEIL: M4 grip acquired")
    elif rifle_held and grip_was_pressed and not right_grip:
        rifle.reparent(self, true)
        rifle_held = false
        right_controller.trigger_haptic_pulse("haptic", 0.55, 0.45, 0.10, 0.0)
        print("IRON VEIL: M4 released")
    grip_was_pressed = right_grip

func _update_two_hand_support() -> void:
    if not rifle_held:
        return
    var left_grip := left_controller.is_button_pressed("grip") or left_controller.get_float("grip") > 0.55
    var foregrip_position := rifle.to_global(Vector3(0.0, 0.01, -0.53))
    if left_grip and left_controller.global_position.distance_to(foregrip_position) < 0.70:
        var support_direction := left_controller.global_position - right_controller.global_position
        if support_direction.length_squared() > 0.01:
            rifle.look_at(rifle.global_position + support_direction.normalized(), Vector3.UP)
    else:
        rifle.rotation_degrees = Vector3(-4.0, 0.0, 0.0)

func _update_weapon_reload() -> void:
    var left_trigger := left_controller.is_button_pressed("trigger") or left_controller.get_float("trigger") > 0.65
    if rifle_held and left_trigger and not left_trigger_was_pressed and rifle_ammo < 30 and rifle_reserve_ammo > 0:
        var needed := 30 - rifle_ammo
        var loaded := mini(needed, rifle_reserve_ammo)
        rifle_ammo += loaded
        rifle_reserve_ammo -= loaded
        left_controller.trigger_haptic_pulse("haptic", 0.7, 0.7, 0.12, 0.0)
        print("IRON VEIL: reload complete | magazine ", rifle_ammo, " | reserve ", rifle_reserve_ammo)
    left_trigger_was_pressed = left_trigger

func _update_firing() -> void:
    var pressed := right_controller.is_button_pressed("trigger") or right_controller.get_float("trigger") > 0.65
    if rifle_held and pressed and not trigger_was_pressed and fire_cooldown <= 0.0 and rifle_ammo > 0:
        _fire_rifle()
        fire_cooldown = fire_interval
    trigger_was_pressed = pressed

func _fire_rifle() -> void:
    if rifle == null or not rifle_held or rifle_ammo <= 0:
        return
    rifle_ammo -= 1
    for child in rifle.get_children():
        if child.name.begins_with("MuzzleFlash_Layer_"):
            child.visible = true
    muzzle_light.light_energy = 4.0
    get_tree().create_timer(0.075).timeout.connect(func():
        if is_instance_valid(rifle):
            for child in rifle.get_children():
                if child.name.begins_with("MuzzleFlash_Layer_"):
                    child.visible = false
            muzzle_light.light_energy = 0.0
    )
    gun_audio.global_position = rifle.global_position
    gun_audio.play()
    right_controller.trigger_haptic_pulse("haptic", 0.95, 0.8, 0.075, 0.0)
    var muzzle := rifle.global_position + (-rifle.global_transform.basis.z * 1.40)
    for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
        if is_instance_valid(enemy) and enemy.has_method("notify_sound"):
            enemy.notify_sound(muzzle)
    var direction := -rifle.global_transform.basis.z.normalized()
    var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + direction * shot_range)
    query.collide_with_areas = true
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        _spawn_bullet_impact(hit.position, hit.normal)
        if hit.collider.has_method("apply_hit"):
            hit.collider.apply_hit(1)
        print("IRON VEIL: hit ", hit.collider.name)

func _create_muzzle_flash_png(tint: Color, brightness: float) -> Texture2D:
    var image := Image.create(128, 96, false, Image.FORMAT_RGBA8)
    for y in range(96):
        for x in range(128):
            var nx := float(x) / 127.0
            var ny := absf((float(y) - 47.5) / 47.5)
            var flicker := 0.72 + 0.28 * sin(float(x) * 0.31 + float(y) * 0.17)
            var envelope := pow(maxf(0.0, 1.0 - nx), 0.58)
            var width := 0.10 + 0.86 * envelope
            var edge := ny / width
            var alpha := clampf((1.0 - edge) * 1.65, 0.0, 1.0) * clampf((1.0 - nx) * 1.55, 0.0, 1.0) * flicker * brightness
            var color := Color(tint.r, tint.g * (0.72 + 0.28 * (1.0 - nx)), tint.b, alpha)
            if edge < 0.25:
                color = Color(1.0, 0.92, 0.64, alpha)
            image.set_pixel(x, y, color)
    return ImageTexture.create_from_image(image)

func _build_audio() -> void:
    gun_audio = AudioStreamPlayer3D.new()
    gun_audio.name = "GunshotAudio"
    gun_audio.volume_db = -2.0
    gun_audio.max_distance = 65.0
    gun_audio.unit_size = 18.0
    add_child(gun_audio)

    footstep_audio = AudioStreamPlayer3D.new()
    footstep_audio.name = "FootstepAudio"
    footstep_audio.volume_db = -7.0
    footstep_audio.max_distance = 18.0
    footstep_audio.unit_size = 7.0
    add_child(footstep_audio)

    # CC0 audio downloads are cached locally after the first successful fetch.
    gun_download = HTTPRequest.new()
    gun_download.name = "CC0_Rifle_Sound_Download"
    add_child(gun_download)
    gun_download.request_completed.connect(_on_gun_sound_downloaded)
    step_download = HTTPRequest.new()
    step_download.name = "CC0_Footstep_Sound_Download"
    add_child(step_download)
    step_download.request_completed.connect(_on_footstep_sound_downloaded)
    # Bundled/imported Godot audio takes priority. Network downloads remain a
    # fallback for the original prototype and are cached in user:// as before.
    var local_rifle_audio := _load_local_audio([
        "res://assets/audio/rifle_shot.ogg",
        "res://assets/audio/rifle_shot.wav",
        "res://assets/audio/rifle_shot.mp3"
    ])
    var local_footstep_audio := _load_local_audio([
        "res://assets/audio/footsteps_concrete.ogg",
        "res://assets/audio/footsteps_concrete.wav",
        "res://assets/audio/footsteps_concrete.mp3"
    ])
    if local_rifle_audio != null:
        gun_audio.stream = local_rifle_audio
    else:
        _load_or_download_sound("user://iron_veil_rifle.mp3", "https://sfxmint.com/dl/impact-gunshot-08.mp3", gun_download)
    if local_footstep_audio != null:
        footstep_audio.stream = local_footstep_audio
    else:
        _load_or_download_sound("user://iron_veil_steps.mp3", "https://sfxmint.com/dl/footsteps-concrete-75.mp3", step_download)

func _load_local_audio(paths: Array[String]) -> AudioStream:
    for path in paths:
        if ResourceLoader.exists(path):
            var stream := ResourceLoader.load(path) as AudioStream
            if stream != null:
                print("IRON VEIL: loaded bundled audio: ", path)
                return stream
            push_warning("IRON VEIL: audio asset could not be loaded: " + path)
    return null

func _try_add_imported_model(parent: Node3D, path: String, instance_name: String) -> bool:
    if not ResourceLoader.exists(path):
        return false
    var packed_scene := ResourceLoader.load(path) as PackedScene
    if packed_scene == null:
        push_warning("IRON VEIL: imported model is not a PackedScene: " + path)
        return false
    var model := packed_scene.instantiate()
    model.name = instance_name
    parent.add_child(model)
    _enhance_imported_materials(model)
    print("IRON VEIL: loaded imported model: ", path)
    return true

func _enhance_imported_materials(root: Node) -> void:
    # Preserve each asset's authored albedo/normal/metallic textures, while
    # adding a subtle high-frequency detail layer and Quest-friendly filtering.
    if root is MeshInstance3D:
        var mesh_instance := root as MeshInstance3D
        if mesh_instance.mesh != null:
            for surface in range(mesh_instance.mesh.get_surface_count()):
                var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
                if source == null:
                    continue
                var tuned := source.duplicate() as StandardMaterial3D
                tuned.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
                tuned.roughness = clampf(tuned.roughness, 0.38, 0.94)
                tuned.detail_enabled = true
                tuned.detail_albedo = detail_texture
                tuned.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
                tuned.roughness = clampf(tuned.roughness * 0.92, 0.32, 0.96)
                mesh_instance.set_surface_override_material(surface, tuned)
    for child in root.get_children():
        _enhance_imported_materials(child)

func _make_house_cutaway(root: Node3D) -> void:
    # Keep the authored exterior asset but remove its street-facing wall and
    # roof panels when they are separate meshes, creating a playable CQB cutaway.
    # This reveals the built-in floor/stair/upper landing without changing the
    # model's remaining walls, facade details, or collision layout.
    var hidden_panels := 0
    var meshes: Array[MeshInstance3D] = []
    _collect_mesh_instances(root, meshes)
    for mesh_instance in meshes:
        if mesh_instance.mesh == null:
            continue
        var bounds := mesh_instance.get_aabb()
        var center_world := mesh_instance.to_global(bounds.get_center())
        var center_local := root.to_local(center_world)
        var size := bounds.size * mesh_instance.global_basis.get_scale().abs()
        var front_wall := center_local.z < -2.25 and center_local.y > 0.35 and center_local.y < 2.8 and size.x > 1.2 and size.y > 1.0 and size.z < 0.65
        var roof_panel := center_local.y > 3.0 and size.x > 2.0 and size.z > 2.0 and size.y < 0.65
        if front_wall or roof_panel:
            mesh_instance.visible = false
            hidden_panels += 1
    print("IRON VEIL: house cutaway panels hidden: ", hidden_panels)

func _collect_mesh_instances(root: Node, output: Array[MeshInstance3D]) -> void:
    for child in root.get_children():
        if child is MeshInstance3D:
            output.append(child as MeshInstance3D)
        _collect_mesh_instances(child, output)

func _strip_imported_physics(root: Node) -> void:
    for child in root.get_children():
        if child is CollisionObject3D or child is CollisionShape3D:
            root.remove_child(child)
            child.queue_free()
        else:
            _strip_imported_physics(child)

func _install_environment_model(label: String, center: Vector3, path: String, model_scale: Vector3) -> void:
    if not ResourceLoader.exists(path):
        return
    var visual_root := Node3D.new()
    visual_root.name = label + "_ImportedVisual"
    visual_root.position = center
    visual_root.scale = model_scale
    add_child(visual_root)
    if not _try_add_imported_model(visual_root, path, "ImportedEnvironmentModel"):
        visual_root.queue_free()
        return
    if label.begins_with("House_"):
        _make_house_cutaway(visual_root)
    # GLB assets are visual-only. Strip any physics nodes imported with the
    # model so only the hand-authored, correctly placed gameplay colliders remain.
    _strip_imported_physics(visual_root)
    # Hide matching procedural render meshes, but deliberately do not touch
    # StaticBody3D or CollisionShape3D nodes generated by _add_box().
    for child in get_children():
        if child is MeshInstance3D and child.name.begins_with(label + "_"):
            # Keep the authored playable interior: floor, stair treads and landing.
            # Only obsolete exterior prototype meshes are hidden by the imported shell.
            var keep_interior := child.name.contains("InteriorFloor") or child.name.contains("Stair_") or child.name.contains("UpperLanding") or child.name.contains("UpperFloor")
            var keep_facade_detail := child.name.contains("Foundation") or child.name.contains("FrontCornerBoard") or child.name.contains("WindowSill") or child.name.contains("WindowJamb") or child.name.contains("DoorJamb") or child.name.contains("DoorHeaderTrim") or child.name.contains("PorchStep") or child.name.contains("RoofFascia") or child.name.contains("Downspout") or child.name.contains("SidingLine")
            if not keep_interior and not keep_facade_detail:
                child.visible = false

func _load_or_download_sound(cache_path: String, url: String, request_node: HTTPRequest) -> void:
    if FileAccess.file_exists(cache_path):
        var file := FileAccess.open(cache_path, FileAccess.READ)
        if file:
            var stream := AudioStreamMP3.load_from_buffer(file.get_buffer(file.get_length()))
            if request_node == gun_download:
                gun_audio.stream = stream
            else:
                footstep_audio.stream = stream
            return
    request_node.request(url)

func _on_gun_sound_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 1000:
        var file := FileAccess.open("user://iron_veil_rifle.mp3", FileAccess.WRITE)
        if file:
            file.store_buffer(body)
        gun_audio.stream = AudioStreamMP3.load_from_buffer(body)
    else:
        push_warning("IRON VEIL: CC0 rifle audio download failed; no recorded rifle sound loaded.")

func _on_footstep_sound_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 500:
        var file := FileAccess.open("user://iron_veil_steps.mp3", FileAccess.WRITE)
        if file:
            file.store_buffer(body)
        footstep_audio.stream = AudioStreamMP3.load_from_buffer(body)
    else:
        push_warning("IRON VEIL: CC0 footstep audio download failed; no recorded footstep sound loaded.")

func _update_footsteps() -> void:
    var stick: Vector2 = left_controller.get_vector2("primary")
    footstep_timer = maxf(0.0, footstep_timer - get_process_delta_time())
    if stick.length() > stick_deadzone and footstep_timer <= 0.0:
        footstep_audio.global_position = xr_camera.global_position
        footstep_audio.play()
        footstep_timer = 0.48

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

# ---------------------------------------------------------------------------
# Suburban CQB training environment
# ---------------------------------------------------------------------------

func _build_suburban_block() -> void:
    var grass_lot := _add_box("GrassLot", Vector3(40, 0.18, 82), Vector3(0, -0.16, -39), Color(0.20, 0.29, 0.17))
    grass_lot.material_override = _grass_material()
    _add_box("AsphaltStreet", Vector3(9.0, 0.12, 82), Vector3(0, -0.045, -39), Color(0.105, 0.115, 0.12))
    _add_box("LeftSidewalk", Vector3(2.0, 0.16, 82), Vector3(-5.5, 0.0, -39), Color(0.42, 0.42, 0.39))
    _add_box("RightSidewalk", Vector3(2.0, 0.16, 82), Vector3(5.5, 0.0, -39), Color(0.42, 0.42, 0.39))
    for z in range(0, 82, 4):
        _add_visual_box("CenterRoadDash_%d" % z, Vector3(0.12, 0.012, 1.8), Vector3(0, 0.02, -float(z) - 1.0), Color(0.78, 0.73, 0.53))

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -28, 0)
    sun.light_energy = 1.15
    add_child(sun)

    # Simple low-poly houses on both sides of the street.
    var house_centers: Array[Vector3] = [
        Vector3(-11, 0, -10), Vector3(11, 0, -18),
        Vector3(-11, 0, -30), Vector3(11, 0, -38),
        Vector3(-11, 0, -50), Vector3(11, 0, -58),
        Vector3(-11, 0, -70), Vector3(11, 0, -76)
    ]
    var house_colors: Array[Color] = [
        Color(0.66, 0.57, 0.45), Color(0.55, 0.61, 0.63),
        Color(0.62, 0.63, 0.54), Color(0.67, 0.55, 0.52),
        Color(0.58, 0.60, 0.65), Color(0.68, 0.62, 0.49),
        Color(0.54, 0.61, 0.53), Color(0.64, 0.57, 0.55)
    ]
    for i in range(house_centers.size()):
        var house_name := "House_%02d" % i
        _build_house(house_name, house_centers[i], house_colors[i])
        _spawn_random_house_targets(house_name, house_centers[i])

    # Fences/hedges live in the gaps between house lots, outside the
    # imported house footprints and clear of the front-door approach.
    for side in [-1.0, 1.0]:
        for i in range(3):
            var zpos := (-20.0 if side < 0.0 else -28.0) - float(i) * 20.0
            # Lots occupy roughly |x|=7.5..14.5. Keep landscaping at the
            # outer property edge so it cannot clip through imported house meshes.
            _build_fence_segment("Fence_%s_%d" % [str(side), i], side * 16.0, zpos)
            _build_hedge("Hedge_%s_%d" % [str(side), i], Vector3(side * 17.35, 0.45, zpos + 2.7))
        _add_streetlight(side * 5.0, -12.0)
        _add_streetlight(side * 5.0, -30.0)

    _build_parked_car("ParkedCar_Left_01", Vector3(-3.5, 0.0, -17.0), Color(0.22, 0.27, 0.31))
    _build_parked_car("ParkedCar_Right_01", Vector3(3.5, 0.0, -28.0), Color(0.35, 0.16, 0.12))
    _build_parked_car("ParkedCar_Left_02", Vector3(-3.5, 0.0, -48.0), Color(0.19, 0.24, 0.20))
    _build_parked_car("ParkedCar_Right_02", Vector3(3.5, 0.0, -66.0), Color(0.28, 0.20, 0.16))
    _spawn_tactical_enemies()



func _spawn_tactical_enemies() -> void:
    xr_camera.add_to_group("player_camera")
    var enemy_positions: Array[Vector3] = [
        Vector3(-12.0, 0.05, -12.0),
        Vector3(12.0, 0.05, -12.0),
        Vector3(-12.0, 0.05, 9.0),
        Vector3(12.0, 0.05, 9.0)
    ]
    var director_script := load("res://scripts/mission_director.gd") as Script
    if director_script != null:
        mission_director = Node.new()
        mission_director.name = "MissionDirector"
        mission_director.set_script(director_script)
        add_child(mission_director)
        mission_director.call("start_operation", enemy_positions.size())
    var enemy_script := load("res://scripts/tactical_enemy.gd") as Script
    if enemy_script == null:
        push_warning("IRON VEIL: tactical enemy script could not be loaded.")
        return
    for i in range(enemy_positions.size()):
        var enemy := CharacterBody3D.new()
        enemy.name = "PvE_OpFor_%02d" % i
        enemy.position = enemy_positions[i]
        enemy.set_script(enemy_script)
        enemy.set("aggression", randf_range(0.35, 0.95))
        enemy.set("move_speed", randf_range(0.9, 1.45))
        var collision := CollisionShape3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.30
        capsule.height = 1.75
        collision.shape = capsule
        collision.position.y = 0.88
        enemy.add_child(collision)
        var uniform := MeshInstance3D.new()
        uniform.name = "Uniform"
        var torso := CapsuleMesh.new()
        torso.radius = 0.29
        torso.height = 1.25
        uniform.mesh = torso
        uniform.position.y = 0.92
        uniform.material_override = _material(Color(0.19, 0.22, 0.18))
        enemy.add_child(uniform)
        var head := MeshInstance3D.new()
        head.name = "Head"
        var head_shape := SphereMesh.new()
        head_shape.radius = 0.16
        head_shape.height = 0.32
        head.mesh = head_shape
        head.position.y = 1.68
        head.material_override = _material(Color(0.34, 0.27, 0.21))
        enemy.add_child(head)
        enemy.set("body_mesh", uniform)
        enemy.set("head_mesh", head)
        add_child(enemy)
        if mission_director != null:
            mission_director.call("register_enemy", enemy)

func _spawn_random_house_targets(house_name: String, center: Vector3) -> void:
    # Each house receives a randomized number and arrangement of indoor CQB targets.
    var count := randi_range(1, 3)
    for n in range(count):
        var local_x := randf_range(-2.2, 2.2)
        var local_z := randf_range(-1.5, 1.45)
        var tint := Color(0.72, 0.13, 0.09) if randf() < 0.5 else Color(0.76, 0.67, 0.43)
        _build_cqb_target("%s_RandomCQB_%02d" % [house_name, n], center + Vector3(local_x, 0, local_z), tint)


func _grass_material() -> StandardMaterial3D:
    # Flat color variation only: no blade meshes, particles, or raised grass.
    var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
    var noise := []
    for y in range(128):
        var row := []
        for x in range(128):
            row.append(randf_range(-0.045, 0.045))
        noise.append(row)
    for y in range(128):
        for x in range(128):
            var variation := float(noise[y][x]) * 0.45
            for oy in [-1, 0, 1]:
                for ox in [-1, 0, 1]:
                    variation += float(noise[posmod(y + oy, 128)][posmod(x + ox, 128)]) * 0.061
            var base := Color(0.19, 0.29, 0.13)
            image.set_pixel(x, y, Color(
                clampf(base.r + variation * 0.72, 0.0, 1.0),
                clampf(base.g + variation, 0.0, 1.0),
                clampf(base.b + variation * 0.55, 0.0, 1.0),
                1.0
            ))
    var texture := ImageTexture.create_from_image(image)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color.WHITE
    mat.albedo_texture = texture
    mat.roughness = 1.0
    mat.metallic = 0.0
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    mat.uv1_scale = Vector3(18.0, 36.0, 1.0)
    return mat

func _build_house(label: String, center: Vector3, wall_color: Color) -> void:
    # Imported shell supplies the detailed exterior. Replace the old prototype
    # wall colliders with a matching playable interior collision layout.
    _add_box(label + "_InteriorFloor", Vector3(6.7, 0.12, 5.2), center + Vector3(0, 0.02, 0), Color(0.34, 0.31, 0.26))
    _add_box(label + "_BackWall", Vector3(7.0, 3.1, 0.18), center + Vector3(0, 1.55, 2.66), wall_color)
    _add_box(label + "_LeftWall", Vector3(0.18, 3.1, 5.5), center + Vector3(-3.41, 1.55, 0), wall_color)
    _add_box(label + "_RightWall", Vector3(0.18, 3.1, 5.5), center + Vector3(3.41, 1.55, 0), wall_color)
    _add_box(label + "_FrontWallLeft", Vector3(2.8, 3.1, 0.18), center + Vector3(-2.1, 1.55, -2.66), wall_color)
    _add_box(label + "_FrontWallRight", Vector3(2.8, 3.1, 0.18), center + Vector3(2.1, 1.55, -2.66), wall_color)
    _add_box(label + "_DoorHeader", Vector3(1.4, 0.65, 0.18), center + Vector3(0, 2.78, -2.66), wall_color)
    _add_box(label + "_Roof", Vector3(7.7, 0.35, 6.2), center + Vector3(0, 3.25, 0), Color(0.20, 0.18, 0.16))
    _add_box(label + "_WindowA", Vector3(1.25, 1.0, 0.07), center + Vector3(-1.6, 1.9, -2.81), Color(0.12, 0.22, 0.27))
    _add_box(label + "_WindowB", Vector3(1.25, 1.0, 0.07), center + Vector3(1.6, 1.9, -2.81), Color(0.12, 0.22, 0.27))
    _add_box(label + "_WindowTrimA", Vector3(1.38, 0.08, 0.09), center + Vector3(-1.6, 2.43, -2.83), Color(0.82, 0.79, 0.68))
    _add_box(label + "_WindowTrimB", Vector3(1.38, 0.08, 0.09), center + Vector3(1.6, 2.43, -2.83), Color(0.82, 0.79, 0.68))

    # Architectural pass: foundation course, corner boards, window sills,
    # door casing, porch landing, fascia and downspouts add depth to the shell.
    _add_visual_box(label + "_FoundationFront", Vector3(7.45, 0.24, 0.22), center + Vector3(0, 0.16, -3.02), Color(0.29, 0.28, 0.25))
    _add_visual_box(label + "_FoundationLeft", Vector3(0.22, 0.24, 5.95), center + Vector3(-3.77, 0.16, 0), Color(0.29, 0.28, 0.25))
    _add_visual_box(label + "_FoundationRight", Vector3(0.22, 0.24, 5.95), center + Vector3(3.77, 0.16, 0), Color(0.29, 0.28, 0.25))
    for side in [-1.0, 1.0]:
        _add_visual_box(label + "_FrontCornerBoard", Vector3(0.13, 3.05, 0.10), center + Vector3(side * 3.58, 1.68, -3.04), Color(0.78, 0.75, 0.66))
        _add_visual_box(label + "_WindowSill", Vector3(1.43, 0.09, 0.15), center + Vector3(side * 1.6, 1.36, -2.91), Color(0.83, 0.80, 0.70))
        _add_visual_box(label + "_WindowJamb", Vector3(0.075, 1.08, 0.10), center + Vector3(side * 2.27, 1.88, -2.91), Color(0.83, 0.80, 0.70))
    _add_visual_box(label + "_DoorJambLeft", Vector3(0.09, 2.18, 0.12), center + Vector3(-0.73, 1.15, -3.03), Color(0.82, 0.78, 0.67))
    _add_visual_box(label + "_DoorJambRight", Vector3(0.09, 2.18, 0.12), center + Vector3(0.73, 1.15, -3.03), Color(0.82, 0.78, 0.67))
    _add_visual_box(label + "_DoorHeaderTrim", Vector3(1.55, 0.10, 0.13), center + Vector3(0, 2.28, -3.03), Color(0.82, 0.78, 0.67))
    _add_visual_box(label + "_PorchStep", Vector3(1.65, 0.16, 0.55), center + Vector3(0, 0.10, -3.34), Color(0.43, 0.42, 0.38))
    _add_visual_box(label + "_RoofFasciaFront", Vector3(7.85, 0.20, 0.18), center + Vector3(0, 3.28, -3.13), Color(0.16, 0.15, 0.14))
    _add_visual_box(label + "_RoofFasciaBack", Vector3(7.85, 0.20, 0.18), center + Vector3(0, 3.28, 3.13), Color(0.16, 0.15, 0.14))
    for side in [-1.0, 1.0]:
        _add_visual_box(label + "_Downspout", Vector3(0.07, 3.05, 0.07), center + Vector3(side * 3.69, 1.68, -2.91), Color(0.22, 0.23, 0.21))
    # Subtle horizontal siding courses break up broad, flat wall surfaces.
    for course in range(1, 6):
        var y := 0.55 + float(course) * 0.43
        _add_visual_box(label + "_SidingLine", Vector3(7.25, 0.018, 0.035), center + Vector3(0, y, -3.075), Color(0.48, 0.46, 0.40))


    _install_environment_model(label, center, "res://assets/models/environment/suburban_house.glb", Vector3.ONE)
    # Imported house meshes are the visible shell. Discard every stale collider
    # created for the old box-house and rebuild a small, consistent collision shell.
    for child in get_children():
        if child is CollisionObject3D and child.name.begins_with(label + "_"):
            # Remove the prototype collision bodies from the scene tree
            # immediately; only the custom shell/stair collision layout below survives.
            remove_child(child)
            child.queue_free()
    _add_house_collider(label + "_FloorCollision", center + Vector3(0, -0.04, 0), Vector3(7.2, 0.18, 5.9))
    _add_house_collider(label + "_BackCollision", center + Vector3(0, 1.55, 2.98), Vector3(7.7, 3.1, 0.16))
    _add_house_collider(label + "_LeftCollision", center + Vector3(-3.83, 1.55, 0), Vector3(0.16, 3.1, 6.0))
    _add_house_collider(label + "_RightCollision", center + Vector3(3.83, 1.55, 0), Vector3(0.16, 3.1, 6.0))
    _add_house_collider(label + "_FrontLeftCollision", center + Vector3(-2.225, 1.55, -2.98), Vector3(3.15, 3.1, 0.16))
    _add_house_collider(label + "_FrontRightCollision", center + Vector3(2.225, 1.55, -2.98), Vector3(3.15, 3.1, 0.16))
    _add_house_collider(label + "_HeaderCollision", center + Vector3(0, 2.85, -2.98), Vector3(1.4, 0.5, 0.16))

    # Ten walkable stair treads rise along the left interior wall to a second floor.
    for step in range(10):
        var tread := 0.29
        var rise := 0.285
        var step_pos := center + Vector3(-2.35, 0.16 + float(step) * rise, -1.45 + float(step) * tread)
        _add_box(label + "_Stair_%02d" % step, Vector3(0.92, 0.18, 0.34), step_pos, Color(0.29, 0.25, 0.20))
    _add_box(label + "_UpperLanding", Vector3(1.0, 0.16, 1.25), center + Vector3(-2.35, 3.02, 1.55), Color(0.30, 0.27, 0.22))
    # A compact upper-floor loft gives the staircase somewhere to lead; it
    # leaves the central/right ground-floor room open for CQB movement.
    _add_box(label + "_UpperFloor", Vector3(6.5, 0.16, 1.55), center + Vector3(0, 3.02, 1.82), Color(0.30, 0.27, 0.22))
    _build_interactive_door(label, center)

func _add_house_collider(label: String, location: Vector3, dimensions: Vector3) -> void:
    var body := StaticBody3D.new()
    body.name = label
    body.position = location
    var shape := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = dimensions
    shape.shape = box_shape
    body.add_child(shape)
    add_child(body)

func _build_interactive_door(label: String, center: Vector3) -> void:
    # Parent the moving hinge to the existing front-left wall collision body.
    # This keeps the door assembly anchored to the original house instead of
    # leaving a free-floating door at world level.
    var wall_anchor := get_node_or_null(label + "_FrontLeftCollision") as StaticBody3D
    if wall_anchor == null:
        push_error("IRON VEIL: cannot attach door to missing front wall for " + label)
        return

    var hinge := Node3D.new()
    hinge.name = label + "_InteractiveDoor"
    hinge.position = Vector3(1.645, -1.55, 0.07)
    hinge.set_meta("target_angle", 0.0)
    hinge.set_meta("is_being_held", false)
    wall_anchor.add_child(hinge)
    hinge.add_to_group("interactive_doors")

    var panel := MeshInstance3D.new()
    panel.name = "DoorPanel"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(1.16, 2.12, 0.075)
    panel.mesh = mesh
    panel.position = Vector3(0.58, 1.06, 0.0)
    panel.material_override = _material(Color(0.19, 0.125, 0.075))
    hinge.add_child(panel)

    # Raised inset panels and edge rails make the door read as a finished
    # residential door while keeping the geometry inexpensive for Quest.
    for panel_index in range(2):
        var inset := MeshInstance3D.new()
        inset.name = "RaisedInsetPanel_%d" % panel_index
        var inset_mesh := BoxMesh.new()
        inset_mesh.size = Vector3(0.78, 0.72, 0.018)
        inset.mesh = inset_mesh
        inset.position = Vector3(0.58, 0.56 + float(panel_index) * 0.91, -0.047)
        inset.material_override = _material(Color(0.27, 0.18, 0.11))
        hinge.add_child(inset)

    for rail in range(2):
        var edge := MeshInstance3D.new()
        edge.name = "DoorEdgeRail_%d" % rail
        var edge_mesh := BoxMesh.new()
        edge_mesh.size = Vector3(0.035, 2.10, 0.035)
        edge.mesh = edge_mesh
        edge.position = Vector3(0.04 + float(rail) * 1.08, 1.06, -0.045)
        edge.material_override = _material(Color(0.12, 0.085, 0.055))
        hinge.add_child(edge)

    var body := AnimatableBody3D.new()
    body.name = "DoorCollider"
    body.sync_to_physics = true
    body.position = panel.position
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = mesh.size
    collision.shape = shape
    body.add_child(collision)
    hinge.add_child(body)

    # Lever-style handle with a visible backplate, shaft and grip.
    var handle_mount := MeshInstance3D.new()
    handle_mount.name = "HandleBackplate"
    var mount_mesh := BoxMesh.new()
    mount_mesh.size = Vector3(0.085, 0.16, 0.018)
    handle_mount.mesh = mount_mesh
    handle_mount.position = Vector3(1.015, 1.02, -0.055)
    handle_mount.material_override = _material(Color(0.30, 0.27, 0.20))
    hinge.add_child(handle_mount)

    var handle := Node3D.new()
    handle.name = "DoorHandle"
    handle.position = Vector3(1.015, 1.02, -0.075)
    hinge.add_child(handle)
    var handle_shaft := MeshInstance3D.new()
    handle_shaft.name = "HandleShaft"
    var shaft_mesh := CylinderMesh.new()
    shaft_mesh.top_radius = 0.014
    shaft_mesh.bottom_radius = 0.014
    shaft_mesh.height = 0.11
    handle_shaft.mesh = shaft_mesh
    handle_shaft.rotation_degrees.z = 90.0
    handle_shaft.position = Vector3(-0.035, 0.0, -0.01)
    handle_shaft.material_override = _material(Color(0.52, 0.46, 0.31))
    handle.add_child(handle_shaft)

    var lever := MeshInstance3D.new()
    lever.name = "HandleLever"
    var lever_mesh := CapsuleMesh.new()
    lever_mesh.radius = 0.018
    lever_mesh.height = 0.16
    lever.mesh = lever_mesh
    lever.rotation_degrees.z = 90.0
    lever.position = Vector3(0.025, 0.0, -0.012)
    lever.material_override = _material(Color(0.62, 0.55, 0.38))
    handle.add_child(lever)

    interactive_doors.append(hinge)


func _controller_grip_pressed(controller: XRController3D) -> bool:
    return controller.is_button_pressed("grip") or controller.get_float("grip") > 0.55


func _update_door_interaction() -> bool:
    var right_pressed := _controller_grip_pressed(right_controller)
    var left_pressed := _controller_grip_pressed(left_controller)
    var right_edge := right_pressed and not door_right_grip_was_pressed
    var left_edge := left_pressed and not left_grip_was_pressed
    door_right_grip_was_pressed = right_pressed
    left_grip_was_pressed = left_pressed

    # Continue driving the door while the same controller holds its handle.
    if held_door != null and is_instance_valid(held_door):
        var still_pressed := _controller_grip_pressed(held_door_controller)
        if still_pressed:
            var parent := held_door.get_parent() as Node3D
            var controller_local := parent.to_local(held_door_controller.global_position)
            var hinge_local := held_door.position
            var current_vector := Vector2(controller_local.x - hinge_local.x, controller_local.z - hinge_local.z)
            if current_vector.length_squared() > 0.0001:
                var swing_delta := door_grab_start_vector.angle_to(current_vector)
                var new_angle := door_grab_start_rotation - swing_delta
                held_door.rotation.y = clampf(new_angle, deg_to_rad(-110.0), deg_to_rad(110.0))
                held_door.set_meta("target_angle", held_door.rotation.y)
            return true
        held_door.set_meta("is_being_held", false)
        held_door = null
        held_door_controller = null
        return true

    # A new grip edge can latch onto a handle only at close range.
    var controller: XRController3D = right_controller if right_edge else (left_controller if left_edge else null)
    if controller == null:
        return false

    var nearest: Node3D
    var nearest_distance := 0.24
    for door in interactive_doors:
        if not is_instance_valid(door):
            continue
        var handle := door.get_node_or_null("DoorHandle") as Node3D
        if handle == null:
            continue
        var distance := controller.global_position.distance_to(handle.global_position)
        if distance < nearest_distance:
            nearest = door
            nearest_distance = distance

    if nearest == null:
        return false

    held_door = nearest
    held_door_controller = controller
    held_door.set_meta("is_being_held", true)
    var parent := held_door.get_parent() as Node3D
    var controller_local := parent.to_local(controller.global_position)
    var hinge_local := held_door.position
    door_grab_start_vector = Vector2(controller_local.x - hinge_local.x, controller_local.z - hinge_local.z)
    door_grab_start_rotation = held_door.rotation.y
    controller.trigger_haptic_pulse("haptic", 0.65, 0.7, 0.10, 0.0)
    print("IRON VEIL: grabbed door handle on ", held_door.name)
    return true


func _animate_doors(delta: float) -> void:
    for door in interactive_doors:
        if not is_instance_valid(door) or bool(door.get_meta("is_being_held")):
            continue
        # Doors remain where the player leaves them; no artificial toggle or
        # auto-close animation fights the hand-driven hinge motion.
        var target := float(door.get_meta("target_angle"))
        door.rotation.y = lerp_angle(door.rotation.y, target, 1.0 - exp(-10.0 * delta))


func _build_parked_car(label: String, center: Vector3, body_color: Color) -> void:
    _add_box(label + "_Body", Vector3(1.8, 0.72, 3.8), center + Vector3(0, 0.72, 0), body_color)
    _add_box(label + "_Cabin", Vector3(1.55, 0.72, 1.85), center + Vector3(0, 1.36, -0.15), Color(0.12, 0.18, 0.21))
    var wheel_index := 0
    for x in [-0.92, 0.92]:
        for z in [-1.2, 1.2]:
            var wheel := MeshInstance3D.new()
            wheel.name = label + "_Wheel_%d" % wheel_index
            var cylinder := CylinderMesh.new()
            cylinder.top_radius = 0.31
            cylinder.bottom_radius = 0.31
            cylinder.height = 0.18
            wheel.mesh = cylinder
            wheel.position = center + Vector3(x, 0.38, z)
            wheel.rotation_degrees.z = 90.0
            wheel.material_override = _material(Color(0.035, 0.04, 0.04))
            add_child(wheel)
            var wheel_body := StaticBody3D.new()
            wheel_body.name = label + "_WheelCollider_%d" % wheel_index
            wheel_body.position = wheel.position
            wheel_body.rotation = wheel.rotation
            var wheel_collision := CollisionShape3D.new()
            var wheel_shape := CylinderShape3D.new()
            wheel_shape.radius = 0.31
            wheel_shape.height = 0.18
            wheel_collision.shape = wheel_shape
            wheel_body.add_child(wheel_collision)
            add_child(wheel_body)
            wheel_index += 1
    # Visual-only replacement: keep the original car and wheel colliders.
    _install_environment_model(label, center, "res://assets/models/environment/sedan.glb", Vector3.ONE)

func _build_fence_segment(label: String, x: float, z: float) -> void:
    var wood := Color(0.27, 0.19, 0.12)
    # Separate square-cut posts, rails and narrow vertical pickets replace the
    # single solid wall; the rails/posts retain simple physics colliders.
    for offset in [-2.0, 0.0, 2.0]:
        _add_box(label + "_Post", Vector3(0.14, 1.12, 0.14), Vector3(x, 0.56, z + offset), wood)
    for y in [0.28, 0.82]:
        _add_box(label + "_Rail", Vector3(0.10, 0.10, 4.0), Vector3(x, y, z), Color(0.34, 0.25, 0.17))
    for plank in range(15):
        var plank_z := z - 1.86 + float(plank) * 0.265
        _add_visual_box(label + "_Picket_%02d" % plank, Vector3(0.075, 0.88, 0.19), Vector3(x, 0.56, plank_z), wood)

func _build_hedge(label: String, center: Vector3) -> void:
    # Keep one invisible broad collider for movement while rendering a varied,
    # rounded foliage mass rather than a rectangular green block.
    var collider_visual := _add_box(label + "_CollisionVisual", Vector3(0.82, 0.98, 2.4), center + Vector3(0.0, 0.46, 0.0), Color(0.12, 0.25, 0.13))
    collider_visual.visible = false
    for row in range(2):
        for col in range(5):
            var leaf := MeshInstance3D.new()
            leaf.name = label + "_Leaf_%d_%d" % [row, col]
            var sphere := SphereMesh.new()
            sphere.radius = 0.34 + randf_range(-0.035, 0.035)
            sphere.height = sphere.radius * 2.0
            sphere.radial_segments = 12
            sphere.rings = 8
            leaf.mesh = sphere
            leaf.position = center + Vector3(randf_range(-0.12, 0.12), 0.27 + float(row) * 0.34, -0.92 + float(col) * 0.46)
            leaf.scale = Vector3(1.0, 0.82, 1.05)
            leaf.material_override = _material(Color(0.09 + randf_range(0,0.035), 0.19 + randf_range(0,0.07), 0.075))
            add_child(leaf)

func _add_round_primitive(label: String, radius: float, length: float, center: Vector3, tint: Color, axis: Vector3 = Vector3.UP) -> void:
    var visual := MeshInstance3D.new()
    visual.name = label
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius
    cylinder.height = length
    cylinder.radial_segments = 16
    visual.mesh = cylinder
    visual.position = center
    visual.material_override = _material(tint)
    visual.quaternion = Quaternion(Vector3.UP, axis.normalized())
    add_child(visual)
    var body := StaticBody3D.new()
    body.name = label + "_Collider"
    body.position = center
    var shape := CollisionShape3D.new()
    var cylinder_shape := CylinderShape3D.new()
    cylinder_shape.radius = radius
    cylinder_shape.height = length
    shape.shape = cylinder_shape
    body.quaternion = visual.quaternion
    body.add_child(shape)
    add_child(body)

func _add_streetlight(x: float, z: float) -> void:
    var pole_color := Color(0.12, 0.14, 0.14)
    var arm_x := 0.68 if x < 0 else -0.68
    _add_round_primitive("StreetlightPole", 0.055, 4.4, Vector3(x, 2.2, z), pole_color)
    _add_round_primitive("StreetlightArm", 0.045, 0.82, Vector3(x + arm_x * 0.5, 4.20, z), pole_color, Vector3(1, 0, 0))
    _add_visual_box("StreetlightLuminaireHousing", Vector3(0.34, 0.09, 0.22), Vector3(x + arm_x, 4.16, z), Color(0.20, 0.22, 0.20))
    _add_visual_box("StreetlightDiffuser", Vector3(0.27, 0.018, 0.16), Vector3(x + arm_x, 4.105, z), Color(0.88, 0.82, 0.64))

func _build_cqb_target(label: String, ground_position: Vector3, target_color: Color) -> void:
    var target := Node3D.new()
    target.name = label
    target.position = ground_position
    add_child(target)

    # Human-shaped cardboard silhouette: head, shoulders, torso and legs.
    _target_piece(target, "Torso", Vector3(0.48, 0.78, 0.10), Vector3(0, 1.25, 0), target_color)
    _target_piece(target, "Shoulders", Vector3(0.82, 0.22, 0.10), Vector3(0, 1.58, 0), target_color)
    _target_piece(target, "Head", Vector3(0.27, 0.30, 0.10), Vector3(0, 1.82, 0), target_color)
    _target_piece(target, "LegLeft", Vector3(0.20, 0.48, 0.10), Vector3(-0.13, 0.62, 0), target_color)
    _target_piece(target, "LegRight", Vector3(0.20, 0.48, 0.10), Vector3(0.13, 0.62, 0), target_color)
    _target_piece(target, "ChestScoringZone", Vector3(0.24, 0.28, 0.018), Vector3(0, 1.34, -0.061), Color(0.08, 0.08, 0.075))
    _target_piece(target, "HeadScoringZone", Vector3(0.12, 0.12, 0.018), Vector3(0, 1.82, -0.061), Color(0.08, 0.08, 0.075))

    var body := StaticBody3D.new()
    body.name = label + "_Hitbox"
    body.position = Vector3(0, 1.25, 0)
    var collision := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = Vector3(0.88, 1.9, 0.14)
    collision.shape = box_shape
    body.add_child(collision)
    target.add_child(body)

func _target_piece(parent: Node3D, label: String, dimensions: Vector3, location: Vector3, tint: Color) -> void:
    var piece := MeshInstance3D.new()
    piece.name = label
    if label == "Head":
        var head := SphereMesh.new()
        head.radius = dimensions.x * 0.5
        head.height = dimensions.y
        head.radial_segments = 16
        head.rings = 10
        piece.mesh = head
    elif label == "ChestScoringZone" or label == "HeadScoringZone":
        var scoring := BoxMesh.new()
        scoring.size = dimensions
        piece.mesh = scoring
    else:
        var body_mesh := CapsuleMesh.new()
        body_mesh.radius = dimensions.x * 0.5
        body_mesh.height = dimensions.y
        body_mesh.radial_segments = 12
        body_mesh.rings = 6
        piece.mesh = body_mesh
        piece.scale.z = dimensions.z / dimensions.x
    piece.position = location
    piece.material_override = _material(tint)
    parent.add_child(piece)

func _start_openxr() -> void:
    var xr_interface := XRServer.find_interface("OpenXR")
    if xr_interface and xr_interface.is_initialized():
        get_viewport().use_xr = true
        print("IRON VEIL: OpenXR initialized.")
    else:
        push_warning("IRON VEIL: OpenXR is not initialized. Check XR settings and launch on the headset.")

func _add_visual_box(label: String, dimensions: Vector3, location: Vector3, tint: Color) -> MeshInstance3D:
    var box := MeshInstance3D.new()
    box.name = label
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    box.mesh = mesh
    box.position = location
    box.material_override = _material(tint)
    add_child(box)
    return box

func _add_box(label: String, dimensions: Vector3, location: Vector3, tint: Color) -> MeshInstance3D:
    var box := _add_visual_box(label, dimensions, location, tint)
    # Architectural and vehicle boxes receive matching static collision.
    var body := StaticBody3D.new()
    body.name = label + "_Collider"
    body.position = location
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = dimensions
    collision.shape = shape
    body.add_child(collision)
    add_child(body)
    return box

func _setup_visual_quality() -> void:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.045, 0.043, 0.04)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.48, 0.44, 0.38)
    environment.ambient_light_energy = 0.52
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.fog_enabled = true
    environment.fog_light_color = Color(0.19, 0.18, 0.16)
    environment.fog_density = 0.0035
    var world := WorldEnvironment.new()
    world.name = "PaintThinnerWorldEnvironment"
    world.environment = environment
    add_child(world)

    # Seamless multi-scale material detail: broad mottling plus fine grain.
    # Kept small so the Quest does not need large texture assets.
    var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
    var coarse := []
    var fine := []
    for y in range(128):
        var coarse_row := []
        var fine_row := []
        for x in range(128):
            coarse_row.append(randf_range(-0.10, 0.10))
            fine_row.append(randf_range(-0.035, 0.035))
        coarse.append(coarse_row)
        fine.append(fine_row)
    for y in range(128):
        for x in range(128):
            var smooth_value := 0.0
            for oy in [-1, 0, 1]:
                for ox in [-1, 0, 1]:
                    smooth_value += float(coarse[posmod(y + oy, 128)][posmod(x + ox, 128)]) * 0.111
            var grain := float(fine[y][x])
            var value := clampf(0.88 + smooth_value * 0.65 + grain, 0.68, 1.0)
            image.set_pixel(x, y, Color(value, value, value, 1.0))
    detail_texture = ImageTexture.create_from_image(image)

func _material(tint: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = tint
    mat.albedo_texture = detail_texture
    mat.roughness = 0.9 if tint.r < 0.3 and tint.g < 0.3 else 0.78
    mat.metallic = 0.12 if tint.r < 0.18 and tint.g < 0.2 else 0.02
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    mat.uv1_scale = Vector3(3.5, 3.5, 1.0)
    return mat
