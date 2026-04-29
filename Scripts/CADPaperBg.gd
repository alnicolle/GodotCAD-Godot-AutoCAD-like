extends ColorRect

@onready var camera = $"../LayoutCamera"

# Couleurs par défaut (gris AutoCAd classic)
const BG_COLOR = Color(0.45, 0.45, 0.45, 1.0)

func _ready():
	# Forcer la couleur pour s'assurer que c'est un fond propre
	color = BG_COLOR
	# Reset z_index -100 mettait le rectangle au tout fin fond du moteur
	# En laissant z_index par défaut, l'ordre de l'arborescence s'applique
	z_index = 0

func _process(delta):
	# Si la caméra est valide, on s'accroche physiquement à elle !
	if camera:
		# On récupère la taille visible exacte (modifiée par le Zoom !)
		var visible_size = get_viewport_rect().size / camera.zoom.x
		
		# On place le coin de notre rectangle en haut à gauche de la vue de la caméra
		global_position = camera.get_screen_center_position() - visible_size / 2.0
		
		# On lui donne la taille magique + une marge de sécurité
		size = visible_size
