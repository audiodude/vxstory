extends Node
# Bidirectional localhost UDP transport bus between the Designer and the preview.
# Role-based fixed port pair. Sends {t, playing} on transport events; emits
# `remote(t, playing)` on receive. process_mode ALWAYS so it keeps polling even
# when the sim is paused via Engine.time_scale.

signal remote(t: float, playing: bool)

const BASE_PORT := 47615

var _udp := PacketPeerUDP.new()
var _ok := false

func setup(role: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ports := ports_for(role)
	var err := _udp.bind(int(ports["listen"]), "127.0.0.1")
	if err != OK:
		push_warning("transport_link: bind %d failed (role %s); sync disabled" % [ports["listen"], role])
		return
	_udp.set_dest_address("127.0.0.1", int(ports["send"]))
	_ok = true

static func ports_for(role: String) -> Dictionary:
	if role == "designer":
		return {"listen": BASE_PORT, "send": BASE_PORT + 1}
	return {"listen": BASE_PORT + 1, "send": BASE_PORT}

static func encode(t: float, playing: bool) -> PackedByteArray:
	return JSON.stringify({"t": t, "playing": playing}).to_utf8_buffer()

static func decode(bytes: PackedByteArray):
	var d = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY or not d.has("t"):
		return null
	return {"t": float(d["t"]), "playing": bool(d.get("playing", false))}

func send(t: float, playing: bool) -> void:
	if _ok:
		_udp.put_packet(encode(t, playing))

func _process(_delta: float) -> void:
	if not _ok:
		return
	while _udp.get_available_packet_count() > 0:
		var d = decode(_udp.get_packet())
		if d != null:
			remote.emit(d["t"], d["playing"])
