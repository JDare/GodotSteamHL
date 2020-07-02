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

```signal player_joined_lobby(steam_id)
signal player_left_lobby(steam_id)
signal lobby_created(lobby_id)
signal lobby_joined(lobby_id)
signal lobby_owner_changed(previous_owner, new_owner)
signal chat_message_received(sender_steam_id, message)
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

