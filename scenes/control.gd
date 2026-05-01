# control_test.gd (reemplaza temporalmente tu script actual)
extends Control

func _ready():
	# Obtener referencia
	var container = $SubViewportContainer
	var viewport = $SubViewportContainer/SubViewport
	
	# Configuración mínima
	container.stretch = true
	
	# Forzar actualización
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	print("--- DIAGNÓSTICO ---")
	print("Container material: ", container.material)
	print("Shader activo? ", container.material != null)
	print("---")
	
	# Si el cubo no aparece aún, quitar el shader manualmente
	# container.material = null
