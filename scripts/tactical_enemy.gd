extends CharacterBody3D
## Lightweight ground-based PvE opponent for the Quest training block.
## Uses a small state machine and physics queries; no NavigationServer dependency.

enum BrainState { GUARD, INVESTIGATE, SEARCH, ENGAGE, RETREAT, DOWN }
signal eliminated
@export var move_speed := 1.15
@export var health := 3
@export var guard_radius := 9.0
@export var hearing_radius := 24.0

var target: Node3D
var aggression := 0.65
var cover_position := Vector3.ZERO
var cover_refresh := 0.0
static var shared_alert_position := Vector3.ZERO
static var shared_alert_revision := 0
var seen_alert_revision := 0
var has_reported_contact := false
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
        eliminated.emit()

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
        if not has_reported_contact:
            shared_alert_position = target.global_position
            shared_alert_revision += 1
            has_reported_contact = true
        if distance < 2.8:
            state = BrainState.RETREAT
        elif distance < 15.0:
            state = BrainState.ENGAGE
        else:
            state = BrainState.GUARD
    else:
        has_reported_contact = false
    if not can_see and seen_alert_revision != shared_alert_revision:
        seen_alert_revision = shared_alert_revision
        last_known_position = shared_alert_position
        investigate_timer = 4.0
        state = BrainState.INVESTIGATE
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
            cover_refresh = maxf(0.0, cover_refresh - delta)
            if cover_refresh <= 0.0:
                cover_position = _find_nearby_cover(target.global_position)
                cover_refresh = randf_range(2.0, 3.5)
            if cover_position != Vector3.ZERO and global_position.distance_to(cover_position) > 0.65:
                desired = cover_position - global_position
            else:
                var away := -to_player.normalized()
                var side := Vector3.UP.cross(away).normalized() * strafe_sign
                desired = side * (0.35 + aggression * 0.75)
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


func _find_nearby_cover(player_position: Vector3) -> Vector3:
    var best := Vector3.ZERO
    var best_score := -INF
    for i in range(8):
        var angle := TAU * float(i) / 8.0
        var candidate := global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.7
        var from_point := candidate + Vector3.UP * 1.25
        var query := PhysicsRayQueryParameters3D.create(from_point, player_position)
        query.exclude = [get_rid()]
        var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
        if obstruction.is_empty():
            continue
        var clearance := PhysicsShapeQueryParameters3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.28
        capsule.height = 1.6
        clearance.shape = capsule
        clearance.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * 0.8)
        clearance.exclude = [get_rid()]
        var blocked := get_world_3d().direct_space_state.intersect_shape(clearance, 4)
        if not blocked.is_empty():
            continue
        var score := -candidate.distance_to(global_position) - absf(candidate.distance_to(player_position) - 5.0) * 0.1
        if score > best_score:
            best_score = score
            best = candidate
    return best

func _has_line_of_sight(point: Vector3) -> bool:
    var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.35, point)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    return hit.is_empty() or (hit.collider is Node3D and hit.collider == target)
