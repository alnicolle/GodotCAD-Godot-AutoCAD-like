extends Resource
class_name CADEntityData

# === DONNÉES GÉOMÉTRIQUES PURES ===
# Cette classe ne contient AUCUNE logique de rendu
# C'est un conteneur de données optimisé pour le traitement mathématique

enum EntityType { LINE, CIRCLE, ARC, POINT }

# === MÉCANISME "UNPACKING" (HYBRIDE) ===
var is_hidden: bool = false
var entity_uid: int = -1

# --- PROPRIÉTÉS DE BASE ---
var type: EntityType
var layer_name: String = "0"
var handle: String = ""  # Handle DXF/DWG

# --- PROPRIÉTÉS VISUELLES ---
var color: Color = Color.WHITE
var linetype: String = "CONTINUOUS"
var lineweight: float = 0.25
var linetype_scale: float = 1.0
var is_visible: bool = true

# --- PROPRIÉTÉS GÉOMÉTRIQUES ---
# Pour les lignes
var points: PackedVector2Array = []

# Pour les cercles
var center: Vector2 = Vector2.ZERO
var radius: float = 0.0

# Pour les arcs
var start_angle: float = 0.0
var end_angle: float = 0.0

# Pour les points
var point_size: float = 5.0
var point_style: String = "CROSS"  # "CROSS", "CIRCLE", "SQUARE"

# --- ÉTATS ---
var is_selected: bool = false
var is_hovered: bool = false

# === CONSTRUCTEURS ===

static func create_line(points_array: PackedVector2Array, layer: String = "0") -> CADEntityData:
	var entity = CADEntityData.new()
	entity.type = EntityType.LINE
	entity.points = points_array
	entity.layer_name = layer
	return entity

static func create_circle(c: Vector2, r: float, layer: String = "0") -> CADEntityData:
	var entity = CADEntityData.new()
	entity.type = EntityType.CIRCLE
	entity.center = c
	entity.radius = r
	entity.layer_name = layer
	return entity

static func create_arc(c: Vector2, r: float, start: float, end: float, layer: String = "0") -> CADEntityData:
	var entity = CADEntityData.new()
	entity.type = EntityType.ARC
	entity.center = c
	entity.radius = r
	entity.start_angle = start
	entity.end_angle = end
	entity.layer_name = layer
	return entity

static func create_point(p: Vector2, layer: String = "0") -> CADEntityData:
	var entity = CADEntityData.new()
	entity.type = EntityType.POINT
	entity.center = p
	entity.layer_name = layer
	return entity

# === GÉOMÉTRIE ===

func get_bounds() -> Rect2:
	match type:
		EntityType.LINE:
			if points.size() == 0:
				return Rect2(center, Vector2.ZERO)
			
			var min_x = points[0].x
			var min_y = points[0].y
			var max_x = points[0].x
			var max_y = points[0].y
			
			for point in points:
				min_x = min(min_x, point.x)
				min_y = min(min_y, point.y)
				max_x = max(max_x, point.x)
				max_y = max(max_y, point.y)
			
			return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
		
		EntityType.CIRCLE:
			return Rect2(center - Vector2(radius, radius), Vector2(radius * 2, radius * 2))
		
		EntityType.ARC:
			# Calculer les points extrêmes de l'arc
			var arc_points = _generate_arc_points(32)
			if arc_points.size() == 0:
				return Rect2(center, Vector2.ZERO)
			
			var min_x = arc_points[0].x
			var min_y = arc_points[0].y
			var max_x = arc_points[0].x
			var max_y = arc_points[0].y
			
			for point in arc_points:
				min_x = min(min_x, point.x)
				min_y = min(min_y, point.y)
				max_x = max(max_x, point.x)
				max_y = max(max_y, point.y)
			
			return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
		
		EntityType.POINT:
			var size = point_size * 0.5
			return Rect2(center - Vector2(size, size), Vector2(size * 2, size * 2))
	
	return Rect2(center, Vector2.ZERO)

func get_world_points() -> PackedVector2Array:
	match type:
		EntityType.LINE:
			return points
		EntityType.CIRCLE:
			return _generate_circle_points(64)
		EntityType.ARC:
			return _generate_arc_points(32)
		EntityType.POINT:
			var result = PackedVector2Array()
			result.append(center)
			return result
	
	return PackedVector2Array()

func get_length() -> float:
	match type:
		EntityType.LINE:
			var length = 0.0
			for i in range(points.size() - 1):
				length += points[i].distance_to(points[i + 1])
			return length
		
		EntityType.CIRCLE:
			return TAU * radius
		
		EntityType.ARC:
			var angle_diff = end_angle - start_angle
			if angle_diff < 0:
				angle_diff += TAU
			return radius * angle_diff
		
		EntityType.POINT:
			return 0.0
	
	return 0.0

# === TESTS DE SÉLECTION MATHÉMATIQUES ===

func hit_test(world_pos: Vector2, tolerance: float) -> bool:
	match type:
		EntityType.LINE:
			return _hit_test_line(world_pos, tolerance)
		
		EntityType.CIRCLE:
			return _hit_test_circle(world_pos, tolerance)
		
		EntityType.ARC:
			return _hit_test_arc(world_pos, tolerance)
		
		EntityType.POINT:
			return _hit_test_point(world_pos, tolerance)
	
	return false

func _hit_test_line(world_pos: Vector2, tolerance: float) -> bool:
	for i in range(points.size() - 1):
		var closest = Geometry2D.get_closest_point_to_segment(world_pos, points[i], points[i + 1])
		if world_pos.distance_to(closest) <= tolerance:
			return true
	return false

func _hit_test_circle(world_pos: Vector2, tolerance: float) -> bool:
	var dist = world_pos.distance_to(center)
	return abs(dist - radius) <= tolerance

func _hit_test_arc(world_pos: Vector2, tolerance: float) -> bool:
	# Test de distance au cercle
	var dist = world_pos.distance_to(center)
	if abs(dist - radius) > tolerance:
		return false
	
	# Test si le point est dans l'angle de l'arc
	var point_angle = atan2(world_pos.y - center.y, world_pos.x - center.x)
	point_angle = _normalize_angle(point_angle)
	
	var start = _normalize_angle(start_angle)
	var end = _normalize_angle(end_angle)
	
	return _is_angle_in_arc(point_angle, start, end, end > start)

func _hit_test_point(world_pos: Vector2, tolerance: float) -> bool:
	return world_pos.distance_to(center) <= (point_size + tolerance)

func intersects_rect(rect: Rect2) -> bool:
	# Optimisation : Si les bounding boxes ne se touchent pas, impossible !
	if not rect.intersects(get_bounds()):
		return false
		
	match type:
		EntityType.LINE:
			for p in points: 
				if rect.has_point(p): return true
			for i in range(points.size() - 1):
				if _segment_intersects_rect(points[i], points[i+1], rect): return true
			return false
			
		EntityType.CIRCLE:
			if rect.has_point(center): return true
			var dist_x = max(0, abs(center.x - rect.get_center().x) - rect.size.x / 2.0)
			var dist_y = max(0, abs(center.y - rect.get_center().y) - rect.size.y / 2.0)
			return (dist_x * dist_x + dist_y * dist_y) < (radius * radius)
			
		EntityType.ARC:
			var arc_points = get_world_points()
			for p in arc_points:
				if rect.has_point(p): return true
			for i in range(arc_points.size() - 1):
				if _segment_intersects_rect(arc_points[i], arc_points[i+1], rect): return true
			return false
			
		EntityType.POINT:
			return rect.has_point(center)
			
	return false

func is_inside_rect(rect: Rect2) -> bool:
	var bounds = get_bounds()
	return rect.encloses(bounds)

func _segment_intersects_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> bool:
	var corners = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in range(4):
		if Geometry2D.segment_intersects_segment(p1, p2, corners[i], corners[(i+1)%4]) != null: 
			return true
	return false

# === PROPRIÉTÉS EFFECTIVES ===

func get_effective_color(base_color: Color) -> Color:
	if is_selected:
		return Color(0.2, 0.6, 1.0)  # Bleu sélection
	elif is_hovered:
		return Color(1.0, 1.0, 1.0, 0.8)  # Blanc semi-transparent
	
	return color if color != Color.WHITE else base_color

func get_effective_lineweight() -> float:
	return lineweight

# === TRANSFORMATIONS ===

func translate(offset: Vector2):
	match type:
		EntityType.LINE:
			for i in range(points.size()):
				points[i] += offset
		EntityType.CIRCLE, EntityType.ARC, EntityType.POINT:
			center += offset

func rotate_around(pivot: Vector2, angle: float):
	match type:
		EntityType.LINE:
			for i in range(points.size()):
				points[i] = _rotate_point_around(points[i], pivot, angle)
		EntityType.CIRCLE, EntityType.ARC, EntityType.POINT:
			center = _rotate_point_around(center, pivot, angle)
			if type == EntityType.ARC:
				start_angle += angle
				end_angle += angle

func scale_around(pivot: Vector2, factor: float):
	match type:
		EntityType.LINE:
			for i in range(points.size()):
				points[i] = _scale_point_around(points[i], pivot, factor)
		EntityType.CIRCLE, EntityType.ARC, EntityType.POINT:
			center = _scale_point_around(center, pivot, factor)
			radius *= factor

func mirror_across_line(p1: Vector2, p2: Vector2):
	match type:
		EntityType.LINE:
			for i in range(points.size()):
				points[i] = _mirror_point_across_line(points[i], p1, p2)
		EntityType.CIRCLE, EntityType.ARC, EntityType.POINT:
			center = _mirror_point_across_line(center, p1, p2)

# === UTILITAIRES INTERNES ===

func _generate_circle_points(num_points: int) -> PackedVector2Array:
	var result = PackedVector2Array()
	for i in range(num_points + 1):
		var angle = (TAU * float(i)) / float(num_points)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return result

func _generate_arc_points(num_points: int) -> PackedVector2Array:
	var result = PackedVector2Array()
	var angle_step = (end_angle - start_angle) / num_points
	
	for i in range(num_points + 1):
		var angle = start_angle + angle_step * i
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	
	return result

func _normalize_angle(angle: float) -> float:
	while angle < 0:
		angle += TAU
	while angle >= TAU:
		angle -= TAU
	return angle

func _is_angle_in_arc(test_angle: float, start: float, end: float, clockwise: bool) -> bool:
	if clockwise:
		return test_angle >= start and test_angle <= end
	else:
		return test_angle >= start or test_angle <= end

func _rotate_point_around(point: Vector2, pivot: Vector2, angle: float) -> Vector2:
	var cos_a = cos(angle)
	var sin_a = sin(angle)
	var translated = point - pivot
	return Vector2(
		translated.x * cos_a - translated.y * sin_a + pivot.x,
		translated.x * sin_a + translated.y * cos_a + pivot.y
	)

func _scale_point_around(point: Vector2, pivot: Vector2, factor: float) -> Vector2:
	return pivot + (point - pivot) * factor

func _mirror_point_across_line(point: Vector2, line_p1: Vector2, line_p2: Vector2) -> Vector2:
	var line_vec = line_p2 - line_p1
	var point_vec = point - line_p1
	
	# Projection du point sur la ligne
	var line_length_sq = line_vec.dot(line_vec)
	if line_length_sq == 0:
		return point
	
	var t = point_vec.dot(line_vec) / line_length_sq
	var projection = line_p1 + line_vec * t
	
	# Le point miroir est symétrique par rapport à la projection
	return projection + (projection - point)

# === SÉRIALISATION ===

func to_dict() -> Dictionary:
	return {
		"type": type,
		"layer_name": layer_name,
		"handle": handle,
		"color": color.to_html(),
		"linetype": linetype,
		"lineweight": lineweight,
		"linetype_scale": linetype_scale,
		"is_visible": is_visible,
		"points": points,
		"center": center,
		"radius": radius,
		"start_angle": start_angle,
		"end_angle": end_angle,
		"point_size": point_size,
		"point_style": point_style,
		"is_selected": is_selected,
		"is_hovered": is_hovered
	}

static func from_dict(data: Dictionary) -> CADEntityData:
	var entity = CADEntityData.new()
	entity.type = data.get("type", EntityType.LINE)
	entity.layer_name = data.get("layer_name", "0")
	entity.handle = data.get("handle", "")
	entity.color = Color.from_string(data.get("color", "#FFFFFF"), Color.WHITE)
	entity.linetype = data.get("linetype", "CONTINUOUS")
	entity.lineweight = data.get("lineweight", 0.25)
	entity.linetype_scale = data.get("linetype_scale", 1.0)
	entity.is_visible = data.get("is_visible", true)
	entity.points = data.get("points", PackedVector2Array())
	entity.center = data.get("center", Vector2.ZERO)
	entity.radius = data.get("radius", 0.0)
	entity.start_angle = data.get("start_angle", 0.0)
	entity.end_angle = data.get("end_angle", 0.0)
	entity.point_size = data.get("point_size", 5.0)
	entity.point_style = data.get("point_style", "CROSS")
	entity.is_selected = data.get("is_selected", false)
	entity.is_hovered = data.get("is_hovered", false)
	
	return entity
