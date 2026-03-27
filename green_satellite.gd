extends Node2D

const ORBIT_RADIUS := 520.0
const ORBIT_SPEED := 2.6

var owner_player: Node2D = null

func _ready() -> void:
	top_level = true
	create_visuals()

func _physics_process(delta: float) -> void:
	if owner_player == null or !is_instance_valid(owner_player):
		queue_free()
		return

	var count: int = int(owner_player.call("get_green_satellite_count"))
	if count <= 0:
		queue_free()
		return

	var index: int = int(owner_player.call("get_green_satellite_index", self))
	if index < 0:
		queue_free()
		return

	var orbit_angle: float = (Time.get_ticks_msec() / 1000.0 * ORBIT_SPEED) + (TAU * float(index) / float(count))
	global_position = owner_player.global_position + Vector2(ORBIT_RADIUS * owner_player.scale.x, 0).rotated(orbit_angle)
	rotation += delta * 2.0

func create_visuals() -> void:
	var aura := Polygon2D.new()
	aura.polygon = make_circle_points(90.0, 22)
	aura.color = Color(0.35, 1.0, 0.35, 0.16)
	add_child(aura)

	var orb := Polygon2D.new()
	orb.polygon = make_circle_points(48.0, 20)
	orb.color = Color(0.45, 1.0, 0.55, 0.94)
	add_child(orb)

	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([
		Vector2(0, -42),
		Vector2(26, -10),
		Vector2(18, 34),
		Vector2(-18, 34),
		Vector2(-26, -10)
	])
	core.color = Color(0.85, 1.0, 0.9, 0.98)
	add_child(core)

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
