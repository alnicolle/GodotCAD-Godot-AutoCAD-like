# RDMConverter.gd
# Convertit les entités CAD en objets RDM/MEF
class_name RDMConverter
extends RefCounted

# Tolérance pour la fusion des nœuds
var node_tolerance: float = 1e-6  # Tolérance standard pour la fusion des nœuds

# Point d'entrée principal de conversion
func convert_to_rdm_objects(line_entities: Array, support_entities: Array, force_entities: Array, tolerance: float = 1e-6) -> Dictionary:
	node_tolerance = tolerance
	
	var result = {
		"nodes": [],
		"elements": [],
		"supports": [],
		"forces": []
	}
	
	# Étape 1: Extraire tous les points uniques des lignes
	var unique_points = _extract_unique_points(line_entities)
	
	# Étape 2: Créer les nœuds RDM à partir des points uniques
	var nodes = _create_nodes_from_points(unique_points)
	result.nodes = nodes
	
	# Étape 3: Créer les éléments RDM à partir des lignes
	var elements = _create_elements_from_lines(line_entities, nodes)
	result.elements = elements
	
	# Étape 4: Traiter les appuis (peuvent nécessiter de découper des éléments)
	var support_result = _process_supports(support_entities, nodes, elements, tolerance)
	if support_result.has("error"):
		return support_result
	
	result.supports = support_result.supports
	nodes = support_result.nodes
	elements = support_result.elements
	result.nodes = nodes
	
	# Étape 5: Traiter les forces
	var element_id = elements.size()  # Récupérer le bon ID
	var forces: Array[RDMForce] = []
	var forces_result = _process_forces(force_entities, nodes, elements, tolerance, element_id)
	if forces_result.has("error"):
		return forces_result
	forces.append_array(forces_result.forces)
	elements = forces_result.elements
	nodes = forces_result.nodes
	result.forces = forces
	result.elements = elements  # Mettre à jour les éléments (peuvent être découpés)
	result.nodes = nodes  # Mettre à jour les nœuds (peuvent être ajoutés)
	
	return result

# Extrait tous les points uniques des entités Line2D
func _extract_unique_points(line_entities: Array) -> Array[Vector2]:
	var points: Array[Vector2] = []
	
	for entity in line_entities:
		if not entity is Line2D:
			continue
			
		var line: Line2D = entity
		var line_points = line.points
		
		# Ajouter le premier et dernier point de chaque ligne
		if line_points.size() >= 2:
			points.append(line_points[0])
			points.append(line_points[-1])
	
	return points

# Crée les nœuds RDM à partir des points en fusionnant les points proches
func _create_nodes_from_points(points: Array[Vector2]) -> Array[RDMNode]:
	var nodes: Array[RDMNode] = []
	var node_id = 0
	
	print("DEBUG: Création de nœuds à partir de %d points" % points.size())
	
	for i in range(points.size()):
		var point = points[i]
		print("DEBUG: Point %d: (%.1f, %.1f)" % [i, point.x, point.y])
		
		# Vérifier si un nœud existe déjà à cette position
		var existing_node = _find_node_at_position(nodes, point.x, point.y)
		if existing_node == null:
			var node = RDMNode.new(point.x, point.y, node_id)
			nodes.append(node)
			print("DEBUG: Nouveau nœud %d créé à (%.1f, %.1f)" % [node_id, point.x, point.y])
			node_id += 1
		else:
			print("DEBUG: Nœud existant %d réutilisé pour (%.1f, %.1f)" % [existing_node.id, point.x, point.y])
	
	print("DEBUG: Total de %d nœuds créés" % nodes.size())
	return nodes

# Trouve un nœud existant à une position donnée
func _find_node_at_position(nodes: Array[RDMNode], x: float, y: float) -> RDMNode:
	print("DEBUG: _find_node_at_position appelé avec (%.1f, %.1f), %d nœuds disponibles, tolérance=%.2f" % [x, y, nodes.size(), node_tolerance])
	
	for i in range(nodes.size()):
		var node = nodes[i]
		var distance = node.distance_to(x, y)
		var is_at_pos = distance <= node_tolerance
		print("DEBUG: Nœud %d à (%.1f, %.1f): distance=%.3f, %s" % [node.id, node.x, node.y, distance, "match" if is_at_pos else "no match"])
		if is_at_pos:
			print("DEBUG: Nœud %d trouvé!" % node.id)
			return node
	
	print("DEBUG: Aucun nœud trouvé à cette position")
	return null

# Crée les éléments RDM à partir des lignes
func _create_elements_from_lines(line_entities: Array, nodes: Array[RDMNode]) -> Array[RDMElement]:
	var elements: Array[RDMElement] = []
	var element_id = 0
	
	for entity in line_entities:
		if not entity is Line2D:
			continue
			
		var line: Line2D = entity
		var line_points = line.points
		
		if line_points.size() < 2:
			continue
		
		# Points de début et de fin
		var start_point = line_points[0]
		var end_point = line_points[-1]
		
		# Trouver les nœuds correspondants
		var start_node = _find_node_at_position(nodes, start_point.x, start_point.y)
		var end_node = _find_node_at_position(nodes, end_point.x, end_point.y)
		
		if start_node != null and end_node != null and start_node != end_node:
			var element = RDMElement.new(start_node, end_node, element_id)
			elements.append(element)
			element_id += 1
	
	return elements

# Traite les appuis et découpe les éléments si nécessaire
func _process_supports(support_entities: Array, nodes: Array[RDMNode], elements: Array[RDMElement], tolerance: float) -> Dictionary:
	var supports: Array[RDMSupport] = []
	var new_elements: Array[RDMElement] = []
	var element_id = elements.size()
	
	# Copier les éléments existants
	for element in elements:
		new_elements.append(element)
	
	for entity in support_entities:
		var support_result = _create_support_from_entity(entity, nodes, new_elements, tolerance, element_id)
		if support_result.has("error"):
			return support_result
		
		if support_result.has("support"):
			supports.append(support_result.support)
			new_elements = support_result.elements
			element_id = new_elements.size()
	
	return {
		"supports": supports,
		"nodes": nodes,
		"elements": new_elements
	}

# Crée un appui à partir d'une entité (sprite ou autre)
func _create_support_from_entity(entity: Node, nodes: Array[RDMNode], elements: Array[RDMElement], tolerance: float, element_id: int) -> Dictionary:
	# À adapter selon votre système de représentation des appuis
	# Pour l'instant, supposons que l'entité a une position et un type
	
	var support_pos = Vector2.ZERO
	if entity.has_method("get_global_position"):
		support_pos = entity.get_global_position()
	elif "position" in entity:
		support_pos = entity.position
	else:
		support_pos = Vector2.ZERO
	
	var support_type = "simple"  # Par défaut
	
	# Essayer de déterminer le type d'appui depuis les métadonnées
	if entity.has_meta("support_type"):
		support_type = entity.get_meta("support_type")
	
	print("DEBUG: Création support %s à position %s" % [support_type, support_pos])
	
	# Trouver si l'appui est sur un nœud existant
	print("DEBUG: Recherche de nœud à position (%.1f, %.1f)" % [support_pos.x, support_pos.y])
	var node_at_support = _find_node_at_position(nodes, support_pos.x, support_pos.y)
	
	print("DEBUG: Résultat recherche nœud: %s" % ("trouvé" if node_at_support != null else "non trouvé"))
	
	if node_at_support != null:
		# L'appui est directement sur un nœud existant
		print("DEBUG: Support trouvé sur nœud existant %d" % node_at_support.id)
		var support = RDMSupport.new(node_at_support, support_type)
		_apply_support_to_node(support, node_at_support)
		return {"support": support, "elements": elements}
	
	# Sinon, l'appui est au milieu d'un élément -> il faut découper
	var split_result = _split_element_at_position(elements, support_pos, tolerance, element_id)
	if split_result.has("error"):
		return split_result
	
	# L'appui est maintenant sur le nouveau nœud créé
	var new_node = split_result.new_node
	print("DEBUG: Support créé sur nouveau nœud %d" % new_node.id)
	var support = RDMSupport.new(new_node, support_type)
	_apply_support_to_node(support, new_node)
	
	return {
		"support": support,
		"elements": split_result.elements
	}

# Applique les conditions limites d'un appui à un nœud
func _apply_support_to_node(support: RDMSupport, node: RDMNode):
	support.apply_to_node()
	print("DEBUG: Support appliqué au nœud %d - u_fixe=%s, v_fixe=%s, theta_fixe=%s" % [
		node.id, node.is_fixed_u, node.is_fixed_v, node.is_fixed_theta
	])

# Découpe un élément à une position donnée
func _split_element_at_position(elements: Array[RDMElement], split_pos: Vector2, tolerance: float, element_id: int) -> Dictionary:
	print("DEBUG: _split_element_at_position appelé avec position (%.1f, %.1f), tolérance=%.3f" % [split_pos.x, split_pos.y, node_tolerance])
	
	for element in elements:
		# Vérifier si le point est sur l'élément
		if _is_point_on_element(element, split_pos, node_tolerance):
			# Créer un nouveau nœud au point de découpe
			var new_node = RDMNode.new(split_pos.x, split_pos.y, -1)
			
			# Créer deux nouveaux éléments
			var element1 = RDMElement.new(element.node_start, new_node, element_id)
			var element2 = RDMElement.new(new_node, element.node_end, element_id + 1)
			
			# Remplacer l'élément original par les deux nouveaux
			var new_elements: Array[RDMElement] = []
			for e in elements:
				if e.id != element.id:  # Comparer par ID au lieu de l'objet
					new_elements.append(e)
			new_elements.append(element1)
			new_elements.append(element2)
			
			print("DEBUG: Élément %d découpé en éléments %d et %d - nouveau nœud créé à %s" % [
				element.id, element_id, element_id + 1, split_pos
			])
			
			return {
				"new_node": new_node,
				"elements": new_elements
			}
	
	return {"error": "Aucun élément trouvé à la position de découpe"}

# Vérifie si un point est sur un élément
func _is_point_on_element(element: RDMElement, point: Vector2, tolerance: float) -> bool:
	# Calcul de la distance point-segment
	var A = Vector2(element.node_start.x, element.node_start.y)
	var B = Vector2(element.node_end.x, element.node_end.y)
	var P = point
	
	print("DEBUG: _is_point_on_element - Élément %d: (%.1f,%.1f) -> (%.1f,%.1f), Point: (%.1f,%.1f)" % [
		element.id, A.x, A.y, B.x, B.y, P.x, P.y
	])
	
	var AB = B - A
	var AP = P - A
	
	var AB_length_sq = AB.length_squared()
	if AB_length_sq == 0:
		var distance = A.distance_to(P)
		print("DEBUG: Élément de longueur nulle, distance=%.3f" % distance)
		return distance <= tolerance
	
	var t = max(0, min(1, AP.dot(AB) / AB_length_sq))
	var projection = A + t * AB
	var distance = projection.distance_to(P)
	
	print("DEBUG: Projection t=%.3f, distance=%.3f, tolérance=%.3f" % [t, distance, tolerance])
	
	return distance <= tolerance

# Traite les forces
func _process_forces(force_entities: Array, nodes: Array[RDMNode], elements: Array[RDMElement], tolerance: float, element_id: int) -> Dictionary:
	var forces: Array[RDMForce] = []
	
	for entity in force_entities:
		var force_result = _create_force_from_entity(entity, nodes, elements, tolerance, element_id)
		if force_result.has("error"):
			return force_result
		if force_result.has("force"):
			forces.append(force_result.force)
			if force_result.has("elements"):
				elements = force_result.elements
			element_id = elements.size()
	
	return {
		"forces": forces,
		"elements": elements,
		"nodes": nodes
	}

# Crée une force à partir d'une entité
func _create_force_from_entity(entity: Node, nodes: Array[RDMNode], elements: Array[RDMElement], tolerance: float, element_id: int) -> Dictionary:
	# À adapter selon votre système de représentation des forces
	var force_pos = Vector2.ZERO
	if entity.has_method("get_global_position"):
		force_pos = entity.get_global_position()
	elif "position" in entity:
		force_pos = entity.position
	else:
		force_pos = Vector2.ZERO
		
	var force_value = Vector2(0, -1000)  # Valeur par défaut
	var moment_value = 0.0
	
	# Essayer de récupérer les valeurs depuis les métadonnées
	if entity.has_meta("force_value"):
		force_value = entity.get_meta("force_value")
	if entity.has_meta("moment_value"):
		moment_value = entity.get_meta("moment_value")
	
	print("DEBUG: Création force %s N, moment %s N·m à position %s" % [force_value, moment_value, force_pos])
	
	# Trouver si la force est sur un nœud existant
	var node_at_force = _find_node_at_position(nodes, force_pos.x, force_pos.y)
	
	if node_at_force != null:
		print("DEBUG: Force appliquée au nœud existant %d" % node_at_force.id)
		var force = RDMForce.new(node_at_force, force_value.x, force_value.y, moment_value)
		_apply_force_to_node(force, node_at_force)
		return {"force": force, "elements": elements}
	
	# Sinon, la force est au milieu d'un élément -> il faut découper
	var split_result = _split_element_at_position(elements, force_pos, tolerance, element_id)
	if split_result.has("error"):
		return split_result
	
	# La force est maintenant sur le nouveau nœud créé
	var new_node = split_result.new_node
	new_node.id = nodes.size()
	nodes.append(new_node)
	print("DEBUG: Nouveau nœud %d ajouté à la liste" % new_node.id)
	print("DEBUG: Force appliquée au nouveau nœud %d" % new_node.id)
	var force = RDMForce.new(new_node, force_value.x, force_value.y, moment_value)
	_apply_force_to_node(force, new_node)
	
	return {
		"force": force,
		"elements": split_result.elements
	}

# Applique une force à un nœud
func _apply_force_to_node(force: RDMForce, node: RDMNode):
	node.fx += force.fx
	node.fy += force.fy
	node.mz += force.mz

# Trouve le nœud le plus proche d'une position
func _find_closest_node(nodes: Array[RDMNode], position: Vector2) -> RDMNode:
	var closest_node: RDMNode = null
	var min_distance = INF
	
	for node in nodes:
		var distance = node.distance_to(position.x, position.y)
		if distance < min_distance:
			min_distance = distance
			closest_node = node
	
	return closest_node
