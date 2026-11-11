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
    for name in ["PT_ConcreteFloor_Collider", "PT_OuterNorth_Collider", "PT_OuterSouth_Collider", "PT_OuterWest_Collider", "PT_OuterEast_Collider"]:
        if not _check(game.get_node_or_null(name) is StaticBody3D, name + " must have static collision."):
            return
    for name in ["PT_Partition_A_Collider", "PT_Partition_B_Collider", "PT_Partition_C_Collider", "PT_Partition_D_Collider", "PT_Partition_E_Collider", "PT_Partition_F_Collider", "PT_Partition_G_Collider", "PT_Partition_H_Collider"]:
        if not _check(game.get_node_or_null(name) is StaticBody3D, name + " must have static collision."):
            return
    for name in ["PT_BrokenCounter_A_Collider", "PT_BrokenCounter_B_Collider", "PT_OverturnedTable_Collider", "PT_LockerBank_Collider"]:
        if not _check(game.get_node_or_null(name) is StaticBody3D, name + " must provide hard cover collision."):
            return
    for enemy in range(4):
        if not _check(game.get_node_or_null("PvE_OpFor_%02d" % enemy) is CharacterBody3D, "All four CQB enemies must spawn inside the map."):
            return
    print("IRON VEIL: Paint Thinner-inspired CQB map collision audit passed.")
    quit(0)
