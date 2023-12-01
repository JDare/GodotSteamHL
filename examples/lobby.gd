extends Node


@onready var create_lobby_btn = $CreateLobbyBtn
@onready var invite_friend_btn = $InviteFriendBtn
@onready var member_list = $ItemList
@onready var connected_gui = $ConnectedGUI

@onready var start_btn = $ConnectedGUI/StartBtn

@onready var rpc_on_server_btn = $ConnectedGUI/RPCOnServerBtn
@onready var rpc_on_server_label = $ConnectedGUI/RPCOnServerBtn/Label

@onready var rset_slider = $ConnectedGUI/RSetSlider
@onready var rset_label = $ConnectedGUI/RSetSlider/Label

@onready var change_owner_btn = $ConnectedGUI/ChangeHostBtn

@onready var chat_line_edit = $ConnectedGUI/ChatLineEdit
@onready var chat_send_btn = $ConnectedGUI/ChatSendBtn
@onready var chat_window = $ConnectedGUI/ChatWindow

var invite_intent = false

func _ready():
	connected_gui.visible = false
	rpc_on_server_label.text = ""
	
	SteamLobby.lobby_created.connect(on_lobby_created)
	SteamLobby.lobby_joined.connect(on_lobby_joined)
	SteamLobby.lobby_owner_changed.connect(on_lobby_owner_changed)
	SteamLobby.player_joined_lobby.connect(on_player_joined)
	SteamLobby.player_left_lobby.connect(on_player_left)
	SteamLobby.chat_message_received.connect(on_chat_message_received)
	
	SteamNetwork.register_rpcs(self,
		[
			["_server_button_pressed", SteamNetwork.PERMISSION.CLIENT_ALL],
			["_client_button_pressed", SteamNetwork.PERMISSION.SERVER],
		]
	)
	
	SteamNetwork.peer_status_updated.connect(on_peer_status_changed)
	SteamNetwork.all_peers_connected.connect(on_all_peers_connected)
	
	create_lobby_btn.pressed.connect(on_create_lobby_pressed)
	invite_friend_btn.pressed.connect(on_invite_friend_pressed)
	
	chat_line_edit.text_submitted.connect(on_chat_text_entered)
	chat_send_btn.pressed.connect(on_chat_send_pressed)

	rpc_on_server_btn.pressed.connect(on_rpc_server_pressed)
	
	change_owner_btn.pressed.connect(on_change_owner_pressed)

###########################################
# Steam Lobby/Network connect functions

func on_lobby_created(lobby_id):
	render_lobby_members()
	if invite_intent:
		invite_intent = false
		on_invite_friend_pressed()

func on_lobby_joined(lobby_id):
	render_lobby_members()
	connected_gui.visible = true
	create_lobby_btn.text = "Leave Lobby"
	
func on_lobby_owner_changed(old_owner, new_owner):
	render_lobby_members()
	print("Lobby Ownership Changed: %s => %s" % [old_owner, new_owner])

func on_player_joined(steam_id):
	render_lobby_members()

func on_player_left(steam_id):
	if steam_id == Steam.getSteamID():
		connected_gui.visible = false
	render_lobby_members()

func on_chat_message_received(sender_steam_id, steam_name, message):
	var display_msg = steam_name + ": " + message
	chat_window.add_item(display_msg)

func on_peer_status_changed(steam_id):
	# This means we have confirmed a P2P connection going back and forth
	# between us and this steam user.
	render_lobby_members()

func on_all_peers_connected():
	start_btn.disabled = false

################################################
# SteamNetwork Examples:

func on_rpc_server_pressed():
	SteamNetwork.rpc_on_server(self, "_server_button_pressed", ["Hello World"])

func _server_button_pressed(sender_id: int, message: String):
	# Server could validate incoming data here, perform state change etc.
	message = Steam.getFriendPersonaName(sender_id) + " says: " + message
	var number = randi() % 100
	SteamNetwork.rpc_all_clients(self, "_client_button_pressed", [message, number])

func _client_button_pressed(sender_id: int, message, number):
	rpc_on_server_label.text = "%s (%s)" % [message, number]

################################################
# Basic lobby connections/setup

func on_change_owner_pressed():
	var user_index = member_list.get_selected_items()[0]
	var user = SteamLobby.get_lobby_members().keys()[user_index]
	var me = Steam.getSteamID()
	if user != me and SteamLobby.is_owner():
		Steam.setLobbyOwner(SteamLobby.get_lobby_id(), user)

func on_create_lobby_pressed():
	if SteamLobby.in_lobby():
		SteamLobby.leave_lobby()
		create_lobby_btn.text = "Create Lobby"
	else:
		SteamLobby.create_lobby(Steam.LOBBY_TYPE_PUBLIC, 3)

func on_invite_friend_pressed():
	if SteamLobby.in_lobby():
		#pop up invite
		Steam.activateGameOverlayInviteDialog(SteamLobby.get_lobby_id())
	else:
		invite_intent = true
		on_create_lobby_pressed()

func on_chat_text_entered(message):
	SteamLobby.send_chat_message(message)
	chat_line_edit.clear()
	
func on_chat_send_pressed():
	var message = chat_line_edit.text
	on_chat_text_entered(message)

func render_lobby_members():
	member_list.clear()
	
	change_owner_btn.visible = SteamLobby.is_owner()

	var lobby_members = SteamLobby.get_lobby_members()
	for member_id in lobby_members:
		var member = lobby_members[member_id]
		if not SteamNetwork.is_peer_connected(member_id):
			start_btn.disabled = true
		var owner_str = "[Host] " if SteamLobby.is_owner(member_id) else ""
		var connected_str = "Connecting ..." if not SteamNetwork.is_peer_connected(member_id) else "Connected"
		var display_str = "%s%s (%s)" % [owner_str, member, connected_str]
		member_list.add_item(display_str)
