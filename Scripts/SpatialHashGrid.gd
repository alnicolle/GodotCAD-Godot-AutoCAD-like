extends RefCounted
class_name SpatialHashGrid

# === GRILLE SPATIALE POUR SÉLECTION OPTIMISÉE ===
# Permet de trouver rapidement les entités près d'une position
# Évite de tester toutes les entités pour chaque clic de souris

var grid: Dictionary = {}
var cell_size: float

func _init(size: float = 100.0):
	cell_size = size

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / cell_size)),
		int(floor(world_pos.y / cell_size))
	)

func cell_to_world(cell_pos: Vector2i) -> Vector2:
	return Vector2(cell_pos.x * cell_size, cell_pos.y * cell_size)

func add_entity(entity_data, bounds: Rect2):
	var min_cell = world_to_cell(bounds.position)
	var max_cell = world_to_cell(bounds.position + bounds.size)
	
	# Protection anti-diagonale : limiter l'expansion de la grille
	var cell_span_x = max_cell.x - min_cell.x
	var cell_span_y = max_cell.y - min_cell.y
	
	# Si l'entité traverse trop de cellules, utiliser une stratégie alternative
	if cell_span_x > 50 or cell_span_y > 50:
		# Pour les entités massives (diagonales, grilles de fond)
		# On stocke dans une liste globale ou on limite l'insertion
		# Solution simple : on limite à une zone raisonnable
		max_cell.x = min(max_cell.x, min_cell.x + 50)
		max_cell.y = min(max_cell.y, min_cell.y + 50)
	
	# Insertion optimisée avec check d'intersection
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell_key = Vector2i(x, y)
			
			# Optionnel : check d'intersection segment/cellule (Bresenham)
			# Pour l'instant, on insère dans toutes les cellules de la bounding box
			
			if not grid.has(cell_key):
				grid[cell_key] = []
			grid[cell_key].append(entity_data)

func remove_entity(entity_data, bounds: Rect2):
	var min_cell = world_to_cell(bounds.position)
	var max_cell = world_to_cell(bounds.position + bounds.size)
	
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell_key = Vector2i(x, y)
			if grid.has(cell_key):
				grid[cell_key].erase(entity_data)

func get_entities_near_position(pos: Vector2, radius: float = 0.0) -> Array:
	var cell_key = world_to_cell(pos)
	var result = []
	
	# Inclure les cellules voisines si un rayon est spécifié
	var radius_cells = 0
	if radius > 0:
		radius_cells = int(ceil(radius / cell_size))
	
	for x in range(cell_key.x - radius_cells, cell_key.x + radius_cells + 1):
		for y in range(cell_key.y - radius_cells, cell_key.y + radius_cells + 1):
			var check_key = Vector2i(x, y)
			if grid.has(check_key):
				for entity in grid[check_key]:
					if not result.has(entity):
						result.append(entity)
	
	return result

func get_entities_in_rect(rect: Rect2) -> Array:
	var min_cell = world_to_cell(rect.position)
	var max_cell = world_to_cell(rect.position + rect.size)
	var result = []
	
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell_key = Vector2i(x, y)
			if grid.has(cell_key):
				for entity in grid[cell_key]:
					if not result.has(entity):
						result.append(entity)
	
	return result

func clear():
	grid.clear()

func get_stats() -> Dictionary:
	var total_cells = grid.size()
	var total_entities = 0
	var max_entities_per_cell = 0
	
	for cell_key in grid:
		var entities_in_cell = grid[cell_key].size()
		total_entities += entities_in_cell
		max_entities_per_cell = max(max_entities_per_cell, entities_in_cell)
	
	return {
		"total_cells": total_cells,
		"total_entities": total_entities,
		"avg_entities_per_cell": float(total_entities) / max(1, total_cells),
		"max_entities_per_cell": max_entities_per_cell
	}
