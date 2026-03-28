extends Node

signal connection_state_changed(state: String)
signal connected_to_server()
signal disconnected_from_server()
signal welcome_received(payload: Dictionary)
signal lobby_state_received(payload: Dictionary)
signal match_started(payload: Dictionary)
signal round_snapshot_received(payload: Dictionary)
signal remote_input_received(payload: Dictionary)
signal server_message(message_type: String, payload: Dictionary)

const SERVER_PORT := 8765

var socket := WebSocketPeer.new()
var is_connected := false
var client_id := ""
var host_client_id := ""
var last_lobby_state: Dictionary = {}
var server_url := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if !is_connected:
			is_connected = true
			connection_state_changed.emit("connected")
			connected_to_server.emit()
		_read_messages()
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			connection_state_changed.emit("disconnected")
			disconnected_from_server.emit()

func connect_to_default_server() -> void:
	connect_to_server(_build_default_url())

func connect_to_server(url: String) -> void:
	server_url = url
	socket = WebSocketPeer.new()
	var error := socket.connect_to_url(server_url)
	if error != OK:
		connection_state_changed.emit("error")

func disconnect_from_server() -> void:
	socket.close()
	is_connected = false

func send_message(message_type: String, payload: Dictionary = {}) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var message := {
		"type": message_type,
		"payload": payload,
	}
	socket.send_text(JSON.stringify(message))

func _read_messages() -> void:
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(packet)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var message_type := str(parsed.get("type", ""))
		var payload: Dictionary = {}
		var parsed_payload = parsed.get("payload", {})
		if typeof(parsed_payload) == TYPE_DICTIONARY:
			payload = parsed_payload
		server_message.emit(message_type, payload)
		match message_type:
			"welcome":
				client_id = str(payload.get("client_id", ""))
				host_client_id = str(payload.get("host_client_id", ""))
				welcome_received.emit(payload)
			"lobby_state":
				last_lobby_state = payload.duplicate(true)
				host_client_id = str(payload.get("host_client_id", host_client_id))
				lobby_state_received.emit(payload)
			"match_started":
				match_started.emit(payload)
			"round_snapshot":
				round_snapshot_received.emit(payload)
			"remote_input":
				remote_input_received.emit(payload)

func _build_default_url() -> String:
	var host := "127.0.0.1"
	if OS.has_feature("web") and typeof(JavaScriptBridge) != TYPE_NIL:
		host = str(JavaScriptBridge.eval("window.location.hostname", true))
	return "wss://%s:%d" % [host, SERVER_PORT]
