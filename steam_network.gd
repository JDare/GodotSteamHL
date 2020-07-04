extends Node

signal peer_status_updated(steam_id)
signal peer_session_failure(steam_id, reason)

enum PACKET_TYPE { HANDSHAKE = 1, HANDSHAKE_REPLY = 2, PEER_STATE = 3, NODE_PATH_UPDATE = 4, NODE_PATH_CONFIRM = 5, RPC = 6, RPC_WITH_NODE_PATH = 7, RSET = 8, RSET_WITH_NODE_PATH = 9 }

enum PERMISSION {SERVER, CLIENT_ALL}

var _peers = {}
var _my_steam_id := 0
var _server_steam_id := 0
var _node_path_cache = {}

var _peers_confirmed_node_path = {}
var _next_path_cache_index := 0

var _permissions = {}

func _ready():
	# This requires SteamLobby to be configured as an autoload/dependency.
	SteamLobby.connect("player_joined_lobby", self, "_init_p2p_session")
	SteamLobby.connect("player_left_lobby", self, "_close_p2p_session")
	
	SteamLobby.connect("lobby_created", self, "_init_p2p_host")
	SteamLobby.connect("lobby_owner_changed", self, "_migrate_host")
	
	Steam.connect("p2p_session_request", self, "_on_p2p_session_request")
	Steam.connect("p2p_session_connect_fail", self, "_on_p2p_session_connect_fail")
	
	_my_steam_id = Steam.getSteamID()

func _process(delta):
	# Ensure that Steam.run_callbacks() is being called somewhere in a _process()
	_read_p2p_packet()

func register_rset(caller: Node, property: String, permission: int):
	var node_path = _get_rset_property_path(caller.get_path(), property)
	var perm_hash = _get_permission_hash(node_path)
	_permissions[perm_hash] = permission
	
func register_rpc(caller: Node, method: String, permission: int):
	var perm_hash = _get_permission_hash(caller.get_path(), method)
	_permissions[perm_hash] = permission
	
func register_rpcs(caller: Node, methods: Array):
	for method in methods:
		method.push_front(caller)
		callv("register_rpc", method)

# CLIENTS AND SERVER
# Calls this method on the server
func rpc_on_server(caller: Node, method: String, args: Array = []):
	_rpc(get_server_steam_id(), caller, method, args)

# SERVER ONLY
# Calls this method on the client specified
func rpc_on_client(to_peer_id: int, caller: Node, method: String, args: Array = []):
	if not is_server():
		push_warning("Tried to call RPC on client: %s %s" % [caller, method])
		return
	_rpc(to_peer_id, caller, method, args)

# SERVER ONLY
# Calls this method on ALL clients connected
func rpc_all_clients(caller: Node, method: String, args: Array = []):
	for peer_id in _peers:
		rpc_on_client(peer_id, caller, method, args)

# SERVER ONLY (OWNERSHIP TBD)
func remote_set(caller: Node, property: String, value):
	# probably need to check basic ownership here, but for now its server only
	for peer in _peers.values(): 
		_rset(peer, caller, property, value)

# Returns whether a peer is connected or not.
func is_peer_connected(steam_id) -> bool:
	if _peers.has(steam_id):
		return _peers[steam_id].connected
	else:
		print("Tried to get status of non-existent peer: %s" % steam_id)
		return false

# Returns a peer object for a given users steam_id
func get_peer(steam_id) -> Peer:
	if _peers.has(steam_id):
		return _peers[steam_id]
	else:
		print("Tried to get non-existent peer: %s" % steam_id)
		return null

# Returns the dictionary of all peers
func get_peers() -> Dictionary:
	return _peers

# Returns whether this peer is the server or not
func is_server() -> bool:
	if not _peers.has(_my_steam_id):
		return false
	return _peers[_my_steam_id].host

# Gets the peer object of the server connection
func get_server_peer() -> Peer:
	return get_peer(get_server_steam_id())

# Gets the server users steam id
func get_server_steam_id() -> int:
	if _server_steam_id > 0:
		return _server_steam_id
	for peer in _peers.values():
		if peer.host:
			_server_steam_id = peer.steam_id
			return _server_steam_id
	return -1

# Returns whether all peers are connected or not.
func peers_connected() -> bool:
	for peer_id in _peers:
		if _peers[peer_id].connected == false:
			return false
	return true

func _get_permission_hash(node_path: NodePath, value: String = ""):
	if value.empty():
		return str(node_path).md5_text()
	return (str(node_path) + value).md5_text()

func _sender_has_permission(sender_id: int, node_path: NodePath, method: String = "") -> bool:
	var perm_hash = _get_permission_hash(node_path, method)
	if not _permissions.has(perm_hash):
		return false
	var permission = _permissions[perm_hash]
	match permission:
		PERMISSION.SERVER:
			return sender_id == get_server_steam_id()
		PERMISSION.CLIENT_ALL:
			return true
	return false

func _migrate_host(old_owner_id, new_owner_id):
	var old_peer = get_peer(old_owner_id)
	if old_peer != null:
		old_peer.host = false
	
	Steam.closeP2PSessionWithUser(old_owner_id)
	
	_server_steam_id = 0
	
	_node_path_cache.clear()
	_next_path_cache_index = 0
	
	_peers.clear()
	for steam_id in SteamLobby.get_lobby_members():
		var p = _create_peer(steam_id)
		_peers[steam_id] = p
	
	var new_owner = get_peer(new_owner_id)
	if new_owner != null:
		new_owner.host = true
	else:
		push_error("Error migrating host, no new host was found!")
		return
	
	if is_server():
		for steam_id in _peers:
			if steam_id != _my_steam_id:
				_init_p2p_session(steam_id)
			else:
				_peers[steam_id].connected = true
			

func _rpc(to_peer_id: int, node: Node, method: String, args: Array):
	var peer = get_peer(to_peer_id)
	if to_peer == null:
		push_warning("Cannot send an RPC to a null peer. Check youre completed connected to the network first")
		return
	#check we are connected first
	if not is_peer_connected(_my_steam_id):
		push_warning("Cannot send an RPC when not connected to the network")
		return
		
	if not is_peer_connected(to_peer.steam_id):
		push_warning("Cannot send an RPC to someone who is not connected to the network!")
		return
	
	var node_path = node.get_path()
	var path_cache_index = _get_path_cache(node_path)
	if path_cache_index == -1 and is_server():
		path_cache_index = _add_node_path_cache(node_path)
	
	if to_peer.steam_id == _my_steam_id and is_server():
		# we can skip sending to network and run locally
		_execute_rpc(to_peer, path_cache_index, method, args.duplicate())
		return
	
	if to_peer.steam_id == _my_steam_id:
		push_warning("Client tried to send self an RPC request!")
	
	var packet = PoolByteArray()
	var payload = [path_cache_index, method, args]
	
	if is_server() and not _peer_confirmed_path(to_peer, node_path) or \
		path_cache_index == -1:
		payload.push_front(node_path)
		packet.append(PACKET_TYPE.RPC_WITH_NODE_PATH)
	else:
		packet.append(PACKET_TYPE.RPC)
	
	var serialized_payload = var2bytes(payload)
	
	packet.append_array(serialized_payload)
	_send_p2p_packet(to_peer.steam_id, packet)

func _rset(to_peer: Peer, node: Node, property: String, value):
	var node_path = _get_rset_property_path(node.get_path(), property)
	var path_cache_index = _get_path_cache(node_path)
	if path_cache_index == -1 and is_server():
		path_cache_index = _add_node_path_cache(node_path)
	
	if to_peer.steam_id == _my_steam_id and is_server():
		# we can skip sending to network and run locally
		_execute_rset(to_peer, path_cache_index, value)
		return
	
	var packet = PoolByteArray()
	var payload = [path_cache_index, value]
	if is_server() and not _peer_confirmed_path(to_peer, node_path) or \
		path_cache_index == -1:
		payload.push_front(node_path)
		packet.append(PACKET_TYPE.RSET_WITH_NODE_PATH)
	else:
		packet.append(PACKET_TYPE.RSET)
	
	var serialized_payload = var2bytes(payload)
	packet.append_array(serialized_payload)
	_send_p2p_packet(to_peer.steam_id, packet)

func _get_rset_property_path(node_path: NodePath, property: String):
	return NodePath("%s:%s" % [node_path, property])

func _peer_confirmed_path(peer: Peer, node_path: NodePath):
	var path_cache_index = _get_path_cache(node_path)
	return path_cache_index in _peers_confirmed_node_path[peer.steam_id]

func _server_update_node_path_cache(peer_id: int, node_path: NodePath):
	if not is_server():
		return
	var path_cache_index = _get_path_cache(node_path)
	if path_cache_index == -1:
		path_cache_index = _add_node_path_cache(node_path)
	var packet = PoolByteArray()
	var payload = var2bytes([path_cache_index, node_path])
	packet.append_array(payload)
	_send_p2p_packet(peer_id, packet)

func _update_node_path_cache(sender_id: int, packet_data: PoolByteArray):
	if sender_id != get_server_steam_id():
		return
	var data = bytes2var(packet_data)
	var path_cache_index = data[0]
	var node_path = data[1]
	_add_node_path_cache(node_path, path_cache_index)
	_send_p2p_command_packet(get_server_steam_id(), PACKET_TYPE.NODE_PATH_CONFIRM, path_cache_index)

func _server_confirm_peer_node_path(peer_id, path_cache_index: int):
	if not is_server():
		return
	_peers_confirmed_node_path[peer_id].append(path_cache_index)

func _add_node_path_cache(node_path: NodePath, path_cache_index: int = -1) -> int:
	var already_exists_id = _get_path_cache(node_path)
	if already_exists_id != -1 and already_exists_id == path_cache_index:
		return already_exists_id
	
	if path_cache_index == -1:
		_next_path_cache_index += 1
		path_cache_index = _next_path_cache_index
	_node_path_cache[path_cache_index] = node_path
	
	return path_cache_index

func _get_node_path(path_cache_index: int) -> NodePath:
	return _node_path_cache.get(path_cache_index)

func _get_path_cache(node_path: NodePath) -> int:
	for path_cache_index in _node_path_cache:
		if _node_path_cache[path_cache_index] == node_path:
			return path_cache_index
	return -1

func _create_peer(steam_id):
	var peer = Peer.new()
	peer.steam_id = steam_id
	_peers_confirmed_node_path[steam_id] = []
	return peer

func _init_p2p_host(lobby_id):
	print("Initializing P2P Host as %s" % _my_steam_id)
	var host_peer = _create_peer(_my_steam_id)
	host_peer.host = true
	host_peer.connected = true
	_peers[_my_steam_id] = host_peer

func _init_p2p_session(steam_id):
	if not is_server():
		# only server should be initializing p2p requests.
		return
	print("Initializing P2P Session with %s" % steam_id)
	_peers[steam_id] = _create_peer(steam_id)
	_send_p2p_command_packet(steam_id, PACKET_TYPE.HANDSHAKE)

func _close_p2p_session(steam_id):
	if steam_id == _my_steam_id:
		Steam.closeP2PSessionWithUser(_server_steam_id)
		_server_steam_id = 0
		_peers.clear()
		return
	
	print("Closing P2P Session with %s" % steam_id)
	var session_state = Steam.getP2PSessionState(steam_id)
	if session_state.has("connection_active") and session_state["connection_active"]:
		Steam.closeP2PSessionWithUser(steam_id)
	if _peers.has(steam_id):
		_peers.erase(steam_id)
	_server_send_peer_state()

func _send_p2p_command_packet(steam_id, packet_type: int, arg = null):
	var payload = PoolByteArray()
	payload.append(packet_type)
	if arg != null:
		payload.append_array(var2bytes(arg))
	if not _send_p2p_packet(steam_id, payload):
		push_error("Failed to send command packet %s" % packet_type)

func _send_p2p_packet(steam_id, data: PoolByteArray, send_type: int = Steam.P2P_SEND_RELIABLE, channel: int = 0) -> bool:
	return Steam.sendP2PPacket(steam_id, data, send_type, channel)

func _broadcast_p2p_packet(data: PoolByteArray, send_type: int = Steam.P2P_SEND_RELIABLE, channel: int = 0):
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

func _confirm_peer(steam_id):
	if not _peers.has(steam_id):
		push_error("Cannot confirm peer %s as they do not exist locally!" % steam_id)
		return
	
	print("Peer Confirmed %s" % steam_id)
	_peers[steam_id].connected = true
	emit_signal("peer_status_updated", steam_id)
	_server_send_peer_state()
	
func _server_send_peer_state():
	print("Sending Peer State")
	var peers = []
	for peer in _peers.values():
		peers.append(peer.serialize())
	var payload = PoolByteArray()
	# add packet type header
	payload.append(PACKET_TYPE.PEER_STATE)
	# add peer data
	payload.append_array(var2bytes(peers))
	
	_broadcast_p2p_packet(payload)

func _update_peer_state(payload: PoolByteArray):
	if is_server():
		return
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
		PACKET_TYPE.NODE_PATH_CONFIRM:
			_server_confirm_peer_node_path(sender_id, bytes2var(packet_data))
		PACKET_TYPE.NODE_PATH_UPDATE:
			_update_node_path_cache(sender_id, packet_data)
		PACKET_TYPE.RPC_WITH_NODE_PATH:
			_handle_rpc_packet_with_path(sender_id, packet_data)
		PACKET_TYPE.RPC:
			_handle_rpc_packet(sender_id, packet_data)
		PACKET_TYPE.RSET_WITH_NODE_PATH:
			_handle_rset_packet_with_path(sender_id, packet_data)
		PACKET_TYPE.RSET:
			handle_rset_packet(sender_id, packet_data)

func _handle_rset_packet_with_path(sender_id: int, payload: PoolByteArray):
	var peer = get_peer(sender_id)
	var data = bytes2var(payload)
	
	var node_path = data[0]
	var path_cache_index = data[1]
	var value = data[2]
	if is_server():
		# send rpc path + cache num to this client
		path_cache_index = _get_path_cache(node_path)
		#if this path cache doesnt exist yet, lets create it now and send to client
		if path_cache_index == -1:
			path_cache_index = _add_node_path_cache(node_path)
		_server_update_node_path_cache(sender_id, node_path)
	else:
		_add_node_path_cache(node_path, path_cache_index)
		_send_p2p_command_packet(sender_id, PACKET_TYPE.NODE_PATH_CONFIRM, path_cache_index)
	_execute_rset(peer, path_cache_index, value)

func handle_rset_packet(sender_id: int, payload: PoolByteArray):
	var peer = get_peer(sender_id)
	var data = bytes2var(payload)

	var path_cache_index = data[0]
	var value = data[1]
	
	_execute_rset(peer, path_cache_index, value)
	
func _execute_rset(sender: Peer, path_cache_index: int, value):
	var node_path = _get_node_path(path_cache_index)
	if node_path == null:
		push_error("NodePath index %s does not exist on this client! Cannot complete RemoteSet" % path_cache_index)
		return
	if not _sender_has_permission(sender.steam_id, node_path):
		push_error("Sender does not have permission to execute remote set %s on node %s" % [value, node_path])
		return
	var node = get_node_or_null(node_path)
	if node == null:
		push_error("Node %s does not exist on this client! Cannot complete RemoteSet" % node_path)
		return
	var property:String = node_path.get_subname(0)
	if property == null or property.empty():
		push_error("Node %s could not resolve to a property. Cannot complete RemoteSet" % node_path)
		return
	
	node.set(property, value)

func _handle_rpc_packet_with_path(sender_id: int, payload: PoolByteArray):
	var peer = get_peer(sender_id)
	var data = bytes2var(payload)
	
	var path_cache_index = data[1]
	var node_path = data[0]
	var method = data[2]
	var args = data[3]
	if is_server():
		# send rpc path + cache num to this client
		path_cache_index = _get_path_cache(node_path)
		#if this path cache doesnt exist yet, lets create it now and send to client
		if path_cache_index == -1:
			path_cache_index = _add_node_path_cache(node_path)
		_server_update_node_path_cache(sender_id, node_path)
	else:
		_add_node_path_cache(node_path, path_cache_index)
		_send_p2p_command_packet(sender_id, PACKET_TYPE.NODE_PATH_CONFIRM, path_cache_index)
	_execute_rpc(peer, path_cache_index, method, args)

func _handle_rpc_packet(sender_id: int, payload: PoolByteArray):
	var peer = get_peer(sender_id)
	var data = bytes2var(payload)
	var path_cache_index = data[0]
	var method = data[1]
	var args = data[2]
	_execute_rpc(peer, path_cache_index, method, args)

func _execute_rpc(sender: Peer, path_cache_index: int, method: String, args: Array):
	var node_path = _get_node_path(path_cache_index)
	if node_path == null:
		push_error("NodePath index %s does not exist on this client! Cannot call RPC" % path_cache_index)
		return
	
	if not _sender_has_permission(sender.steam_id, node_path, method):
		push_error("Sender does not have permission to execute method %s on node %s" % [method, node_path])
		return
	
	var node = get_node_or_null(node_path)
	if node == null:
		push_error("Node %s does not exist on this client! Cannot call RPC" % node_path)
		return
	if not node.has_method(method):
		push_error("Node %s does not have a method %s" % [node.name, method])
		return
	
	
	args.push_front(sender.steam_id)
	node.callv(method, args)

func _on_p2p_session_connect_fail(steam_id: int, session_error):
	# If no error was given
	match session_error:
		Steam.P2P_SESSION_ERROR_NONE:
			push_warning("Session failure with "+str(steam_id)+" [no error given].")
		Steam.P2P_SESSION_ERROR_NOT_RUNNING_APP:
			push_warning("Session failure with "+str(steam_id)+" [target user not running the same game].")
		Steam.P2P_SESSION_ERROR_NO_RIGHTS_TO_APP:
			push_warning("Session failure with "+str(steam_id)+" [local user doesn't own app / game].")
		Steam.P2P_SESSION_ERROR_DESTINATION_NOT_LOGGED_ON:
			push_warning("Session failure with "+str(steam_id)+" [target user isn't connected to Steam].")
		Steam.P2P_SESSION_ERROR_TIMEOUT:
			push_warning("Session failure with "+str(steam_id)+" [connection timed out].")
		Steam.P2P_SESSION_ERROR_MAX:
			push_warning("Session failure with "+str(steam_id)+" [unused].")
		_:
			push_warning("Session failure with "+str(steam_id)+" [unknown error "+str(session_error)+"].")
	
	emit_signal("peer_session_failure", steam_id, session_error)
	if steam_id in _peers:
		_peers[steam_id].connected = false
		_server_send_peer_state()

func _on_p2p_session_request(remote_steam_id):
	print("Received p2p session request from %s" % remote_steam_id)
	# Get the requester's name
	var requestor = Steam.getFriendPersonaName(remote_steam_id)
	
	# Only accept this p2p request if its from the host of the lobby.
	if SteamLobby.get_owner() == remote_steam_id:
		Steam.acceptP2PSessionWithUser(remote_steam_id)
	else:
		push_warning("Got a rogue p2p session request from %s. Not accepting." % remote_steam_id)

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
	
