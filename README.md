# Godot Steam HighLevel Networking

This library is designed to work with [GodotSteam](https://github.com/Gramps/GodotSteam) and provide a higher level implementation of some of the basic Steam Networking functionality, namely Lobbies and P2P Networking.

GodotSteamHL is currently in **ALPHA** use at your own risk.

### Features
* Easy to use Steam P2P Networking, no more manually sending and receiving packets
* Server / Client architecture where one peer is the host and all other users connect to them.
* Host migration for when that host leave the lobby/game
* RPC/RSet support
* Remote execution disabled by default. All methods/properties must be individually whitelisted to be invoked through the network.
* Basic Steam Lobby interface providing easy access to player join/leave and other key events.

### What this is and what this isnt
This isnt a highly performant one size fits all networking solution. Its an opinionated P2P server client architecture with Godots high level networking equivalent functions RPC and RSet. Its entirely implemented in GodotScript so it wont win any awards for performance but its incredibly easy to customize and get started with (no compilation required). It requires [GodotSteam](https://github.com/Gramps/GodotSteam) to function as it relys on the Steamworks SDK to be present.

This means its ideal for small scale games with low numbers of users playing together in fairly low action scenarios.

## Getting Started

1. Clone this repo into your project or copy the 3 main files (steam_init.gd, steam_lobby.gd and steam_network.gd)
2. Add the 3 files as autoloads in the order (steam_init, steam_lobby and finally steam_network). They should be added with the names `SteamInit`, `SteamLobby` and `SteamNetwork`.
  * Note: if you are already initializing Steam, you can ignore the `steam_init.gd` file as long as the `Steam.run_callbacks()` function is called somewhere.
3. Thats it! Check the example directory of this repo and docs to get started.

## SteamNetwork Example
This is taken from the lobby example in the /examples/ directory of the repo.

### RPC Example
```
func _ready():
  # Bind RPC button signal
  $RPCOnServerBtn.connect("pressed", self, "on_rpc_server_pressed")
  
  # Register any RPCs/Methods you want to be called and their permissions
  SteamNetwork.register_rpcs(self,
    [
     ["_server_button_pressed", SteamNetwork.PERMISSION.CLIENT_ALL],
     ["_client_button_pressed", SteamNetwork.PERMISSION.SERVER],
    ]
   )

func on_rpc_server_pressed():
  # When client clicks the button, we send an RPC to the server
	 SteamNetwork.rpc_on_server(self, "_server_button_pressed", ["Hello World"])

# This function will only be called on the server due to permissions we configured it with at `register_rpc`
func _server_button_pressed(sender_id: int, message: String):
	# Server could validate incoming data here, perform state change etc.
	message = Steam.getFriendPersonaName(sender_id) + " says: " + message
	var number = randi() % 100
 # Now the server calls an RPC on ALL clients, only the server has permission to do this.
	SteamNetwork.rpc_all_clients(self, "_client_button_pressed", [message, number])

# This function will be called on all clients and can only be invoked by the server.
func _client_button_pressed(sender_id: int, message, number):
	 $RPCOnServerLabel.text = "%s (%s)" % [message, number]
```

### Remote Set Example

```
var health := 20 setget set_health

func _ready():
	# This registers the variable health to be remote_set by the server
	SteamNetwork.register_rset(self, "health", SteamNetwork.PERMISSION.SERVER)
 
 connect("value_changed", self, "on_value_changed") 
 
	set_health(health)

func on_value_changed(new_value):
	if SteamNetwork.is_server():
		SteamNetwork.remote_set(self, "health", new_value)
	else:
		value = health
		
func set_health(new_health):
	health = new_health
	value = health
	$Label.text = "Player Health: " + str(new_health)
```

For more indepth documentation and examples, please visit the [Wiki](https://github.com/JDare/GodotSteamHL/wiki)


## TODO
* Implement Matchmaking Lobby features / listing and filtering Lobbies.
* Object ownership, allow peers other than Server make authorized changes.
* Potentially move cpu intensive portions to GDNative
