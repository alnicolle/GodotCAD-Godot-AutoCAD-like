extends Node2D

# Paramètres du curseur
var aperture_size = 10.0
var crosshair_len = 10000.0 
var cursor_color = Color.WHITE
var line_width = 1.0

var show_crosshair = true

func _ready():
	# La gestion du curseur système est maintenant assurée par CursorManager
	# On ne fait que configurer le curseur CAD lui-même
	z_index = 100 

# SUPPRESSION DE _PROCESS : C'est le SelectionManager qui déplace ce curseur !

func _draw():
	# 1. Carré Central
	var rect_pos = Vector2(-aperture_size / 2, -aperture_size / 2)
	var rect_size = Vector2(aperture_size, aperture_size)
	draw_rect(Rect2(rect_pos, rect_size), cursor_color, false, line_width)

	# 2.# 2. La Croix (Conditionnelle)
	if show_crosshair:
		draw_line(Vector2(-crosshair_len, 0), Vector2(crosshair_len, 0), cursor_color, line_width)
		draw_line(Vector2(0, -crosshair_len), Vector2(0, crosshair_len), cursor_color, line_width)
