extends Node


signal player_joined_lobby(steam_id)
signal player_left_lobby(steam_id)
signal lobby_created(lobby_id)
signal lobby_joined(lobby_id)
signal lobby_owner_changed(previous_owner, new_owner)
signal chat_message_received(sender_steam_id, message)

var _my_steam_id := 0
var _steam_lobby_id := 0
var _steam_lobby_host := 0
var _members = {}

var _creating_lobby = false

func _ready():
	_my_steam_id = Steam.getSteamID()
	if _my_steam_id == 0:
		push_warning("Unable to get steam id of user, check steam has been initialized first.")
		return
	
	Steam.connect("lobby_created", self, "_on_lobby_created")
	Steam.connect("lobby_match_list", self, "_on_match_list")
	Steam.connect("lobby_joined", self, "_on_lobby_joined")
	Steam.connect("lobby_chat_update", self, "_on_lobby_chat_update")
	Steam.connect("lobby_message", self, "_on_lobby_message")
	Steam.connect("lobby_data_update", self, "_on_lobby_data_update")
	Steam.connect("lobby_invite", self, "_on_lobby_invite")
	Steam.connect("join_requested", self, "_on_lobby_join_requested")
	# Check for command line arguments
	_check_command_line()

func get_lobby_id():
	return _steam_lobby_id

func in_lobby() -> bool:
	return not _steam_lobby_id == 0

func is_owner(steam_id = -1) -> bool:
	if steam_id > 0:
		return get_owner() == steam_id
	return get_owner() == _my_steam_id

func get_owner():
	return Steam.getLobbyOwner(_steam_lobby_id)

func create_lobby(lobby_type: int, max_players: int):
	if _creating_lobby:
		return
	_creating_lobby = true
	if _steam_lobby_id == 0:
		print("Trying to create lobby of type %s" % lobby_type)
		Steam.createLobby(lobby_type, max_players)

func join_lobby(lobby_id: int):
	print("Trying to join lobby %s" % lobby_id)
	_members.clear()
	Steam.joinLobby(lobby_id)

func leave_lobby():
	# If in a lobby, leave it
	if _steam_lobby_id != 0:
		print("Leaving Lobby %s" % _steam_lobby_id)
		# Send leave request to Steam
		Steam.leaveLobby(_steam_lobby_id)
		# Wipe the Steam lobby ID then display the default lobby ID and player list title
		_steam_lobby_id = 0
		# Close session with all users
		# This is a bit of a hack for now to keep SteamNetwork isolated
		for steam_id in _members.keys():
			var session_state = Steam.getP2PSessionState(steam_id)
			if session_state.has("connection_active") and session_state["connection_active"]:
				Steam.closeP2PSessionWithUser(steam_id)
		# Clear the local lobby list
		_members.clear()
		emit_signal("player_left_lobby", _my_steam_id)

func get_lobby_members() -> Dictionary:
	_update_lobby_members()
	return _members
	
func send_chat_message(message: String) -> bool:
	return Steam.sendLobbyChatMsg(_steam_lobby_id, message)

func _on_lobby_created(connect, lobby_id):
	print("Lobby Created called")
	_creating_lobby = false
	if connect == 1:
		_steam_lobby_id = lobby_id
		print("Created Steam Lobby with id: %s" % lobby_id)

		var relay = Steam.allowP2PPacketRelay(true)
		print("Relay configuration response: %s" % relay)
		
		emit_signal("lobby_created", lobby_id)
	else:
		push_error("Failed to create lobby: %s" % connect)

func _on_lobby_joined(lobby_id: int, permissions, locked: bool, response):
	print("Lobby Joined!")
	_steam_lobby_id = lobby_id
	_update_lobby_members()
	emit_signal("lobby_joined", lobby_id)

func _on_lobby_join_requested(lobby_id: int, friend_id):
	print("Attempting to join lobby %s from request" % lobby_id)
	# Attempt to join the lobby
	join_lobby(lobby_id)
	
func _update_lobby_members():
		# Clear your previous lobby list
	_members.clear()

	_steam_lobby_host = Steam.getLobbyOwner(_steam_lobby_id)

	# Get the number of members from this lobby from Steam
	var num_members: int = Steam.getNumLobbyMembers(_steam_lobby_id)

	# Get the data of these players from Steam
	for member_index in range(0, num_members):

		# Get the member's Steam ID
		var member_steam_id = Steam.getLobbyMemberByIndex(_steam_lobby_id, member_index)

		# Get the member's Steam name
		var member_steam_name = Steam.getFriendPersonaName(member_steam_id)

		# Add them to the list
		_members[member_steam_id] = member_steam_name
	
func _on_lobby_invite(inviter, lobby, game):
	pass
	
func _on_lobby_data_update(success, lobby_id, member_id, key):
	if success:
		# check for host change
		var host = Steam.getLobbyOwner(_steam_lobby_id)
		if host != _steam_lobby_host and host > 0:
			_owner_changed(_steam_lobby_host, host)
			_steam_lobby_host = host
		
#	print("Lobby Updated %s %s %s %s" % [success, lobby_id, member_id, key])

func _owner_changed(was_steam_id, now_steam_id):
	emit_signal("lobby_owner_changed", was_steam_id, now_steam_id)

func _on_lobby_message(result, sender_steam_id, message, chat_type):
	if result == 0:
		push_error("Received lobby message, but 0 bytes were retrieved!")
	match(chat_type):
		Steam.CHAT_ENTRY_TYPE_CHAT_MSG:
			if not _members.has(sender_steam_id):
				push_error("Received a message from a user we dont have locally!")
			var profile_name = _members[sender_steam_id]
			emit_signal("chat_message_received", sender_steam_id, profile_name, message)
		_:
			push_warning("Unhandled chat message type received: %s" % chat_type)

func _on_lobby_chat_update(lobby_id, changed_user_steam_id, user_made_change_steam_id, chat_state):
	match chat_state:
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
			print("Player joined lobby %s" % changed_user_steam_id)
			emit_signal("player_joined_lobby", changed_user_steam_id)
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
			print("Player left the lobby %s" % changed_user_steam_id)
			emit_signal("player_left_lobby", changed_user_steam_id)
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED:
			print("Player %s was kicked by %s" % [changed_user_steam_id, user_made_change_steam_id])
			emit_signal("player_left_lobby", changed_user_steam_id)
		Steam.CHAT_MEMBER_STATE_CHANGE_BANNED:
			print("Player %s was banned by %s" % [changed_user_steam_id, user_made_change_steam_id])
			emit_signal("player_left_lobby", changed_user_steam_id)
		Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED:
			print("Player disconnected %s" % [changed_user_steam_id, user_made_change_steam_id])
			emit_signal("player_left_lobby", changed_user_steam_id)

func _on_match_list(lobbies):
	pass
	
func _check_command_line():
	var args = OS.get_cmdline_args()

	# There are arguments to process
	if args.size() > 0:
		var _lobby_invite_arg := false
		# Loop through them and get the useful ones
		for arg in args:
			print("Command line: "+str(arg))

			# An invite argument was passed
			if _lobby_invite_arg:
				join_lobby(int(arg))

			# A Steam connection argument exists
			if arg == "+connect_lobby":
				_lobby_invite_arg = true

func _exit_tree():
	leave_lobby()
