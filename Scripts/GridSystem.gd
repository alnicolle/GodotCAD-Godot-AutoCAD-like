extends Node2D

@onready var camera = $"../Camera2D"

var grid_step = 100.0   # Taille des carreaux
var grid_color = Color(0.2, 0.2, 0.2, 0.5) # Gris discret

func _ready() -> void:
	# Placer la grille sur le calque de visibilité 2 
	# pour pouvoir la cacher dans la fenêtre de présentation (Layout)
	visibility_layer = 2

func _process(delta):
	# Redessine en permanence quand on bouge
	queue_redraw()

func _draw():
	if not camera: return

	var zoom = camera.zoom.x
	var cam_pos = camera.global_position
	var viewport_size = get_viewport_rect().size
	
	# Calcul de la taille de la zone visible dans le MONDE
	# On divise par le zoom : si on zoom (2x), on voit 2x moins de monde
	var visible_world_size = viewport_size / zoom
	
	# Calcul des bornes (Gauche, Droite, Haut, Bas)
	# Comme la caméra est au centre, on enlève la moitié de la taille visible
	var left = cam_pos.x - (visible_world_size.x / 2)
	var right = cam_pos.x + (visible_world_size.x / 2)
	var top = cam_pos.y - (visible_world_size.y / 2)
	var bottom = cam_pos.y + (visible_world_size.y / 2)
	
	# On "snappe" le début du tracé sur la grille pour que ça ait l'air infini
	# (Sinon les lignes glisseraient avec la caméra)
	var first_x = floor(left / grid_step) * grid_step
	var first_y = floor(top / grid_step) * grid_step
	
	# Dessin des lignes Verticales
	var x = first_x
	while x < right + grid_step:
		draw_line(Vector2(x, top), Vector2(x, bottom), grid_color, 1.0 / zoom)
		x += grid_step
		
	# Dessin des lignes Horizontales
	var y = first_y
	while y < bottom + grid_step:
		draw_line(Vector2(left, y), Vector2(right, y), grid_color, 1.0 / zoom)
		y += grid_step

	# AXES X et Y (Bien rouges et verts pour se repérer)
	# On ne les dessine que s'ils sont dans le champ de vision
	if top < 0 and bottom > 0:
		draw_line(Vector2(left, 0), Vector2(right, 0), Color.GREEN, 2.0 / zoom) # Axe X
	if left < 0 and right > 0:
		draw_line(Vector2(0, top), Vector2(0, bottom), Color.RED, 2.0 / zoom)   # Axe Y
