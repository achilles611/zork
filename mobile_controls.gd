extends Control

signal dash_requested

const JOYSTICK_RADIUS := 128.0
const MOUSE_TOUCH_ID := -999
const JOYSTICK_MARGIN := 56.0
const BUTTON_GROUP_MARGIN_X := 40.0
const BUTTON_GROUP_MARGIN_Y := 118.0
const BUTTON_GROUP_SIZE := Vector2(420.0, 500.0)

var move_vector: Vector2 = Vector2.ZERO
var joystick_touch_id := -1

@onready var joystick_area = $JoystickArea
@onready var joystick_base = $JoystickArea/JoystickBase
@onready var joystick_knob = $JoystickArea/JoystickBase/JoystickKnob
@onready var dash_button = $Buttons/BurnButton
@onready var rotate_button = $Buttons/FireButton

func _ready() -> void:
	set_process_input(false)
	get_viewport().size_changed.connect(_layout_controls)
	dash_button.pressed.connect(_on_dash_button_pressed)
	rotate_button.visible = false
	_layout_controls()
	reset_joystick()

func set_controls_active(active: bool) -> void:
	visible = active
	set_process_input(active)
	if !active:
		reset_joystick()

func get_move_vector() -> Vector2:
	return move_vector

func _on_dash_button_pressed() -> void:
	dash_requested.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if joystick_touch_id == -1 and is_inside_joystick_activation_area(event.position):
				joystick_touch_id = event.index
				anchor_joystick_to_touch(event.position)
				update_joystick(event.position)
				get_viewport().set_input_as_handled()
			elif dash_button.get_global_rect().has_point(event.position):
				dash_requested.emit()
				get_viewport().set_input_as_handled()
		else:
			if event.index == joystick_touch_id:
				reset_joystick()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == joystick_touch_id:
			update_joystick(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_inside_joystick_activation_area(event.position):
			joystick_touch_id = MOUSE_TOUCH_ID
			anchor_joystick_to_touch(event.position)
			update_joystick(event.position)
		elif !event.pressed and joystick_touch_id == MOUSE_TOUCH_ID:
			reset_joystick()
	elif event is InputEventMouseMotion and joystick_touch_id == MOUSE_TOUCH_ID and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		update_joystick(event.position)

func _layout_controls() -> void:
	var viewport_size := get_viewport_rect().size
	joystick_area.position = Vector2(JOYSTICK_MARGIN, viewport_size.y - joystick_area.size.y - JOYSTICK_MARGIN)
	$Buttons.position = viewport_size - BUTTON_GROUP_SIZE - Vector2(BUTTON_GROUP_MARGIN_X, BUTTON_GROUP_MARGIN_Y)
	dash_button.position = Vector2(188.0, 208.0)

func is_inside_joystick_activation_area(global_position: Vector2) -> bool:
	return !dash_button.get_global_rect().has_point(global_position)

func anchor_joystick_to_touch(global_position: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	var desired_position: Vector2 = global_position - (joystick_area.size * 0.5)
	var max_position: Vector2 = viewport_size - joystick_area.size
	joystick_area.position = Vector2(
		clampf(desired_position.x, 0.0, max_position.x),
		clampf(desired_position.y, 0.0, max_position.y)
	)

func update_joystick(global_position: Vector2) -> void:
	var center := get_joystick_center()
	var offset := global_position - center
	if offset.length() > JOYSTICK_RADIUS:
		offset = offset.normalized() * JOYSTICK_RADIUS

	move_vector = offset / JOYSTICK_RADIUS
	joystick_knob.position = (joystick_base.size - joystick_knob.size) * 0.5 + offset

func reset_joystick() -> void:
	joystick_touch_id = -1
	move_vector = Vector2.ZERO
	joystick_knob.position = (joystick_base.size - joystick_knob.size) * 0.5

func get_joystick_center() -> Vector2:
	return joystick_base.global_position + (joystick_base.size * 0.5)
