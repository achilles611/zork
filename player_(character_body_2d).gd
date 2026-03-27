extends CharacterBody2D

const GREEN_SATELLITE_SCENE = preload("res://GreenSatellite.tscn")

@export var move_speed: float = 1450.0
@export var player_id: int = 0

const BASE_MODEL_SCALE := 3.1
const FACING_SMOOTHNESS := 16.0
const MAX_ENERGY := 10
const DASH_ENERGY_COST := 3
const DASH_COOLDOWN := 0.45
const DASH_TIME := 0.1
const DASH_EASE_OUT_DISTANCE_MULTIPLIER := 0.92
const TIP_DAMAGE := 10
const CRYSTAL_DAMAGE := 10
const HIT_COOLDOWN := 0.16
const CLASH_COOLDOWN := 0.12
const CLASH_KNOCKBACK_DISTANCE := 220.0
const BODY_KNOCKBACK_DISTANCE := 250.0
const LABEL_MARGIN := 120.0
const DAMAGE_NUMBER_OFFSET := Vector2(0, -240)
const STATS_NORMAL_COLOR := Color.WHITE
const STATS_DAMAGE_COLOR := Color(1.0, 0.2, 0.2)
const STATS_DAMAGE_FLASH_TIME := 0.28
const BODY_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.97)
const DAMAGE_SOUND_MIX_RATE := 22050.0
const DAMAGE_SOUND_DURATION := 0.28
const DAMAGE_SOUND_VOLUME_DB := -7.0
const PICKUP_SOUND_MIX_RATE := 22050.0
const PICKUP_SOUND_DURATION := 0.32
const PICKUP_SOUND_VOLUME_DB := -5.0
const CLASH_SOUND_MIX_RATE := 22050.0
const CLASH_SOUND_DURATION := 0.18
const CLASH_SOUND_VOLUME_DB := -4.0
const BODY_POINT_COUNT := 48

var hp: int = 100
var energy: int = 0
var alive := true

var move_input: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.RIGHT
var recently_hit := {}
var recent_clashes := {}
var green_satellites: Array = []
var stats_flash_tween: Tween = null
var dash_tween: Tween = null
var dash_cooldown_remaining := 0.0
var is_dashing := false
var damage_audio_player: AudioStreamPlayer = null
var pickup_audio_player: AudioStreamPlayer = null
var clash_audio_player: AudioStreamPlayer = null

@onready var label = $Label
@onready var body_collision_shape = $CollisionShape2D
@onready var body_hurtbox = $BodyHurtbox
@onready var tip = $Tip
@onready var tip_collision_shape = $Tip/CollisionShape2D

func _ready() -> void:
	tip.owner_player = self
	scale = Vector2.ONE * BASE_MODEL_SCALE
	label.top_level = true
	label.add_theme_color_override("font_color", STATS_NORMAL_COLOR)
	create_visual_model()
	setup_audio()
	update_label()
	update_label_position()

func _physics_process(delta: float) -> void:
	if !alive:
		return

	update_cooldowns(delta)

	if dash_cooldown_remaining > 0.0:
		dash_cooldown_remaining = maxf(dash_cooldown_remaining - delta, 0.0)

	if !is_dashing:
		if move_input.length_squared() > 0.0001:
			facing_direction = move_input.normalized()
			rotation = lerp_angle(rotation, facing_direction.angle(), minf(delta * FACING_SMOOTHNESS, 1.0))
		velocity = move_input.normalized() * move_speed
		move_and_slide()

	update_label_position()

func update_cooldowns(delta: float) -> void:
	for target in recently_hit.keys():
		recently_hit[target] -= delta
		if recently_hit[target] <= 0.0:
			recently_hit.erase(target)

	for target in recent_clashes.keys():
		recent_clashes[target] -= delta
		if recent_clashes[target] <= 0.0:
			recent_clashes.erase(target)

func set_input(dir: Vector2) -> void:
	move_input = dir

func set_rotation_input(value: float) -> void:
	return

func try_dash_attack() -> bool:
	if !alive or is_dashing or dash_cooldown_remaining > 0.0:
		return false
	if energy < DASH_ENERGY_COST:
		return false

	energy -= DASH_ENERGY_COST
	sync_energy_satellites()
	update_label()

	var dash_direction := get_tip_direction()
	var dash_distance: float = get_tip_local_center().length() * scale.x * DASH_EASE_OUT_DISTANCE_MULTIPLIER
	var destination := global_position + dash_direction * dash_distance

	is_dashing = true
	dash_cooldown_remaining = DASH_COOLDOWN
	velocity = Vector2.ZERO

	if dash_tween != null:
		dash_tween.kill()

	dash_tween = create_tween()
	dash_tween.set_trans(Tween.TRANS_QUINT)
	dash_tween.set_ease(Tween.EASE_OUT)
	dash_tween.tween_property(self, "global_position", destination, DASH_TIME)
	dash_tween.tween_callback(_finish_dash)
	return true

func _finish_dash() -> void:
	is_dashing = false
	dash_tween = null

func gain_white_orb() -> void:
	gain_energy(1)

func gain_blue_orb() -> void:
	gain_energy(1)

func gain_red_orb() -> void:
	gain_energy(1)

func gain_energy(amount: int = 1) -> bool:
	var previous_energy := energy
	energy = mini(energy + amount, MAX_ENERGY)
	if energy == previous_energy:
		return false

	sync_energy_satellites()
	update_label()
	play_green_pickup_sound()
	return true

func add_green_satellite() -> bool:
	return gain_energy(1)

func can_hit(target: Node) -> bool:
	return alive and target != self and !recently_hit.has(target)

func register_hit(target: Node) -> void:
	recently_hit[target] = HIT_COOLDOWN

func can_clash(target: Node) -> bool:
	return alive and target != self and !recent_clashes.has(target)

func register_clash(target: Node) -> void:
	recent_clashes[target] = CLASH_COOLDOWN

func is_body_hurtbox(area: Area2D) -> bool:
	return area == body_hurtbox

func get_tip_direction() -> Vector2:
	var direction: Vector2 = (get_tip_global_position() - global_position).normalized()
	if direction == Vector2.ZERO:
		return facing_direction
	return direction

func get_tip_global_position() -> Vector2:
	return tip.to_global(get_tip_local_center())

func get_tip_local_center() -> Vector2:
	if tip_collision_shape != null:
		return tip_collision_shape.position
	return Vector2(get_body_radius() * 2.2, 0.0)

func deal_tip_damage(other: Node) -> void:
	if !alive or other == null or !is_instance_valid(other):
		return
	if !other.alive or !can_hit(other):
		return

	register_hit(other)
	other.take_damage(TIP_DAMAGE)

	var push_direction_to_other: Vector2 = (other.global_position - global_position).normalized()
	if push_direction_to_other == Vector2.ZERO:
		push_direction_to_other = get_tip_direction()
	other.apply_knockback(push_direction_to_other, BODY_KNOCKBACK_DISTANCE)

func handle_tip_clash(other: Node) -> void:
	if !alive or other == null or !is_instance_valid(other):
		return
	if !other.alive:
		return
	if int(player_id) > int(other.player_id):
		return
	if !can_clash(other) or !other.can_clash(self):
		return

	register_clash(other)
	other.register_clash(self)

	var separation: Vector2 = (get_tip_global_position() - other.get_tip_global_position()).normalized()
	if separation == Vector2.ZERO:
		separation = (global_position - other.global_position).normalized()
	if separation == Vector2.ZERO:
		separation = Vector2.RIGHT

	apply_knockback(separation, CLASH_KNOCKBACK_DISTANCE)
	other.apply_knockback(-separation, CLASH_KNOCKBACK_DISTANCE)
	play_clash_sound()

func apply_knockback(direction: Vector2, distance: float = BODY_KNOCKBACK_DISTANCE) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", global_position + direction * distance, 0.16)

func hit_by_player(player: Node2D) -> void:
	if !alive or player == null or !is_instance_valid(player):
		return
	if recently_hit.has(player):
		return

	recently_hit[player] = HIT_COOLDOWN
	play_clash_sound()

func get_attack_power() -> int:
	return CRYSTAL_DAMAGE

func get_camera_zoom_factor() -> float:
	return 1.0

func get_green_satellite_count() -> int:
	cleanup_green_satellites()
	return green_satellites.size()

func get_green_satellite_index(satellite: Node) -> int:
	cleanup_green_satellites()
	return green_satellites.find(satellite)

func sync_energy_satellites() -> void:
	cleanup_green_satellites()
	if get_tree().current_scene == null:
		return

	while green_satellites.size() < energy:
		var satellite = GREEN_SATELLITE_SCENE.instantiate()
		satellite.owner_player = self
		get_tree().current_scene.add_child(satellite)
		green_satellites.append(satellite)

	while green_satellites.size() > energy:
		var satellite_to_remove = green_satellites.pop_back()
		if is_instance_valid(satellite_to_remove):
			satellite_to_remove.queue_free()

func cleanup_green_satellites() -> void:
	for i in range(green_satellites.size() - 1, -1, -1):
		if !is_instance_valid(green_satellites[i]):
			green_satellites.remove_at(i)

func clear_green_satellites() -> void:
	for satellite in green_satellites:
		if is_instance_valid(satellite):
			satellite.queue_free()
	green_satellites.clear()

func take_damage(amount: int) -> void:
	if !alive:
		return

	hp -= amount
	play_damage_impact_sound()
	flash_stats_damage(amount)
	show_damage_number(amount)

	if hp <= 0:
		kill_instantly()

func flash_stats_damage(amount: int) -> void:
	if stats_flash_tween != null:
		stats_flash_tween.kill()

	label.add_theme_color_override("font_color", STATS_DAMAGE_COLOR)
	label.text = "HP -%d\nEN %d" % [amount, energy]

	stats_flash_tween = create_tween()
	stats_flash_tween.tween_interval(STATS_DAMAGE_FLASH_TIME)
	stats_flash_tween.tween_callback(restore_stats_label)

func restore_stats_label() -> void:
	label.add_theme_color_override("font_color", STATS_NORMAL_COLOR)
	update_label()
	stats_flash_tween = null

func show_damage_number(amount: int) -> void:
	var damage_label := Label.new()
	damage_label.top_level = true
	damage_label.z_index = 100
	damage_label.text = "-%d" % amount
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	damage_label.add_theme_font_size_override("font_size", 52)
	damage_label.global_position = global_position + (DAMAGE_NUMBER_OFFSET * scale.x)
	get_tree().current_scene.add_child(damage_label)
	damage_label.global_position -= damage_label.size * 0.5

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "global_position", damage_label.global_position + Vector2(0, -90), 0.5)
	tween.tween_property(damage_label, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(damage_label.queue_free)

func update_label() -> void:
	label.text = "HP %d\nEN %d" % [hp, energy]

func update_label_position() -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := Vector2.ONE
	if camera != null:
		camera_zoom = camera.zoom

	label.scale = Vector2.ONE / camera_zoom

	var body_radius := get_body_radius() * scale.y
	var label_size: Vector2 = label.size * label.scale
	var world_offset := Vector2(0.0, -(body_radius + (LABEL_MARGIN * scale.y)))
	label.global_position = global_position + world_offset - Vector2(label_size.x * 0.5, label_size.y)

func get_body_radius() -> float:
	var circle_shape := body_collision_shape.shape as CircleShape2D
	if circle_shape == null:
		return 180.0
	return circle_shape.radius

func create_visual_model() -> void:
	create_silhouette_outline()

func create_silhouette_outline() -> void:
	var outline := Line2D.new()
	outline.name = "SilhouetteOutline"
	outline.width = 16.0
	outline.default_color = BODY_OUTLINE_COLOR
	outline.antialiased = true
	outline.closed = true
	outline.z_index = 3
	outline.points = build_silhouette_outline()
	add_child(outline)

func build_silhouette_outline() -> PackedVector2Array:
	var radius := get_body_radius()
	var attach_upper_angle := deg_to_rad(-48.0)
	var attach_lower_angle := deg_to_rad(-12.0)
	var attach_upper := Vector2(cos(attach_upper_angle), sin(attach_upper_angle)) * radius
	var attach_lower := Vector2(cos(attach_lower_angle), sin(attach_lower_angle)) * radius
	var tip_point := Vector2(radius * 2.55, -radius * 1.95)

	var points := PackedVector2Array([attach_upper, tip_point, attach_lower])
	var arc_point_count := 36
	for i in range(arc_point_count + 1):
		var t: float = float(i) / float(arc_point_count)
		var angle: float = lerp(attach_lower_angle, attach_upper_angle + TAU, t)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func setup_audio() -> void:
	damage_audio_player = AudioStreamPlayer.new()
	damage_audio_player.volume_db = DAMAGE_SOUND_VOLUME_DB
	damage_audio_player.stream = build_damage_stream()
	add_child(damage_audio_player)

	pickup_audio_player = AudioStreamPlayer.new()
	pickup_audio_player.volume_db = PICKUP_SOUND_VOLUME_DB
	pickup_audio_player.stream = build_pickup_stream()
	add_child(pickup_audio_player)

	clash_audio_player = AudioStreamPlayer.new()
	clash_audio_player.volume_db = CLASH_SOUND_VOLUME_DB
	clash_audio_player.stream = build_clash_stream()
	add_child(clash_audio_player)

func play_damage_impact_sound() -> void:
	if damage_audio_player != null:
		damage_audio_player.play()

func play_green_pickup_sound() -> void:
	if pickup_audio_player != null:
		pickup_audio_player.play()

func play_clash_sound() -> void:
	if clash_audio_player != null:
		clash_audio_player.play()

func build_damage_stream() -> AudioStreamWAV:
	var frame_count: int = int(DAMAGE_SOUND_MIX_RATE * DAMAGE_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / DAMAGE_SOUND_MIX_RATE
		var decay: float = exp(-7.5 * t)
		var low_sweep: float = 180.0 - (90.0 * (t / DAMAGE_SOUND_DURATION))
		var bass: float = sin(TAU * low_sweep * t) * 0.28 * decay
		var crunch: float = sin(TAU * 78.0 * t) * 0.16 * decay
		var grit: float = (randf() * 2.0 - 1.0) * 0.08 * decay
		var sample: float = clampf(bass + crunch + grit, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, DAMAGE_SOUND_MIX_RATE)

func build_pickup_stream() -> AudioStreamWAV:
	var frame_count: int = int(PICKUP_SOUND_MIX_RATE * PICKUP_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / PICKUP_SOUND_MIX_RATE
		var decay: float = exp(-7.0 * t)
		var tone_a: float = sin(TAU * 880.0 * t) * 0.22 * decay
		var tone_b: float = sin(TAU * 1320.0 * t) * 0.15 * decay
		var tone_c: float = sin(TAU * 1760.0 * t) * 0.08 * decay
		var sample: float = clampf(tone_a + tone_b + tone_c, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, PICKUP_SOUND_MIX_RATE)

func build_clash_stream() -> AudioStreamWAV:
	var frame_count: int = int(CLASH_SOUND_MIX_RATE * CLASH_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / CLASH_SOUND_MIX_RATE
		var decay: float = exp(-13.0 * t)
		var ping_a: float = sin(TAU * 1650.0 * t) * 0.34 * decay
		var ping_b: float = sin(TAU * 2440.0 * t) * 0.18 * decay
		var bite: float = sin(TAU * 980.0 * t) * 0.12 * decay
		var sample: float = clampf(ping_a + ping_b + bite, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, CLASH_SOUND_MIX_RATE)

func make_wav_stream(buffer: StreamPeerBuffer, mix_rate: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(mix_rate)
	stream.stereo = false
	stream.data = buffer.data_array
	return stream

func kill_instantly() -> void:
	if !alive:
		return

	alive = false
	hp = 0
	clear_green_satellites()
	if stats_flash_tween != null:
		stats_flash_tween.kill()
	if dash_tween != null:
		dash_tween.kill()
	label.queue_free()
	queue_free()
