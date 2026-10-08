extends Node
func _ready() -> void:
	print("USER ARGS:", OS.get_cmdline_user_args())
	print("ALL ARGS:", OS.get_cmdline_args())
	get_tree().quit(0)
