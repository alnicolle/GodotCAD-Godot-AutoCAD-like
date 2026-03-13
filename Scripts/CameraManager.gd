extends Camera2D

# 1. DÉCLARATION DU SIGNAL
signal zoom_changed(new_zoom_value)

# Référence vers le conteneur des lignes
@onready var entities_container = find_child("Entities")


var zoom_min = Vector2(0.01, 0.01)
var zoom_max = Vector2(100, 100)
var zoom_speed = 0.1

# --- CORRECTION MAJEURE : _input au lieu de _unhandled_input ---
# _input reçoit les événements MÊME si la fenêtre n'a pas le focus.
# C'est ce qui permet de bouger la caméra dès le démarrage sans cliquer.
func _input(event):
	
	# SÉCURITÉ 1 : Si la souris est sur une interface bloquante (Bouton, Panel...)
	# On laisse l'interface gérer l'événement.
	if event is InputEventMouseButton:
		var hovered_control = get_viewport().gui_get_hovered_control()
		if hovered_control and hovered_control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return

	# SÉCURITÉ 2 (Spécifique à votre Fenêtre Propriétés) :
	# Si vous avez une Window flottante, gui_get_hovered_control ne la voit pas toujours.
	# On ne peut pas accéder facilement aux variables du Main ici, mais la sécurité 1 
	# suffit généralement si le Mouse Filter du PanelContainer dans la Window est sur STOP.

	var has_zoomed = false
	
	# 1. GESTION DU ZOOM (Clics et Molette)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom += zoom * zoom_speed
			has_zoomed = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom -= zoom * zoom_speed
			if zoom.x < zoom_min.x: zoom = zoom_min
			has_zoomed = true
		
		# 2. ZOOM ETENDU (Double Clic Molette)
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.double_click:
			zoom_extents()
			has_zoomed = true

		if has_zoomed:
			zoom_changed.emit(zoom.x)

	# 3. GESTION DU PAN (Mouvement souris avec clic molette maintenu)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			position -= event.relative / zoom

# --- FONCTION ZOOM ETENDU (Inchangée) ---
func zoom_extents():
	if not entities_container: return

	var all_items = _get_all_visible_entities(entities_container)
	if all_items.is_empty():
		position = Vector2.ZERO
		zoom = Vector2(1, 1)
		zoom_changed.emit(zoom.x)
		return

	var min_p = Vector2(INF, INF)
	var max_p = Vector2(-INF, -INF)
	var has_content = false

	for ent in all_items:
		if ent.has_meta("is_ghost"): continue

		if "is_circle" in ent and ent.is_circle:
			var c = ent.position
			if "circle_center" in ent: c += ent.circle_center
			var r = ent.circle_radius
			min_p = min_p.min(c - Vector2(r, r))
			max_p = max_p.max(c + Vector2(r, r))
			has_content = true
		elif ent is Line2D and ent.get_point_count() > 0:
			for pt in ent.points:
				var global_pt = ent.to_global(pt)
				min_p = min_p.min(global_pt)
				max_p = max_p.max(global_pt)
			has_content = true

	if not has_content: return

	var rect_size = max_p - min_p
	if rect_size.x < 1: rect_size.x = 100
	if rect_size.y < 1: rect_size.y = 100
	
	var center = min_p + rect_size / 2.0
	var viewport_size = get_viewport_rect().size
	var zoom_x = viewport_size.x / (rect_size.x * 1.1)
	var zoom_y = viewport_size.y / (rect_size.y * 1.1)
	var final_zoom = clamp(min(zoom_x, zoom_y), 0.01, 50.0)
	
	position = center
	zoom = Vector2(final_zoom, final_zoom)
	zoom_changed.emit(zoom.x)

func _get_all_visible_entities(root_node: Node) -> Array:
	var list = []
	for child in root_node.get_children():
		if child is Node2D and child.visible:
			var is_entity = (child is Line2D) or ("is_circle" in child)
			if is_entity: list.append(child)
			list.append_array(_get_all_visible_entities(child))
	return list
