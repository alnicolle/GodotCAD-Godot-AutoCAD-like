extends HBoxContainer

signal snap_settings_changed

@onready var menu_btn = find_child("BtnSnapSettings")
@onready var check_box = find_child("CheckSnap")

# --- REFERENCE AU MARKER VISUEL ---
@export var snap_marker : Node2D 

var is_snapping_active = true

var snap_modes = {
	"ENDPOINT": true,
	"MIDPOINT": true,
	"CENTER": true,
	"INTERSECTION": true,
	"PERPENDICULAR": true # Activé
}

var mode_names = {
	"ENDPOINT": "Extrémité",
	"MIDPOINT": "Milieu",
	"CENTER": "Centre",
	"INTERSECTION": "Intersection",
	"PERPENDICULAR": "Perpendiculaire"
}

func _ready():
	check_box.toggled.connect(_on_check_snap_toggled)
	var popup = menu_btn.get_popup()
	popup.id_pressed.connect(_on_menu_item_pressed)
	popup.hide_on_checkable_item_selection = false
	build_menu()

func build_menu():
	var popup = menu_btn.get_popup()
	popup.clear()
	var keys = snap_modes.keys()
	for i in range(keys.size()):
		var key = keys[i]
		popup.add_check_item(mode_names[key], i)
		popup.set_item_checked(i, snap_modes[key])

func _on_check_snap_toggled(toggled_on):
	is_snapping_active = toggled_on
	modulate = Color.WHITE if is_snapping_active else Color(1, 1, 1, 0.5)
	
	GlobalLogger.debug("Accrochage " + ("activé" if is_snapping_active else "désactivé"))
	
	if not is_snapping_active:
		reset_visuals()

func _on_menu_item_pressed(id):
	var popup = menu_btn.get_popup()
	var keys = snap_modes.keys()
	var key = keys[id]
	snap_modes[key] = !snap_modes[key]
	popup.set_item_checked(id, snap_modes[key])

func reset_visuals():
	if snap_marker:
		snap_marker.hide_marker()

# --- CŒUR DU SNAPPING ---

func get_snapped_position(mouse_pos: Vector2, world_entities_node: Node2D, camera_zoom: float, exclude_entity = null, ignored_index: int = -1) -> Vector2:
	if not is_snapping_active:
		reset_visuals()
		return mouse_pos
		
	var snap_distance = 15.0 / camera_zoom
	var best_point = mouse_pos
	var min_dist = snap_distance
	var found = false
	var best_mode = "ENDPOINT"
	
	# --- DEBUG : Affiche info sur l'objet en cours ---
	var debug_self = (exclude_entity is CADEntity)
	# Décommenter la ligne suivante si vous ne voyez RIEN du tout dans la console
	# if debug_self: print("--- DEBUG FRAME --- Objet en cours : ", exclude_entity, " | Points : ", exclude_entity.points.size())

	# 1. POINT DE RÉFÉRENCE (Perpendiculaire) - inchangé
	var ref_point = null
	if snap_modes["PERPENDICULAR"] and exclude_entity is CADEntity and not exclude_entity.get("is_circle"):
		var pts = exclude_entity.points
		if ignored_index > 0 and ignored_index < pts.size():
			ref_point = exclude_entity.to_global(pts[ignored_index - 1])
		elif pts.size() >= 2:
			ref_point = exclude_entity.to_global(pts[pts.size() - 2])

	# 2. RÉCUPÉRATION ET FILTRAGE SPATIAL
	var valid_entities = []
	var raw_list = _get_all_entities_recursive(world_entities_node)
	
	# Ajout forcé si absent
	if exclude_entity is CADEntity:
		if not (exclude_entity in raw_list) and exclude_entity.visible:
			if debug_self: print("DEBUG: Ajout forcé de l'objet self à la liste brute.")
			raw_list.append(exclude_entity)
	
	for ent in raw_list:
		if not ent.visible: continue
		if typeof(exclude_entity) == TYPE_ARRAY and ent in exclude_entity: continue
		
		# On vérifie si c'est l'objet en cours
		var is_current_obj = (exclude_entity and ent == exclude_entity)
		
		# Filtre spatial
		var is_near = _is_mouse_near_entity(ent, mouse_pos, snap_distance)
		
		# DEBUG FILTRE
		if is_current_obj and debug_self:
			if not is_near:
				print("DEBUG ALERTE: L'objet SELF est rejeté par le filtre spatial (Trop loin) !")
			else:
				# print("DEBUG: L'objet SELF est accepté par le filtre spatial.")
				pass

		if is_current_obj or is_near:
			valid_entities.append(ent)

	# 3. BOUCLE PRINCIPALE
	for ent in valid_entities:
		var is_self = (typeof(exclude_entity) != TYPE_ARRAY and ent == exclude_entity)
		
		# Calcul de l'index à ignorer
		var current_ignored_index = ignored_index
		if is_self and current_ignored_index == -1 and "points" in ent:
			current_ignored_index = ent.points.size() - 1
			
			if debug_self:
				# print("DEBUG: Mode Self. Index ignoré calculé : ", current_ignored_index, " (Total points: ", ent.points.size(), ")")
				pass
		
		var is_circle = ent.get("is_circle")
		var is_point = ent.get("is_point")
		
		# --- ENDPOINT ---
		if snap_modes["ENDPOINT"]:
			if is_circle:
				# (Code cercle inchangé...)
				var c = ent.circle_center
				if ent.position != Vector2.ZERO: c += ent.position
				var r = ent.circle_radius
				var quadrants = [c + Vector2(r, 0), c + Vector2(-r, 0), c + Vector2(0, r), c + Vector2(0, -r)]
				for q in quadrants:
					var dist = q.distance_to(mouse_pos)
					if dist < min_dist: min_dist = dist; best_point = q; found = true; best_mode = "ENDPOINT"
			
			elif is_point:
				# Pour les points, le point lui-même est un endpoint
				var point_pos = ent.to_global(Vector2.ZERO)
				var dist = point_pos.distance_to(mouse_pos)
				if dist < min_dist: 
					min_dist = dist
					best_point = point_pos
					found = true
					best_mode = "ENDPOINT"
			
			elif "points" in ent:
				for i in range(ent.points.size()):
					# DEBUG LOOP POINTS
					if is_self and debug_self:
						var p_debug = ent.to_global(ent.points[i])
						var d_debug = p_debug.distance_to(mouse_pos)
						# print("  > Point ", i, " Dist: ", d_debug)
						
						if i == current_ignored_index:
							# print("    -> REJETÉ (Index ignoré)")
							continue
					
					# Filtre standard
					if is_self and i == current_ignored_index: continue
					
					var global_p = ent.to_global(ent.points[i])
					var dist = global_p.distance_to(mouse_pos)
					
					# DEBUG REUSSITE
					if is_self and debug_self and dist < min_dist:
						print("DEBUG SUCCÈS: Snap trouvé sur point ", i, " (Dist: ", dist, ")")

					if dist < min_dist: 
						min_dist = dist
						best_point = global_p
						found = true
						best_mode = "ENDPOINT"

		# --- MIDPOINT (inchangé pour le debug, le problème est souvent sur Endpoint) ---
		if snap_modes["MIDPOINT"] and not is_circle and "points" in ent:
			for i in range(ent.points.size() - 1):
				if is_self and (i == current_ignored_index or (i + 1) == current_ignored_index): continue 
				var p1 = ent.to_global(ent.points[i])
				var p2 = ent.to_global(ent.points[i+1])
				var mid = (p1 + p2) / 2.0
				var dist = mid.distance_to(mouse_pos)
				if dist < min_dist: min_dist = dist; best_point = mid; found = true; best_mode = "MIDPOINT"
		
		# --- CENTER (inchangé) ---
		if snap_modes["CENTER"]:
			if is_circle:
				var center = ent.circle_center
				if ent.position != Vector2.ZERO: center += ent.position
				if not (is_self and current_ignored_index == 0):
					var dist = center.distance_to(mouse_pos)
					if dist < min_dist: min_dist = dist; best_point = center; found = true; best_mode = "CENTER"
			elif is_point:
				# Pour les points, le centre est le point lui-même
				var point_pos = ent.to_global(Vector2.ZERO)
				var dist = point_pos.distance_to(mouse_pos)
				if dist < min_dist: 
					min_dist = dist
					best_point = point_pos
					found = true
					best_mode = "CENTER"

		# --- PERPENDICULAR (inchangé) ---
		if snap_modes["PERPENDICULAR"] and ref_point != null:
			if is_circle:
				if is_self: continue
				var c = ent.circle_center
				if ent.position != Vector2.ZERO: c += ent.position
				var r = ent.circle_radius
				var dir = (c - ref_point).normalized()
				var p_near = c - dir * r
				var p_far = c + dir * r
				if p_near.distance_to(mouse_pos) < min_dist: min_dist = p_near.distance_to(mouse_pos); best_point = p_near; found = true; best_mode = "PERPENDICULAR"
				if p_far.distance_to(mouse_pos) < min_dist: min_dist = p_far.distance_to(mouse_pos); best_point = p_far; found = true; best_mode = "PERPENDICULAR"
			elif "points" in ent:
				for i in range(ent.points.size() - 1):
					if is_self and (i == current_ignored_index or (i + 1) == current_ignored_index): continue
					var p1 = ent.to_global(ent.points[i])
					var p2 = ent.to_global(ent.points[i+1])
					var proj = _get_projection_on_line(ref_point, p1, p2)
					if _is_point_on_segment(proj, p1, p2):
						var dist = proj.distance_to(mouse_pos)
						if dist < min_dist: min_dist = dist; best_point = proj; found = true; best_mode = "PERPENDICULAR"

	# 4. INTERSECTIONS (inchangé)
	if snap_modes["INTERSECTION"]:
		for i in range(valid_entities.size()):
			var ent_a = valid_entities[i]
			for j in range(i + 1, valid_entities.size()):
				var ent_b = valid_entities[j]
				var intersections = _get_intersections(ent_a, ent_b)
				for pt in intersections:
					var dist = pt.distance_to(mouse_pos)
					if dist < min_dist: min_dist = dist; best_point = pt; found = true; best_mode = "INTERSECTION"

	if snap_marker:
		if found: snap_marker.update_marker(best_point, camera_zoom, best_mode)
		else: snap_marker.hide_marker()
	
	return best_point if found else mouse_pos

# --- UTILITAIRES MATHÉMATIQUES ---

func _get_projection_on_line(pt: Vector2, v1: Vector2, v2: Vector2) -> Vector2:
	var v = v2 - v1
	if v.is_zero_approx(): return v1
	var t = (pt - v1).dot(v) / v.dot(v)
	return v1 + v * t

func _is_point_on_segment(pt: Vector2, v1: Vector2, v2: Vector2) -> bool:
	var v = v2 - v1
	if v.is_zero_approx(): return pt.distance_to(v1) < 0.1
	# On projette pour avoir t
	var t = (pt - v1).dot(v) / v.dot(v)
	return t >= 0.0 and t <= 1.0

# --- MOTEUR D'INTERSECTION (EXISTANT) ---

func _get_intersections(ent_a: Node2D, ent_b: Node2D) -> Array:
	var result = []
	var a_is_circle := ("is_circle" in ent_a) and bool(ent_a.is_circle)
	var b_is_circle := ("is_circle" in ent_b) and bool(ent_b.is_circle)
	var a_is_arc := ("is_arc" in ent_a) and bool(ent_a.is_arc)
	var b_is_arc := ("is_arc" in ent_b) and bool(ent_b.is_arc)
	var a_is_point := ("is_point" in ent_a) and bool(ent_a.is_point)
	var b_is_point := ("is_point" in ent_b) and bool(ent_b.is_point)
	var a_is_circlelike := a_is_circle or a_is_arc
	var b_is_circlelike := b_is_circle or b_is_arc
	
	# Les points n'ont pas d'intersection avec d'autres objets
	if a_is_point or b_is_point:
		return result
	
	if a_is_circlelike and b_is_circlelike:
		result = _intersect_circle_circle(ent_a, ent_b)
	elif a_is_circlelike != b_is_circlelike:
		var circle_ent = ent_a if a_is_circlelike else ent_b
		var line_ent = ent_b if a_is_circlelike else ent_a
		result = _intersect_circle_line(circle_ent, line_ent)
	else:
		result = _intersect_line_line(ent_a, ent_b)

	# Filtrer si un des deux est un arc (intersection cercle->arc)
	if a_is_arc:
		result = _filter_points_on_arc_world(ent_a, result)
	if b_is_arc:
		result = _filter_points_on_arc_world(ent_b, result)
	return result

func _circlelike_center_world(ent: Node2D) -> Vector2:
	if ("is_circle" in ent) and ent.is_circle:
		return ent.circle_center + ent.global_position
	if ("is_arc" in ent) and ent.is_arc:
		return ent.arc_center + ent.global_position
	return ent.global_position

func _circlelike_radius(ent: Node2D) -> float:
	if ("is_circle" in ent) and ent.is_circle:
		return ent.circle_radius
	if ("is_arc" in ent) and ent.is_arc:
		return ent.arc_radius
	return 0.0

func _lift_angle_into_range(angle: float, start_angle: float, end_angle: float) -> float:
	var a = fposmod(angle, TAU)
	while a < start_angle:
		a += TAU
	while a > end_angle:
		a -= TAU
	return a

func _filter_points_on_arc_world(arc: Node2D, points_world: Array) -> Array:
	# Tolérance en pixels monde pour la distance au cercle
	var tol_dist := 5.0
	var tol_ang := 0.01
	var out: Array = []
	if not (("is_arc" in arc) and arc.is_arc):
		return points_world
	var center = arc.arc_center + arc.global_position
	var r = arc.arc_radius
	var sa_raw: float = arc.arc_start_angle
	var ea_raw: float = arc.arc_end_angle
	var ccw := ea_raw >= sa_raw
	var sa = fposmod(sa_raw, TAU)
	var ea = fposmod(ea_raw, TAU)
	for p in points_world:
		if abs(p.distance_to(center) - r) > tol_dist:
			continue
		var a = fposmod((p - center).angle(), TAU)
		if ccw:
			var diff = ArcGeometry._angle_difference_ccw(sa, ea)
			var angle_diff = ArcGeometry._angle_difference_ccw(sa, a)
			if angle_diff <= diff + tol_ang:
				out.append(p)
		else:
			var diff = ArcGeometry._angle_difference_cw(sa, ea)
			var angle_diff = ArcGeometry._angle_difference_cw(sa, a)
			if angle_diff <= diff + tol_ang:
				out.append(p)
	return out

func _intersect_line_line(ent_a, ent_b) -> Array:
	var res = []
	var points_a = ent_a.points
	var points_b = ent_b.points
	if points_a.size() < 2 or points_b.size() < 2: return res
	for i in range(points_a.size() - 1):
		var a1 = ent_a.to_global(points_a[i])
		var a2 = ent_a.to_global(points_a[i+1])
		for j in range(points_b.size() - 1):
			var b1 = ent_b.to_global(points_b[j])
			var b2 = ent_b.to_global(points_b[j+1])
			var intersection = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
			if intersection != null: res.append(intersection)
	return res

func _intersect_circle_line(circle, line) -> Array:
	var res = []
	var center = _circlelike_center_world(circle)
	var radius = _circlelike_radius(circle)
	var pts = line.points
	if pts.size() < 2: return res
	for i in range(pts.size() - 1):
		var p1 = line.to_global(pts[i])
		var p2 = line.to_global(pts[i+1])
		var d = p2 - p1
		var f = p1 - center
		var a = d.dot(d)
		var b = 2.0 * f.dot(d)
		var c = f.dot(f) - radius * radius
		var discriminant = b*b - 4*a*c
		if discriminant >= 0:
			discriminant = sqrt(discriminant)
			var t1 = (-b - discriminant) / (2*a)
			var t2 = (-b + discriminant) / (2*a)
			if t1 >= 0 and t1 <= 1: res.append(p1 + d * t1)
			if t2 >= 0 and t2 <= 1: res.append(p1 + d * t2)
	return res

func _intersect_circle_circle(c1, c2) -> Array:
	var res = []
	var p1 = _circlelike_center_world(c1)
	var r1 = _circlelike_radius(c1)
	var p2 = _circlelike_center_world(c2)
	var r2 = _circlelike_radius(c2)
	var d_vec = p2 - p1
	var d = d_vec.length()
	if d > r1 + r2 or d < abs(r1 - r2) or d == 0: return res
	var a = (r1*r1 - r2*r2 + d*d) / (2*d)
	var h = sqrt(max(0, r1*r1 - a*a))
	var p2_proj = p1 + (d_vec * (a/d))
	var x3 = p2_proj.x + h * (p2.y - p1.y) / d
	var y3 = p2_proj.y - h * (p2.x - p1.x) / d
	var x4 = p2_proj.x - h * (p2.y - p1.y) / d
	var y4 = p2_proj.y + h * (p2.x - p1.x) / d
	res.append(Vector2(x3, y3))
	res.append(Vector2(x4, y4))
	return res


# Fonction récursive pour récupérer les entités dans les calques
func _get_all_entities_recursive(node: Node) -> Array:
	var list = []
	for child in node.get_children():
		# Si c'est un calque (Node2D simple) visible
		if child is Node2D and not (child is CADEntity) and child.visible:
			list.append_array(_get_all_entities_recursive(child))
		# Si c'est une entité CAD visible
		elif child is CADEntity and child.visible:
			list.append(child)
	return list

# Fonction de filtrage spatial MANUEL (Remplace get_rect qui buggait)
func _is_mouse_near_entity(ent, mouse_pos: Vector2, margin: float) -> bool:
	# Cas Cercle : Distance au centre
	if ent.get("is_circle"):
		var c = ent.global_position
		if "circle_center" in ent: c += ent.circle_center
		var r = ent.circle_radius
		# On vérifie si on est dans le rayon + marge
		return c.distance_squared_to(mouse_pos) < (r + margin) ** 2

	# Cas Point : Distance au point
	elif ent.get("is_point"):
		var point_pos = ent.to_global(Vector2.ZERO)
		return point_pos.distance_squared_to(mouse_pos) < margin ** 2

	# Cas Polyligne / Ligne : Vérification Box des points
	elif "points" in ent and ent.points.size() > 0:
		# On convertit la souris en local pour comparer avec les points locaux
		var local_mouse = ent.to_local(mouse_pos)
		
		# On calcule une "Bounding Box" rapide autour des points
		# Pas besoin d'être précis au pixel, on veut juste éliminer ce qui est loin
		var min_x = ent.points[0].x
		var max_x = ent.points[0].x
		var min_y = ent.points[0].y
		var max_y = ent.points[0].y
		
		# Note : Pour 2000 objets simples, cette boucle est très rapide
		for p in ent.points:
			if p.x < min_x: min_x = p.x
			if p.x > max_x: max_x = p.x
			if p.y < min_y: min_y = p.y
			if p.y > max_y: max_y = p.y
			
		# On ajoute la marge de snap
		var rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		return rect.grow(margin).has_point(local_mouse)
		
	return false
