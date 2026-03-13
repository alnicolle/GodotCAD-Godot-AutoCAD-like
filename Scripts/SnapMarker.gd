extends Node2D

var marker_size = 15.0
var marker_color = Color(0.0, 1.0, 0.0) # Vert
var line_thickness = 2.0

var current_pos_global = Vector2.ZERO
var is_active = false
var current_zoom = 1.0
var current_mode = "ENDPOINT"

func update_marker(global_pos: Vector2, zoom: float, mode: String = "ENDPOINT"):
	current_pos_global = global_pos
	current_zoom = zoom
	current_mode = mode # Important : On met à jour le mode reçu du SnapManager
	
	if not is_active:
		is_active = true
		visible = true 
		
	queue_redraw()

func hide_marker():
	is_active = false
	visible = false
	queue_redraw()

func _draw():
	if not is_active: return
	
	var local_pos = to_local(current_pos_global)
	var s = marker_size / current_zoom
	var th = line_thickness / current_zoom
	
	match current_mode:
		"MIDPOINT":
			# TRIANGLE
			var p1 = local_pos + Vector2(0, -s/1.5)
			var p2 = local_pos + Vector2(-s/1.5, s/1.5)
			var p3 = local_pos + Vector2(s/1.5, s/1.5)
			var pts = PackedVector2Array([p1, p2, p3, p1])
			draw_polyline(pts, marker_color, th)
			
		"INTERSECTION":
			# CROIX (X)
			var half = s / 1.5
			draw_line(local_pos + Vector2(-half, -half), local_pos + Vector2(half, half), marker_color, th)
			draw_line(local_pos + Vector2(-half, half), local_pos + Vector2(half, -half), marker_color, th)
			
		"CENTER":
			# CERCLE
			draw_arc(local_pos, s/1.5, 0, TAU, 32, marker_color, th)
			
		"PERPENDICULAR":
			# ANGLE DROIT
			var half = s / 1.5
			var p_corner = local_pos + Vector2(-half, half)
			var p_top = local_pos + Vector2(-half, -half)
			var p_right = local_pos + Vector2(half, half)
			draw_line(p_top, p_corner, marker_color, th)
			draw_line(p_corner, p_right, marker_color, th)
			
		_:
			# ENDPOINT (Carré par défaut)
			var offset = Vector2(s / 2.0, s / 2.0)
			var rect = Rect2(local_pos - offset, Vector2(s, s))
			draw_rect(rect, marker_color, false, th)
