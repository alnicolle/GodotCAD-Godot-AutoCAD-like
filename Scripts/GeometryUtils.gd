extends RefCounted
class_name GeometryUtils

static func generate_insulation_points(original_points: PackedVector2Array, width: float) -> PackedVector2Array:
	var result = PackedVector2Array()
	if original_points.size() < 2: return result
	
	
	# Paramètres fixes
	var separation_factor = 0.5
	
	# QUALITÉ FIXE OPTIMISÉE
	# 8 est suffisant pour que ça paraisse rond sans tuer le processeur
	# Inutile de mettre 32 si on a un système de LOD (voir CADEntity)
	var steps = 6 
	
	var h_offset = (width * separation_factor) / 2.0
	var target_diameter = width * 0.5 
	
	for i in range(original_points.size() - 1):
		var p_start = original_points[i]
		var p_end = original_points[i+1]
		var seg_vec = p_end - p_start
		var seg_len = seg_vec.length()
		
		if seg_len < 0.001: continue
		
		var dir = seg_vec / seg_len
		var norm = Vector2(-dir.y, dir.x) 
		
		var num_cycles = max(1, round(seg_len / target_diameter))
		var actual_diameter = seg_len / num_cycles
		var r = actual_diameter / 2.0
		
		for c in range(num_cycles):
			var origin_x = c * actual_diameter
			var p_origin = p_start + dir * origin_x
			var center_bot = p_origin + (dir * r) - (norm * h_offset)
			
			# ARC BAS
			for s in range(steps + 1):
				var t = float(s) / steps
				var angle = PI + (t * PI)
				var pt = center_bot + (dir * cos(angle) * r) + (norm * sin(angle) * r)
				result.append(pt)
			
			var center_top = p_origin + (dir * (2.0 * r)) + (norm * h_offset)
			
			# ARC HAUT
			for s in range(steps + 1):
				var t = float(s) / steps
				var angle = PI - (t * PI)
				var pt = center_top + (dir * cos(angle) * r) + (norm * sin(angle) * r)
				result.append(pt)

	return result
