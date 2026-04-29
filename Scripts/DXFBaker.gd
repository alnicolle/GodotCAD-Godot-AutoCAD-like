extends Node
class_name DXFBaker

# Fonction Ã  appeler JUSTE APRÃˆS que dxfservice.import_dxf() ait terminÃ©
static func bake_imported_scene(world_node: Node2D, renderer: EntitiesRenderer):
	var root_entities = world_node.get_node("Entities")
	var baked_count = 0
	
	print("DÃ©but du Baking des entitÃ©s DXF...")
	var start_time = Time.get_ticks_msec()
	
	# On dÃ©sactive temporairement le rebuild du renderer pour des raisons de perf
	renderer.geometry_dirty = true
	
	# On parcourt les calques et les entitÃ©s
	for layer_node in root_entities.get_children():
		if layer_node is Node2D and not (layer_node is CADEntity):
			var layer_name = layer_node.name
			
			# On parcourt les enfants de ce calque en sens inverse pour pouvoir les supprimer sans bug
			var children = layer_node.get_children()
			for i in range(children.size() - 1, -1, -1):
				var child = children[i]
				if child is CADEntity:
					_bake_single_entity(child, layer_name, renderer)
					baked_count += 1
					child.queue_free() # ðŸ—‘ï¸ DESTRUCTION DU NÅ’UD LOURD
					
		elif layer_node is CADEntity: # Cas oÃ¹ l'entitÃ© est directement Ã  la racine
			_bake_single_entity(layer_node, "0", renderer)
			baked_count += 1
			layer_node.queue_free()
			
	# On force le rendu global une fois que tout est importÃ©
	renderer._invalidate_cache()
	
	print("Baking terminÃ© : %d entitÃ©s converties en %d ms." % [baked_count, Time.get_ticks_msec() - start_time])

static func _bake_single_entity(node: CADEntity, layer: String, renderer: EntitiesRenderer):
	var data : CADEntityData
	
	# Extraction des donnÃ©es gÃ©omÃ©triques globales
	if node.is_circle:
		var global_center = node.to_global(node.circle_center)
		data = CADEntityData.create_circle(global_center, node.circle_radius, layer)
		
	elif node.is_arc:
		var global_center = node.to_global(node.arc_center)
		data = CADEntityData.create_arc(global_center, node.arc_radius, node.arc_start_angle, node.arc_end_angle, layer)
		
	elif node.is_point:
		var global_center = node.to_global(Vector2.ZERO)
		data = CADEntityData.create_point(global_center, layer)
		
	else: # Polyline
		var global_points = PackedVector2Array()
		for p in node.points:
			global_points.append(node.to_global(p))
		data = CADEntityData.create_line(global_points, layer)
	
	# Extraction des propriÃ©tÃ©s visuelles (en Ã©vitant l'erreur de paramÃ¨tre manquant)
	data.color = node.get_effective_color(Color.WHITE) if node.has_method("get_effective_color") else node.default_color_val
	data.lineweight = node.lineweight
	data.linetype = node.linetype
	data.linetype_scale = node.linetype_scale
	
	# Envoi direct au moteur de rendu Data-Oriented
	renderer.entities.append(data)
	renderer._update_spatial_grid(data)
	renderer._group_entity_by_layer(data)
	renderer._group_entity_by_type(data)

# === GESTION DE L'ÉDITION HYBRIDE (UNPACKING & REBAKING) ===

static func unpack_entity(data: CADEntityData, world_node: Node2D, renderer: EntitiesRenderer) -> Node2D:
	var root_entities = world_node.get_node_or_null("Entities")
	if not root_entities: return null
	
	var CADEntityScript = load("res://Scripts/CADEntity.gd")
	var node = CADEntityScript.new()
	
	if data.type == CADEntityData.EntityType.CIRCLE:
		node.is_circle = true
		node.circle_center = Vector2.ZERO
		node.circle_radius = data.radius
		node.global_position = data.center
	elif data.type == CADEntityData.EntityType.ARC:
		node.is_arc = true
		node.arc_center = Vector2.ZERO
		node.arc_radius = data.radius
		node.arc_start_angle = data.start_angle
		node.arc_end_angle = data.end_angle
		node.global_position = data.center
	elif data.type == CADEntityData.EntityType.POINT:
		node.is_point = true
		node.global_position = data.center
	else:
		var local_points = PackedVector2Array()
		var offset = data.points[0] if data.points.size() > 0 else Vector2.ZERO
		node.global_position = offset
		for p in data.points:
			local_points.append(p - offset)
		node.points = local_points

	node.default_color_val = data.color
	node.lineweight = data.lineweight
	node.linetype = data.linetype
	node.linetype_scale = data.linetype_scale
	
	node.set_meta("unpacked_data", data)
	node.set_meta("is_ghost", false) 
	node.set_meta("source_layer", data.layer_name)

	var layer_node = root_entities.get_node_or_null(data.layer_name)
	if not layer_node:
		layer_node = Node2D.new()
		layer_node.name = data.layer_name
		root_entities.add_child(layer_node)
		
	layer_node.add_child(node)
	
	data.is_hidden = true
	renderer._invalidate_cache()
	
	return node

static func rebake_unpacked_entity(node: Node2D, renderer: EntitiesRenderer):
	if not node or not node.has_meta("unpacked_data"): 
		return

	var data: CADEntityData = node.get_meta("unpacked_data")
	
	if node.get("is_circle") and node.is_circle:
		data.center = node.to_global(node.circle_center)
		data.radius = node.circle_radius
	elif node.get("is_arc") and node.is_arc:
		data.center = node.to_global(node.arc_center)
		data.radius = node.arc_radius
		data.start_angle = node.arc_start_angle
		data.end_angle = node.arc_end_angle
	elif node.get("is_point") and node.is_point:
		data.center = node.to_global(Vector2.ZERO)
	else:
		var global_points = PackedVector2Array()
		for p in node.points:
			global_points.append(node.to_global(p))
		data.points = global_points
		
	if node.has_method("get_effective_color"):
		data.color = node.get_effective_color(Color.WHITE)
	elif node.get("default_color_val"):
		data.color = node.default_color_val
		
	if node.get("lineweight") != null: data.lineweight = node.lineweight
	if node.get("linetype") != null: data.linetype = node.linetype
	
	data.is_hidden = false
	
	renderer.update_entity(data)
	renderer._invalidate_cache()
	
	node.queue_free()
