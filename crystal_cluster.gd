extends Node2D

const GREEN_CRYSTAL_PICKUP_SCENE = preload("res://GreenCrystalPickup.tscn")

const MAX_HP := 100
const DROP_COUNT := 6
const HIT_COOLDOWN := 0.25
const HP_BAR_WIDTH := 220.0
const HP_BAR_OFFSET := Vector2(0, -270)
const HIT_SOUND_MIX_RATE := 22050.0
const HIT_SOUND_DURATION := 0.18
const HIT_SOUND_VOLUME_DB := -9.0

var hp: int = MAX_HP
var attacker_cooldowns := {}
var hp_bar_root: Node2D = null
var hp_bar_fill: Line2D = null
var crystal_hit_audio_player: AudioStreamPlayer2D = null
var crystal_hit_playback: AudioStreamGeneratorPlayback = null

func _ready() -> void:
	create_visuals()
	create_hp_bar()
	setup_hit_audio()
	update_hp_bar_visual()
	update_hp_bar_position()

func _process(delta: float) -> void:
	update_attacker_cooldowns(delta)
	update_hp_bar_position()

func hit_by_player(player: Node2D) -> void:
	if hp <= 0 or attacker_cooldowns.has(player):
		return

	attacker_cooldowns[player] = HIT_COOLDOWN
	bounce_player(player)
	play_crystal_hit_sound()

	var damage: int = 10
	if player.has_method("get_attack_power"):
		damage = int(player.call("get_attack_power"))

	hp = max(hp - damage, 0)
	update_hp_bar_visual()

	if hp <= 0:
		shatter()

func shatter() -> void:
	if get_tree().current_scene != null:
		for i in range(DROP_COUNT):
			var pickup: Node2D = GREEN_CRYSTAL_PICKUP_SCENE.instantiate()
			var angle: float = TAU * float(i) / float(DROP_COUNT)
			pickup.global_position = global_position + Vector2(150, 0).rotated(angle) + Vector2(randf_range(-35.0, 35.0), randf_range(-35.0, 35.0))
			get_tree().current_scene.add_child(pickup)

	queue_free()

func update_attacker_cooldowns(delta: float) -> void:
	for attacker in attacker_cooldowns.keys():
		attacker_cooldowns[attacker] -= delta
		if attacker_cooldowns[attacker] <= 0.0:
			attacker_cooldowns.erase(attacker)

func create_visuals() -> void:
	add_child(make_crystal(Vector2(-80, 40), 1.2, Color(0.1, 0.85, 0.25, 0.35), Color(0.35, 1.0, 0.45, 0.95)))
	add_child(make_crystal(Vector2(0, -20), 1.6, Color(0.1, 0.75, 0.2, 0.32), Color(0.55, 1.0, 0.65, 0.98)))
	add_child(make_crystal(Vector2(90, 60), 1.0, Color(0.08, 0.8, 0.18, 0.3), Color(0.3, 0.95, 0.4, 0.95)))
	add_child(make_crystal(Vector2(40, 120), 0.9, Color(0.08, 0.75, 0.2, 0.25), Color(0.45, 0.95, 0.55, 0.9)))
	add_child(make_crystal(Vector2(-130, 120), 0.8, Color(0.08, 0.7, 0.18, 0.22), Color(0.4, 0.92, 0.5, 0.88)))

func make_crystal(offset: Vector2, size_multiplier: float, glow_color: Color, core_color: Color) -> Node2D:
	var crystal := Node2D.new()
	crystal.position = offset

	var glow := Polygon2D.new()
	glow.polygon = PackedVector2Array([
		Vector2(0, -120),
		Vector2(70, -25),
		Vector2(45, 110),
		Vector2(-45, 110),
		Vector2(-70, -25)
	])
	glow.color = glow_color
	glow.scale = Vector2.ONE * size_multiplier * 1.25
	crystal.add_child(glow)

	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([
		Vector2(0, -96),
		Vector2(52, -18),
		Vector2(34, 84),
		Vector2(-34, 84),
		Vector2(-52, -18)
	])
	core.color = core_color
	core.scale = Vector2.ONE * size_multiplier
	crystal.add_child(core)

	var highlight := Polygon2D.new()
	highlight.polygon = PackedVector2Array([
		Vector2(-18, -62),
		Vector2(6, -48),
		Vector2(-2, 12),
		Vector2(-22, 2)
	])
	highlight.color = Color(0.92, 1.0, 0.95, 0.45)
	highlight.scale = Vector2.ONE * size_multiplier
	crystal.add_child(highlight)

	return crystal

func create_hp_bar() -> void:
	hp_bar_root = Node2D.new()
	hp_bar_root.top_level = true
	add_child(hp_bar_root)

	var background := Line2D.new()
	background.width = 18.0
	background.default_color = Color(0.02, 0.08, 0.02, 0.85)
	background.points = PackedVector2Array([
		Vector2(-HP_BAR_WIDTH * 0.5, 0),
		Vector2(HP_BAR_WIDTH * 0.5, 0)
	])
	hp_bar_root.add_child(background)

	hp_bar_fill = Line2D.new()
	hp_bar_fill.width = 12.0
	hp_bar_fill.default_color = Color(0.35, 1.0, 0.45, 0.95)
	hp_bar_root.add_child(hp_bar_fill)

func update_hp_bar_visual() -> void:
	if hp_bar_fill == null:
		return

	var ratio: float = float(hp) / float(MAX_HP)
	hp_bar_fill.points = PackedVector2Array([
		Vector2(-HP_BAR_WIDTH * 0.5, 0),
		Vector2((-HP_BAR_WIDTH * 0.5) + (HP_BAR_WIDTH * ratio), 0)
	])

func update_hp_bar_position() -> void:
	if hp_bar_root == null:
		return

	var camera := get_viewport().get_camera_2d()
	var camera_zoom := Vector2.ONE
	if camera != null:
		camera_zoom = camera.zoom

	hp_bar_root.scale = Vector2.ONE / camera_zoom
	hp_bar_root.global_position = global_position + (HP_BAR_OFFSET * scale.y)

func bounce_player(player: Node2D) -> void:
	if !player.has_method("apply_knockback"):
		return

	var direction: Vector2 = (player.global_position - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP

	player.call("apply_knockback", direction)

func setup_hit_audio() -> void:
	crystal_hit_audio_player = AudioStreamPlayer2D.new()
	crystal_hit_audio_player.top_level = true
	crystal_hit_audio_player.max_distance = 100000.0
	crystal_hit_audio_player.volume_db = HIT_SOUND_VOLUME_DB

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = HIT_SOUND_MIX_RATE
	stream.buffer_length = HIT_SOUND_DURATION
	crystal_hit_audio_player.stream = stream
	add_child(crystal_hit_audio_player)

func play_crystal_hit_sound() -> void:
	if crystal_hit_audio_player == null:
		return

	crystal_hit_audio_player.global_position = global_position
	crystal_hit_audio_player.play()
	crystal_hit_playback = crystal_hit_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if crystal_hit_playback == null:
		return

	var frame_count: int = int(HIT_SOUND_MIX_RATE * HIT_SOUND_DURATION)
	for i in range(frame_count):
		var t: float = float(i) / HIT_SOUND_MIX_RATE
		var decay: float = max(1.0 - (t / HIT_SOUND_DURATION), 0.0)
		var metallic: float = sin(TAU * 1700.0 * t) * 0.18 * decay
		var body: float = sin(TAU * 520.0 * t) * 0.1 * decay
		var grit: float = (randf() * 2.0 - 1.0) * 0.12 * decay
		var sample: float = metallic + body + grit
		crystal_hit_playback.push_frame(Vector2(sample, sample))

	var timer := get_tree().create_timer(HIT_SOUND_DURATION + 0.02)
	timer.timeout.connect(_stop_crystal_hit_sound)

func _stop_crystal_hit_sound() -> void:
	if crystal_hit_audio_player != null:
		crystal_hit_audio_player.stop()
	crystal_hit_playback = null
