extends Control

signal layout_mode_changed(is_model_active: bool)

@onready var container := $SubViewportContainer
@onready var model_camera := $SubViewportContainer/SubViewport/ModelSpaceCamera2D
@onready var selection_border := $SelectionBorder

const RESIZE_MARGIN := 15.0

var is_model_active := false
var interaction_mode := "NONE" # NONE, DRAG, RESIZE
var drag_offset := Vector2.ZERO

func _ready() -> void:
	_update_visual_state()
	
	# Magie noire CAO: La sous-fenêtre ne doit JAMAIS voir les objets "Papier"
	# On supprime le Render Layer 3 (valeur binaire 4) du sous-viewport
	# Les objets "WorkspacePaper" seront forcés sur ce layer.
	var internal_viewport = $SubViewportContainer/SubViewport
	if internal_viewport:
		internal_viewport.canvas_cull_mask = internal_viewport.canvas_cull_mask & ~4

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		
		# 1. Double clic : Activer/Désactiver
		if event.double_click:
			_toggle_model_space()
			accept_event()
			return
			
		# 2. Clic normal : Resize ou Drag (seulement si inactif)
		if event.pressed and not is_model_active:
			var mouse_pos = event.position
			var is_on_border = mouse_pos.x > size.x - RESIZE_MARGIN or mouse_pos.y > size.y - RESIZE_MARGIN
			
			if is_on_border:
				interaction_mode = "RESIZE"
			else:
				interaction_mode = "DRAG"
				drag_offset = event.position
		else:
			interaction_mode = "NONE"

	elif event is InputEventMouseMotion:
		if interaction_mode == "RESIZE":
			size = event.position
			accept_event()
		elif interaction_mode == "DRAG" and not is_model_active:
			position += event.position - drag_offset
			accept_event()

func _input(event: InputEvent) -> void:
	# Quitter l'état actif (double clic hors de la fenêtre)
	if is_model_active and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			var local_mouse = get_local_mouse_position()
			if not Rect2(Vector2.ZERO, size).has_point(local_mouse):
				_toggle_model_space()

func _toggle_model_space() -> void:
	is_model_active = !is_model_active
	_update_visual_state()

func _update_visual_state() -> void:
	if is_model_active:
		selection_border.border_color = Color(0, 0.47, 0.83) # Bleu
		selection_border.border_width = 3
		container.mouse_filter = Control.MOUSE_FILTER_PASS
		if model_camera: model_camera.make_current()
	else:
		selection_border.border_color = Color(0.3, 0.3, 0.3) # Gris
		selection_border.border_width = 1
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	emit_signal("layout_mode_changed", is_model_active)
