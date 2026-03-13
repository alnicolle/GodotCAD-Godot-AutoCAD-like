# RDMAssembler.gd
# Assemble la matrice de raideur globale et le vecteur forces
class_name RDMAssembler
extends RefCounted

# Assemble le système global [K]{U}={F}
func assemble_global_system(nodes: Array[RDMNode], elements: Array[RDMElement], supports: Array[RDMSupport], forces: Array[RDMForce]) -> Dictionary:
	
	# Étape 1: Numéroter les degrés de liberté
	var ddl_mapping = _number_degrees_of_freedom(nodes)
	var total_ddls = _count_free_ddls(nodes)
	
	print("DDL mapping: %d DDL libres sur %d totaux" % [total_ddls, nodes.size() * 3])
	
	# Étape 2: Initialiser la matrice K et le vecteur F
	var K_global: Array[float] = []
	K_global.resize(total_ddls * total_ddls)
	K_global.fill(0.0)
	
	var F_global: Array[float] = []
	F_global.resize(total_ddls)
	F_global.fill(0.0)
	
	# Étape 3: Assembler la matrice de raideur
	for element in elements:
		_assemble_element_stiffness(K_global, element, ddl_mapping, total_ddls)
	
	# Étape 4: Assembler le vecteur forces
	for force in forces:
		_assemble_force_vector(F_global, force, ddl_mapping, total_ddls)
	
	# Étape 5: Appliquer les conditions limites (déjà gérées dans le DDL mapping)
	
	return {
		"K_global": K_global,
		"F_global": F_global,
		"ddl_mapping": ddl_mapping,
		"total_ddls": total_ddls
	}

# Numérote les degrés de liberté et crée le mapping
func _number_degrees_of_freedom(nodes: Array[RDMNode]) -> Dictionary:
	var ddl_mapping = {}
	var ddl_index = 0
	
	for node in nodes:
		# DDL 0: u (déplacement horizontal)
		if not node.is_fixed_u:
			node.ddl_indices[0] = ddl_index
			ddl_mapping[str(node.id) + "_u"] = ddl_index
			ddl_index += 1
		else:
			node.ddl_indices[0] = -1
		
		# DDL 1: v (déplacement vertical)
		if not node.is_fixed_v:
			node.ddl_indices[1] = ddl_index
			ddl_mapping[str(node.id) + "_v"] = ddl_index
			ddl_index += 1
		else:
			node.ddl_indices[1] = -1
		
		# DDL 2: θ (rotation)
		if not node.is_fixed_theta:
			node.ddl_indices[2] = ddl_index
			ddl_mapping[str(node.id) + "_theta"] = ddl_index
			ddl_index += 1
		else:
			node.ddl_indices[2] = -1
	
	return ddl_mapping

# Compte le nombre total de DDL libres
func _count_free_ddls(nodes: Array[RDMNode]) -> int:
	var count = 0
	for node in nodes:
		if not node.is_fixed_u: count += 1
		if not node.is_fixed_v: count += 1
		if not node.is_fixed_theta: count += 1
	return count

# Assemble la matrice de raideur d'un élément dans la matrice globale
func _assemble_element_stiffness(K_global: Array[float], element: RDMElement, ddl_mapping: Dictionary, total_ddls: int):
	var k_elem = element.get_global_stiffness_matrix()
	
	# Indices des DDL pour les deux nœuds
	var ddl_indices = [
		element.node_start.ddl_indices[0],  # u_start
		element.node_start.ddl_indices[1],  # v_start
		element.node_start.ddl_indices[2],  # θ_start
		element.node_end.ddl_indices[0],   # u_end
		element.node_end.ddl_indices[1],   # v_end
		element.node_end.ddl_indices[2]    # θ_end
	]
	
	# Assemblage dans la matrice globale
	for i in range(6):
		if ddl_indices[i] == -1:  # DDL bloqué
			continue
		
		for j in range(6):
			if ddl_indices[j] == -1:  # DDL bloqué
				continue
			
			var global_i = ddl_indices[i]
			var global_j = ddl_indices[j]
			
			# Ajouter la contribution de l'élément
			K_global[global_i * total_ddls + global_j] += k_elem[i * 6 + j]

# Assemble une force dans le vecteur forces global
func _assemble_force_vector(F_global: Array[float], force: RDMForce, ddl_mapping: Dictionary, total_ddls: int):
	var node = force.node
	
	# Force horizontale
	if not node.is_fixed_u and node.ddl_indices[0] != -1:
		F_global[node.ddl_indices[0]] += force.fx
	
	# Force verticale
	if not node.is_fixed_v and node.ddl_indices[1] != -1:
		F_global[node.ddl_indices[1]] += force.fy
	
	# Moment
	if not node.is_fixed_theta and node.ddl_indices[2] != -1:
		F_global[node.ddl_indices[2]] += force.mz
