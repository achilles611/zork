extends Area2D

const PICKUP_SOUND_MIX_RATE := 22050.0
const PICKUP_SOUND_DURATION := 0.32
const PICKUP_SOUND_VOLUME_DB := -11.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	create_visuals()

func _process(delta: float) -> void:
	rotation += delta * 0.8

func _on_body_entered(body: Node) -> void:
	if body.has_method("add_green_satellite"):
		var added: bool = bool(body.call("add_green_satellite"))
		if added:
			play_pickup_chime()
			queue_free()

func create_visuals() -> void:
	var aura := Polygon2D.new()
	aura.polygon = make_circle_points(72.0, 22)
	aura.color = Color(0.2, 1.0, 0.35, 0.15)
	add_child(aura)

	var shell := Polygon2D.new()
	shell.polygon = make_circle_points(48.0, 20)
	shell.color = Color(0.35, 0.95, 0.45, 0.35)
	add_child(shell)

	var gem_back := Polygon2D.new()
	gem_back.polygon = PackedVector2Array([
		Vector2(0, -34),
		Vector2(20, -10),
		Vector2(14, 30),
		Vector2(-14, 30),
		Vector2(-20, -10)
	])
	gem_back.color = Color(0.1, 0.7, 0.2, 0.85)
	add_child(gem_back)

	var gem_front := Polygon2D.new()
	gem_front.polygon = PackedVector2Array([
		Vector2(0, -24),
		Vector2(13, -6),
		Vector2(9, 22),
		Vector2(-9, 22),
		Vector2(-13, -6)
	])
	gem_front.color = Color(0.7, 1.0, 0.8, 0.95)
	add_child(gem_front)

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func play_pickup_chime() -> void:
	if get_tree().current_scene == null:
		return

	var player := AudioStreamPlayer2D.new()
	player.top_level = true
	player.global_position = global_position
	player.max_distance = 100000.0
	player.volume_db = PICKUP_SOUND_VOLUME_DB

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = PICKUP_SOUND_MIX_RATE
	stream.buffer_length = PICKUP_SOUND_DURATION
	player.stream = stream
	get_tree().current_scene.add_child(player)
	player.play()

	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return

	var frame_count: int = int(PICKUP_SOUND_MIX_RATE * PICKUP_SOUND_DURATION)
	for i in range(frame_count):
		var t: float = float(i) / PICKUP_SOUND_MIX_RATE
		var decay: float = exp(-7.0 * t)
		var tone_a: float = sin(TAU * 880.0 * t) * 0.22 * decay
		var tone_b: float = sin(TAU * 1320.0 * t) * 0.15 * decay
		var tone_c: float = sin(TAU * 1760.0 * t) * 0.08 * decay
		var sample: float = tone_a + tone_b + tone_c
		playback.push_frame(Vector2(sample, sample))

	var timer := get_tree().create_timer(PICKUP_SOUND_DURATION + 0.03)
	timer.timeout.connect(player.queue_free)
