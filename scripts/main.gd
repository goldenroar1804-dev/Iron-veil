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

func _ready() -> void:
    _start_openxr()
    _build_suburban_block()
    _build_hands()
    _build_rifle()
    _build_audio()

func _process(delta: float) -> void:
    if not _xr_is_active():
        return
    _update_smooth_movement(delta)
    _update_smooth_turn(delta)
    _update_weapon_grab()
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
    xr_origin.global_position += move_direction * move_speed * delta

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
    # The support hand follows the left controller. The firing hand is modeled
    # around the rifle grip so it remains visually wrapped around the weapon.
    _make_gloved_hand(left_controller, Vector3(0.0, -0.035, -0.10), false)

func _make_gloved_hand(parent: Node3D, hand_offset: Vector3, is_gripping: bool) -> void:
    var hand := Node3D.new()
    hand.name = "GlovedHand"
    hand.position = hand_offset
    parent.add_child(hand)
    var glove := Color(0.12, 0.14, 0.13)
    var cuff := Color(0.20, 0.22, 0.19)
    _add_hand_piece(hand, "Palm", Vector3(0.105, 0.12, 0.045), Vector3(0, 0, 0), glove)
    _add_hand_piece(hand, "WristCuff", Vector3(0.09, 0.065, 0.07), Vector3(0, -0.085, 0.015), cuff)
    # Four fingers, each made from two rounded-looking glove segments.
    for i in range(4):
        var x := (float(i) - 1.5) * 0.025
        var length := 0.075 if i == 1 or i == 2 else 0.065
        _add_hand_piece(hand, "Finger_%d_A" % i, Vector3(0.021, length, 0.024), Vector3(x, 0.085, -0.005), glove)
        _add_hand_piece(hand, "Finger_%d_B" % i, Vector3(0.019, length * 0.72, 0.022), Vector3(x, 0.085 + length * 0.78, -0.005), glove)
    var thumb := _add_hand_piece(hand, "Thumb", Vector3(0.027, 0.085, 0.027), Vector3(0.067, 0.025, -0.005), glove)
    thumb.rotation_degrees.z = -38.0

func _add_hand_piece(parent: Node3D, label: String, dimensions: Vector3, location: Vector3, tint: Color) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = label
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    part.mesh = mesh
    part.position = location
    part.material_override = _material(tint)
    parent.add_child(part)
    return part

func _build_rifle() -> void:
    rifle = Node3D.new()
    rifle.name = "Detailed_VR_Carbine"
    # Local forward is -Z. This offset puts the stock near the right shoulder.
    rifle.position = Vector3(0.025, -0.11, -0.22)
    rifle.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
    add_child(rifle)
    var forward := -xr_camera.global_transform.basis.z
    forward.y = 0.0
    rifle.global_position = xr_camera.global_position + forward.normalized() * 0.85 + Vector3(0, -0.55, 0)
    rifle.global_rotation = xr_camera.global_rotation

    var dark := Color(0.075, 0.085, 0.08)
    var polymer := Color(0.13, 0.15, 0.13)
    var metal := Color(0.22, 0.24, 0.22)
    var glass := Color(0.035, 0.07, 0.055)

    # Receiver, upper/lower split, handguard, barrel and muzzle.
    _add_weapon_box(rifle, "UpperReceiver", Vector3(0.105, 0.105, 0.34), Vector3(0, 0, -0.17), metal)
    _add_weapon_box(rifle, "LowerReceiver", Vector3(0.105, 0.105, 0.25), Vector3(0, -0.095, -0.15), polymer)
    _add_weapon_box(rifle, "Handguard", Vector3(0.095, 0.105, 0.34), Vector3(0, 0.005, -0.49), polymer)
    _add_weapon_cylinder(rifle, "Barrel", 0.018, 0.54, Vector3(0, 0.012, -0.83), dark)
    _add_weapon_cylinder(rifle, "MuzzleDevice", 0.026, 0.075, Vector3(0, 0.012, -1.12), metal)
    _add_weapon_box(rifle, "Stock", Vector3(0.085, 0.12, 0.30), Vector3(0, -0.015, 0.22), polymer)
    _add_weapon_box(rifle, "ButtPad", Vector3(0.095, 0.14, 0.035), Vector3(0, -0.015, 0.37), dark)
    _add_weapon_box(rifle, "PistolGrip", Vector3(0.065, 0.17, 0.085), Vector3(0, -0.19, -0.09), dark)
    _add_weapon_box(rifle, "Magazine", Vector3(0.075, 0.24, 0.105), Vector3(0, -0.22, -0.20), dark)
    _add_weapon_box(rifle, "MagazineBase", Vector3(0.082, 0.025, 0.11), Vector3(0, -0.35, -0.20), metal)

    # Top rail, optic, backup sights and side accessory.
    _add_weapon_box(rifle, "TopRail", Vector3(0.045, 0.025, 0.62), Vector3(0, 0.075, -0.40), dark)
    _add_weapon_box(rifle, "OpticBody", Vector3(0.085, 0.085, 0.14), Vector3(0, 0.15, -0.27), dark)
    _add_weapon_box(rifle, "OpticLens", Vector3(0.07, 0.065, 0.008), Vector3(0, 0.15, -0.345), glass)
    _add_weapon_box(rifle, "FrontSight", Vector3(0.025, 0.075, 0.035), Vector3(0, 0.13, -0.68), metal)
    _add_weapon_box(rifle, "SideRail", Vector3(0.025, 0.035, 0.25), Vector3(0.058, 0.0, -0.52), dark)
    _add_weapon_box(rifle, "Flashlight", Vector3(0.045, 0.055, 0.13), Vector3(0.09, -0.015, -0.60), metal)
    _add_weapon_box(rifle, "TriggerGuard", Vector3(0.075, 0.018, 0.09), Vector3(0, -0.16, -0.09), metal)

    # The right glove is attached to the rifle grip; the left glove tracks its controller.
    var right_hand := Node3D.new()
    right_hand.name = "RightGripHand"
    right_hand.position = Vector3(0.0, -0.19, -0.055)
    rifle.add_child(right_hand)
    _make_gloved_hand(right_hand, Vector3.ZERO, true)
    # Support-hand model sits farther forward along the handguard.
    var support_hand := Node3D.new()
    support_hand.name = "SupportHandOnHandguard"
    support_hand.position = Vector3(0.0, -0.035, -0.55)
    rifle.add_child(support_hand)
    _add_hand_piece(support_hand, "SupportPalm", Vector3(0.11, 0.105, 0.13), Vector3(0, 0, 0), Color(0.12, 0.14, 0.13))
    for i in range(4):
        var finger_x := (float(i) - 1.5) * 0.025
        _add_hand_piece(support_hand, "SupportFinger_%d" % i, Vector3(0.02, 0.025, 0.10), Vector3(finger_x, -0.025, -0.105), Color(0.12, 0.14, 0.13))

    muzzle_flash = MeshInstance3D.new()
    muzzle_flash.name = "MuzzleFlash"
    var flash_mesh := SphereMesh.new()
    flash_mesh.radius = 0.075
    flash_mesh.height = 0.15
    muzzle_flash.mesh = flash_mesh
    muzzle_flash.position = Vector3(0, 0.012, -1.22)
    muzzle_flash.material_override = _material(Color(1.0, 0.58, 0.12))
    muzzle_flash.visible = false
    rifle.add_child(muzzle_flash)
    muzzle_light = OmniLight3D.new()
    muzzle_light.light_color = Color(1.0, 0.55, 0.18)
    muzzle_light.light_energy = 0.0
    muzzle_light.omni_range = 4.0
    muzzle_light.position = muzzle_flash.position
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
    part.mesh = mesh
    part.position = location
    part.rotation_degrees.x = 90.0
    part.material_override = _material(tint)
    parent.add_child(part)

func _update_weapon_grab() -> void:
    var right_grip := right_controller.is_button_pressed("grip")
    var any_grip := right_grip or left_controller.is_button_pressed("grip")
    if not rifle_held and any_grip and right_controller.global_position.distance_to(rifle.global_position) < 1.0:
        rifle.reparent(right_controller, true)
        rifle.position = Vector3(0.025, -0.11, -0.22)
        rifle.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
        rifle_held = true
        print("IRON VEIL: rifle picked up")
    elif rifle_held and grip_was_pressed and not right_grip:
        rifle.reparent(self, true)
        rifle_held = false
        print("IRON VEIL: rifle dropped")
    grip_was_pressed = right_grip

func _update_firing() -> void:
    var pressed := right_controller.is_button_pressed("trigger")
    if rifle_held and pressed and not trigger_was_pressed and fire_cooldown <= 0.0:
        _fire_rifle()
        fire_cooldown = fire_interval
    trigger_was_pressed = pressed

func _fire_rifle() -> void:
    if rifle == null or not rifle_held:
        return
    muzzle_flash.visible = true
    muzzle_light.light_energy = 3.5
    get_tree().create_timer(0.06).timeout.connect(func():
        if is_instance_valid(muzzle_flash):
            muzzle_flash.visible = false
            muzzle_light.light_energy = 0.0
    )
    gun_audio.global_position = rifle.global_position
    gun_audio.play()
    var muzzle := rifle.global_position + (-rifle.global_transform.basis.z * 1.18)
    var direction := -rifle.global_transform.basis.z.normalized()
    var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + direction * shot_range)
    query.collide_with_areas = true
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        _spawn_bullet_impact(hit.position, hit.normal)
        print("IRON VEIL: hit ", hit.collider.name)

func _build_audio() -> void:
    gun_audio = AudioStreamPlayer3D.new()
    gun_audio.name = "GunshotAudio"
    gun_audio.stream = _make_audio_stream(true)
    gun_audio.volume_db = -4.0
    gun_audio.max_distance = 45.0
    add_child(gun_audio)
    footstep_audio = AudioStreamPlayer3D.new()
    footstep_audio.name = "FootstepAudio"
    footstep_audio.stream = _make_audio_stream(false)
    footstep_audio.volume_db = -8.0
    footstep_audio.max_distance = 12.0
    add_child(footstep_audio)

func _make_audio_stream(gunshot: bool) -> AudioStreamWAV:
    var rate := 22050
    var frames := int(rate * (0.32 if gunshot else 0.15))
    var pcm := PackedByteArray()
    pcm.resize(frames * 2)
    for i in range(frames):
        var t := float(i) / float(rate)
        var envelope := exp(-t * (10.0 if gunshot else 25.0))
        var wave := (randf_range(-1.0, 1.0) * 0.75 + sin(t * TAU * 75.0) * 0.25) * envelope
        if not gunshot:
            wave = (sin(t * TAU * 90.0) * 0.7 + randf_range(-1.0, 1.0) * 0.3) * envelope
        pcm.encode_s16(i * 2, int(clampf(wave, -1.0, 1.0) * 26000.0))
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = rate
    stream.stereo = false
    stream.data = pcm
    return stream

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
    _add_box("GrassLot", Vector3(34, 0.18, 42), Vector3(0, -0.16, -16), Color(0.20, 0.29, 0.17))
    _add_box("AsphaltStreet", Vector3(9.0, 0.12, 42), Vector3(0, -0.045, -16), Color(0.105, 0.115, 0.12))
    _add_box("LeftSidewalk", Vector3(2.0, 0.16, 42), Vector3(-5.5, 0.0, -16), Color(0.42, 0.42, 0.39))
    _add_box("RightSidewalk", Vector3(2.0, 0.16, 42), Vector3(5.5, 0.0, -16), Color(0.42, 0.42, 0.39))
    for z in range(0, 42, 4):
        _add_box("CenterRoadDash_%d" % z, Vector3(0.12, 0.012, 1.8), Vector3(0, 0.02, -float(z) - 1.0), Color(0.78, 0.73, 0.53))

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -28, 0)
    sun.light_energy = 1.15
    add_child(sun)

    # Simple low-poly houses on both sides of the street.
    _build_house("House_Left_Front", Vector3(-10.0, 0.0, -9.0), Color(0.66, 0.57, 0.45))
    _build_house("House_Right_Front", Vector3(10.0, 0.0, -15.0), Color(0.55, 0.61, 0.63))
    _build_house("House_Left_Back", Vector3(-10.0, 0.0, -29.0), Color(0.62, 0.63, 0.54))
    _build_house("House_Right_Back", Vector3(10.0, 0.0, -34.0), Color(0.67, 0.55, 0.52))

    # Low privacy fences, gates, hedges and street furniture make cover lanes.
    for side in [-1.0, 1.0]:
        for i in range(5):
            var zpos := -5.0 - float(i) * 6.0
            _add_box("Fence_%s_%d" % [str(side), i], Vector3(0.12, 1.05, 4.0), Vector3(side * 7.2, 0.55, zpos), Color(0.31, 0.23, 0.16))
            _add_box("Hedge_%s_%d" % [str(side), i], Vector3(1.0, 0.85, 2.4), Vector3(side * 7.8, 0.45, zpos - 2.1), Color(0.12, 0.25, 0.13))
        _add_streetlight(side * 5.0, -12.0)
        _add_streetlight(side * 5.0, -30.0)

    _build_parked_car("ParkedCar_Left", Vector3(-3.5, 0.0, -17.0), Color(0.22, 0.27, 0.31))
    _build_parked_car("ParkedCar_Right", Vector3(3.5, 0.0, -28.0), Color(0.35, 0.16, 0.12))

    # CQB silhouette targets in staggered lanes, with separate physics hitboxes.
    _build_cqb_target("CQB_Target_01", Vector3(-1.6, 0.0, -9.0), Color(0.72, 0.13, 0.09))
    _build_cqb_target("CQB_Target_02", Vector3(1.7, 0.0, -13.0), Color(0.76, 0.67, 0.43))
    _build_cqb_target("CQB_Target_03", Vector3(-2.0, 0.0, -23.0), Color(0.72, 0.13, 0.09))
    _build_cqb_target("CQB_Target_04", Vector3(2.0, 0.0, -36.0), Color(0.76, 0.67, 0.43))

func _build_house(label: String, center: Vector3, wall_color: Color) -> void:
    # Enterable shell with a doorway opening and a walkable interior floor.
    _add_box(label + "_InteriorFloor", Vector3(6.7, 0.12, 5.2), center + Vector3(0, 0.02, 0), Color(0.34, 0.31, 0.26))
    _add_box(label + "_BackWall", Vector3(7.0, 3.1, 0.18), center + Vector3(0, 1.55, 2.66), wall_color)
    _add_box(label + "_LeftWall", Vector3(0.18, 3.1, 5.5), center + Vector3(-3.41, 1.55, 0), wall_color)
    _add_box(label + "_RightWall", Vector3(0.18, 3.1, 5.5), center + Vector3(3.41, 1.55, 0), wall_color)
    _add_box(label + "_FrontWallLeft", Vector3(2.8, 3.1, 0.18), center + Vector3(-2.1, 1.55, -2.66), wall_color)
    _add_box(label + "_FrontWallRight", Vector3(2.8, 3.1, 0.18), center + Vector3(2.1, 1.55, -2.66), wall_color)
    _add_box(label + "_DoorHeader", Vector3(1.4, 0.65, 0.18), center + Vector3(0, 2.78, -2.66), wall_color)
    _add_box(label + "_Roof", Vector3(7.7, 0.35, 6.2), center + Vector3(0, 3.25, 0), Color(0.20, 0.18, 0.16))
    _add_box(label + "_WindowA", Vector3(1.25, 1.0, 0.07), center + Vector3(-1.6, 1.9, -2.81), Color(0.12, 0.22, 0.27))
    _add_box(label + "_WindowB", Vector3(1.25, 1.0, 0.07), center + Vector3(0.0, 1.9, -2.81), Color(0.12, 0.22, 0.27))
    _add_box(label + "_WindowTrimA", Vector3(1.38, 0.08, 0.09), center + Vector3(-1.6, 2.43, -2.83), Color(0.82, 0.79, 0.68))
    _add_box(label + "_WindowTrimB", Vector3(1.38, 0.08, 0.09), center + Vector3(0.0, 2.43, -2.83), Color(0.82, 0.79, 0.68))

func _build_parked_car(label: String, center: Vector3, body_color: Color) -> void:
    _add_box(label + "_Body", Vector3(1.8, 0.72, 3.8), center + Vector3(0, 0.72, 0), body_color)
    _add_box(label + "_Cabin", Vector3(1.55, 0.72, 1.85), center + Vector3(0, 1.36, -0.15), Color(0.12, 0.18, 0.21))
    for x in [-0.92, 0.92]:
        for z in [-1.2, 1.2]:
            var wheel := MeshInstance3D.new()
            wheel.name = label + "_Wheel"
            var cylinder := CylinderMesh.new()
            cylinder.top_radius = 0.31
            cylinder.bottom_radius = 0.31
            cylinder.height = 0.18
            wheel.mesh = cylinder
            wheel.position = center + Vector3(x, 0.38, z)
            wheel.rotation_degrees.z = 90.0
            wheel.material_override = _material(Color(0.035, 0.04, 0.04))
            add_child(wheel)

func _add_streetlight(x: float, z: float) -> void:
    _add_box("StreetlightPole", Vector3(0.10, 4.4, 0.10), Vector3(x, 2.2, z), Color(0.16, 0.17, 0.16))
    _add_box("StreetlightArm", Vector3(0.75, 0.08, 0.08), Vector3(x + (0.32 if x < 0 else -0.32), 4.25, z), Color(0.16, 0.17, 0.16))
    _add_box("StreetlightHead", Vector3(0.30, 0.10, 0.20), Vector3(x + (0.68 if x < 0 else -0.68), 4.18, z), Color(0.78, 0.72, 0.53))

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
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    piece.mesh = mesh
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

func _add_box(label: String, dimensions: Vector3, location: Vector3, tint: Color) -> MeshInstance3D:
    var box := MeshInstance3D.new()
    box.name = label
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    box.mesh = mesh
    box.position = location
    box.material_override = _material(tint)
    add_child(box)
    return box

func _material(tint: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = tint
    mat.roughness = 0.9
    return mat
