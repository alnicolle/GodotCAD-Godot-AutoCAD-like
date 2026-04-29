extends Node2D
class_name SelectionManagerDataOriented

# === GESTION DE SÉLECTION 100% MATHÉMATIQUE ===
# Plus de nœuds physiques, plus de Area2D/CollisionShape2D
# Sélection basée sur les données pures et la géométrie

# --- RÉFÉRENCES ---
@export var entities_renderer: EntitiesRenderer
@export var camera: Camera2D
@export var layer_manager: Node

# --- ÉTATS SÉLECTION ---
enum State { IDLE, SELECTION_BOX, GRIP_EDIT }
var current_state = State.IDLE

# --- ÉTATS COMMANDES ---
enum CommandType { NONE, MOVE, COPY, PASTE, MIRROR, ROTATE, SCALE, OFFSET, TRIM, POINT }
var current_command = CommandType.NONE

# --- DONNÉES DE SÉLECTION ---
var selected_entities: Array[CADEntityData] = []
var hovered_entity: CADEntityData = null

# --- PARAMÈTRES SÉLECTION ---
var drag_start_pos = Vector2.ZERO
var drag_threshold = 10.0
var selection_tolerance: float = 10.0

# --- GRIPS (POINTS DE CONTRÔLE) ---
var active_grip_entity: CADEntityData = null
var active_grip_index: int = -1
var grip_size: float = 10.0

# --- TRANSFORMATIONS ---
var move_base_point = Vector2.ZERO
var move_step = 0
var transform_data: Dictionary = {}

# --- SIGNAUX ---
signal selection_changed(selected_entities: Array[CADEntityData])
signal hover_changed(entity: CADEntityData)

func _ready():
	set_process_unhandled_input(true)

# === API PUBLIQUE ===

func select_entity(entity: CADEntityData, add_to_selection: bool = false):
	if not add_to_selection:
		clear_selection()
	
	if not selected_entities.has(entity):
		entity.is_selected = true
		selected_entities.append(entity)
		entities_renderer.queue_redraw()
		selection_changed.emit(selected_entities)

func deselect_entity(entity: CADEntityData):
	if selected_entities.has(entity):
		entity.is_selected = false
		selected_entities.erase(entity)
		entities_renderer.queue_redraw()
		selection_changed.emit(selected_entities)

func clear_selection():
	for entity in selected_entities:
		entity.is_selected = false
	selected_entities.clear()
	entities_renderer.queue_redraw()
	selection_changed.emit(selected_entities)

func select_entities_in_rect(rect: Rect2, add_to_selection: bool = false):
	if not add_to_selection:
		clear_selection()
	
	var entities_in_rect = entities_renderer.get_entities_in_rect(rect)
	for entity in entities_in_rect:
		if not selected_entities.has(entity):
			entity.is_selected = true
			selected_entities.append(entity)
	
	entities_renderer.queue_redraw()
	selection_changed.emit(selected_entities)

func get_entity_at_position(world_pos: Vector2) -> CADEntityData:
	var tolerance = selection_tolerance / camera.zoom.x
	return entities_renderer.get_entity_at_position(world_pos, tolerance)

func get_grip_at_position(world_pos: Vector2) -> Dictionary:
	var tolerance = grip_size / camera.zoom.x
	
	for entity in selected_entities:
		var grips = _get_entity_grips(entity)
		for i in range(grips.size()):
			if world_pos.distance_to(grips[i]) <= tolerance:
				return {"entity": entity, "grip_index": i, "position": grips[i]}
	
	return {}

# === GESTION DES INPUTS ===

func _unhandled_input(event):
	if current_command == CommandType.NONE:
		_handle_selection_input(event)
	else:
		_handle_command_input(event)

func _handle_selection_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_selection(event.position)
		else:
			_end_selection(event.position)
	
	elif event is InputEventMouseMotion and current_state == State.SELECTION_BOX:
		_update_selection_box(event.position)

func _start_selection(screen_pos: Vector2):
	drag_start_pos = screen_pos
	var world_pos = camera.screen_to_world_point(screen_pos)
	
	# Priorité aux grips si on est en mode édition
	var grip_info = get_grip_at_position(world_pos)
	if not grip_info.is_empty():
		current_state = State.GRIP_EDIT
		active_grip_entity = grip_info.entity
		active_grip_index = grip_info.grip_index
		return
	
	# Sinon, tester la sélection d'entité
	var entity = get_entity_at_position(world_pos)
	if entity:
		var add_to_selection = Input.is_key_pressed(KEY_SHIFT)
		if entity.is_selected:
			if add_to_selection:
				deselect_entity(entity)
		else:
			select_entity(entity, add_to_selection)
	else:
		# Commencer une sélection par boîte
		current_state = State.SELECTION_BOX
		drag_start_pos = screen_pos

func _update_selection_box(screen_pos: Vector2):
	# Logique de preview de la boîte de sélection
	# Peut être implémentée avec un dessin temporaire
	pass

func _end_selection(screen_pos: Vector2):
	if current_state == State.SELECTION_BOX:
		var world_start = camera.screen_to_world_point(drag_start_pos)
		var world_end = camera.screen_to_world_point(screen_pos)
		
		var drag_distance = world_start.distance_to(world_end)
		var threshold_world = drag_threshold / camera.zoom.x
		
		if drag_distance < threshold_world:
			# Clic simple - déjà géré dans _start_selection
			pass
		else:
			# Sélection par boîte
			var rect = Rect2(world_start, world_end - world_start).abs()
			var add_to_selection = Input.is_key_pressed(KEY_SHIFT)
			select_entities_in_rect(rect, add_to_selection)
	
	current_state = State.IDLE
	queue_redraw()

# === GESTION DES GRIPS ===

func _get_entity_grips(entity: CADEntityData) -> PackedVector2Array:
	var grips = PackedVector2Array()
	
	match entity.type:
		CADEntityData.EntityType.LINE:
			for point in entity.points:
				grips.append(point)
		
		CADEntityData.EntityType.CIRCLE:
			grips.append(entity.center)  # Centre
			grips.append(entity.center + Vector2(entity.radius, 0))  # Droite
			grips.append(entity.center + Vector2(0, entity.radius))  # Haut
			grips.append(entity.center - Vector2(entity.radius, 0))  # Gauche
			grips.append(entity.center - Vector2(0, entity.radius))  # Bas
		
		CADEntityData.EntityType.ARC:
			grips.append(entity.center)  # Centre
			# Points de l'arc
			var arc_points = entity.get_world_points()
			if arc_points.size() > 0:
				grips.append(arc_points[0])  # Début
				var mid_index = arc_points.size() / 2
				grips.append(arc_points[mid_index])  # Milieu
				grips.append(arc_points[-1])  # Fin
		
		CADEntityData.EntityType.POINT:
			grips.append(entity.center)
	
	return grips

func move_grip_to_position(grip_entity: CADEntityData, grip_index: int, new_pos: Vector2):
	match grip_entity.type:
		CADEntityData.EntityType.LINE:
			if grip_index >= 0 and grip_index < grip_entity.points.size():
				grip_entity.points[grip_index] = new_pos
		
		CADEntityData.EntityType.CIRCLE:
			match grip_index:
				0: grip_entity.center = new_pos  # Centre
				1, 2, 3, 4:  # Points périphériques
					grip_entity.radius = grip_entity.center.distance_to(new_pos)
		
		CADEntityData.EntityType.ARC:
			var grips = _get_entity_grips(grip_entity)
			match grip_index:
				0:  # Centre
					var offset = new_pos - grip_entity.center
					grip_entity.center = new_pos
					# Ajuster les autres points si nécessaire
				1, 2, 3:  # Points de l'arc
					# Recalculer l'arc à partir des 3 points
					_recalculate_arc_from_grips(grip_entity, grip_index, new_pos)
		
		CADEntityData.EntityType.POINT:
			grip_entity.center = new_pos
	
	# Mettre à jour le rendu
	entities_renderer.update_entity(grip_entity)

func _recalculate_arc_from_grips(entity: CADEntityData, grip_index: int, new_pos: Vector2):
	# Logique pour recalculer un arc à partir de 3 points
	# C'est une version simplifiée - l'implémentation complète utiliserait ArcGeometry
	var grips = _get_entity_grips(entity)
	
	if grip_index == 1:  # Point de départ
		entity.start_angle = atan2(new_pos.y - entity.center.y, new_pos.x - entity.center.x)
	elif grip_index == 2:  # Point milieu
		# Recalculer le rayon
		entity.radius = entity.center.distance_to(new_pos)
	elif grip_index == 3:  # Point de fin
		entity.end_angle = atan2(new_pos.y - entity.center.y, new_pos.x - entity.center.x)

# === TRANSFORMATIONS ===

func start_move_command():
	current_command = CommandType.MOVE
	move_step = 1
	if selected_entities.size() > 0:
		# Capturer les positions initiales
		transform_data.clear()
		for entity in selected_entities:
			transform_data[entity] = {
				"original_points": entity.points.duplicate(),
				"original_center": entity.center
			}

func apply_move_to_entities(offset: Vector2):
	for entity in selected_entities:
		entity.translate(offset)
		entities_renderer.update_entity(entity)

func start_rotate_command():
	current_command = CommandType.ROTATE
	move_step = 1
	if selected_entities.size() > 0:
		transform_data.clear()
		for entity in selected_entities:
			transform_data[entity] = {
				"original_points": entity.points.duplicate(),
				"original_center": entity.center,
				"original_angles": {
					"start": entity.start_angle,
					"end": entity.end_angle
				} if entity.type == CADEntityData.EntityType.ARC else {}
			}

func apply_rotation_to_entities(pivot: Vector2, angle: float):
	for entity in selected_entities:
		entity.rotate_around(pivot, angle)
		entities_renderer.update_entity(entity)

func start_scale_command():
	current_command = CommandType.SCALE
	move_step = 1
	if selected_entities.size() > 0:
		transform_data.clear()
		for entity in selected_entities:
			transform_data[entity] = {
				"original_points": entity.points.duplicate(),
				"original_center": entity.center,
				"original_radius": entity.radius
			}

func apply_scale_to_entities(pivot: Vector2, factor: float):
	for entity in selected_entities:
		entity.scale_around(pivot, factor)
		entities_renderer.update_entity(entity)

func start_mirror_command():
	current_command = CommandType.MIRROR
	move_step = 1

func apply_mirror_to_entities(p1: Vector2, p2: Vector2):
	for entity in selected_entities:
		entity.mirror_across_line(p1, p2)
		entities_renderer.update_entity(entity)

# === UTILITAIRES ===

func count_selected() -> int:
	return selected_entities.size()

func get_selected_entities() -> Array[CADEntityData]:
	return selected_entities.duplicate()

func delete_selected_entities():
	if selected_entities.size() == 0:
		return
	
	# Supprimer du renderer
	for entity in selected_entities:
		entities_renderer.remove_entity(entity)
	
	# Vider la sélection
	selected_entities.clear()
	selection_changed.emit(selected_entities)

func copy_selected_entities() -> Array[CADEntityData]:
	var copies = []
	for entity in selected_entities:
		var copy = CADEntityData.from_dict(entity.to_dict())
		copy.is_selected = false
		copies.append(copy)
	return copies

func paste_entities_at_position(entities_to_paste: Array[CADEntityData], position: Vector2):
	if entities_to_paste.size() == 0:
		return
	
	# Calculer le centre des entités à coller
	var center = Vector2.ZERO
	for entity in entities_to_paste:
		center += entity.get_bounds().get_center()
	center /= entities_to_paste.size()
	
	# Déplacer vers la position souhaitée
	var offset = position - center
	for entity in entities_to_paste:
		entity.translate(offset)
		entities_renderer.add_entity(entity)

# === HOVER ===

func update_hover(world_pos: Vector2):
	var entity = get_entity_at_position(world_pos)
	
	if entity != hovered_entity:
		if hovered_entity:
			hovered_entity.is_hovered = false
		
		hovered_entity = entity
		
		if hovered_entity:
			hovered_entity.is_hovered = true
		
		entities_renderer.queue_redraw()
		hover_changed.emit(hovered_entity)

# === DESSIN (POUR LA BOÎTE DE SÉLECTION) ===

func _draw():
	if current_state == State.SELECTION_BOX:
		var world_start = camera.screen_to_world_point(drag_start_pos)
		var world_end = camera.screen_to_world_point(get_global_mouse_position())
		var rect = Rect2(world_start, world_end - world_start).abs()
		
		# Dessiner la boîte de sélection
		draw_rect(rect, Color(0.2, 0.6, 1.0, 0.3), true)
		draw_rect(rect, Color(0.2, 0.6, 1.0, 0.8), false, 2.0 / camera.zoom.x)
	
	# Dessiner les grips des entités sélectionnées
	for entity in selected_entities:
		_draw_entity_grips(entity)

func _draw_entity_grips(entity: CADEntityData):
	var grips = _get_entity_grips(entity)
	var grip_color = Color(0.0, 0.0, 1.0)  # Bleu
	var grip_world_size = grip_size / camera.zoom.x
	
	for grip_pos in grips:
		var rect = Rect2(grip_pos - Vector2(grip_world_size/2, grip_world_size/2), 
						Vector2(grip_world_size, grip_world_size))
		draw_rect(rect, grip_color, true)

# === NETTOYAGE ===

func cancel_current_command():
	current_command = CommandType.NONE
	move_step = 0
	transform_data.clear()
	current_state = State.IDLE
	queue_redraw()
