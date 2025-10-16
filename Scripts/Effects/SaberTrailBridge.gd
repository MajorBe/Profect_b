extends Node

@export_node_path("Node") var saber_path
@export_node_path("SwordTrail3D") var trail_path

var _saber: Node
var _trail: SwordTrail3D

func _ready() -> void:
	_saber = get_node_or_null(saber_path)
	_trail = get_node_or_null(trail_path)

	if not _saber or not _trail:
		push_warning("TrailBridge: назначь saber_path и trail_path в инспекторе.")
		return

	if not _saber.attack_started.is_connected(_on_attack_started):
		_saber.attack_started.connect(_on_attack_started)
	if not _saber.attack_finished.is_connected(_on_attack_finished):
		_saber.attack_finished.connect(_on_attack_finished)

func _on_attack_started(_clip: StringName, _length: float) -> void:
	_trail.enable_trail()

func _on_attack_finished(_clip: StringName) -> void:
	_trail.disable_trail()
