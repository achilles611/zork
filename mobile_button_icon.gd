extends Control

@export_enum("rotate", "dash") var icon_type := "rotate":
	set(value):
		icon_type = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if icon_type == "dash":
		draw_dash_icon()
	else:
		draw_rotate_icon()

func draw_rotate_icon() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.28
	var line_width: float = maxf(6.0, size.x * 0.03)

	draw_arc(center, radius, PI * 0.2, PI * 1.35, 28, Color(0.86, 0.92, 1.0, 0.95), line_width, true)
	draw_arc(center, radius, -PI * 0.15, -PI * 1.25, 28, Color(0.6, 0.78, 1.0, 0.95), line_width, true)

	var arrow_a := PackedVector2Array([
		center + Vector2(-radius * 0.9, -radius * 0.55),
		center + Vector2(-radius * 1.45, -radius * 0.78),
		center + Vector2(-radius * 1.1, -radius * 0.18),
	])
	var arrow_b := PackedVector2Array([
		center + Vector2(radius * 0.85, radius * 0.55),
		center + Vector2(radius * 1.38, radius * 0.75),
		center + Vector2(radius * 1.05, radius * 0.16),
	])
	draw_colored_polygon(arrow_a, Color.WHITE)
	draw_colored_polygon(arrow_b, Color.WHITE)
	draw_circle(center, radius * 0.24, Color(1, 1, 1, 0.8))

func draw_dash_icon() -> void:
	var center: Vector2 = size * 0.5
	var body_radius: float = minf(size.x, size.y) * 0.18
	var body_center: Vector2 = center + size * Vector2(-0.06, 0.08)

	draw_circle(body_center, body_radius, Color(0.84, 0.16, 0.16, 0.98))
	draw_arc(body_center, body_radius * 1.04, 0.0, TAU, 36, Color.WHITE, max(4.0, size.x * 0.018), true)

	var arm_points := PackedVector2Array([
		size * Vector2(0.47, 0.56),
		size * Vector2(0.61, 0.42),
		size * Vector2(0.79, 0.34),
		size * Vector2(0.72, 0.53),
		size * Vector2(0.56, 0.62),
	])
	draw_colored_polygon(arm_points, Color.WHITE)

	var tip_points := PackedVector2Array([
		size * Vector2(0.73, 0.33),
		size * Vector2(0.94, 0.2),
		size * Vector2(0.79, 0.55),
	])
	draw_colored_polygon(tip_points, Color(0.3, 0.65, 1.0, 1.0))

	var dash_line_width: float = maxf(5.0, size.x * 0.02)
	draw_line(size * Vector2(0.1, 0.42), size * Vector2(0.28, 0.42), Color(0.6, 0.9, 1.0, 0.9), dash_line_width, true)
	draw_line(size * Vector2(0.1, 0.58), size * Vector2(0.33, 0.58), Color(0.6, 0.9, 1.0, 0.9), dash_line_width, true)
	draw_line(size * Vector2(0.16, 0.5), size * Vector2(0.38, 0.5), Color(0.6, 0.9, 1.0, 0.9), dash_line_width, true)
