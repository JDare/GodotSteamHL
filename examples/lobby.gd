extends Node


onready var create_lobby_btn = $CreateLobbyBtn
onready var invite_friend_btn = $InviteFriendBtn
onready var member_list = $ItemList

onready var connected_gui = $ConnectedGUI

onready var chat_line_edit = $ConnectedGUI/ChatLineEdit
onready var chat_send_btn = $ConnectedGUI/ChatSendBtn
onready var chat_window = $ConnectedGUI/ChatWindow

var invite_intent = false

func _ready():
	connected_gui.visible = false
	
	SteamLobby.connect("lobby_created", self, "on_lobby_created")
	SteamLobby.connect("lobby_joined", self, "on_lobby_joined")
	SteamLobby.connect("player_joined_lobby", self, "on_player_joined")
	SteamLobby.connect("player_left_lobby", self, "on_player_left")
	SteamLobby.connect("chat_message_received", self, "on_chat_message_received")
	
	SteamNetwork.connect("peer_status_updated", self, "on_peer_status_changed")
	
	create_lobby_btn.connect("pressed", self, "on_create_lobby_pressed")
	invite_friend_btn.connect("pressed", self, "on_invite_friend_pressed")
	chat_line_edit.connect("text_entered", self, "on_chat_text_entered")
	chat_send_btn.connect("pressed", self, "on_chat_send_pressed")


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

################################################

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
	print("Rendering player list ...")
	member_list.clear()
	var lobby_members = SteamLobby.get_lobby_members()
	for member_id in lobby_members:
		var member = lobby_members[member_id]
		var owner_str = "[Host] " if SteamLobby.is_owner(member_id) else ""
		var connected_str = "Connecting ..." if not SteamNetwork.is_peer_connected(member_id) else "Connected"
		var display_str = "%s%s (%s)" % [owner_str, member, connected_str]
		member_list.add_item(display_str)
