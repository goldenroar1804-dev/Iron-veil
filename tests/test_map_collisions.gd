extends SceneTree
## Runtime audit for the hand-authored suburban map collision layout.

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("IRON VEIL COLLISION TEST FAILED: " + message)
        quit(1)
        return false
    return true

func _run() -> void:
    var packed := load("res://scenes/main.tscn") as PackedScene
    if not _check(packed != null, "Main scene must load."):
        return
    var game := packed.instantiate()
    root.add_child(game)
    await process_frame
    await physics_frame

    for car in ["ParkedCar_Left_01", "ParkedCar_Right_01", "ParkedCar_Left_02", "ParkedCar_Right_02"]:
        for wheel in range(4):
            var collider := game.get_node_or_null(car + "_WheelCollider_%d" % wheel) as StaticBody3D
            if not _check(collider != null, car + " wheel collider %d must exist." % wheel):
                return
            if not _check(is_equal_approx(collider.rotation.z, deg_to_rad(90.0)), car + " wheel collider must match the horizontal wheel mesh orientation."):
                return

    for house in range(8):
        var prefix := "House_%02d" % house
        for part in ["FloorCollision", "BackCollision", "LeftCollision", "RightCollision", "FrontLeftCollision", "FrontRightCollision", "HeaderCollision"]:
            if not _check(game.get_node_or_null(prefix + "_" + part) is StaticBody3D, prefix + " is missing " + part + "."):
                return
        for step in range(10):
            if not _check(game.get_node_or_null(prefix + "_Stair_%02d_Collider" % step) is StaticBody3D, prefix + " stair %d must have a collider." % step):
                return
        if not _check(game.get_node_or_null(prefix + "_UpperLanding_Collider") is StaticBody3D, prefix + " upper landing must have a collider."):
            return
        if not _check(game.get_node_or_null(prefix + "_UpperFloor_Collider") is StaticBody3D, prefix + " upper floor must have a collider."):
            return
        var door := game.find_child(prefix + "_InteractiveDoor", true, false) as Node3D
        if not _check(door != null, prefix + " interactive door must exist."):
            return
        if not _check(door.get_parent() is StaticBody3D, prefix + " door hinge must be attached to the original front-wall collider."):
            return
        if not _check(door.get_node_or_null("DoorHandle/HandleLever") is MeshInstance3D, prefix + " door must have a grabbable lever handle."):
            return
        var door_body := door.get_node_or_null("DoorCollider") as AnimatableBody3D
        if not _check(door_body != null, prefix + " interactive door must have a physics body."):
            return
        var door_has_shape := false
        for child in door_body.get_children():
            if child is CollisionShape3D and child.shape != null:
                door_has_shape = true
        if not _check(door_has_shape, prefix + " interactive door must have a collision shape."):
            return

    for side in ["-1.0", "1.0"]:
        for segment in range(3):
            var fence := "Fence_%s_%d" % [side, segment]
            if not _check(game.get_node_or_null(fence + "_Post_Collider") is StaticBody3D, fence + " posts need collision."):
                return
            if not _check(game.get_node_or_null(fence + "_Rail_Collider") is StaticBody3D, fence + " rails need collision."):
                return
            var hedge := "Hedge_%s_%d_CollisionVisual_Collider" % [side, segment]
            if not _check(game.get_node_or_null(hedge) is StaticBody3D, "Hedge collision volume is missing: " + hedge):
                return

    var origin := game.get_node("XROrigin3D") as XROrigin3D
    origin.global_position = Vector3(-11.0, 0.0, -12.65)
    if not _check(bool(game.call("_player_space_blocked", Vector3(0.0, 0.0, -0.02))), "Player collision query must detect the front house wall."):
        return

    print("IRON VEIL: all suburban map collider and attached-door audits passed.")
    quit(0)
