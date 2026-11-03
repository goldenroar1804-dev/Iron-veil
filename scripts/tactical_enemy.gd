extends CharacterBody3D
## Lightweight ground-based PvE opponent for the Quest training block.
## Uses a small state machine and physics queries; no NavigationServer dependency.

enum BrainState { GUARD, INVESTIGATE, SEARCH, ENGAGE, RETREAT, DOWN }
@export var move_speed := 1.15
@export var health := 3
@export var guard_radius := 9.0
@export var hearing_radius := 24.0

var target: Node3D
var state: BrainState = BrainState.GUARD
var home_position := Vector3.ZERO
var last_known_position := Vector3.ZERO
var investigate_timer := 0.0
var search_timer := 0.0
var decision_timer := 0.0
var strafe_sign := 1.0
var body_mesh: MeshInstance3D
var head_mesh: MeshInstance3D

func _ready() -> void:
    home_position = global_position
    add_to_group("tactical_enemies")
    target = get_tree().get_first_node_in_group("player_camera") as Node3D
    decision_timer = randf_range(0.5, 1.5)
    strafe_sign = -1.0 if randf() < 0.5 else 1.0

func notify_sound(sound_position: Vector3) -> void:
    if state == BrainState.DOWN:
        return
    if global_position.distance_to(sound_position) <= hearing_radius:
        last_known_position = sound_position
        investigate_timer = 5.0
        state = BrainState.INVESTIGATE

func apply_hit(damage: int) -> void:
    if state == BrainState.DOWN:
        return
    health -= damage
    if health <= 0:
        state = BrainState.DOWN
        velocity = Vector3.ZERO
        collision_layer = 0
        collision_mask = 0
        if body_mesh:
            body_mesh.rotation_degrees.z = 82.0
            body_mesh.position.y = 0.55
        if head_mesh:
            head_mesh.visible = false

func _physics_process(delta: float) -> void:
    if state == BrainState.DOWN:
        return
    if target == null or not is_instance_valid(target):
        target = get_tree().get_first_node_in_group("player_camera") as Node3D
    if target == null:
        return

    var to_player := target.global_position - global_position
    var distance := to_player.length()
    var can_see := distance < 22.0 and _has_line_of_sight(target.global_position)

    if can_see:
        last_known_position = target.global_position
        if distance < 2.8:
            state = BrainState.RETREAT
        elif distance < 15.0:
            state = BrainState.ENGAGE
        else:
            state = BrainState.GUARD
    elif state == BrainState.INVESTIGATE:
        investigate_timer = maxf(0.0, investigate_timer - delta)
        if global_position.distance_to(last_known_position) < 1.0 or investigate_timer <= 0.0:
            state = BrainState.SEARCH
            search_timer = 3.5
    elif state == BrainState.SEARCH:
        search_timer = maxf(0.0, search_timer - delta)
        decision_timer -= delta
        if decision_timer <= 0.0:
            strafe_sign *= -1.0
            decision_timer = randf_range(0.7, 1.4)
        if search_timer <= 0.0:
            state = BrainState.GUARD
    else:
        if global_position.distance_to(home_position) > guard_radius:
            state = BrainState.GUARD

    var desired := Vector3.ZERO
    match state:
        BrainState.INVESTIGATE:
            desired = last_known_position - global_position
        BrainState.SEARCH:
            desired = Vector3(strafe_sign, 0.0, -0.25)
        BrainState.ENGAGE:
            var away := -to_player.normalized()
            var side := Vector3.UP.cross(away).normalized() * strafe_sign
            desired = side * 0.8
            if distance > 8.0:
                desired += to_player.normalized() * 0.45
        BrainState.RETREAT:
            desired = -to_player.normalized()
        BrainState.GUARD:
            desired = home_position - global_position
        _:
            desired = Vector3.ZERO

    desired.y = 0.0
    if desired.length_squared() > 0.001:
        desired = desired.normalized()
        velocity.x = desired.x * move_speed
        velocity.z = desired.z * move_speed
        if state == BrainState.ENGAGE or state == BrainState.RETREAT:
            look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)
        elif desired.length_squared() > 0.1:
            look_at(global_position + desired, Vector3.UP)
    else:
        velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, move_speed * 4.0 * delta)

    if not is_on_floor():
        velocity.y -= 9.8 * delta
    else:
        velocity.y = -0.05
    move_and_slide()

func _has_line_of_sight(point: Vector3) -> bool:
    var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.35, point)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    return hit.is_empty() or (hit.collider is Node3D and hit.collider == target)
