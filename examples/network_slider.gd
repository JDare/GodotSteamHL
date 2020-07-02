extends HSlider

var health := 20 setget set_health
# Called when the node enters the scene tree for the first time.
func _ready():
	value = health
	set_health(health)
	connect("value_changed", self, "on_value_changed")

func on_value_changed(new_value):
	if SteamNetwork.is_server():
		SteamNetwork.remote_set(self, "health", new_value)
	else:
		value = health
		
func set_health(new_health):
	health = new_health
	value = health
	$Label.text = "Player Health: " + str(new_health)
