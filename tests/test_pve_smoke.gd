extends SceneTree
## Headless regression checks for the first PvE enemy and objective flow.

const ENEMY_SCRIPT = preload("res://scripts/tactical_enemy.gd")
const DIRECTOR_SCRIPT = preload("res://scripts/mission_director.gd")

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("IRON VEIL TEST FAILED: " + message)
        quit(1)
        return false
    return true

func _run() -> void:
    var world := Node3D.new()
    world.name = "TestWorld"
    root.add_child(world)

    var player := Node3D.new()
    player.name = "TestPlayerCamera"
    player.add_to_group("player_camera")
    player.position = Vector3(10.0, 0.0, 0.0)
    world.add_child(player)

    var enemy := CharacterBody3D.new()
    enemy.name = "TestEnemy"
    enemy.set_script(ENEMY_SCRIPT)
    var enemy_shape := CollisionShape3D.new()
    var enemy_capsule := CapsuleShape3D.new()
    enemy_capsule.radius = 0.3
    enemy_capsule.height = 1.7
    enemy_shape.shape = enemy_capsule
    enemy_shape.position.y = 0.85
    enemy.add_child(enemy_shape)
    world.add_child(enemy)
    enemy.set_physics_process(false)
    enemy.set("home_position", Vector3(-10.0, 0.0, 0.0))
    enemy.set_physics_process(true)

    await physics_frame
    await physics_frame
    if not _check(int(enemy.get("state")) == 3, "Enemy should stay ENGAGE when it sees the player outside its guard radius."):
        return

    var wall := StaticBody3D.new()
    wall.name = "SightBlockingWall"
    wall.position = Vector3(5.0, 1.0, 0.0)
    var wall_shape := CollisionShape3D.new()
    var wall_box := BoxShape3D.new()
    wall_box.size = Vector3(0.5, 3.0, 3.0)
    wall_shape.shape = wall_box
    wall.add_child(wall_shape)
    world.add_child(wall)
    await physics_frame
    await physics_frame
    if not _check(int(enemy.get("state")) == 1, "Enemy should investigate its last known position after losing line of sight."):
        return

    var blocked_attack_events := [0]
    enemy.connect("player_attacked", func(_damage: int) -> void:
        blocked_attack_events[0] += 1
    )
    enemy.set("attack_cooldown", 0.0)
    enemy.call("_try_attack_player")
    if not _check(blocked_attack_events[0] == 0, "An enemy must not attack through a blocking wall."):
        return
    var blocked_retry_delay := float(enemy.get("attack_cooldown"))
    if not _check(blocked_retry_delay > 0.0 and blocked_retry_delay <= 0.55, "Blocked enemy shots must set a short retry cooldown."):
        return
    enemy.call("_try_attack_player")
    if not _check(blocked_attack_events[0] == 0, "A blocked enemy shot must not repeat a raycast attempt before its retry cooldown expires."):
        return

    wall.queue_free()
    await physics_frame
    await physics_frame

    enemy.set("attack_cooldown", 0.0)
    var attack_events := [0]
    var attack_damage := [0]
    enemy.connect("player_attacked", func(damage: int) -> void:
        attack_events[0] += 1
        attack_damage[0] = damage
    )
    enemy.call("_try_attack_player")
    if not _check(attack_events[0] == 1, "An enemy with a clear line of sight should emit a player attack."):
        return
    if not _check(attack_damage[0] == 4, "Enemy attacks should deal the reduced, more survivable 4 damage."):
        return

    var squadmate := CharacterBody3D.new()
    squadmate.name = "TestSquadmate"
    squadmate.set_script(ENEMY_SCRIPT)
    squadmate.position = Vector3(0.0, 0.0, 30.0)
    world.add_child(squadmate)
    squadmate.set_physics_process(false)
    squadmate.set_physics_process(true)
    await physics_frame
    await physics_frame
    if not _check(int(squadmate.get("state")) == 1, "Squadmate should investigate a shared contact alert it cannot see directly."):
        return

    var eliminated_count := [0]
    enemy.connect("eliminated", func() -> void:
        eliminated_count[0] += 1
    )
    enemy.call("apply_hit", 3)
    if not _check(int(enemy.get("state")) == 5, "Enemy should enter DOWN when health reaches zero."):
        return
    if not _check(eliminated_count[0] == 1, "Enemy should emit eliminated exactly once."):
        return

    var director := Node.new()
    director.name = "TestMissionDirector"
    director.set_script(DIRECTOR_SCRIPT)
    world.add_child(director)
    director.call("start_operation", 1)
    director.call("_on_enemy_eliminated")
    if not _check(bool(director.get("complete")), "Mission should complete when the final hostile is eliminated."):
        return
    if not _check(int(director.get("hostiles_remaining")) == 0, "Mission hostile count should not go below zero."):
        return

    print("IRON VEIL: all headless PvE regression checks passed.")
    quit(0)
