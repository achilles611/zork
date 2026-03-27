extends CharacterBody2D

const GREEN_SATELLITE_SCENE = preload("res://GreenSatellite.tscn")

@export var move_speed: float = 1100.0
@export var rotation_speed: float = 2.0
@export var player_id: int = 0

const DAMAGE_NUMBER_OFFSET := Vector2(0, -170)
const KNOCKBACK_DISTANCE := 240.0
const FLASH_TIME := 0.12
const HIT_COOLDOWN := 0.08
const ORB_GROWTH_FACTOR := 1.05
const BURN_SPEED_MULTIPLIER := 3.0
const BURN_TICK_TIME := 1.0
const BURN_TRAIL_LIFETIME := 1.0
const BURN_SOUND_MIX_RATE := 22050.0
const BURN_SOUND_BUFFER_LENGTH := 0.2
const BURN_SOUND_VOLUME_DB := -10.0
const DAMAGE_SOUND_MIX_RATE := 22050.0
const DAMAGE_SOUND_DURATION := 0.28
const DAMAGE_SOUND_VOLUME_DB := -7.0
const STATS_DAMAGE_FLASH_TIME := 0.28
const STATS_NORMAL_COLOR := Color.WHITE
const STATS_DAMAGE_COLOR := Color(1.0, 0.2, 0.2)
const STATS_MARGIN := 80.0
const MAX_GREEN_SATELLITES := 8
const SATELLITE_VOLLEY_INTERVAL := 0.1
const SATELLITE_FIRE_SOUND_MIX_RATE := 22050.0
const SATELLITE_FIRE_SOUND_DURATION := 0.14
const SATELLITE_FIRE_SOUND_VOLUME_DB := -9.0
const MODEL_NORMAL_COLOR := Color.WHITE
const MODEL_BURN_COLOR := Color(0.35, 1.0, 0.35)
const MODEL_DAMAGE_COLOR := Color(1.0, 0.25, 0.25)
const MODEL_TINT_SHADER_CODE := """
shader_type canvas_item;

uniform vec4 base_core_color : source_color = vec4(0.98, 0.99, 1.0, 1.0);
uniform vec4 base_glow_color : source_color = vec4(0.35, 0.72, 1.0, 1.0);
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float outline_size = 4.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * outline_size;

	float a_r1 = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	float a_l1 = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
	float a_u1 = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
	float a_d1 = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	float a_ur1 = texture(TEXTURE, UV + vec2(px.x, -px.y)).a;
	float a_ul1 = texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
	float a_dr1 = texture(TEXTURE, UV + vec2(px.x, px.y)).a;
	float a_dl1 = texture(TEXTURE, UV + vec2(-px.x, px.y)).a;

	float a_r2 = texture(TEXTURE, UV + vec2(px.x * 2.0, 0.0)).a;
	float a_l2 = texture(TEXTURE, UV + vec2(-px.x * 2.0, 0.0)).a;
	float a_u2 = texture(TEXTURE, UV + vec2(0.0, -px.y * 2.0)).a;
	float a_d2 = texture(TEXTURE, UV + vec2(0.0, px.y * 2.0)).a;

	float max_neighbor = max(
		max(max(a_r1, a_l1), max(a_u1, a_d1)),
		max(max(a_ur1, a_ul1), max(a_dr1, a_dl1))
	);
	max_neighbor = max(max_neighbor, max(max(a_r2, a_l2), max(a_u2, a_d2)));

	float min_neighbor = min(
		min(min(a_r1, a_l1), min(a_u1, a_d1)),
		min(min(a_ur1, a_ul1), min(a_dr1, a_dl1))
	);
	min_neighbor = min(min_neighbor, min(min(a_r2, a_l2), min(a_u2, a_d2)));

	float inside_edge = smoothstep(0.04, 0.65, tex.a - min_neighbor) * step(0.02, tex.a);
	float outer_glow = smoothstep(0.03, 0.45, max_neighbor) * (1.0 - step(0.02, tex.a));
	float outline_alpha = max(inside_edge, outer_glow * 0.85);

	vec3 outline_color = mix(base_glow_color.rgb, base_core_color.rgb, clamp(inside_edge * 1.15, 0.0, 1.0));
	outline_color = mix(outline_color, tint_color.rgb, tint_strength * 0.88);

	COLOR = vec4(outline_color, outline_alpha);
}
"""
const TRAIL_OUTLINE_SHADER_CODE := """
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.35, 1.0, 0.35, 0.95);
uniform float outline_size = 4.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 step = TEXTURE_PIXEL_SIZE * outline_size;

	float neighbor_alpha = 0.0;
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(step.x, 0.0)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-step.x, 0.0)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(0.0, step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(0.0, -step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + step).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV - step).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(step.x, -step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-step.x, step.y)).a);

	float outline_alpha = max(neighbor_alpha - tex.a, 0.0);
	COLOR = vec4(outline_color.rgb, outline_alpha * outline_color.a);
}
"""

var attack: int = 10
var hp: int = 100
var alive: bool = true

var move_input: Vector2 = Vector2.ZERO
var recently_hit := {}
var stats_flash_tween: Tween = null
var burn_tick_timer := 0.0
var burn_active := false
var growth_steps: int = 0
var model_flash_tween: Tween = null
var sprite_tint_material: ShaderMaterial = null
var burn_trail_material: ShaderMaterial = null
var green_satellites: Array = []
var pending_satellite_volley: Array = []
var satellite_volley_target: Node2D = null
var satellite_volley_timer := 0.0
var burn_audio_player: AudioStreamPlayer2D = null
var burn_audio_playback: AudioStreamGeneratorPlayback = null
var burn_audio_phase := 0.0
var burn_audio_noise_phase := 0.0
var damage_audio_player: AudioStreamPlayer2D = null
var damage_audio_playback: AudioStreamGeneratorPlayback = null

@onready var label = $Label
@onready var sprite = $Sprite2D

func _ready() -> void:
	$Tip1.owner_player = self
	$Tip2.owner_player = self
	$Tip3.owner_player = self
	label.top_level = true
	label.add_theme_color_override("font_color", STATS_NORMAL_COLOR)
	setup_model_material()
	setup_burn_trail_material()
	setup_burn_audio()
	setup_damage_audio()
	update_model_visual()
	update_label_position()
	update_label()

func _process(_delta: float) -> void:
	update_burn_audio()

func _physics_process(delta: float) -> void:
	if !alive:
		return

	rotation += rotation_speed * delta
	update_burn(delta)
	update_satellite_volley(delta)
	var current_move_speed: float = move_speed * (BURN_SPEED_MULTIPLIER if burn_active else 1.0)
	velocity = move_input.normalized() * current_move_speed
	move_and_slide()
	if burn_active:
		spawn_burn_trail()
	update_label_position()

	for target in recently_hit.keys():
		recently_hit[target] -= delta
		if recently_hit[target] <= 0:
			recently_hit.erase(target)

func set_input(dir: Vector2) -> void:
	move_input = dir

func set_burning(active: bool) -> void:
	burn_active = active and growth_steps > 0
	if burn_active and burn_tick_timer <= 0.0:
		burn_tick_timer = BURN_TICK_TIME
	elif !burn_active:
		burn_tick_timer = 0.0
	update_model_visual()

func gain_white_orb() -> void:
	attack += 1
	hp += 1
	grow_from_orb()
	update_label()

func gain_blue_orb() -> void:
	hp += 2
	grow_from_orb()
	update_label()

func gain_red_orb() -> void:
	attack += 2
	grow_from_orb()
	update_label()

func can_hit(target: Node) -> bool:
	return alive and target != self and !recently_hit.has(target)

func register_hit(target: Node) -> void:
	recently_hit[target] = HIT_COOLDOWN

func take_damage(amount: int) -> void:
	if !alive:
		return

	hp -= amount
	print(name, " took ", amount, " damage, hp now ", hp)
	play_damage_impact_sound()
	play_damage_feedback(amount)
	flash_stats_damage(amount)

	if hp <= 0:
		die()

	if hp <= 0:
		die()

func die() -> void:
	alive = false
	pending_satellite_volley.clear()
	satellite_volley_target = null
	stop_burn_audio()
	clear_green_satellites()
	label.queue_free()
	queue_free()

func resolve_combat(other: Node) -> void:
	if !alive or !other.alive:
		return

	if !can_hit(other) or !other.can_hit(self):
		return

	print(name, " hit ", other.name, " | my atk=", attack, " their atk=", other.attack)

	register_hit(other)
	other.register_hit(self)

	var my_attack = attack
	var their_attack = other.attack

	var push_direction_to_self: Vector2 = (global_position - other.global_position).normalized()
	if push_direction_to_self == Vector2.ZERO:
		push_direction_to_self = Vector2.UP

	var push_direction_to_other: Vector2 = -push_direction_to_self

	take_damage(their_attack)
	other.take_damage(my_attack)

	apply_knockback(push_direction_to_self)
	other.apply_knockback(push_direction_to_other)

func update_label() -> void:
	label.text = "ATK %d\nHP %d" % [attack, hp]

func update_label_position() -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := Vector2.ONE
	if camera != null:
		camera_zoom = camera.zoom

	# Counter the world-camera zoom so the text stays readable on screen.
	label.scale = Vector2.ONE / camera_zoom

	var sprite_height := 0.0
	if sprite.texture != null:
		sprite_height = sprite.texture.get_size().y * sprite.scale.y * scale.y

	var label_size: Vector2 = label.size * label.scale
	var world_offset: Vector2 = Vector2(0, -((sprite_height * 0.5) + (STATS_MARGIN * scale.y)))
	label.global_position = global_position + world_offset - Vector2(label_size.x * 0.5, label_size.y)

func play_damage_feedback(amount: int) -> void:
	flash_red()
	show_damage_number(amount)

func flash_stats_damage(amount: int) -> void:
	if stats_flash_tween != null:
		stats_flash_tween.kill()

	label.add_theme_color_override("font_color", STATS_DAMAGE_COLOR)
	label.text = "ATK %d\nHP -%d" % [attack, amount]

	stats_flash_tween = create_tween()
	stats_flash_tween.tween_interval(STATS_DAMAGE_FLASH_TIME)
	stats_flash_tween.tween_callback(restore_stats_label)

func restore_stats_label() -> void:
	label.add_theme_color_override("font_color", STATS_NORMAL_COLOR)
	update_label()
	stats_flash_tween = null

func flash_red() -> void:
	if model_flash_tween != null:
		model_flash_tween.kill()

	set_model_tint(MODEL_DAMAGE_COLOR, 1.0)

	model_flash_tween = create_tween()
	model_flash_tween.tween_interval(FLASH_TIME)
	model_flash_tween.tween_callback(update_model_visual)

func apply_knockback(direction: Vector2) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", global_position + direction * KNOCKBACK_DISTANCE, 0.18)

func show_damage_number(amount: int) -> void:
	var damage_label := Label.new()
	damage_label.top_level = true
	damage_label.z_index = 100
	damage_label.text = "-%d" % amount
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	damage_label.add_theme_font_size_override("font_size", 48)
	damage_label.global_position = global_position + (DAMAGE_NUMBER_OFFSET * scale.x)
	get_tree().current_scene.add_child(damage_label)
	damage_label.global_position -= damage_label.size * 0.5

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "global_position", damage_label.global_position + Vector2(0, -90), 0.5)
	tween.tween_property(damage_label, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(damage_label.queue_free)

func grow_from_orb() -> void:
	growth_steps += 1
	apply_growth_scale()
	update_label_position()

func add_green_satellite() -> bool:
	cleanup_green_satellites()
	if green_satellites.size() >= MAX_GREEN_SATELLITES or get_tree().current_scene == null:
		return false

	var satellite = GREEN_SATELLITE_SCENE.instantiate()
	satellite.owner_player = self
	get_tree().current_scene.add_child(satellite)
	green_satellites.append(satellite)
	return true

func remove_green_satellite(satellite: Node) -> void:
	cleanup_green_satellites()
	green_satellites.erase(satellite)
	if is_instance_valid(satellite):
		satellite.queue_free()

func release_green_satellite(satellite: Node) -> void:
	cleanup_green_satellites()
	green_satellites.erase(satellite)

func clear_green_satellites() -> void:
	for satellite in green_satellites:
		if is_instance_valid(satellite):
			satellite.queue_free()
	green_satellites.clear()

func cleanup_green_satellites() -> void:
	for i in range(green_satellites.size() - 1, -1, -1):
		if !is_instance_valid(green_satellites[i]):
			green_satellites.remove_at(i)

func get_green_satellite_count() -> int:
	cleanup_green_satellites()
	return green_satellites.size()

func get_green_satellite_index(satellite: Node) -> int:
	cleanup_green_satellites()
	return green_satellites.find(satellite)

func get_attack_power() -> int:
	return attack

func fire_green_satellites(players: Array) -> void:
	cleanup_green_satellites()
	if green_satellites.is_empty() or !pending_satellite_volley.is_empty():
		return

	var nearest_enemy: Node2D = get_nearest_enemy_player(players)
	if nearest_enemy == null:
		return

	pending_satellite_volley = green_satellites.duplicate()
	satellite_volley_target = nearest_enemy
	satellite_volley_timer = 0.0

func get_nearest_enemy_player(players: Array) -> Node2D:
	var nearest_enemy: Node2D = null
	var nearest_distance := INF

	for candidate in players:
		var candidate_node := candidate as Node2D
		if candidate_node == null or candidate_node == self or !is_instance_valid(candidate_node):
			continue
		if candidate_node.has_method("take_damage"):
			var distance_to_candidate: float = global_position.distance_squared_to(candidate_node.global_position)
			if distance_to_candidate < nearest_distance:
				nearest_distance = distance_to_candidate
				nearest_enemy = candidate_node

	return nearest_enemy

func update_satellite_volley(delta: float) -> void:
	if pending_satellite_volley.is_empty():
		return

	if satellite_volley_target == null or !is_instance_valid(satellite_volley_target):
		pending_satellite_volley.clear()
		satellite_volley_target = null
		return

	satellite_volley_timer -= delta
	while satellite_volley_timer <= 0.0 and !pending_satellite_volley.is_empty():
		var satellite = pending_satellite_volley.pop_front()
		if is_instance_valid(satellite):
			satellite.call("launch_at", satellite_volley_target)
			play_satellite_fire_sound()

		if pending_satellite_volley.is_empty():
			satellite_volley_target = null
			satellite_volley_timer = 0.0
			break

		satellite_volley_timer += SATELLITE_VOLLEY_INTERVAL

func update_burn(delta: float) -> void:
	if !burn_active:
		return

	if growth_steps <= 0:
		set_burning(false)
		return

	burn_tick_timer -= delta
	while burn_tick_timer <= 0.0 and burn_active:
		apply_burn_tick()
		if growth_steps <= 0:
			set_burning(false)
			break
		burn_tick_timer += BURN_TICK_TIME

func apply_burn_tick() -> void:
	hp = max(hp - 1, 0)
	attack = max(attack - 1, 0)
	growth_steps = max(growth_steps - 1, 0)
	apply_growth_scale()
	update_label()

	if hp <= 0:
		die()

func apply_growth_scale() -> void:
	var growth_scale: float = pow(ORB_GROWTH_FACTOR, float(growth_steps))
	scale = Vector2.ONE * growth_scale

func kill_instantly() -> void:
	if !alive:
		return

	hp = 0
	update_label()
	die()

func update_model_visual() -> void:
	if burn_active:
		set_model_tint(MODEL_BURN_COLOR, 1.0)
	else:
		set_model_tint(MODEL_NORMAL_COLOR, 0.0)

func get_model_color() -> Color:
	if burn_active:
		return MODEL_BURN_COLOR
	return MODEL_NORMAL_COLOR

func setup_model_material() -> void:
	var shader := Shader.new()
	shader.code = MODEL_TINT_SHADER_CODE

	sprite_tint_material = ShaderMaterial.new()
	sprite_tint_material.shader = shader
	sprite.material = sprite_tint_material

func set_model_tint(color: Color, strength: float) -> void:
	if sprite_tint_material == null:
		return

	sprite_tint_material.set_shader_parameter("tint_color", color)
	sprite_tint_material.set_shader_parameter("tint_strength", strength)

func setup_burn_trail_material() -> void:
	var shader := Shader.new()
	shader.code = TRAIL_OUTLINE_SHADER_CODE

	burn_trail_material = ShaderMaterial.new()
	burn_trail_material.shader = shader

func setup_burn_audio() -> void:
	burn_audio_player = AudioStreamPlayer2D.new()
	burn_audio_player.top_level = true
	burn_audio_player.max_distance = 100000.0
	burn_audio_player.attenuation = 1.0
	burn_audio_player.volume_db = BURN_SOUND_VOLUME_DB

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = BURN_SOUND_MIX_RATE
	stream.buffer_length = BURN_SOUND_BUFFER_LENGTH
	burn_audio_player.stream = stream
	add_child(burn_audio_player)

func setup_damage_audio() -> void:
	damage_audio_player = AudioStreamPlayer2D.new()
	damage_audio_player.top_level = true
	damage_audio_player.max_distance = 100000.0
	damage_audio_player.attenuation = 1.0
	damage_audio_player.volume_db = DAMAGE_SOUND_VOLUME_DB

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = DAMAGE_SOUND_MIX_RATE
	stream.buffer_length = DAMAGE_SOUND_DURATION
	damage_audio_player.stream = stream
	add_child(damage_audio_player)

func update_burn_audio() -> void:
	if burn_audio_player == null:
		return

	burn_audio_player.global_position = global_position

	if burn_active:
		if !burn_audio_player.playing:
			burn_audio_player.play()
			burn_audio_playback = burn_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
		fill_burn_audio_buffer()
	else:
		stop_burn_audio()

func stop_burn_audio() -> void:
	if burn_audio_player == null or !burn_audio_player.playing:
		return

	burn_audio_player.stop()
	burn_audio_playback = null
	burn_audio_phase = 0.0
	burn_audio_noise_phase = 0.0

func fill_burn_audio_buffer() -> void:
	if burn_audio_playback == null:
		return

	var frames_available: int = burn_audio_playback.get_frames_available()
	for i in range(frames_available):
		var rumble_mod: float = sin(burn_audio_noise_phase * 0.4) * 0.5 + 0.5
		var sub_rumble: float = sin(burn_audio_phase * 0.34) * 0.2
		var engine_core: float = sin(burn_audio_phase) * 0.16
		var engine_harmonic: float = sin(burn_audio_phase * 1.48) * 0.09
		var pressure_wave: float = sin(burn_audio_phase * 0.18) * 0.08
		var turbulence: float = (randf() * 2.0 - 1.0) * (0.025 + (0.04 * rumble_mod))
		var sample: float = sub_rumble + engine_core + engine_harmonic + pressure_wave + turbulence
		burn_audio_playback.push_frame(Vector2(sample, sample))

		burn_audio_phase += TAU * 46.0 / BURN_SOUND_MIX_RATE
		burn_audio_noise_phase += TAU * 3.0 / BURN_SOUND_MIX_RATE

func play_damage_impact_sound() -> void:
	if damage_audio_player == null:
		return

	damage_audio_player.global_position = global_position
	damage_audio_player.play()
	damage_audio_playback = damage_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if damage_audio_playback == null:
		return

	var frame_count: int = int(DAMAGE_SOUND_MIX_RATE * DAMAGE_SOUND_DURATION)
	for i in range(frame_count):
		var t: float = float(i) / DAMAGE_SOUND_MIX_RATE
		var decay: float = exp(-7.5 * t)
		var low_sweep: float = 180.0 - (90.0 * (t / DAMAGE_SOUND_DURATION))
		var bass: float = sin(TAU * low_sweep * t) * 0.28 * decay
		var crunch: float = sin(TAU * 78.0 * t) * 0.16 * decay
		var grit: float = (randf() * 2.0 - 1.0) * 0.08 * decay
		var sample: float = bass + crunch + grit
		damage_audio_playback.push_frame(Vector2(sample, sample))

	var timer := get_tree().create_timer(DAMAGE_SOUND_DURATION + 0.03)
	timer.timeout.connect(_stop_damage_impact_sound)

func _stop_damage_impact_sound() -> void:
	if damage_audio_player != null:
		damage_audio_player.stop()
	damage_audio_playback = null

func spawn_burn_trail() -> void:
	if burn_trail_material == null or sprite.texture == null or get_tree().current_scene == null:
		return

	var trail := Sprite2D.new()
	trail.top_level = true
	trail.z_index = sprite.z_index - 1
	trail.texture = sprite.texture
	trail.centered = sprite.centered
	trail.offset = sprite.offset
	trail.flip_h = sprite.flip_h
	trail.flip_v = sprite.flip_v
	trail.material = burn_trail_material
	trail.global_position = sprite.global_position
	trail.global_rotation = sprite.global_rotation
	trail.scale = sprite.global_transform.get_scale()
	trail.modulate = Color(1.0, 1.0, 1.0, 0.9)

	get_tree().current_scene.add_child(trail)

	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, BURN_TRAIL_LIFETIME)
	tween.tween_callback(trail.queue_free)

func play_satellite_fire_sound() -> void:
	if get_tree().current_scene == null:
		return

	var player := AudioStreamPlayer2D.new()
	player.top_level = true
	player.global_position = global_position
	player.max_distance = 100000.0
	player.volume_db = SATELLITE_FIRE_SOUND_VOLUME_DB

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SATELLITE_FIRE_SOUND_MIX_RATE
	stream.buffer_length = SATELLITE_FIRE_SOUND_DURATION
	player.stream = stream
	get_tree().current_scene.add_child(player)
	player.play()

	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return

	var frame_count: int = int(SATELLITE_FIRE_SOUND_MIX_RATE * SATELLITE_FIRE_SOUND_DURATION)
	for i in range(frame_count):
		var t: float = float(i) / SATELLITE_FIRE_SOUND_MIX_RATE
		var decay: float = exp(-12.0 * t)
		var sweep := 1400.0 - (900.0 * (t / SATELLITE_FIRE_SOUND_DURATION))
		var core: float = sin(TAU * sweep * t) * 0.24 * decay
		var sparkle: float = sin(TAU * (sweep * 1.8) * t) * 0.08 * decay
		var sample: float = core + sparkle
		playback.push_frame(Vector2(sample, sample))

	var timer := get_tree().create_timer(SATELLITE_FIRE_SOUND_DURATION + 0.03)
	timer.timeout.connect(player.queue_free)
