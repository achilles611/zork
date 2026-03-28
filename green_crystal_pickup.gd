extends Area2D

var entity_id := ""
var network_proxy := false

func _ready() -> void:
	if entity_id == "":
		entity_id = "pickup_%d" % Time.get_ticks_usec()
	body_entered.connect(_on_body_entered)
	create_visuals()

func _process(delta: float) -> void:
	if network_proxy:
		return
	rotation += delta * 0.8

func _on_body_entered(body: Node) -> void:
	if body.has_method("gain_leg"):
		var added: bool = bool(body.call("gain_leg", 1))
		if added:
			queue_free()

func create_visuals() -> void:
	var aura := Polygon2D.new()
	aura.polygon = make_circle_points(72.0, 22)
	aura.color = Color(0.2, 1.0, 0.35, 0.15)
	add_child(aura)

	var leg := Polygon2D.new()
	leg.polygon = PackedVector2Array([
		Vector2(-18, -16),
		Vector2(52, -56),
		Vector2(34, 0),
		Vector2(52, 56),
		Vector2(-18, 16),
		Vector2(-34, 0)
	])
	leg.color = Color(0.9, 1.0, 0.92, 0.95)
	add_child(leg)

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func set_network_proxy(enabled: bool) -> void:
	network_proxy = enabled
	monitoring = !enabled
	monitorable = !enabled
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = enabled

func get_snapshot() -> Dictionary:
	return {
		"entity_id": entity_id,
		"position": [global_position.x, global_position.y],
	}

func apply_network_snapshot(data: Dictionary) -> void:
	entity_id = str(data.get("entity_id", entity_id))
	var position_data = data.get("position", [global_position.x, global_position.y])
	if position_data is Array and position_data.size() >= 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
