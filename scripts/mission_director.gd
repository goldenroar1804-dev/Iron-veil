extends Node
## Small objective tracker for the first ground-based PvE operation.

signal objective_updated(message: String)

var hostiles_remaining := 0
var operation_name := "OPERATION: SUBURBAN BREACH"
var complete := false

func start_operation(enemy_count: int) -> void:
    hostiles_remaining = enemy_count
    complete = false
    _publish("Clear the block | Hostiles remaining: %d" % hostiles_remaining)

func register_enemy(enemy: Node) -> void:
    if enemy != null and enemy.has_signal("eliminated"):
        enemy.eliminated.connect(_on_enemy_eliminated)

func _on_enemy_eliminated() -> void:
    if complete:
        return
    hostiles_remaining = maxi(0, hostiles_remaining - 1)
    if hostiles_remaining == 0:
        complete = true
        _publish("OBJECTIVE COMPLETE | Suburban block secured")
    else:
        _publish("Clear the block | Hostiles remaining: %d" % hostiles_remaining)

func _publish(message: String) -> void:
    print("IRON VEIL | %s | %s" % [operation_name, message])
    objective_updated.emit(message)
