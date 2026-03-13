extends Line2D
class_name CADEntity

# --- PROPRIÉTÉS LIGNES ---
var linetype = "CONTINUOUS" : set = set_linetype
var lineweight = -1.0
var linetype_scale = 1.0 : set = set_linetype_scale
var layer_name = "0"

# --- VARIABLES RÉSOLUES ---
var _effective_linetype = "CONTINUOUS"
var _effective_lineweight = 0.25
var _effective_color = Color.WHITE

# --- CACHE PERFORMANCE ---
var _cached_iso_points = PackedVector2Array()
var _is_geometry_dirty = true 

# --- OPTIMISATION DESSIN (La variable qui manquait) ---
var visual_width = 1.0

# Référence au Shader
static var line_shader = preload("res://Shaders/Linetype.gdshader")

# --- ÉTATS ---
var is_selected = false : set = set_selected
var is_hovered = false : set = set_hover

# --- PARAMÈTRES VISUELS ---
var default_color_val = Color.WHITE
var selected_color = Color(0.2, 0.6, 1.0)
var grip_size = 10.0
var grip_color = Color(0.0, 0.0, 1.0)

# --- GUIDE VISUEL ---
var show_dimension_guide = false 
var guide_color = Color(0.5, 0.5, 0.5, 0.8) 
var guide_screen_offset = 60.0 

# --- DONNÉES CERCLE ---
var is_circle = false
var circle_center = Vector2.ZERO
var circle_radius = 0.0
var circle_visual_target = Vector2.ZERO

# --- DONNÉES ARC ---
var is_arc = false
var arc_center = Vector2.ZERO
var arc_radius = 0.0
var arc_start_angle = 0.0  # En radians
var arc_end_angle = 0.0    # En radians

# --- DONNÉES POINT ---
var is_point = false
var point_size = 5.0
var point_style = "CROSS"  # "CROSS", "CIRCLE", "SQUARE"

func _ready():
	default_color_val = default_color
	
	if is_circle and circle_visual_target == Vector2.ZERO:
		circle_visual_target = circle_center + Vector2(circle_radius, 0)
	
	if not is_circle and not is_arc:
		texture_mode = Line2D.LINE_TEXTURE_STRETCH
	
	# 1. CONNEXION LAYER MANAGER
	var lm = get_tree().get_first_node_in_group("LayerManager_Global")
	if lm:
		if not lm.layers_changed.is_connected(_on_layers_changed):
			lm.layers_changed.connect(_on_layers_changed)
	
	# [cite_start]2. CONNEXION CAMERA (POUR REMPLACER _PROCESS) [cite: 384]
	var cam = get_viewport().get_camera_2d()
	if cam:
		# On s'abonne au signal de zoom pour mettre à jour l'épaisseur intelligemment
		if cam.has_signal("zoom_changed"):
			if not cam.zoom_changed.is_connected(_on_camera_zoom_changed):
				cam.zoom_changed.connect(_on_camera_zoom_changed)
			# Initialisation de l'épaisseur
			_update_width_from_zoom(cam.zoom.x)
	
	update_visuals()
	_mark_dirty()

# --- OPTIMISATION MAJEURE : SUPPRESSION DE _PROCESS ---
# On ne recalcule plus rien à chaque frame. Tout se fait par signaux.

func _on_camera_zoom_changed(new_zoom_value: float):
	# On ne met à jour l'épaisseur que quand le zoom change vraiment
	_update_width_from_zoom(new_zoom_value)

func _update_width_from_zoom(zoom_val: float):
	var display_scale_factor = 4.0 
	var target_pixel_width = 1.0
	
	if _effective_lineweight > 0.0:
		target_pixel_width = max(1.0, _effective_lineweight * display_scale_factor)
	
	# Calcul de la nouvelle largeur visuelle
	var new_width = target_pixel_width / zoom_val
	
	# 1. Mise à jour de visual_width (Pour le dessin manuel dans _draw)
	# On évite les mises à jour inutiles avec une petite tolérance
	if abs(visual_width - new_width) > 0.001:
		visual_width = new_width
		queue_redraw() # Indispensable pour rafraîchir le dessin immédiat
	
	# 2. Gestion du Line2D natif (Optimisation)
	# Si on a un shader (pointillés), on a besoin du maillage Line2D, donc on met à jour self.width.
	# Sinon, on met self.width à 0 pour que Line2D ne dessine rien (on dessine tout dans _draw), ce qui économise des perfs.
	if material != null:
		self.width = new_width
	else:
		self.width = 0 # Cache le rendu natif pour éviter le double dessin

# --- SETTERS OPTIMISÉS ---

func set_selected(val):
	if is_selected == val: return # Optimisation
	is_selected = val
	z_index = 10 if is_selected else 0
	update_visuals()

func set_hover(val):
	if is_selected: return
	
	# --- OPTIMISATION MAJEURE ICI ---
	# Si l'état ne change pas, ON NE FAIT RIEN.
	# Cela empêche les 1999 redessins inutiles quand la souris bouge.
	if is_hovered == val: return 
	
	is_hovered = val
	z_index = 1 if is_hovered else 0
	queue_redraw() # On redessine UNIQUEMENT si l'état a changé

func set_linetype(val):
	if linetype != val:
		linetype = val
		_mark_dirty()
		update_visuals()

func set_linetype_scale(val):
	if linetype_scale != val:
		linetype_scale = val
		_mark_dirty()
		update_visuals()

func _mark_dirty():
	_is_geometry_dirty = true
	queue_redraw()

# --- DESSIN (Optimisé avec LOD) ---

func _draw():
	# 1. Récupération du zoom (Sécurisée)
	var current_zoom = 1.0
	if is_inside_tree():
		var vp = get_viewport()
		if vp and vp.get_camera_2d():
			current_zoom = vp.get_camera_2d().zoom.x

	# 2. Variable optimisée pour l'épaisseur (voir nos optimisations précédentes)
	var draw_w = visual_width 
	
	# --- 3. LOGIQUE TAILLE DU MOTIF ---
	var pattern_geometry_size = 0.0
	
	if _effective_linetype == "ISOLATION":
		# CAS ISOLATION : L'échelle correspond directement à la hauteur en mm (Unités Monde)
		# Exemple : Echelle 150 -> Hauteur 150mm
		pattern_geometry_size = linetype_scale
	else:
		# CAS STANDARD : On garde le multiplicateur x20 pour les pointillés classiques
		pattern_geometry_size = 20.0 * linetype_scale

	# LOD (Level of Detail) : On ne dessine pas les détails si c'est trop petit à l'écran
	var screen_pattern_size = pattern_geometry_size * current_zoom
	var use_simplified_render = (screen_pattern_size < 5.0) # Seuil abaissé à 5px pour voir mieux
	# -----------------------------------
	
	# A. ISOLATION
	if _effective_linetype == "ISOLATION":
		if not is_circle:
			var col = default_color_val if not is_selected else selected_color
			
			if use_simplified_render:
				# Mode simplifié : Ligne simple
				draw_polyline(points, col, draw_w)
			else:
				# Si la géométrie a changé (ou si l'échelle a changé), on recalcule les points
				if _is_geometry_dirty:
					# C'est ici qu'on utilise la nouvelle taille calculée
					_cached_iso_points = GeometryUtils.generate_insulation_points(points, pattern_geometry_size)
					_is_geometry_dirty = false
				
				if _cached_iso_points.size() > 0:
					draw_polyline(_cached_iso_points, col, draw_w)
		else:
			var col = default_color_val if not is_selected else selected_color
			var nb_points = clamp(int(circle_radius * current_zoom * 2.0), 32, 128)
			var circle_pts = PackedVector2Array()
			for i in range(nb_points + 1):
				var a = (TAU * float(i)) / float(nb_points)
				circle_pts.append(to_local(circle_center + Vector2(cos(a), sin(a)) * circle_radius))
			
			if use_simplified_render:
				draw_polyline(circle_pts, col, draw_w)
			else:
				if _is_geometry_dirty:
					_cached_iso_points = GeometryUtils.generate_insulation_points(circle_pts, pattern_geometry_size)
					_is_geometry_dirty = false
				if _cached_iso_points.size() > 0:
					draw_polyline(_cached_iso_points, col, draw_w)

	# B. CERCLE / ARC
	elif is_circle:
		if material == null:
			_draw_standard_circle(draw_w, current_zoom)
	elif is_arc:
		if material == null:
			_draw_standard_arc(draw_w, current_zoom)
	elif is_point:
		if material == null:
			_draw_standard_point(draw_w, current_zoom)
		
	# C. LIGNES STANDARDS
	else:
		var col = default_color_val if not is_selected else selected_color
		
		# Si un shader est actif (pointillés), on laisse le Line2D gérer
		if material == null:
			draw_polyline(points, col, draw_w)
		else:
			pass # Le rendu se fait via le ShaderMaterial attaché

	# D. SURBRILLANCE (HOVER)
	if is_hovered and not is_selected:
		var hover_col = Color(1, 1, 1, 0.4)
		var hover_w = draw_w + (4.0 / current_zoom)
		
		if is_circle:
			draw_arc(to_local(circle_center), circle_radius, 0, TAU, 64, hover_col, hover_w)
		elif is_arc:
			draw_arc(to_local(arc_center), arc_radius, arc_start_angle, arc_end_angle, 64, hover_col, hover_w)
		else:
			# Si isolation visible, on surbrille le zigzag exact
			if _effective_linetype == "ISOLATION" and not use_simplified_render and _cached_iso_points.size() > 0:
				draw_polyline(_cached_iso_points, hover_col, hover_w)
			else:
				draw_polyline(points, hover_col, hover_w)

	if is_selected: draw_grips(current_zoom)
	if show_dimension_guide: draw_guide_visuals(current_zoom)

# --- MISE À JOUR VISUELS ---

func update_visuals():
	_resolve_properties()
	
	default_color_val = _effective_color
	
	var is_procedural = (_effective_linetype == "ISOLATION")
	var needs_shader = (not is_procedural and _effective_linetype != "CONTINUOUS")
	
	if needs_shader and is_circle:
		var nb_points = 128
		var circle_pts = PackedVector2Array()
		for i in range(nb_points + 1):
			var a = (TAU * float(i)) / float(nb_points)
			circle_pts.append(circle_center + Vector2(cos(a), sin(a)) * circle_radius)
			
		points = circle_pts
		texture_mode = Line2D.LINE_TEXTURE_STRETCH
	elif needs_shader and is_arc:
		texture_mode = Line2D.LINE_TEXTURE_STRETCH
	
	if is_procedural or is_circle or is_arc or is_point:
		default_color = Color(0, 0, 0, 0)
	else:
		if is_selected: 
			default_color = selected_color
		else: 
			default_color = _effective_color 
	
	if needs_shader:
		_apply_shader()
	else:
		material = null
	
	# --- CORRECTION CRASH ---
	# On ne met à jour l'épaisseur via la caméra QUE si on est dans l'arbre
	if is_inside_tree():
		var vp = get_viewport()
		if vp:
			var cam = vp.get_camera_2d()
			if cam:
				_update_width_from_zoom(cam.zoom.x)
		
	queue_redraw()

func _apply_shader():
	var pattern = LinetypeManager.get_pattern(_effective_linetype)
	if pattern.is_empty():
		material = null
		return

	if material == null or not (material is ShaderMaterial):
		material = ShaderMaterial.new()
		material.shader = line_shader
	
	var total_len = 0.0
	if is_circle: total_len = TAU * circle_radius
	else:
		for i in range(points.size() - 1): total_len += points[i].distance_to(points[i+1])
	
	var shader_pattern = []
	for p in pattern: shader_pattern.append(abs(p))
	while shader_pattern.size() < 20: shader_pattern.append(0.0)
	
	material.set_shader_parameter("pattern", shader_pattern)
	material.set_shader_parameter("pattern_count", pattern.size())
	material.set_shader_parameter("line_length", total_len)
	material.set_shader_parameter("linetype_scale", linetype_scale * LinetypeManager.global_scale)
	
	var final_col = _effective_color if not is_selected else selected_color
	material.set_shader_parameter("color", final_col)

# --- RÉSOLUTION DES PROPRIÉTÉS ---

func _resolve_properties():
	if not is_inside_tree(): return

	var lm = get_tree().get_first_node_in_group("LayerManager_Global")
	if not lm: 
		_effective_linetype = linetype
		_effective_lineweight = lineweight
		_effective_color = default_color_val
		return

	# Type de Ligne
	if linetype == "ByLayer" or linetype == "DuCalque":
		_effective_linetype = lm.get_layer_linetype(layer_name)
	else:
		_effective_linetype = linetype

	# Épaisseur
	if lineweight < 0.0:
		_effective_lineweight = lm.get_layer_lineweight(layer_name)
	else:
		_effective_lineweight = lineweight
		
	# Couleur
	var found = false
	if "layers" in lm:
		for lay in lm.layers:
			if lay.name == layer_name:
				_effective_color = lay.color
				found = true
				break
	
	if not found:
		_effective_color = default_color_val

# --- HELPERS DESSIN & MANIPULATION (Inchangés mais nettoyés) ---

func _draw_standard_circle(w, z):
	var nb_points = clamp(int(circle_radius * z * 2.0), 32, 128)
	var col = default_color_val if not is_selected else selected_color
	draw_arc(to_local(circle_center), circle_radius, 0, TAU, nb_points, col, w)

func _draw_standard_arc(w, z):
	var nb_points = clamp(int(arc_radius * z * 2.0), 32, 128)
	var col = default_color_val if not is_selected else selected_color
	draw_arc(to_local(arc_center), arc_radius, arc_start_angle, arc_end_angle, nb_points, col, w)

func _draw_standard_point(w, z):
	var col = default_color_val if not is_selected else selected_color
	# Adapter la taille du point en fonction du zoom pour garder une taille constante à l'écran
	var size = point_size / z
	
	match point_style:
		"CROSS":
			# Dessiner une croix
			draw_line(Vector2(-size, 0), Vector2(size, 0), col, w)
			draw_line(Vector2(0, -size), Vector2(0, size), col, w)
		"CIRCLE":
			# Dessiner un cercle
			draw_arc(Vector2.ZERO, size, 0, TAU, 32, col, w)
		"SQUARE":
			# Dessiner un carré
			var rect_pos = Vector2(-size/2, -size/2)
			var rect_size = Vector2(size, size)
			draw_rect(Rect2(rect_pos, rect_size), col, false, w)
		_:
			# Par défaut, croix
			draw_line(Vector2(-size, 0), Vector2(size, 0), col, w)
			draw_line(Vector2(0, -size), Vector2(0, size), col, w)

func draw_grips(current_zoom: float):
	var s = grip_size / current_zoom
	var offset = Vector2(s / 2.0, s / 2.0)
	var grip_positions = []
	if is_circle:
		grip_positions = [
			circle_center, circle_center + Vector2(circle_radius, 0), 
			circle_center + Vector2(0, circle_radius), 
			circle_center + Vector2(-circle_radius, 0), circle_center + Vector2(0, -circle_radius)
		]
	elif is_arc:
		# Points de contrôle pour l'arc : centre, départ, fin, et points intermédiaires
		var start_point = arc_center + Vector2(cos(arc_start_angle), sin(arc_start_angle)) * arc_radius
		var end_point = arc_center + Vector2(cos(arc_end_angle), sin(arc_end_angle)) * arc_radius
		var mid_angle = (arc_start_angle + arc_end_angle) / 2.0
		var mid_point = arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * arc_radius
		grip_positions = [arc_center, start_point, mid_point, end_point]
	elif is_point:
		# Pour les points, un seul grip au centre (en coordonnées globales)
		grip_positions = [global_position]
	else:
		for p in points: grip_positions.append(to_global(p))

	for g_pos in grip_positions:
		var local_pos = to_local(g_pos) 
		var rect = Rect2(local_pos - offset, Vector2(s, s))
		draw_rect(rect, grip_color, true)

func draw_guide_visuals(current_zoom: float):
	var start_pos = Vector2.ZERO
	var end_pos = Vector2.ZERO
	var offset_dist = guide_screen_offset / current_zoom
	var guide_width = 1.0 / current_zoom
	var dash_len = 5.0 / current_zoom
	
	if is_circle:
		start_pos = to_local(circle_center)
		if circle_visual_target != Vector2.ZERO and circle_visual_target != circle_center:
			end_pos = to_local(circle_visual_target)
		else:
			end_pos = start_pos + Vector2(circle_radius, 0)
	else:
		if points.size() < 2: return
		start_pos = points[points.size() - 2]
		end_pos = points[points.size() - 1]

	if start_pos.distance_to(end_pos) < 0.1: return
	var direction = (end_pos - start_pos).normalized()
	var normal = Vector2(-direction.y, direction.x)
	draw_custom_dashed_line(start_pos, start_pos + normal * offset_dist, guide_color, guide_width, dash_len)
	draw_custom_dashed_line(end_pos, end_pos + normal * offset_dist, guide_color, guide_width, dash_len)
	draw_custom_dashed_line(start_pos + normal * offset_dist, end_pos + normal * offset_dist, guide_color, guide_width, dash_len)

func draw_custom_dashed_line(from: Vector2, to: Vector2, color: Color, line_width: float, dash_length: float):
	var total_length = from.distance_to(to)
	var dir = (to - from).normalized()
	var current_dist = 0.0
	while current_dist < total_length:
		var start = from + dir * current_dist
		var end_dist = min(current_dist + dash_length, total_length)
		var end = from + dir * end_dist
		draw_line(start, end, color, line_width)
		current_dist += dash_length * 2.0

# ... (Code existant avant)

func hit_test(global_mouse_pos: Vector2, aperture_radius: float) -> bool:
	# CORRECTION : On ajoute l'épaisseur visuelle à la tolérance pour faciliter le clic
	var tolerance = aperture_radius + (visual_width / 2.0)
	var local_point = to_local(global_mouse_pos)
	
	if is_circle:
		# CORRECTION : On compare en local (local_point vs circle_center)
		var dist = local_point.distance_to(circle_center)
		return abs(dist - circle_radius) <= tolerance
		
	elif is_arc:
		# Pour les arcs, toute la courbe est sélectionnable (pas seulement les 3 points)
		var num_segments = 32
		var angle_step = (arc_end_angle - arc_start_angle) / num_segments
		
		for i in range(num_segments):
			var angle1 = arc_start_angle + angle_step * i
			var angle2 = arc_start_angle + angle_step * (i + 1)
			var p1 = arc_center + Vector2(cos(angle1), sin(angle1)) * arc_radius
			var p2 = arc_center + Vector2(cos(angle2), sin(angle2)) * arc_radius
			
			var closest = Geometry2D.get_closest_point_to_segment(local_point, p1, p2)
			if local_point.distance_to(closest) <= tolerance:
				return true
		return false
		
	elif is_point:
		# Pour les points, on teste si la souris est dans la zone du point
		# Adapter la taille au zoom pour la sélection
		var current_zoom = 1.0
		if is_inside_tree():
			var vp = get_viewport()
			if vp and vp.get_camera_2d():
				current_zoom = vp.get_camera_2d().zoom.x
		var adjusted_size = point_size / current_zoom
		return local_point.distance_to(Vector2.ZERO) <= (adjusted_size + tolerance)
		
	else:
		for i in range(points.size() - 1):
			var closest = Geometry2D.get_closest_point_to_segment(local_point, points[i], points[i+1])
			if local_point.distance_to(closest) <= tolerance: return true
		return false

func get_grip_index_at_position(global_mouse_pos: Vector2, aperture_radius: float) -> int:
	if is_circle:
		var grips = [circle_center, circle_center + Vector2(circle_radius, 0), circle_center + Vector2(0, circle_radius), circle_center + Vector2(-circle_radius, 0), circle_center + Vector2(0, -circle_radius)]
		for i in range(grips.size()): if grips[i].distance_to(global_mouse_pos) <= aperture_radius: return i
	elif is_arc:
		# Pour les arcs, uniquement les grips de contrôle (centre, départ, milieu, fin)
		var start_point = arc_center + Vector2(cos(arc_start_angle), sin(arc_start_angle)) * arc_radius
		var end_point = arc_center + Vector2(cos(arc_end_angle), sin(arc_end_angle)) * arc_radius
		var mid_angle = (arc_start_angle + arc_end_angle) / 2.0
		var mid_point = arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * arc_radius
		var grips = [arc_center, start_point, mid_point, end_point]
		for i in range(grips.size()): if grips[i].distance_to(global_mouse_pos) <= aperture_radius: return i
	elif is_point:
		# Pour les points, un seul grip au centre
		if to_global(Vector2.ZERO).distance_to(global_mouse_pos) <= aperture_radius: return 0
	else:
		for i in range(points.size()): if to_global(points[i]).distance_to(global_mouse_pos) <= aperture_radius: return i
	return -1

func get_grip_position(index: int) -> Vector2:
	if is_circle:
		if index == 0: return circle_center
		elif index == 1: return circle_center + Vector2(circle_radius, 0)
		elif index == 2: return circle_center + Vector2(0, circle_radius)
		elif index == 3: return circle_center + Vector2(-circle_radius, 0)
		elif index == 4: return circle_center + Vector2(0, -circle_radius)
	elif is_arc:
		if index == 0: return arc_center
		elif index == 1: return arc_center + Vector2(cos(arc_start_angle), sin(arc_start_angle)) * arc_radius
		elif index == 2: 
			var mid_angle = (arc_start_angle + arc_end_angle) / 2.0
			return arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * arc_radius
		elif index == 3: return arc_center + Vector2(cos(arc_end_angle), sin(arc_end_angle)) * arc_radius
	elif is_point:
		# Pour les points, retourner la position globale du centre
		return to_global(Vector2.ZERO)
	else:
		if index >= 0 and index < points.size(): return to_global(points[index])
	return Vector2.ZERO

func move_point(index: int, new_global_pos: Vector2):
	if is_circle:
		if index == 0: circle_center = new_global_pos
		else: circle_radius = circle_center.distance_to(new_global_pos)
	elif is_arc:
		# Modification des grips pour les arcs - recalculer la géométrie
		# Garder les 2 autres points fixes et recalculer l'arc pour passer par les 3 points
		var start_point = arc_center + Vector2(cos(arc_start_angle), sin(arc_start_angle)) * arc_radius
		var end_point = arc_center + Vector2(cos(arc_end_angle), sin(arc_end_angle)) * arc_radius
		var mid_angle = (arc_start_angle + arc_end_angle) / 2.0
		var mid_point = arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * arc_radius
		
		if index == 0:
			# Déplacer le centre - déplacer tous les points
			var offset = new_global_pos - arc_center
			arc_center = new_global_pos
			start_point += offset
			mid_point += offset
			end_point += offset
		elif index == 1:
			# Modifier le point de départ - garder les autres fixes
			start_point = new_global_pos
		elif index == 2:
			# Modifier le point milieu - garder les autres fixes
			mid_point = new_global_pos
		elif index == 3:
			# Modifier le point de fin - garder les autres fixes
			end_point = new_global_pos
		
		# Recalculer l'arc à partir des 3 points
		var arc_info = ArcGeometry.three_points_to_arc(start_point, mid_point, end_point)
		if arc_info:
			arc_center = arc_info.center
			arc_radius = arc_info.radius
			arc_start_angle = arc_info.start_angle
			arc_end_angle = arc_info.end_angle
			# Régénérer les points de l'arc
			var arc_points = ArcGeometry.generate_arc_points(arc_info, 64)
			points = arc_points
	elif is_point:
		# Pour les points, déplacer le point entier
		global_position = new_global_pos
	else:
		if index >= 0 and index < points.size():
			super.set_point_position(index, to_local(new_global_pos))
	_mark_dirty()
	update_visuals()

func translate_entity(offset: Vector2):
	if is_circle:
		circle_center += offset
		if circle_visual_target != Vector2.ZERO: circle_visual_target += offset
	elif is_arc:
		arc_center += offset
		update_arc_properties(arc_center, arc_radius, arc_start_angle, arc_end_angle)
		return
	elif is_point:
		# Pour les points, déplacer la position globale
		global_position += offset
	else:
		super.translate(offset)
	update_visuals()

# --- FONCTIONS D'ACCROCHAGE (SNAP) ---

# Retourne les points d'accrochage pour le snap_manager
func get_snap_points() -> PackedVector2Array:
	if is_arc:
		# Pour les arcs, uniquement les 3 points de contrôle
		var snap_points = PackedVector2Array()
		var start_point = arc_center + Vector2(cos(arc_start_angle), sin(arc_start_angle)) * arc_radius
		var end_point = arc_center + Vector2(cos(arc_end_angle), sin(arc_end_angle)) * arc_radius
		var mid_angle = (arc_start_angle + arc_end_angle) / 2.0
		var mid_point = arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * arc_radius
		
		snap_points.append(to_global(start_point))
		snap_points.append(to_global(mid_point))
		snap_points.append(to_global(end_point))
		return snap_points
	elif is_point:
		# Pour les points, retourner la position globale (centre du point)
		return PackedVector2Array([to_global(Vector2.ZERO)])
	else:
		# Pour les autres entités, tous les points
		var global_points = PackedVector2Array()
		for p in points:
			global_points.append(to_global(p))
		return global_points

func is_inside_rect(rect: Rect2) -> bool:
	if is_circle:
		var circle_rect = Rect2(circle_center.x - circle_radius, circle_center.y - circle_radius, circle_radius*2, circle_radius*2)
		return rect.encloses(circle_rect)
	elif is_point:
		# Pour les points, vérifier si la position est dans le rectangle
		return rect.has_point(to_global(Vector2.ZERO))
	else:
		for p in points: if not rect.has_point(to_global(p)): return false
		return true

func is_intersecting_rect(rect: Rect2) -> bool:
	if is_circle:
		if rect.has_point(circle_center): return true
		var dist_x = max(0, abs(circle_center.x - rect.get_center().x) - rect.size.x / 2.0)
		var dist_y = max(0, abs(circle_center.y - rect.get_center().y) - rect.size.y / 2.0)
		return (dist_x * dist_x + dist_y * dist_y) < (circle_radius * circle_radius)
	elif is_point:
		# Pour les points, vérifier si la position est dans le rectangle
		return rect.has_point(to_global(Vector2.ZERO))
	else:
		for p in points: if rect.has_point(to_global(p)): return true
		for i in range(points.size() - 1):
			if _segment_intersects_rect(to_global(points[i]), to_global(points[i+1]), rect): return true
		return false
		
func _segment_intersects_rect(p1, p2, rect):
	var corners = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in range(4):
		if Geometry2D.segment_intersects_segment(p1, p2, corners[i], corners[(i+1)%4]) != null: return true
	return false

func _on_layers_changed():
	update_visuals()

# --- FONCTIONS SPÉCIFIQUES AUX ARCS ---

# Crée un arc à partir de trois points
func create_arc_from_three_points(p1: Vector2, p2: Vector2, p3: Vector2) -> bool:
	var arc_info = ArcGeometry.three_points_to_arc(p1, p2, p3)
	if not arc_info:
		return false
	
	# Configurer l'entité comme un arc
	is_arc = true
	is_circle = false
	
	arc_center = arc_info.center
	arc_radius = arc_info.radius
	arc_start_angle = arc_info.start_angle
	arc_end_angle = arc_info.end_angle
	
	# Générer les points pour le Line2D (pour le rendu)
	var arc_points = ArcGeometry.generate_arc_points(arc_info, 64)
	points = arc_points
	
	# Positionner l'entité
	position = Vector2.ZERO
	
	_mark_dirty()
	update_visuals()
	return true

# Met à jour les propriétés d'un arc
func update_arc_properties(center: Vector2, radius: float, start_angle: float, end_angle: float):
	arc_center = center
	arc_radius = radius
	arc_start_angle = start_angle
	arc_end_angle = end_angle
	
	# Régénérer les points
	# Créer les points de l'arc manuellement
	var start_point = center + Vector2(cos(start_angle), sin(start_angle)) * radius
	var end_point = center + Vector2(cos(end_angle), sin(end_angle)) * radius
	var mid_angle = (start_angle + end_angle) / 2.0
	var middle_point = center + Vector2(cos(mid_angle), sin(mid_angle)) * radius
	
	# Utiliser three_points_to_arc pour créer un ArcInfo valide
	var arc_info = ArcGeometry.three_points_to_arc(start_point, middle_point, end_point)
	if arc_info:
		points = ArcGeometry.generate_arc_points(arc_info, 64)
	
	_mark_dirty()
	update_visuals()

# Vérifie si un point est sur l'arc
func is_point_on_arc(point: Vector2, tolerance: float = 5.0) -> bool:
	if not is_arc:
		return false
	
	var dist_to_center = point.distance_to(arc_center)
	if abs(dist_to_center - arc_radius) > tolerance:
		return false
	
	var point_angle = atan2(point.y - arc_center.y, point.x - arc_center.x)
	point_angle = ArcGeometry._normalize_angle(point_angle)
	
	var start = ArcGeometry._normalize_angle(arc_start_angle)
	var end = ArcGeometry._normalize_angle(arc_end_angle)
	
	# Vérifier si l'angle est dans l'intervalle de l'arc
	return ArcGeometry._is_angle_in_arc(point_angle, start, end, end > start)
