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

func _ready() -> void:
    _start_openxr()
    _setup_visual_quality()
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
    var displacement := move_direction * move_speed * delta
    # XR origin movement is manual, so engine physics will not stop it by itself.
    # Sweep a standing capsule before moving; try each axis separately for wall sliding.
    if not _player_space_blocked(displacement):
        xr_origin.global_position += displacement
    else:
        var slide_x := Vector3(displacement.x, 0.0, 0.0)
        var slide_z := Vector3(0.0, 0.0, displacement.z)
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
    query.transform = Transform3D(Basis.IDENTITY, xr_origin.global_position + Vector3(0.0, 0.82, 0.0) + displacement)
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
    var hand := Node3D.new()
    hand.name = hand_name
    hand.position = Vector3(0.0, -0.025, -0.075)
    parent.add_child(hand)
    var skin := Color(0.39, 0.27, 0.20)
    var glove := Color(0.12, 0.14, 0.12)
    _add_hand_sphere(hand, "Palm", Vector3(0.085, 0.105, 0.035), Vector3.ZERO, skin)
    _add_hand_sphere(hand, "GloveBack", Vector3(0.075, 0.088, 0.018), Vector3(0, 0.018, -0.023), glove)
    _add_hand_capsule(hand, "Wrist", 0.033, 0.09, Vector3(0, 0, 0.09), skin)
    for i in range(4):
        var x := (float(i) - 1.5) * 0.032
        var lengths := [0.075, 0.092, 0.087, 0.068]
        var base := _add_hand_capsule(hand, "Finger_%d_Base" % i, 0.012, lengths[i], Vector3(x, -0.075, -0.008), skin)
        base.rotation_degrees.x = -12.0
        var knuckle := _add_hand_sphere(hand, "Finger_%d_Knuckle" % i, Vector3(0.014, 0.018, 0.014), Vector3(x, -0.12, -0.012), skin)
        var tip := _add_hand_capsule(hand, "Finger_%d_Tip" % i, 0.010, 0.052, Vector3(x, -0.145, -0.025), skin)
        tip.rotation_degrees.x = -38.0
    var thumb := _add_hand_capsule(hand, "Thumb", 0.014, 0.085, Vector3(0.065, -0.035, 0.02), skin)
    thumb.rotation_degrees.z = -48.0

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

func _update_weapon_grab() -> void:
    var right_grip := right_controller.is_button_pressed("grip")
    if not rifle_held and right_grip and right_controller.global_position.distance_to(rifle.global_position) < 0.65:
        rifle.reparent(right_controller, false)
        rifle.position = Vector3(0.025, -0.11, -0.22)
        rifle.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
        rifle_held = true
        print("IRON VEIL: M4 grip acquired")
    elif rifle_held and grip_was_pressed and not right_grip:
        rifle.reparent(self, true)
        rifle_held = false
        print("IRON VEIL: M4 released")
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
    var muzzle := rifle.global_position + (-rifle.global_transform.basis.z * 1.40)
    var direction := -rifle.global_transform.basis.z.normalized()
    var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + direction * shot_range)
    query.collide_with_areas = true
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        _spawn_bullet_impact(hit.position, hit.normal)
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
    _load_or_download_sound("user://iron_veil_rifle.mp3", "https://sfxmint.com/dl/impact-gunshot-08.mp3", gun_download)
    _load_or_download_sound("user://iron_veil_steps.mp3", "https://sfxmint.com/dl/footsteps-concrete-75.mp3", step_download)

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
    _add_box("GrassLot", Vector3(40, 0.18, 82), Vector3(0, -0.16, -39), Color(0.20, 0.29, 0.17))
    _add_box("AsphaltStreet", Vector3(9.0, 0.12, 82), Vector3(0, -0.045, -39), Color(0.105, 0.115, 0.12))
    _add_box("LeftSidewalk", Vector3(2.0, 0.16, 82), Vector3(-5.5, 0.0, -39), Color(0.42, 0.42, 0.39))
    _add_box("RightSidewalk", Vector3(2.0, 0.16, 82), Vector3(5.5, 0.0, -39), Color(0.42, 0.42, 0.39))
    for z in range(0, 82, 4):
        _add_box("CenterRoadDash_%d" % z, Vector3(0.12, 0.012, 1.8), Vector3(0, 0.02, -float(z) - 1.0), Color(0.78, 0.73, 0.53))

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

    # Low privacy fences, gates, hedges and street furniture make cover lanes.
    for side in [-1.0, 1.0]:
        for i in range(10):
            var zpos := -5.0 - float(i) * 7.5
            _add_box("Fence_%s_%d" % [str(side), i], Vector3(0.12, 1.05, 4.0), Vector3(side * 7.2, 0.55, zpos), Color(0.31, 0.23, 0.16))
            _add_box("Hedge_%s_%d" % [str(side), i], Vector3(1.0, 0.85, 2.4), Vector3(side * 7.8, 0.45, zpos - 2.1), Color(0.12, 0.25, 0.13))
        _add_streetlight(side * 5.0, -12.0)
        _add_streetlight(side * 5.0, -30.0)

    _build_parked_car("ParkedCar_Left_01", Vector3(-3.5, 0.0, -17.0), Color(0.22, 0.27, 0.31))
    _build_parked_car("ParkedCar_Right_01", Vector3(3.5, 0.0, -28.0), Color(0.35, 0.16, 0.12))
    _build_parked_car("ParkedCar_Left_02", Vector3(-3.5, 0.0, -48.0), Color(0.19, 0.24, 0.20))
    _build_parked_car("ParkedCar_Right_02", Vector3(3.5, 0.0, -66.0), Color(0.28, 0.20, 0.16))



func _spawn_random_house_targets(house_name: String, center: Vector3) -> void:
    # Each house receives a randomized number and arrangement of indoor CQB targets.
    var count := randi_range(1, 3)
    for n in range(count):
        var local_x := randf_range(-2.2, 2.2)
        var local_z := randf_range(-1.5, 1.45)
        var tint := Color(0.72, 0.13, 0.09) if randf() < 0.5 else Color(0.76, 0.67, 0.43)
        _build_cqb_target("%s_RandomCQB_%02d" % [house_name, n], center + Vector3(local_x, 0, local_z), tint)

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
            var wheel_body := StaticBody3D.new()
            wheel_body.name = label + "_WheelCollider"
            wheel_body.position = wheel.position
            var wheel_collision := CollisionShape3D.new()
            var wheel_shape := CylinderShape3D.new()
            wheel_shape.radius = 0.31
            wheel_shape.height = 0.18
            wheel_collision.shape = wheel_shape
            wheel_body.add_child(wheel_collision)
            add_child(wheel_body)

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
    # Every static architectural/vehicle box receives a matching physics collider.
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
    environment.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    sky.sky_material = ProceduralSkyMaterial.new()
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.ambient_light_energy = 0.7
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.fog_enabled = true
    environment.fog_light_color = Color(0.57, 0.64, 0.68)
    environment.fog_density = 0.0018
    var world := WorldEnvironment.new()
    world.name = "SuburbanWorldEnvironment"
    world.environment = environment
    add_child(world)

    # Small seamless noise tile adds subtle surface variation without large textures.
    var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
    for y in range(64):
        for x in range(64):
            var value := randf_range(0.91, 1.0)
            image.set_pixel(x, y, Color(value, value, value, 1.0))
    detail_texture = ImageTexture.create_from_image(image)

func _material(tint: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = tint
    mat.albedo_texture = detail_texture
    mat.roughness = 0.82
    mat.metallic = 0.04
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    return mat
