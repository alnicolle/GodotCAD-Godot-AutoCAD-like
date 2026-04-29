extends Node2D
class_name EntitiesRenderer

# --- RENDU OPTIMISÉ DATA-ORIENTED ---
# Ce nœud unique dessine TOUTES les entités du projet
# Utilise draw_multiline() et draw_multiline_colors() pour réduire les draw calls

# --- RÉFÉRENCES ---
@export var layer_manager: Node
@export var selection_manager: Node
@export var camera: Camera2D

# --- DONNÉES DES ENTITÉS (Pure Data) ---
var entities: Array[CADEntityData] = []
var entities_by_layer: Dictionary = {}  # layer_name -> Array[CADEntityData]
var entities_by_type: Dictionary = {}  # entity_type -> Array[CADEntityData]

# --- CACHE DE RENDU OPTIMISÉ ---
var compiled_batches: Dictionary = {}  # Clé: layer_name, Valeur: Array de dictionnaires de lots pré-calculés
var geometry_dirty: bool = true
var last_camera_transform: Transform2D
var last_viewport_size: Vector2

# --- PERFORMANCE ---
var spatial_grid: SpatialHashGrid
var selection_tolerance: float = 10.0

# --- SHADERS ---
var line_shader: Shader = preload("res://Shaders/Linetype.gdshader")

signal entities_changed()
signal render_cache_updated()

func _ready():
	spatial_grid = SpatialHashGrid.new(100.0)  # Grid de 100 unités
	
	# Connexions aux signaux
	if layer_manager:
		layer_manager.layers_changed.connect(_on_layers_changed)
	
	if camera:
		camera.zoom_changed.connect(_on_camera_changed)

# === API PUBLIQUE ===

func add_entity(entity_data: CADEntityData) -> void:
	entities.append(entity_data)
	_update_spatial_grid(entity_data)
	_group_entity_by_layer(entity_data)
	_group_entity_by_type(entity_data)
	_invalidate_cache()
	entities_changed.emit()

func remove_entity(entity_data: CADEntityData) -> void:
	entities.erase(entity_data)
	_remove_from_spatial_grid(entity_data)
	_remove_from_groupings(entity_data)
	_invalidate_cache()
	entities_changed.emit()

func update_entity(entity_data: CADEntityData) -> void:
	_update_spatial_grid(entity_data)
	_invalidate_cache()
	entities_changed.emit()

func get_entities_in_rect(rect: Rect2) -> Array[CADEntityData]:
	var result: Array[CADEntityData] = []
	var grid_bounds = _rect_to_grid_bounds(rect)
	
	for cell_key in grid_bounds:
		if spatial_grid.grid.has(cell_key):
			for entity_data in spatial_grid.grid[cell_key]:
				if not entity_data.is_hidden and entity_data.intersects_rect(rect):
					result.append(entity_data)
	
	return result

func get_entity_at_position(pos: Vector2, tolerance: float = 0.0) -> CADEntityData:
	var actual_tolerance = tolerance if tolerance > 0 else selection_tolerance / camera.zoom.x
	var grid_bounds = _pos_to_grid_bounds(pos, actual_tolerance)
	
	for cell_key in grid_bounds:
		if spatial_grid.grid.has(cell_key):
			for entity_data in spatial_grid.grid[cell_key]:
				if not entity_data.is_hidden and entity_data.hit_test(pos, actual_tolerance):
					return entity_data
	
	return null

# === RENDU PRINCIPAL ===

func _draw():
	if geometry_dirty:
		_rebuild_render_cache()
	
	# Rendu optimisé avec lots pré-calculés
	for layer_name in compiled_batches:
		# Vérifier la visibilité du calque
		var layer_visible = true
		if layer_manager and layer_manager.has_method("get_layer_data"):
			var layer_data = layer_manager.get_layer_data(layer_name)
			if layer_data:
				layer_visible = layer_data.visible
		
		if not layer_visible:
			continue
		
		# 1. Rendre les lignes par lots (optimisé)
		for batch in compiled_batches[layer_name]:
			# ÉPAISSEUR CONSTANTE À L'ÉCRAN :
			# On divise l'épaisseur mathématique pure par le zoom de la caméra au moment du rendu.
			# Coût CPU : 1 division mathématique par lot (quasi nul) !
			var dynamic_lineweight = batch.lineweight / camera.zoom.x
			draw_multiline(batch.points, batch.color, dynamic_lineweight)
		
		# 2. Rendre les autres formes (cercles, arcs, points)
		if entities_by_layer.has(layer_name):
			var layer_entities = entities_by_layer[layer_name]
			
			var circles: Array[CADEntityData] = []
			var arcs: Array[CADEntityData] = []
			var points: Array[CADEntityData] = []
			
			for entity in layer_entities:
				if entity.is_hidden:
					continue
				match entity.type:
					CADEntityData.EntityType.CIRCLE:
						circles.append(entity)
					CADEntityData.EntityType.ARC:
						arcs.append(entity)
					CADEntityData.EntityType.POINT:
						points.append(entity)
			
			# Rendre les formes non-lignes avec les méthodes existantes
			if circles.size() > 0:
				_draw_circles_batch(circles, Color.WHITE)
			if arcs.size() > 0:
				_draw_arcs_batch(arcs, Color.WHITE)
			if points.size() > 0:
				_draw_points_batch(points, Color.WHITE)

func _draw_circles_batch(circles: Array[CADEntityData], base_color: Color):
	for entity in circles:
		var color = entity.get_effective_color(base_color)
		var width = entity.get_effective_lineweight() / camera.zoom.x
		
		# LOD : adapter le nombre de points selon le zoom
		var screen_radius = entity.radius * camera.zoom.x
		var num_points = clamp(int(screen_radius * 0.5), 16, 64)
		
		draw_arc(entity.center, entity.radius, 0, TAU, num_points, color, width)

func _draw_arcs_batch(arcs: Array[CADEntityData], base_color: Color):
	for entity in arcs:
		var color = entity.get_effective_color(base_color)
		var width = entity.get_effective_lineweight() / camera.zoom.x
		
		# LOD
		var screen_radius = entity.radius * camera.zoom.x
		var num_points = clamp(int(screen_radius * 0.3), 12, 48)
		
		draw_arc(entity.center, entity.radius, entity.start_angle, entity.end_angle, num_points, color, width)

func _draw_points_batch(points: Array[CADEntityData], base_color: Color):
	for entity in points:
		var color = entity.get_effective_color(base_color)
		var size = entity.point_size / camera.zoom.x
		
		match entity.point_style:
			"CROSS":
				draw_line(entity.center - Vector2(size, 0), entity.center + Vector2(size, 0), color, 1.0 / camera.zoom.x)
				draw_line(entity.center - Vector2(0, size), entity.center + Vector2(0, size), color, 1.0 / camera.zoom.x)
			"CIRCLE":
				draw_arc(entity.center, size, 0, TAU, 16, color, 1.0 / camera.zoom.x)
			"SQUARE":
				var rect = Rect2(entity.center - Vector2(size/2, size/2), Vector2(size, size))
				draw_rect(rect, color, false, 1.0 / camera.zoom.x)

# === GESTION DU CACHE OPTIMISÉ ===

func _rebuild_render_cache():
	compiled_batches.clear()
	
	for layer_name in entities_by_layer:
		var layer_entities = entities_by_layer[layer_name]
		var groups = _group_lines_by_properties(layer_entities)
		
		var layer_batches = []
		for group_key in groups:
			var group = groups[group_key]
			var points = PackedVector2Array()
			
			# Construire le tableau de points UNE SEULE FOIS
			for entity in group.entities:
				if entity.type == CADEntityData.EntityType.LINE:
					for i in range(entity.points.size() - 1):
						points.append(entity.points[i])
						points.append(entity.points[i + 1])
			
			if points.size() > 0:
				layer_batches.append({
					"points": points,
					"color": group.color,
					"lineweight": group.lineweight  # Épaisseur brute, gérée par la caméra
				})
		
		compiled_batches[layer_name] = layer_batches
	
	geometry_dirty = false
	render_cache_updated.emit()

func _invalidate_cache():
	geometry_dirty = true
	queue_redraw()

# === GESTION SPATIALE ===

func _update_spatial_grid(entity_data: CADEntityData):
	# Retirer de l'ancienne position
	_remove_from_spatial_grid(entity_data)
	
	# Ajouter à la nouvelle position EN UTILISANT L'API DE LA GRILLE
	var bounds = entity_data.get_bounds()
	spatial_grid.add_entity(entity_data, bounds)  # Utilise la méthode officielle avec protection anti-diagonale

func _remove_from_spatial_grid(entity_data: CADEntityData):
	var bounds = entity_data.get_bounds()
	spatial_grid.remove_entity(entity_data, bounds)  # Utilise la méthode optimisée

func _group_entity_by_layer(entity_data: CADEntityData):
	if not entities_by_layer.has(entity_data.layer_name):
		var new_arr: Array[CADEntityData] = [] # Typage strict ici !
		entities_by_layer[entity_data.layer_name] = new_arr
	entities_by_layer[entity_data.layer_name].append(entity_data)

func _group_entity_by_type(entity_data: CADEntityData):
	if not entities_by_type.has(entity_data.type):
		var new_arr: Array[CADEntityData] = [] # Typage strict ici !
		entities_by_type[entity_data.type] = new_arr
	entities_by_type[entity_data.type].append(entity_data)

func _remove_from_groupings(entity_data: CADEntityData):
	if entities_by_layer.has(entity_data.layer_name):
		entities_by_layer[entity_data.layer_name].erase(entity_data)
	if entities_by_type.has(entity_data.type):
		entities_by_type[entity_data.type].erase(entity_data)

# === UTILITAIRES ===

func _group_lines_by_properties(lines: Array[CADEntityData]) -> Dictionary:
	var groups = {}
	
	for entity in lines:
		if entity.is_hidden:
			continue
			
		# CORRECTION 1 : Ajout de Color.WHITE
		var key = "%s|%s|%.2f" % [entity.linetype, entity.get_effective_color(Color.WHITE).to_html(), entity.get_effective_lineweight()]
		
		if not groups.has(key):
			groups[key] = {
				"entities": [],
				"linetype": entity.linetype,
				# CORRECTION 2 : Ajout de Color.WHITE
				"color": entity.get_effective_color(Color.WHITE), 
				"lineweight": entity.get_effective_lineweight()  # On garde l'épaisseur mathématique pure
			}
		
		groups[key].entities.append(entity)
	
	return groups

func _rect_to_grid_bounds(rect: Rect2) -> Array:
	var min_cell = spatial_grid.world_to_cell(rect.position)
	var max_cell = spatial_grid.world_to_cell(rect.position + rect.size)
	
	var keys = []
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			keys.append(Vector2i(x, y))
	
	return keys

func _pos_to_grid_bounds(pos: Vector2, radius: float) -> Array:
	var rect = Rect2(pos - Vector2(radius, radius), Vector2(radius * 2, radius * 2))
	return _rect_to_grid_bounds(rect)

# === SIGNAUX ===

func _on_layers_changed():
	_invalidate_cache()

func _on_camera_changed():
	# PLUS D'INVALIDATION DU CACHE ICI !
	# La caméra gère la transformation automatiquement en C++
	# On redessine juste pour le LOD si nécessaire
	queue_redraw()

# === NETTOYAGE ===

func clear_all():
	entities.clear()
	entities_by_layer.clear()
	entities_by_type.clear()
	spatial_grid.clear()
	_invalidate_cache()
	entities_changed.emit()
