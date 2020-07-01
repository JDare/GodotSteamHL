extends Node

signal peer_status_updated(steam_id)

enum PACKET_TYPE { HANDSHAKE = 1, HANDSHAKE_REPLY = 2, PEER_STATE = 3 }

var _peers = {}
var _my_steam_id := 0

func _ready():
	# This requires SteamLobby to be configured as an autoload/dependency.
	SteamLobby.connect("player_joined_lobby", self, "_init_p2p_session")
	SteamLobby.connect("player_left_lobby", self, "_close_p2p_session")
	
	SteamLobby.connect("lobby_created", self, "_init_p2p_host")
	
	Steam.connect("p2p_session_request", self, "_on_p2p_session_request")
	Steam.connect("p2p_session_connect_fail", self, "_on_p2p_session_connect_fail")
	
	_my_steam_id = Steam.getSteamID()

func _process(delta):
	# Ensure that Steam.run_callbacks() is being called somewhere in a _process()
	_read_p2p_packet()

func is_peer_connected(steam_id):
	if _peers.has(steam_id):
		return _peers[steam_id].connected
	else:
		print("Tried to get status of non-existent peer: %s" % steam_id)
		return null

func get_peer(steam_id) -> Peer:
	if _peers.has(steam_id):
		return _peers[steam_id]
	else:
		print("Tried to get non-existent peer: %s" % steam_id)
		return null

func is_server() -> bool:
	return _peers[_my_steam_id].host

func _init_p2p_host(lobby_id):
	print("Initializing P2P Host as %s" % _my_steam_id)
	var host_peer = Peer.new()
	host_peer.steam_id = _my_steam_id
	host_peer.host = true
	host_peer.connected = true
	_peers[_my_steam_id] = host_peer

func _init_p2p_session(steam_id):
	print("Initializing P2P Session with %s" % steam_id)
	_peers[steam_id] = Peer.new()
	_peers[steam_id].steam_id = steam_id
	_send_p2p_command_packet(steam_id, PACKET_TYPE.HANDSHAKE)

func _close_p2p_session(steam_id):
	var session_state = Steam.getP2PSessionState(steam_id)
	if session_state.has("connection_active") and session_state["connection_active"]:
		Steam.closeP2PSessionWithUser(steam_id)
	if _peers.has(steam_id):
		_peers.erase(steam_id)
	_send_peer_state()

func _send_p2p_command_packet(steam_id, packet_type: int):
	var payload = PoolByteArray()
	payload.append(packet_type)
	if not _send_p2p_packet(steam_id, payload):
		push_error("Failed to send command packet %s" % packet_type)

func _send_p2p_packet(steam_id, data: PoolByteArray, send_type: int = Steam.P2P_SEND_RELIABLE, channel: int = 0) -> bool:
	return Steam.sendP2PPacket(steam_id, data, send_type, channel)

func _broadcast_p2p_packet(data: PoolByteArray, send_type: int = Steam.P2P_SEND_RELIABLE, channel: int = 0):
	print("Broadcast:", data)
	for peer_id in _peers:
		if peer_id != _my_steam_id:
			_send_p2p_packet(peer_id, data, send_type, channel)

func _read_p2p_packet():
	var packet_size = Steam.getAvailableP2PPacketSize(0)

	# There is a packet
	if packet_size > 0:
		
		# Packet is a Dict which contains {"data": PoolByteArray, "steamIDRemote": CSteamID}
		var packet = Steam.readP2PPacket(packet_size, 0)
		
		# or empty if it fails
		if packet.empty():
			push_warning("Steam Networking: read an empty packet with non-zero size!")

		# Get the remote user's ID
		var sender_id: int = packet["steamIDRemote"]
		var packet_data: PoolByteArray = packet["data"]

		_handle_packet(sender_id, packet_data)
#		var readable = bytes2var(packet.data.subarray(1, packet_size - 1))

func _confirm_peer(steam_id):
	if not _peers.has(steam_id):
		push_error("Cannot confirm peer %s as they do not exist locally!" % steam_id)
		return
	
	print("Peer Confirmed %s" % steam_id)
	_peers[steam_id].connected = true
	emit_signal("peer_status_updated", steam_id)
	_send_peer_state()
	
func _send_peer_state():
	print("Sending Peer State")
	var peers = []
	for peer in _peers.values():
		prints(peer.steam_id, peer.connected, peer.host)
		peers.append(peer.serialize())
	var payload = PoolByteArray()
	# add packet type header
	payload.append(PACKET_TYPE.PEER_STATE)
	# add peer data
	payload.append_array(var2bytes(peers))
	
	_broadcast_p2p_packet(payload)

func _update_peer_state(payload: PoolByteArray):
	print("Updating Peer State")
	var serialized_peers = bytes2var(payload)
	var new_peers = []
	for serialized_peer in serialized_peers:
		var peer = Peer.new()
		peer.deserialize(serialized_peer)
		prints(peer.steam_id, peer.connected, peer.host)
		if not _peers.has(peer.steam_id) or not peer.eq(_peers[peer.steam_id]):
			_peers[peer.steam_id] = peer
			emit_signal("peer_status_updated", peer.steam_id)
		new_peers.append(peer.steam_id)
	for peer_id in _peers.keys():
		if not peer_id in new_peers:
			_peers.erase(peer_id)
			emit_signal("peer_status_updated", peer_id)
			

func _handle_packet(sender_id, payload: PoolByteArray):
	if payload.size() == 0:
		push_error("Cannot handle an empty packet payload!")
		return
	var packet_type = payload[0]
	print("Received packet %s from %s" % [packet_type, sender_id])
	var packet_data = null
	if payload.size() > 1:
		packet_data = payload.subarray(1, payload.size()-1)
	match packet_type:
		PACKET_TYPE.HANDSHAKE:
			_send_p2p_command_packet(sender_id, PACKET_TYPE.HANDSHAKE_REPLY)
		PACKET_TYPE.HANDSHAKE_REPLY:
			_confirm_peer(sender_id)
		PACKET_TYPE.PEER_STATE:
			_update_peer_state(packet_data)

func _on_p2p_session_connect_fail(lobby_id: int, session_error):
	# If no error was given
	match session_error:
		Steam.P2P_SESSION_ERROR_NONE:
			push_warning("Session failure with "+str(lobby_id)+" [no error given].")
		Steam.P2P_SESSION_ERROR_NOT_RUNNING_APP:
			push_warning("Session failure with "+str(lobby_id)+" [target user not running the same game].")
		Steam.P2P_SESSION_ERROR_NO_RIGHTS_TO_APP:
			push_warning("Session failure with "+str(lobby_id)+" [local user doesn't own app / game].")
		Steam.P2P_SESSION_ERROR_DESTINATION_NOT_LOGGED_ON:
			push_warning("Session failure with "+str(lobby_id)+" [target user isn't connected to Steam].")
		Steam.P2P_SESSION_ERROR_TIMEOUT:
			push_warning("Session failure with "+str(lobby_id)+" [connection timed out].")
		Steam.P2P_SESSION_ERROR_MAX:
			push_warning("Session failure with "+str(lobby_id)+" [unused].")
		_:
			push_warning("Session failure with "+str(lobby_id)+" [unknown error "+str(session_error)+"].")
	
func _on_p2p_session_request(remote_steam_id):
	print("Received p2p session request from %s" % remote_steam_id)
	# Get the requester's name
	var requestor = Steam.getFriendPersonaName(remote_steam_id)
	
	# Accept the P2P session; can apply logic to deny this request if needed
	Steam.acceptP2PSessionWithUser(remote_steam_id)
	
	# Make the initial handshake
	_send_p2p_command_packet(remote_steam_id, PACKET_TYPE.HANDSHAKE_REPLY)

class Peer:
	var connected := false
	var host := false
	
	var steam_id: int
	
	func serialize() -> PoolByteArray:
		var data = [steam_id, connected, host]
		return var2bytes(data)

	func deserialize(data: PoolByteArray):
		var unpacked = bytes2var(data)
		steam_id = unpacked[0]
		connected = unpacked[1]
		host = unpacked[2]
		
	func eq(peer: Peer):
		return peer.steam_id == steam_id and \
				peer.host == host and \
				peer.connected == connected
	
