extends Control
@onready var riso_viewport  = $HBoxContainer/RisoViewport/SubViewport
@onready var riso_container = $HBoxContainer/RisoViewport
@onready var id_viewport    = $HBoxContainer/IdMapViewport/SubViewport

func _ready():
	$HBoxContainer/IdMapViewport.visible = false
	id_viewport.size = riso_viewport.size
	id_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var mat = riso_container.material as ShaderMaterial
	mat.set_shader_parameter("id_map", id_viewport.get_texture())

func _process(_delta):
	if id_viewport.size != riso_viewport.size:
		id_viewport.size = riso_viewport.size
