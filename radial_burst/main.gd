extends Node2D

const Probe = preload("res://core/symlink_probe.gd")

func _ready() -> void:
	print("SYMLINK_PROBE=", Probe.ping())
