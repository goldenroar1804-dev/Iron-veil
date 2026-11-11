extends Node3D
## Original compact CQB interior inspired by the neglected, grimy atmosphere
## and close-quarters pacing of Blood Trail's Paint Thinner map.

const H := 3.15
const T := 0.22

func build_map(game: Node3D) -> void:
    _environment(game)
    _shell(game)
    _partitions(game)
    _dressing(game)
    game.call("_spawn_tactical_enemies")

func _material(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = 0.96
    return m

func _box(parent: Node3D, label: String, size: Vector3, pos: Vector3, tint: Color, collision := true) -> void:
    var mesh := MeshInstance3D.new()
    mesh.name = label
    var bm := BoxMesh.new()
    bm.size = size
    mesh.mesh = bm
    mesh.position = pos
    mesh.material_override = _material(tint)
    parent.add_child(mesh)
    if collision:
        var body := StaticBody3D.new()
        body.name = label + "_Collider"
        body.position = pos
        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        cs.shape = shape
        body.add_child(cs)
        parent.add_child(body)

func _wall(parent: Node3D, label: String, size: Vector3, pos: Vector3, tint := Color(0.30, 0.28, 0.25)) -> void:
    _box(parent, label, size, pos, tint, true)
    if size.y > 2.0:
        _box(parent, label + "_DampSkirting", Vector3(size.x, 0.30, size.z + 0.015), pos + Vector3(0, -1.12, 0), Color(tint.r * 0.58, tint.g * 0.56, tint.b * 0.52), false)

func _environment(game: Node3D) -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.045, 0.043, 0.04)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.48, 0.44, 0.38)
    env.ambient_light_energy = 0.52
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color(0.19, 0.18, 0.16)
    env.fog_density = 0.004
    var world := WorldEnvironment.new()
    world.name = "PaintThinner_InteriorEnvironment"
    world.environment = env
    game.add_child(world)
    var key := DirectionalLight3D.new()
    key.name = "DirtyWindowLight"
    key.rotation_degrees = Vector3(-58, 22, 0)
    key.light_energy = 0.28
    key.light_color = Color(0.72, 0.68, 0.57)
    game.add_child(key)
    for p in [Vector3(-7, 2.65, -5), Vector3(7, 2.65, -5), Vector3(0, 2.65, 6)]:
        var lamp := OmniLight3D.new()
        lamp.name = "WarmCeilingFixture"
        lamp.position = p
        lamp.light_color = Color(1.0, 0.72, 0.48)
        lamp.light_energy = 0.52
        lamp.omni_range = 8.0
        game.add_child(lamp)

func _shell(game: Node3D) -> void:
    _box(game, "PT_ConcreteFloor", Vector3(34, 0.28, 34), Vector3(0, -0.16, 0), Color(0.22, 0.21, 0.19))
    _box(game, "PT_Ceiling", Vector3(34, 0.25, 34), Vector3(0, 3.35, 0), Color(0.12, 0.12, 0.11))
    _wall(game, "PT_OuterNorth", Vector3(34, H, T), Vector3(0, H * 0.5, -17), Color(0.31, 0.29, 0.25))
    _wall(game, "PT_OuterSouth", Vector3(34, H, T), Vector3(0, H * 0.5, 17), Color(0.28, 0.27, 0.24))
    _wall(game, "PT_OuterWest", Vector3(T, H, 34), Vector3(-17, H * 0.5, 0), Color(0.27, 0.26, 0.23))
    _wall(game, "PT_OuterEast", Vector3(T, H, 34), Vector3(17, H * 0.5, 0), Color(0.30, 0.28, 0.24))
    # The south entry is deliberately broad and unobstructed.
    _wall(game, "PT_EntryLeft", Vector3(10, H, T), Vector3(-12, H * 0.5, 16))
    _wall(game, "PT_EntryRight", Vector3(10, H, T), Vector3(12, H * 0.5, 16))

func _partitions(game: Node3D) -> void:
    var plaster := Color(0.34, 0.32, 0.28)
    var dirty := Color(0.24, 0.23, 0.21)
    # Dog-legged corridors and irregular side rooms. Gaps between segments
    # are intentional doorways, never sealed by a continuous wall.
    _wall(game, "PT_Partition_A", Vector3(0.20, H, 11), Vector3(-6, H * 0.5, -8), plaster)
    _wall(game, "PT_Partition_B", Vector3(0.20, H, 8), Vector3(6, H * 0.5, -12.5), dirty)
    _wall(game, "PT_Partition_C", Vector3(11, H, 0.20), Vector3(-11.5, H * 0.5, -2), plaster)
    _wall(game, "PT_Partition_D", Vector3(9, H, 0.20), Vector3(12.5, H * 0.5, -1), dirty)
    _wall(game, "PT_Partition_E", Vector3(0.20, H, 8), Vector3(-11, H * 0.5, 8), dirty)
    _wall(game, "PT_Partition_F", Vector3(0.20, H, 7), Vector3(10, H * 0.5, 8.5), plaster)
    _wall(game, "PT_Partition_G", Vector3(8, H, 0.20), Vector3(5, H * 0.5, 4), dirty)
    _wall(game, "PT_Partition_H", Vector3(7, H, 0.20), Vector3(-6.5, H * 0.5, 11), plaster)
    _wall(game, "PT_Return_01", Vector3(3.8, H, 0.20), Vector3(-1.8, H * 0.5, -8), dirty)
    _wall(game, "PT_Return_02", Vector3(4, H, 0.20), Vector3(1.8, H * 0.5, -1), plaster)
    _wall(game, "PT_Return_03", Vector3(4, H, 0.20), Vector3(-1.5, H * 0.5, 7), dirty)
    _wall(game, "PT_Return_04", Vector3(3.6, H, 0.20), Vector3(1.8, H * 0.5, 12), plaster)
    for i in range(6):
        var x := -13.0 + float(i % 3) * 13.0
        var z := -13.0 + float(i / 3) * 25.0
        _box(game, "PT_ConcreteColumn_%02d" % i, Vector3(0.52, 3.0, 0.52), Vector3(x, 1.5, z), Color(0.23, 0.22, 0.20))

func _dressing(game: Node3D) -> void:
    var r := RandomNumberGenerator.new()
    r.randomize()
    for i in range(32):
        var x := r.randf_range(-15.5, 15.5)
        var z := r.randf_range(-15.5, 15.5)
        _box(game, "PT_FloorScuff_%02d" % i, Vector3(r.randf_range(0.25, 1.4), 0.012, r.randf_range(0.18, 0.9)), Vector3(x, 0.002, z), Color(0.16, 0.15, 0.14), false)
    # Thin painted marks read as crude graffiti from normal VR viewing distance.
    for i in range(22):
        var side := -16.82 if i % 2 == 0 else 16.82
        var mark := MeshInstance3D.new()
        mark.name = "PT_Graffiti_%02d" % i
        var bm := BoxMesh.new()
        bm.size = Vector3(0.018, r.randf_range(0.12, 0.62), r.randf_range(0.04, 0.16))
        mark.mesh = bm
        mark.position = Vector3(side, r.randf_range(0.7, 2.5), -13.5 + float(i) * 1.2)
        mark.rotation_degrees.x = r.randf_range(-18, 18)
        mark.material_override = _material(Color(0.38, 0.18, 0.13) if i % 3 == 0 else Color(0.19, 0.26, 0.22))
        game.add_child(mark)
    # Damaged counters, lockers and overturned furniture provide hard cover.
    _box(game, "PT_BrokenCounter_A", Vector3(2.6, 0.92, 0.62), Vector3(-11.5, 0.46, -8), Color(0.19, 0.16, 0.13))
    _box(game, "PT_BrokenCounter_B", Vector3(2.0, 0.78, 0.58), Vector3(10.5, 0.39, -8), Color(0.21, 0.18, 0.15))
    _box(game, "PT_OverturnedTable", Vector3(2.0, 0.35, 1.1), Vector3(1.5, 0.32, 9.5), Color(0.18, 0.15, 0.12))
    _box(game, "PT_LockerBank", Vector3(0.65, 1.85, 2.8), Vector3(14.8, 0.93, 2), Color(0.16, 0.19, 0.18))
    for i in range(18):
        var debris := MeshInstance3D.new()
        debris.name = "PT_Debris_%02d" % i
        var dm := BoxMesh.new()
        dm.size = Vector3(r.randf_range(0.12, 0.42), r.randf_range(0.04, 0.12), r.randf_range(0.12, 0.34))
        debris.mesh = dm
        debris.position = Vector3(r.randf_range(-15, 15), 0.06, r.randf_range(-15, 15))
        debris.rotation.y = r.randf_range(-PI, PI)
        debris.material_override = _material(Color(0.20, 0.18, 0.15))
        game.add_child(debris)
