extends Node
## Asks the relay server (addresses in the key file's RELAY list) which games are open.
## Tries each address in turn (the LAN name at home, the public IP elsewhere); the first that
## answers wins, so the join addresses it returns are ones this computer can reach.

const NetSession = preload("res://scripts/net/net_session.gd")
const WAIT := 1.5  # seconds per relay address


## [{"address": "ip:port", "players": int}], or empty if no game is open or no relay answers.
## `reached` is set to whether any relay answered at all.
var reached := false


func find() -> Array:
	reached = false
	var k = NetSession.keys()
	var servers: Array = k.get_script_constant_map().get("RELAY", []) if k else []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--relay="):
			servers = [arg.trim_prefix("--relay=")]  # test: a relay on this PC
	for name in servers:
		var ip: String = name if name.is_valid_ip_address() else IP.resolve_hostname(name, IP.TYPE_IPV4)
		if ip == "":
			continue
		var udp := PacketPeerUDP.new()
		if udp.connect_to_host(ip, NetSession.RELAY_PORT) != OK:
			continue
		udp.put_packet("MSR1L".to_ascii_buffer())
		var t := 0.0
		while t < WAIT:
			await get_tree().process_frame
			t += get_process_delta_time()
			if udp.get_available_packet_count() == 0:
				continue
			var pkt := udp.get_packet()
			if pkt.slice(0, 5).get_string_from_ascii() != "MSR1R":
				continue
			udp.close()
			reached = true
			var games = JSON.parse_string(pkt.slice(5).get_string_from_utf8())
			var out: Array = []
			if games is Array:
				for g in games:
					out.append({"address": "%s:%d" % [ip, int(g.get("port", 0))],
						"players": int(g.get("players", 1))})
			return out
		udp.close()
	return []
