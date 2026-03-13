# RDMVisual.gd
# Gère l'affichage visuel des éléments RDM
class_name RDMVisual
extends Node2D

# Crée un visuel pour un appui
static func create_support_visual(position: Vector2, support_type: String) -> Node2D:
	var visual = Node2D.new()
	# Décaler visuellement le support pour que le point soit au sommet du triangle
	visual.position = position + Vector2(0, -15)
	
	match support_type:
		"simple":
			_create_simple_support_icon(visual)
		"articulation":
			_create_articulation_support_icon(visual)
		"encastrement":
			_create_fixed_support_icon(visual)
	
	return visual

# Crée un visuel pour une force ponctuelle
static func create_force_visual(position: Vector2, force_value: Vector2) -> Node2D:
	var visual = Node2D.new()
	visual.position = position
	
	# Créer la flèche
	var arrow = _create_arrow(Vector2.ZERO, force_value.normalized() * 30, Color.ORANGE, 3.0)
	visual.add_child(arrow)
	
	# Ajouter le texte de la force
	var label = Label.new()
	label.text = "%.0f N" % force_value.length()
	label.position = Vector2(10, -20)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.ORANGE)
	visual.add_child(label)
	
	return visual

# Crée un visuel pour une force répartie
static func create_distributed_force_visual(start_pos: Vector2, end_pos: Vector2, force_per_meter: float) -> Node2D:
	var visual = Node2D.new()
	visual.position = start_pos
	
	# Ligne représentant la force répartie
	var line = Line2D.new()
	line.add_point(Vector2.ZERO)
	line.add_point(end_pos - start_pos)
	line.width = 3.0
	line.default_color = Color.RED
	visual.add_child(line)
	
	# Flèches le long de la ligne
	var direction = (end_pos - start_pos).normalized()
	var length = (end_pos - start_pos).length()
	var num_arrows = int(length / 50) + 1
	
	for i in range(num_arrows):
		var arrow_pos = start_pos + direction * (i * length / (num_arrows - 1))
		var arrow = _create_arrow(arrow_pos - start_pos, direction * 20, Color.RED, 2.0)
		visual.add_child(arrow)
	
	# Texte
	var label = Label.new()
	label.text = "%.0f N/m" % abs(force_per_meter)
	label.position = (end_pos - start_pos) / 2 + Vector2(0, -25)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.RED)
	visual.add_child(label)
	
	return visual

# Icone appui simple (triangle avec deux cercles en dessous)
static func _create_simple_support_icon(parent: Node2D):
	var triangle = Polygon2D.new()
	triangle.polygon = [
		Vector2(-15, 30),
		Vector2(15, 30),
		Vector2(0, 15)
	]
	triangle.color = Color.BLUE
	parent.add_child(triangle)
	
	# Ligne de sol
	var ground_line = Line2D.new()
	ground_line.add_point(Vector2(-20, 40))
	ground_line.add_point(Vector2(20, 40))
	ground_line.width = 2.0
	ground_line.default_color = Color.BLUE
	parent.add_child(ground_line)
	
	# Deux cercles en dessous
	var circle1 = Polygon2D.new()
	var points1 = []
	for i in range(16):
		var angle = 2 * PI * i / 16
		points1.append(Vector2(cos(angle), sin(angle)) * 6)
	circle1.polygon = points1
	circle1.color = Color.BLUE
	circle1.position = Vector2(-7, 34)
	parent.add_child(circle1)
	
	var circle2 = Polygon2D.new()
	var points2 = []
	for i in range(16):
		var angle = 2 * PI * i / 16
		points2.append(Vector2(cos(angle), sin(angle)) * 6)
	circle2.polygon = points2
	circle2.color = Color.BLUE
	circle2.position = Vector2(7, 34)
	parent.add_child(circle2)

# Icone articulation (triangle avec cercle sur la pointe)
static func _create_articulation_support_icon(parent: Node2D):
	# Triangle (comme l'appui simple original)
	var triangle = Polygon2D.new()
	triangle.polygon = [
		Vector2(-15, 30),
		Vector2(15, 30),
		Vector2(0, 15)
	]
	triangle.color = Color.GREEN
	parent.add_child(triangle)
	
	# Ligne de sol
	var ground_line = Line2D.new()
	ground_line.add_point(Vector2(-20, 30))
	ground_line.add_point(Vector2(20, 30))
	ground_line.width = 2.0
	ground_line.default_color = Color.GREEN
	parent.add_child(ground_line)
	
	# Cercle sur la pointe du triangle
	var circle = Polygon2D.new()
	var points = []
	for i in range(16):
		var angle = 2 * PI * i / 16
		points.append(Vector2(cos(angle), sin(angle)) * 5)
	circle.polygon = points
	circle.color = Color.WHITE
	circle.position = Vector2(0, 15)  # Position sur la pointe (déjà correcte)
	parent.add_child(circle)

# Icone encastrement (rectangle avec hachures)
static func _create_fixed_support_icon(parent: Node2D):
	var rect = Polygon2D.new()
	rect.polygon = [
		Vector2(-15, -15),
		Vector2(15, -15),
		Vector2(15, 15),
		Vector2(-15, 15)
	]
	rect.color = Color.RED
	parent.add_child(rect)
	
	# Hachures
	for i in range(-10, 11, 5):
		var hachure = Line2D.new()
		hachure.add_point(Vector2(i, -15))
		hachure.add_point(Vector2(i - 5, -20))
		hachure.width = 1.0
		hachure.default_color = Color.WHITE
		parent.add_child(hachure)

# Crée une flèche
static func _create_arrow(start: Vector2, end: Vector2, color: Color, width: float) -> Line2D:
	var arrow = Line2D.new()
	arrow.add_point(start)
	arrow.add_point(end)
	arrow.width = width
	arrow.default_color = color
	
	# Tête de flèche
	var direction = (end - start).normalized()
	var perp = Vector2(-direction.y, direction.x)
	
	var head_size = 8.0
	var head1 = end - direction * head_size + perp * head_size * 0.5
	var head2 = end - direction * head_size - perp * head_size * 0.5
	
	arrow.add_point(head1)
	arrow.add_point(end)
	arrow.add_point(head2)
	
	return arrow
