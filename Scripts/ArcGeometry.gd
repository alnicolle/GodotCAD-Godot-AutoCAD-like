extends RefCounted
class_name ArcGeometry

# Classe statique pour les calculs géométriques des arcs de cercle
# Implémente l'algorithme "3 points vers Arc"

# Structure pour stocker les informations d'un arc
class ArcInfo:
	var center: Vector2
	var radius: float
	var start_angle: float  # En radians
	var end_angle: float    # En radians
	var start_point: Vector2
	var middle_point: Vector2
	var end_point: Vector2
	
	func _init(c: Vector2, r: float, sa: float, ea: float, sp: Vector2, mp: Vector2, ep: Vector2):
		center = c
		radius = r
		start_angle = sa
		end_angle = ea
		start_point = sp
		middle_point = mp
		end_point = ep

# Fonction principale : 3 points vers Arc
# Retourne null si les points sont colinéaires ou invalides
static func three_points_to_arc(p1: Vector2, p2: Vector2, p3: Vector2) -> ArcInfo:
	# Vérifier si les points sont colinéaires
	if _are_points_collinear(p1, p2, p3):
		#GlobalLogger.warning(tr("MSG_CONSOLE_ARC_1"))
		return null
	
	# Calculer le centre du cercle passant par les 3 points
	var center = _calculate_circle_center(p1, p2, p3)
	if center == Vector2.INF:  # Centre invalide (points colinéaires)
		return null
	
	# Calculer le rayon
	var radius = center.distance_to(p1)
	
	# Calculer les angles de départ et de fin
	var start_angle = _point_to_angle(center, p1)
	var middle_angle = _point_to_angle(center, p2)
	var end_angle = _point_to_angle(center, p3)
	
	# Déterminer le sens de l'arc (horaire ou anti-horaire)
	var arc_direction = _determine_arc_direction(start_angle, middle_angle, end_angle)
	
	# Ajuster les angles pour le sens correct
	var adjusted_angles = _adjust_angles_for_direction(start_angle, middle_angle, end_angle, arc_direction)
	
	return ArcInfo.new(center, radius, adjusted_angles.start, adjusted_angles.end, p1, p2, p3)

# Vérifie si trois points sont colinéaires
static func _are_points_collinear(p1: Vector2, p2: Vector2, p3: Vector2) -> bool:
	# Calcul de l'aire du triangle formé par les trois points
	# Si l'aire est proche de 0, les points sont colinéaires
	var area = abs((p2.x - p1.x) * (p3.y - p1.y) - (p3.x - p1.x) * (p2.y - p1.y))
	return area < 0.001  # Tolérance pour les erreurs de précision

# Calcule le centre du cercle passant par trois points
static func _calculate_circle_center(p1: Vector2, p2: Vector2, p3: Vector2) -> Vector2:
	# Utiliser la formule basée sur les intersections des médiatrices
	var ax = p1.x
	var ay = p1.y
	var bx = p2.x
	var by = p2.y
	var cx = p3.x
	var cy = p3.y
	
	# Calcul des déterminants
	var d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
	
	if abs(d) < 0.001:  # Points colinéaires
		return Vector2.INF  # Indique que le centre est invalide
	
	var ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
	var uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
	
	return Vector2(ux, uy)

# Convertit un point par rapport à un centre en angle (en radians)
static func _point_to_angle(center: Vector2, point: Vector2) -> float:
	var diff = point - center
	if diff.length_squared() < 0.001:  # Points identiques
		return 0.0
	return atan2(diff.y, diff.x)

# Détermine le sens de l'arc (true = anti-horaire, false = horaire)
static func _determine_arc_direction(start_angle: float, middle_angle: float, end_angle: float) -> bool:
	# Normaliser les angles entre 0 et 2π
	var sa = _normalize_angle(start_angle)
	var ma = _normalize_angle(middle_angle)
	var ea = _normalize_angle(end_angle)
	
	# Calculer la différence angulaire dans le sens anti-horaire
	var ccw_diff = _angle_difference_ccw(sa, ea)
	var cw_diff = _angle_difference_cw(sa, ea)
	
	# Vérifier si l'angle du milieu est dans le sens anti-horaire
	var middle_in_ccw = _is_angle_in_arc(ma, sa, ea, true)
	var middle_in_cw = _is_angle_in_arc(ma, sa, ea, false)
	
	if middle_in_ccw:
		return true  # Anti-horaire
	elif middle_in_cw:
		return false  # Horaire
	else:
		# Cas par défaut : anti-horaire
		return true

# Normalise un angle entre 0 et 2π
static func _normalize_angle(angle: float) -> float:
	while angle < 0:
		angle += 2 * PI
	while angle >= 2 * PI:
		angle -= 2 * PI
	return angle

# Calcule la différence angulaire dans le sens anti-horaire
static func _angle_difference_ccw(start: float, end: float) -> float:
	var diff = end - start
	if diff < 0:
		diff += 2 * PI
	return diff

# Calcule la différence angulaire dans le sens horaire
static func _angle_difference_cw(start: float, end: float) -> float:
	var diff = start - end
	if diff < 0:
		diff += 2 * PI
	return diff

# Vérifie si un angle est dans un arc
static func _is_angle_in_arc(angle: float, start: float, end: float, ccw: bool) -> bool:
	if ccw:
		var diff = _angle_difference_ccw(start, end)
		var angle_diff = _angle_difference_ccw(start, angle)
		return angle_diff <= diff + 0.001  # Tolérance
	else:
		var diff = _angle_difference_cw(start, end)
		var angle_diff = _angle_difference_cw(start, angle)
		return angle_diff <= diff + 0.001  # Tolérance

# Ajuste les angles pour le sens correct de l'arc
static func _adjust_angles_for_direction(start_angle: float, middle_angle: float, end_angle: float, ccw: bool) -> Dictionary:
	var sa = _normalize_angle(start_angle)
	var ea = _normalize_angle(end_angle)
	
	if ccw:
		# S'assurer que l'angle de fin est après l'angle de départ dans le sens anti-horaire
		if ea < sa:
			ea += 2 * PI
	else:
		# S'assurer que l'angle de fin est avant l'angle de départ dans le sens horaire
		if ea > sa:
			ea -= 2 * PI
	
	return {"start": sa, "end": ea}

# Calcule un point sur l'arc à un angle donné
static func get_point_on_arc(arc_info: ArcInfo, angle: float) -> Vector2:
	var x = arc_info.center.x + arc_info.radius * cos(angle)
	var y = arc_info.center.y + arc_info.radius * sin(angle)
	return Vector2(x, y)

# Génère les points pour dessiner l'arc (pour l'affichage)
static func generate_arc_points(arc_info: ArcInfo, num_segments: int = 32) -> PackedVector2Array:
	var points = PackedVector2Array()
	
	if not arc_info:
		return points
	
	var angle_step = (arc_info.end_angle - arc_info.start_angle) / num_segments
	
	for i in range(num_segments + 1):
		var angle = arc_info.start_angle + angle_step * i
		var point = get_point_on_arc(arc_info, angle)
		points.append(point)
	
	return points

# Calcule la longueur de l'arc
static func calculate_arc_length(arc_info: ArcInfo) -> float:
	if not arc_info:
		return 0.0
	
	var angle_span = abs(arc_info.end_angle - arc_info.start_angle)
	return arc_info.radius * angle_span
