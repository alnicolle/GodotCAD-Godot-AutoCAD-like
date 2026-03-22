extends Node2D

# --- Énumérations ---
enum Tool { NONE, POLYLINE, CIRCLE, ARC }

# --- Variables ---
var current_tool = Tool.NONE
var current_line: Line2D = null
var is_ortho_active = false

# Variables pour la création d'arcs
var arc_points = []  # Stocke les 3 points pour l'arc
var current_arc_preview: Line2D = null

# --- Références ---
@onready var entities_container = $Entities
@onready var preview_container = $Preview
@export var snap_manager : HBoxContainer
@export var dynamic_input : Control
@onready var camera = $"../World/Camera2D"
@export var btn_ortho : CheckBox

@export var layer_manager : Node

# --- Configuration ---
var active_color = Color.WHITE
var active_width = 2.0

# CONSTANTE D'ESPACEMENT (Doit être la même que dans CADEntity)
const DIMENSION_OFFSET_PIXELS = 60.0 

const CADEntityScript = preload("res://Scripts/CADEntity.gd")

func _ready():
	if dynamic_input:
		dynamic_input.value_committed.connect(_on_length_committed)
		# Connexion du signal "Entrée sur vide"
		dynamic_input.finish_requested.connect(finish_polyline)
		
	if btn_ortho:
		btn_ortho.toggled.connect(_on_ortho_toggled)

func _on_ortho_toggled(toggled_on):
	is_ortho_active = toggled_on
	GlobalLogger.info(tr("MSG_CONSOLE_ORTHO_1") + (tr("MSG_CONSOLE_ORTHO_2") if toggled_on else tr("MSG_CONSOLE_ORTHO_3")))

func _unhandled_input(event):
	# CORRECTION 3 : ÉCHAP INTELLIGENT
	if event.is_action_pressed("ui_cancel"):
		# Si on est en train de dessiner une polyligne
		if current_tool == Tool.POLYLINE and current_line != null:
			# Si on a plus de 2 points (Départ + Souris + au moins 1 validé), on finit proprement
			if current_line.get_point_count() > 2:
				finish_polyline()
			else:
				# Sinon (on n'a posé que le premier point), on annule tout
				cancel_current_operation()
		else:
			cancel_current_operation()
		return

	if current_tool == Tool.POLYLINE:
		handle_polyline_input(event)
	elif current_tool == Tool.CIRCLE:
		handle_circle_input(event)
	elif current_tool == Tool.ARC:
		handle_arc_input(event)

# --- FACTORIES (MODIFIÉES POUR LE GUIDE) ---

func spawn_polyline(is_preview: bool = false) -> Line2D:
	var l = Line2D.new()
	l.set_script(CADEntityScript)
	l.width = active_width
	l.joint_mode = Line2D.LINE_JOINT_SHARP
	l.end_cap_mode = Line2D.LINE_CAP_NONE
	
	if is_preview:
		l.default_color = active_color
		preview_container.add_child(l)
		l.show_dimension_guide = true
		l.guide_screen_offset = DIMENSION_OFFSET_PIXELS
	else:
		# --- GESTION CALQUES CORRIGÉE ---
		var added_to_layer = false
		
		if layer_manager:
			var layer_node = layer_manager.get_active_layer_node()
			var layer_data = layer_manager.get_active_layer_data()
			
			if layer_node:
				# 1. On assigne le NOM du calque (Vital pour que CADEntity retrouve ses parents)
				l.layer_name = layer_data.name 
				
				# 2. On configure en "DuCalque"
				l.linetype = "ByLayer"
				l.lineweight = -1.0
				
				# 3. On ajoute au noeud
				layer_node.add_child(l)
				added_to_layer = true
				
				# 4. On force le calcul immédiat de la couleur/type
				if l.has_method("update_visuals"):
					l.update_visuals()
		
		if not added_to_layer:
			l.default_color = active_color
			l.layer_name = "0"
			entities_container.add_child(l)
		# -------------------------------
		
		l.show_dimension_guide = false
		
	return l

func spawn_circle(center: Vector2, radius: float, is_preview: bool = false) -> Line2D:
	if radius <= 0: return null
	
	# 1. On récupère un objet de base (déjà configuré sur le bon calque grâce à notre modif)
	var l = spawn_polyline(is_preview)
	
	# 2. On le transforme en cercle
	l.is_circle = true
	l.circle_center = center
	l.circle_radius = radius
		
	# Un cercle n'utilise pas le tableau de points standard du Line2D
	l.points = PackedVector2Array() 
	
	# 3. CRUCIAL : On force une mise à jour visuelle finale
	# Car lors du 'spawn_polyline', l'objet croyait être une ligne.
	# Maintenant qu'il sait qu'il est un cercle, il doit peut-être adapter sa transparence ou son shader.
	if l.has_method("update_visuals"):
		l.update_visuals()
		
	return l

# --- GESTION OUTILS ---

func set_tool(new_tool: int):
	current_tool = new_tool
	if current_line:
		current_line.queue_free()
		current_line = null
	if current_arc_preview:
		current_arc_preview.queue_free()
		current_arc_preview = null
	arc_points.clear()
	if dynamic_input: dynamic_input.hide_input()
	GlobalLogger.info("Outil activé : " + Tool.keys()[new_tool])
	
func cancel_current_operation():
	if current_line != null:
		current_line.queue_free()
		current_line = null
		GlobalLogger.info("Tracé annulé.")
	if current_arc_preview != null:
		current_arc_preview.queue_free()
		current_arc_preview = null
		arc_points.clear()
		GlobalLogger.info("Arc annulé.")
	if current_tool != Tool.NONE:
		current_tool = Tool.NONE
		GlobalLogger.info("Commande annulée.")
	if dynamic_input: dynamic_input.hide_input()

# --- VALIDATION CLAVIER (Longueur fixe) ---

func _on_length_committed(length: float):
	if current_tool == Tool.POLYLINE and current_line != null:
		var count = current_line.get_point_count()
		if count >= 2:
			var start_point = current_line.points[count - 2]
			var mouse_point = current_line.points[count - 1]
			
			var direction = (mouse_point - start_point).normalized()
			if direction == Vector2.ZERO: direction = Vector2.RIGHT
			
			var new_point = start_point + direction * length
			add_point(new_point)
			
			# On redonne la main à la souris pour le segment suivant
			if dynamic_input: dynamic_input.is_typing = false

	elif current_tool == Tool.CIRCLE and current_line != null:
		current_line.circle_radius = length
		finish_circle()

# --- CALCUL ORTHO ---

func get_ortho_position(current: Vector2, previous: Vector2) -> Vector2:
	var diff = current - previous
	# Si la différence X est plus grande que la différence Y -> On veut horizontal
	if abs(diff.x) > abs(diff.y):
		return Vector2(current.x, previous.y)
	else:
		# Sinon on veut vertical
		return Vector2(previous.x, current.y)


# --- LOGIQUE POLYLIGNE ---

func handle_polyline_input(event):
	var raw_mouse_pos = get_global_mouse_position()
	var final_pos = raw_mouse_pos
	
	# 1. SNAP (Prioritaire)
	var snapped = false
	if snap_manager:
		var active_entity = current_line
		var moving_index = -1
		if current_line: moving_index = current_line.get_point_count() - 1
		
		# On stocke la position snapée
		var snap_pos = snap_manager.get_snapped_position(raw_mouse_pos, entities_container, camera.zoom.x, active_entity, moving_index)
		
		# Si la position snapée est différente de la brute, c'est qu'on a accroché quelque chose
		if not snap_pos.is_equal_approx(raw_mouse_pos):
			final_pos = snap_pos
			snapped = true

	# 2. ORTHO (Seulement si PAS de Snap et mode activé)
	if is_ortho_active and not snapped and current_line != null:
		var count = current_line.get_point_count()
		# Il faut au moins un point précédent (le point fixe est à l'index count - 2)
		if count >= 2:
			var prev_point = current_line.points[count - 2]
			final_pos = get_ortho_position(final_pos, prev_point)
	
	# 3. Dynamic Input & Visuals
	if current_line and dynamic_input:
		var count = current_line.get_point_count()
		if count >= 2:
			var start_point = current_line.points[count - 2]
			var end_point = final_pos
			
			if not dynamic_input.is_typing:
				var mid_point = (start_point + end_point) / 2.0
				var direction = (end_point - start_point).normalized()
				var normal = Vector2(-direction.y, direction.x)
				var offset_world = DIMENSION_OFFSET_PIXELS / camera.zoom.x
				var text_position = mid_point + normal * offset_world
				var length = start_point.distance_to(end_point)
				dynamic_input.show_input(text_position, length, camera)
			
			if event is InputEventKey and event.pressed and not dynamic_input.line_edit.has_focus():
				_handle_typing_event(event)

	# INPUTS SOURIS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if dynamic_input: dynamic_input.is_typing = false
		if current_line == null:
			current_line = spawn_polyline(true)
			current_line.add_point(final_pos)
			current_line.add_point(final_pos)
		else:
			add_point(final_pos)

	elif event is InputEventMouseMotion and current_line != null:
		if not (dynamic_input and dynamic_input.is_typing):
			var last_idx = current_line.get_point_count() - 1
			current_line.set_point_position(last_idx, final_pos)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		finish_polyline()
	elif event.is_action_pressed("ui_accept"):
		if dynamic_input and not dynamic_input.line_edit.has_focus():
			finish_polyline()


func add_point(pos: Vector2):
	var last_idx = current_line.get_point_count() - 1
	current_line.set_point_position(last_idx, pos)
	current_line.add_point(pos)

func finish_polyline():
	if current_line == null: return
	var last_idx = current_line.get_point_count() - 1
	current_line.remove_point(last_idx)
	
	if current_line.get_point_count() >= 2:
		var pts = current_line.points
		current_line.queue_free()
		var final_line = spawn_polyline(false)
		final_line.points = pts
		GlobalLogger.success("Polyligne créée.")
	else:
		current_line.queue_free()
		GlobalLogger.warning("Annulé (trop court).")
	
	current_line = null
	if dynamic_input: dynamic_input.hide_input()

# --- LOGIQUE CERCLE ---

func handle_circle_input(event):
	var raw_pos = get_global_mouse_position()
	var final_pos = raw_pos
	var snapped = false

	# 1. Snap
	if snap_manager:
		var snap_pos = snap_manager.get_snapped_position(raw_pos, entities_container, camera.zoom.x, current_line, -1)
		if not snap_pos.is_equal_approx(raw_pos):
			final_pos = snap_pos
			snapped = true

	# 2. Ortho (Pour le cercle, on aligne le point du rayon horizontalement ou verticalement par rapport au centre)
	if is_ortho_active and not snapped and current_line != null:
		final_pos = get_ortho_position(final_pos, current_line.circle_center)

	# 3. Logique suite
	if current_line and dynamic_input:
		if not dynamic_input.is_typing:
			var center = current_line.circle_center
			var radius = center.distance_to(final_pos)
			var mid_point = (center + final_pos) / 2.0
			var direction = (final_pos - center).normalized()
			var normal = Vector2(-direction.y, direction.x)
			var offset_world = DIMENSION_OFFSET_PIXELS / camera.zoom.x
			var text_position = mid_point + normal * offset_world
			dynamic_input.show_input(text_position, radius, camera)
		
		if event is InputEventKey and event.pressed and not dynamic_input.line_edit.has_focus():
			_handle_typing_event(event)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if dynamic_input: dynamic_input.is_typing = false
		if current_line == null:
			current_line = spawn_circle(final_pos, 0.1, true)
		else:
			finish_circle()

	elif event is InputEventMouseMotion and current_line != null:
		if not (dynamic_input and dynamic_input.is_typing):
			var center = current_line.circle_center
			var new_radius = center.distance_to(final_pos)
			current_line.circle_radius = new_radius
			current_line.queue_redraw()

func finish_circle():
	if current_line == null: return
	var center = current_line.circle_center
	var radius = current_line.circle_radius
	current_line.queue_free()
	current_line = null
	var final_circle = spawn_circle(center, radius, false)
	GlobalLogger.success("Cercle créé (R=" + str(snapped(radius, 0.01)) + ")")
	if dynamic_input: dynamic_input.hide_input()

# --- LOGIQUE ARC ---

func handle_arc_input(event):
	var raw_pos = get_global_mouse_position()
	var final_pos = raw_pos
	var snapped = false

	# 1. Snap
	if snap_manager:
		var snap_pos = snap_manager.get_snapped_position(raw_pos, entities_container, camera.zoom.x, current_arc_preview, -1)
		if not snap_pos.is_equal_approx(raw_pos):
			final_pos = snap_pos
			snapped = true

	# 2. Logique suite
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if dynamic_input: dynamic_input.is_typing = false
		
		# Ajouter le point cliqué
		arc_points.append(final_pos)
		
		# Créer ou mettre à jour le preview
		if arc_points.size() == 1:
			# Premier point : créer un preview simple
			current_arc_preview = spawn_arc_preview(final_pos)
		elif arc_points.size() == 2:
			# Deuxième point : mettre à jour le preview
			update_arc_preview()
		elif arc_points.size() == 3:
			# Troisième point : créer l'arc final
			create_final_arc()
			# Réinitialiser pour un prochain arc
			arc_points.clear()
			if current_arc_preview:
				current_arc_preview.queue_free()
				current_arc_preview = null

	elif event is InputEventMouseMotion and current_arc_preview != null:
		if not (dynamic_input and dynamic_input.is_typing):
			update_arc_preview_with_mouse(final_pos)

func spawn_arc_preview(first_point: Vector2) -> Line2D:
	var arc = Line2D.new()
	arc.set_script(CADEntityScript)
	arc.width = active_width
	arc.default_color = active_color
	arc.joint_mode = Line2D.LINE_JOINT_SHARP
	arc.end_cap_mode = Line2D.LINE_CAP_NONE
	
	# Configurer comme preview
	preview_container.add_child(arc)
	
	# Ajouter le premier point
	arc.add_point(first_point)
	arc.add_point(first_point)  # Point temporaire pour la souris
	
	return arc

func update_arc_preview():
	if current_arc_preview == null or arc_points.size() < 2:
		return
	
	# Mettre à jour avec les deux premiers points
	current_arc_preview.points = [arc_points[0], arc_points[1]]

func update_arc_preview_with_mouse(mouse_pos: Vector2):
	if current_arc_preview == null:
		return
	
	if arc_points.size() == 1:
		# Un seul point : tracer une ligne jusqu'à la souris
		current_arc_preview.points = [arc_points[0], mouse_pos]
	elif arc_points.size() == 2:
		# Deux points : essayer de créer un arc preview
		var arc_info = ArcGeometry.three_points_to_arc(arc_points[0], arc_points[1], mouse_pos)
		if arc_info:
			# Créer l'arc preview
			var arc_points_preview = ArcGeometry.generate_arc_points(arc_info, 32)
			current_arc_preview.points = arc_points_preview
		else:
			# Points colinéaires : tracer une ligne
			current_arc_preview.points = [arc_points[0], mouse_pos]

func create_final_arc():
	if arc_points.size() != 3:
		return
	
	# Créer l'arc final
	var final_arc = spawn_arc_from_points(arc_points[0], arc_points[1], arc_points[2])
	if final_arc:
		GlobalLogger.success("Arc créé")
	else:
		GlobalLogger.error("Impossible de créer l'arc (points colinéaires ?)")

func spawn_arc_from_points(p1: Vector2, p2: Vector2, p3: Vector2) -> Line2D:
	var arc = Line2D.new()
	arc.set_script(CADEntityScript)
	arc.width = active_width
	arc.joint_mode = Line2D.LINE_JOINT_SHARP
	arc.end_cap_mode = Line2D.LINE_CAP_NONE
	
	# Créer l'arc à partir des trois points
	if not arc.create_arc_from_three_points(p1, p2, p3):
		arc.queue_free()
		return null
	
	# Ajouter au calque actif
	if layer_manager:
		var layer_node = layer_manager.get_active_layer_node()
		var layer_data = layer_manager.get_active_layer_data()
		
		if layer_node:
			arc.layer_name = layer_data.name
			arc.linetype = "ByLayer"
			arc.lineweight = -1.0
			layer_node.add_child(arc)
	
	return arc

# --- FACTORY ARC ---

func spawn_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, is_preview: bool = false) -> Line2D:
	var arc = Line2D.new()
	arc.set_script(CADEntityScript)
	arc.width = active_width
	arc.joint_mode = Line2D.LINE_JOINT_SHARP
	arc.end_cap_mode = Line2D.LINE_CAP_NONE
	
	# Configurer l'arc
	arc.is_arc = true
	arc.arc_center = center
	arc.arc_radius = radius
	arc.arc_start_angle = start_angle
	arc.arc_end_angle = end_angle
	
	# Générer les points pour l'arc
	# Créer un ArcInfo directement en utilisant la méthode statique
	var arc_info = ArcGeometry.three_points_to_arc(
		center + Vector2(cos(start_angle), sin(start_angle)) * radius,
		center + Vector2(cos((start_angle + end_angle) / 2), sin((start_angle + end_angle) / 2)) * radius,
		center + Vector2(cos(end_angle), sin(end_angle)) * radius
	)
	if arc_info:
		arc.points = ArcGeometry.generate_arc_points(arc_info, 64)
	
	if is_preview:
		arc.default_color = active_color
		preview_container.add_child(arc)
	else:
		# Ajouter au calque actif
		if layer_manager:
			var layer_node = layer_manager.get_active_layer_node()
			var layer_data = layer_manager.get_active_layer_data()
			
			if layer_node:
				arc.layer_name = layer_data.name
				arc.linetype = "ByLayer"
				arc.lineweight = -1.0
				layer_node.add_child(arc)
	
	return arc

# --- UTILITAIRE CLAVIER ---
func _handle_typing_event(event):
	var char_typed = ""
	if event.keycode >= KEY_0 and event.keycode <= KEY_9: char_typed = str(event.keycode - KEY_0)
	elif event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9: char_typed = str(event.keycode - KEY_KP_0)
	elif event.keycode == KEY_PERIOD or event.keycode == KEY_COMMA or event.keycode == KEY_KP_PERIOD: char_typed = "."
	if char_typed != "": dynamic_input.start_typing(char_typed)

func update_lines_width(current_zoom: float):
	if current_zoom == 0: return
	var new_width = 2.0 / current_zoom
	
	# --- MODIFICATION POUR LES CALQUES ---
	# On parcourt les enfants de Entities (qui sont maintenant des Calques/Node2D)
	for layer_node in entities_container.get_children():
		
		# Cas 1 : C'est un calque (Node2D), on parcourt ses enfants (les objets)
		if layer_node is Node2D and not (layer_node is Line2D):
			for child in layer_node.get_children():
				if child is Line2D:
					child.width = new_width
					if child.has_method("update_grips_scale"):
						child.update_grips_scale(current_zoom)
						
		# Cas 2 : C'est un objet qui traine à la racine (Legacy / Fallback)
		elif layer_node is Line2D:
			layer_node.width = new_width
			if layer_node.has_method("update_grips_scale"):
				layer_node.update_grips_scale(current_zoom)
				
	# Gestion de la ligne en cours de tracé
	if current_line: current_line.width = new_width
	active_width = new_width
