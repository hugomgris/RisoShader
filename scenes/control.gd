extends Control

@onready var riso_vp       = $RisoViewport/SubViewport
@onready var riso_container = $RisoViewport
@onready var riso_cam      = $RisoViewport/SubViewport/Camera3D

@onready var group_vp      = $GroupMapViewport/SubViewport
@onready var group_cam     = $GroupMapViewport/SubViewport/Camera3D

var riso_mat: ShaderMaterial

func _ready():
	group_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	$GroupMapViewport.visible = true
	$GroupMapViewport.modulate.a = 0.0
	
	riso_mat = riso_container.material as ShaderMaterial
	
	# Match viewport sizes
	group_vp.size = riso_vp.size
	
	# Pass group map texture to shader
	riso_mat.set_shader_parameter("group_map", group_vp.get_texture())

func _process(_delta):
	# Sync group camera to main camera every frame
	group_cam.global_transform = riso_cam.global_transform
	group_cam.projection       = riso_cam.projection
	group_cam.size             = riso_cam.size
	
	# Keep sizes in sync on window resize
	if group_vp.size != riso_vp.size:
		group_vp.size = riso_vp.size

# Public API for changing ink colors at runtime
func set_ink(index: int, color: Color):
	riso_mat.set_shader_parameter("ink_color_" + str(index), 
		Vector3(color.r, color.g, color.b))

func set_gradient(top_density: float, bottom_density: float):
	riso_mat.set_shader_parameter("gradient_top_density",    top_density)
	riso_mat.set_shader_parameter("gradient_bottom_density", bottom_density)
