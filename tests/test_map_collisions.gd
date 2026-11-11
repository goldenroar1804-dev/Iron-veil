extends SceneTree
## Runtime audit for the Paint Thinner-inspired CQB interior.

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("IRON VEIL CQB MAP TEST FAILED: " + message)
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
    var map_root := game.get_node_or_null("CompactPaintThinnerCQB") as Node3D
    if not _check(map_root != null, "Compact scaled CQB map root must exist."):
        return
    if not _check(is_equal_approx(map_root.scale.x, 0.68) and is_equal_approx(map_root.scale.z, 0.68), "CQB footprint must be reduced to 68 percent horizontally."):
        return
    for name in ["PT_ConcreteFloor_Collider", "PT_OuterNorth_Collider", "PT_OuterSouth_Collider", "PT_OuterWest_Collider", "PT_OuterEast_Collider"]:
        if not _check(map_root.get_node_or_null(name) is StaticBody3D, name + " must have static collision."):
            return
    for name in ["PT_Partition_A_Collider", "PT_Partition_B_Collider", "PT_Partition_C_Collider", "PT_Partition_D_Collider", "PT_Partition_E_Collider", "PT_Partition_F_Collider", "PT_Partition_G_Collider", "PT_Partition_H_Collider"]:
        if not _check(map_root.get_node_or_null(name) is StaticBody3D, name + " must have static collision."):
            return
    for name in ["PT_BrokenCounter_A_Collider", "PT_BrokenCounter_B_Collider", "PT_OverturnedTable_Collider", "PT_LockerBank_Collider"]:
        if not _check(map_root.get_node_or_null(name) is StaticBody3D, name + " must provide hard cover collision."):
            return
    var hud := game.get_node_or_null("XROrigin3D/XRCamera3D/TacticalStatusHUD") as Label3D
    if not _check(hud != null and hud.text.contains("AMMO"), "The in-headset tactical HUD must be present and show ammunition."):
        return
    if not _check(int(game.get("player_health")) == 100, "Player health must start at 100."):
        return
    var glock_display := game.get_node_or_null("Glock17_Display") as Node3D
    if ResourceLoader.exists("res://assets/models/weapons/glock17.glb"):
        if not _check(glock_display != null and glock_display.get_node_or_null("ImportedGlock17") != null, "Installed Glock asset must appear on the weapon pickup stand."):
            return
    var rifle := game.get_node_or_null("M4A1_Carbine") as RigidBody3D
    if not _check(rifle != null, "The M4 must be a physical rigid body."):
        return
    if not _check(rifle.get_node_or_null("RiflePhysicsCollider") is CollisionShape3D, "The M4 must have a collision shape for dropping and floor impacts."):
        return
    var gun_audio := game.get_node_or_null("GunshotAudio") as AudioStreamPlayer3D
    var step_audio := game.get_node_or_null("FootstepAudio") as AudioStreamPlayer3D
    if not _check(gun_audio != null and gun_audio.stream != null, "Gunshot audio must be available offline."):
        return
    if not _check(step_audio != null and step_audio.stream != null, "Footstep audio must be available offline."):
        return
    var left_hand := game.get_node_or_null("XROrigin3D/LeftController/LeftHumanHand") as Node3D
    var right_hand := game.get_node_or_null("XROrigin3D/RightController/RightHumanHand") as Node3D
    if not _check(left_hand != null and right_hand != null, "Both VR hands must be present."):
        return
    if not _check(is_equal_approx(left_hand.rotation.z, deg_to_rad(-90.0)) and is_equal_approx(right_hand.rotation.z, deg_to_rad(90.0)), "Palm normals must face inward toward one another."):
        return
    for enemy in range(4):
        var npc := game.get_node_or_null("PvE_OpFor_%02d" % enemy) as CharacterBody3D
        if not _check(npc != null, "All four CQB enemies must spawn inside the map."):
            return
        var humanoid := npc.get_node_or_null("HumanoidVisual") as Node3D
        var imported_soldier := npc.get_node_or_null("ImportedSoldierVisual") as Node3D
        if ResourceLoader.exists("res://assets/models/characters/military_soldier.glb"):
            if not _check(imported_soldier != null and humanoid != null and not humanoid.visible, "Installed soldier asset must replace the procedural NPC visual."):
                return
        else:
            if not _check(humanoid != null and humanoid.get_child_count() >= 18, "Each NPC must retain the multipart humanoid fallback when the soldier asset is absent."):
                return
    print("IRON VEIL: Paint Thinner-inspired CQB map collision audit passed.")
    quit(0)
