extends CADEntity
class_name CADViewportEntity

const CADViewportScene = preload("res://Scenes/CADLayoutViewport.tscn")
var viewport_panel: Control

func _ready():
	super._ready()
	
	# closed = false car on gère le segment ferment manuellement via le 5e point
	# (Line2D.closed ne fonctionne pas avec draw_polyline() surchargé dans CADEntity)
	closed = false
	
	# Viewport UI enfant
	viewport_panel = CADViewportScene.instantiate()
	viewport_panel.visible = true
	add_child(viewport_panel)
	
	# Forcer le rendu du fond dans le SubViewport (transparent_bg = false par défaut)
	var internal_vp = viewport_panel.get_node_or_null("SubViewportContainer/SubViewport")
	if internal_vp:
		internal_vp.transparent_bg = false
	
	# Mettre sur le bon layer de visibilité (Layer binaire 3 = bitmask 4)
	_apply_visibility_layer_recursive(viewport_panel, 4)
	
	_sync_panel_to_polyline()

func _process(_delta):
	_sync_panel_to_polyline()

func _sync_panel_to_polyline():
	if points.size() < 2 or not viewport_panel:
		return
	
	# --- Calcul Bounding Box en coordonnées GLOBALES ---
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	
	for p in points:
		var gp = to_global(p)
		if gp.x < min_x: min_x = gp.x
		if gp.x > max_x: max_x = gp.x
		if gp.y < min_y: min_y = gp.y
		if gp.y > max_y: max_y = gp.y
	
	# --- Positionnement du Control via global_position ---
	# Bypass total des coordonnées locales pour éviter toute confusion de repère
	viewport_panel.global_position = Vector2(min_x, min_y)
	viewport_panel.size = Vector2(max_x - min_x, max_y - min_y)
	
	# --- Forcer le SubViewportContainer à remplir le panel ---
	var container = viewport_panel.get_node_or_null("SubViewportContainer")
	if container:
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# --- Grips : on n'affiche que les 4 vrais sommets (pas le doublon de fermeture) ---
func draw_grips(current_zoom: float):
	var s = grip_size / current_zoom
	var offset = Vector2(s / 2.0, s / 2.0)
	# On exclut le dernier point car il est un doublon du premier (fermeture)
	var count = points.size() - 1 if points.size() > 1 else points.size()
	for i in range(count):
		var local_pos = points[i]
		var rect = Rect2(local_pos - offset, Vector2(s, s))
		draw_rect(rect, grip_color, true)

# --- Override move_point : maintenir la fermeture si dernier point == premier ---
func move_point(index: int, new_global_pos: Vector2):
	super.move_point(index, new_global_pos)
	# Si on bouge le premier point, on synchronise le dernier (fermeture)
	if points.size() > 1:
		if index == 0:
			super.set_point_position(points.size() - 1, points[0])
		elif index == points.size() - 1:
			super.set_point_position(0, points[index])

# --- Override get_grip_index_at_position : ignorer le dernier point (doublon) ---
func get_grip_index_at_position(global_mouse_pos: Vector2, aperture_radius: float) -> int:
	var count = points.size() - 1 if points.size() > 1 else points.size()
	for i in range(count):
		if to_global(points[i]).distance_to(global_mouse_pos) <= aperture_radius:
			return i
	return -1

func _apply_visibility_layer_recursive(node: Node, layer: int):
	if node is CanvasItem:
		node.visibility_layer = layer
	for child in node.get_children():
		if child is SubViewportContainer or child is SubViewport:
			continue
		_apply_visibility_layer_recursive(child, layer)
