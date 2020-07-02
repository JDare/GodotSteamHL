# Godot Steam HighLevel Networking

This library is designed to work with [GodotSteam](https://github.com/Gramps/GodotSteam) and provide a higher level implementation of some of the basic Steam Networking functionality, namely Lobbies and P2P Networking.

### Features
* Easy to use Steam P2P Networking, no more manually sending and receiving packets
* Server / Client architecture where one peer is the host and all other users connect to them.
* Host migration for when that host leave the lobby/game
* RPC/RSet support
* Basic Steam Lobby interface providing easy access to player join/leave and other key events.

### What this is and what this isnt
This isnt a highly performant one size fits all networking solution. Its an opinionated P2P server client architecture with Godots high level networking equivalent functions RPC and RSet. Its entirely implemented in GodotScript so it wont win any awards for performance but its incredibly easy to customize and get started with (no compilation required). It requires [GodotSteam](https://github.com/Gramps/GodotSteam) to function as it relys on the Steamworks SDK to be present.

This means its ideal for small scale games with low numbers of users playing together in fairly low action scenarios.

## Getting Started

1. Clone this repo into your project or copy the 3 main files (steam_init.gd, steam_lobby.gd and steam_network.gd)
2. Add the 3 files as autoloads in the order (steam_init, steam_lobby and finally steam_network). They should be added with the names `SteamInit`, `SteamLobby` and `SteamNetwork`.
  * Note: if you are already initializing Steam, you can ignore the `steam_init.gd` file as long as the `Steam.run_callbacks()` function is called somewhere.
3. Thats it! Check the example directory of this repo and docs to get started.

## SteamLobby

### Connections

These are all the connections emitted from the SteamLobby autoload.

```player_joined_lobby(steam_id)
player_left_lobby(steam_id)
lobby_created(lobby_id)
lobby_joined(lobby_id)
lobby_owner_changed(previous_owner, new_owner)
chat_message_received(sender_steam_id, message)
```

### Functions

```create_lobby(lobby_type: int, max_players: int)```

Starts the process to create a lobby of type `lobby_type` with max players. `lobby_type` is one of `Steam.LOBBY_TYPE_*`. When completed, the signal `lobby_created` will emit.

```join_lobby(lobby_id: int)```

Similar to create lobby, this will start the process of joining the lobby specified in the lobby_id. The `lobby_joined` signal will be fired upon completion.

```leave_lobby()```

Leaves the lobby and terminates any potential connections with lobby members.

```get_lobby_members() -> Dictionary```

Returns a dict of `steam_id: steam_name` for each member in the lobby.

```get_lobby_id()```

Returns the lobby ID your Steam Session (the current user) is connected to. (0 if none)

```in_lobby() -> bool```

Returns a bool as to whether your Steam Session is in a lobby or not.

```is_owner(steam_id = -1) -> bool```

Returns a bool as to whether the steam_id provided is the owner of this lobby. If no steam_id is provided, it will use the current user.

```get_owner()```

Returns the steam_id of the current owner of the lobby.

```send_chat_message(message: String) -> bool```

Sends a chat message to the lobby, this will emit a `chat_message_received` signal on each user connected to the lobby.


## SteamNetwork

### Connections

These are all the connections emitted from the SteamNetwork autoload.

```
peer_status_updated(steam_id)
```

### Functions

*The following can be called on clients:*

```rpc_on_server(caller: Node, method: String, args: Array)```

This calls an RPC on the server, it works very similar to Godots HighLevel networking.

Usage Example: 
```
func shoot(bad_guy):
  SteamNetwork.rpc_on_server(self, "server_shoot", [bad_guy])
  
func server_shoot(sender_id: int, bad_guy):
  if not SteamNetwork.is_server():
    return
  if can_shoot(sender_id, bad_guy):
    bad_guy.remove_health(10)
    # now update bad_guy state to all peers
```

---

*The following are all designed to be used on the peer acting as the server.*

```rpc_on_client(to_peer: Peer, caller: Node, method: String, args: Array)```

Calls this method on the client specified.

Usage Example:
```
func server_buy_item(sender_id: int, expensive_item):
  if not SteamNetwork.is_server():
    return
  get_player(sender_id).remove_gold(999)
  SteamNetwork.rpc_on_client(sender_id, "client_got_scammed")  
```


```rpc_all_clients(caller: Node, method: String, args: Array)```

Similar to `rpc_on_client`, this calls an RPC on ALL clients.

Usage Example:
```
func server_stun_bad_guy(bad_guy):
  if not SteamNetwork.is_server():
    return
  SteamNetwork.rpc_all_clients(self, "client_bad_guy_got_stunned", [bad_guy])
  
func client_bad_guy_got_stunned(sender_id, the_bad_guy):
  # do something with bad guy
  pass
```


```remote_set(caller: Node, property: String, value)```

Sets a property on a node to the specified value

Usage Example:
```
var bad_guy_health := 30
func server_update_bad_guy_health(health):
  if not SteamNetwork.is_server():
    return
  SteamNetwork.remote_set(self, "bad_guy_health", health)
```


```is_peer_connected(steam_id) -> bool```

Returns whether the peer passed by `steam_id` argument is connected or not

```get_peer(steam_id) -> Peer```

Returns a peer object for a given users steam_id

```is_server() -> bool```

Returns whether this peer is the server or not


```get_server_peer() -> Peer```

Gets the peer object of the server connection

```get_server_steam_id() -> int```

Gets the server users steam id
