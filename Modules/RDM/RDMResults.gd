# RDMResults.gd
# Extraction et gestion des résultats du calcul MEF
class_name RDMResults
extends RefCounted

# Données résultats
var max_displacement: float = 0.0
var max_rotation: float = 0.0
var total_strain_energy: float = 0.0

# Réactions aux appuis
var reactions: Dictionary = {}

# Efforts dans les éléments
var element_forces: Dictionary = {}

# Constructeur
func _init():
	pass

# Extrait les résultats de la solution et les distribue aux nœuds
func extract_results(nodes: Array[RDMNode], elements: Array[RDMElement], U_global: Array[float], ddl_mapping: Dictionary):
	
	# Étape 1: Distribuer les déplacements aux nœuds
	_distribute_displacements(nodes, U_global, ddl_mapping)
	
	# Étape 2: Calculer les réactions aux appuis
	_calculate_reactions(nodes, elements, U_global, ddl_mapping)
	
	# Étape 3: Calculer les efforts dans les éléments
	_calculate_element_forces(elements, U_global, ddl_mapping)
	
	# Étape 4: Calculer les statistiques
	_calculate_statistics(nodes, elements)
	
	print("Résultats extraits: déplacement max=%.6f, rotation max=%.6f rad" % [max_displacement, max_rotation])

# Distribue les déplacements aux nœuds à partir de la solution globale
func _distribute_displacements(nodes: Array[RDMNode], U_global: Array[float], ddl_mapping: Dictionary):
	for node in nodes:
		# Réinitialiser les résultats
		node.reset_results()
		
		# Récupérer les déplacements depuis la solution
		var key_u = str(node.id) + "_u"
		var key_v = str(node.id) + "_v"
		var key_theta = str(node.id) + "_theta"
		
		if ddl_mapping.has(key_u) and node.ddl_indices[0] != -1:
			node.u = U_global[node.ddl_indices[0]]
		
		if ddl_mapping.has(key_v) and node.ddl_indices[1] != -1:
			node.v = U_global[node.ddl_indices[1]]
		
		if ddl_mapping.has(key_theta) and node.ddl_indices[2] != -1:
			node.theta = U_global[node.ddl_indices[2]]

# Calcule les réactions aux appuis
func _calculate_reactions(nodes: Array[RDMNode], elements: Array[RDMElement], U_global: Array[float], ddl_mapping: Dictionary):
	reactions.clear()
	
	for node in nodes:
		var reaction = {"fx": 0.0, "fy": 0.0, "mz": 0.0}
		
		# Si le nœud a des conditions limites, calculer les réactions
		if node.is_fixed_u or node.is_fixed_v or node.is_fixed_theta:
			# Assembler les forces internes au nœud
			var internal_force = _assemble_internal_forces_at_node(node, elements, U_global, ddl_mapping)
			
			# Réaction = Forces appliquées - Forces internes
			reaction.fx = node.fx - internal_force.fx
			reaction.fy = node.fy - internal_force.fy
			reaction.mz = node.mz - internal_force.mz
			
			reactions[str(node.id)] = reaction

# Assemble les forces internes à un nœud
func _assemble_internal_forces_at_node(node: RDMNode, elements: Array[RDMElement], U_global: Array[float], ddl_mapping: Dictionary) -> Dictionary:
	var internal_force = {"fx": 0.0, "fy": 0.0, "mz": 0.0}
	
	for element in elements:
		if element.node_start == node or element.node_end == node:
			var element_force = _calculate_element_end_forces(element, U_global, ddl_mapping)
			
			if element.node_start == node:
				internal_force.fx += element_force.fx_start
				internal_force.fy += element_force.fy_start
				internal_force.mz += element_force.mz_start
			else:
				internal_force.fx += element_force.fx_end
				internal_force.fy += element_force.fy_end
				internal_force.mz += element_force.mz_end
	
	return internal_force

# Calcule les forces aux extrémités d'un élément
func _calculate_element_end_forces(element: RDMElement, U_global: Array[float], ddl_mapping: Dictionary) -> Dictionary:
	# Récupérer les déplacements nodaux
	var u_elem: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	
	# Nœud de départ
	if element.node_start.ddl_indices[0] != -1:
		u_elem[0] = U_global[element.node_start.ddl_indices[0]]
	if element.node_start.ddl_indices[1] != -1:
		u_elem[1] = U_global[element.node_start.ddl_indices[1]]
	if element.node_start.ddl_indices[2] != -1:
		u_elem[2] = U_global[element.node_start.ddl_indices[2]]
	
	# Nœud d'arrivée
	if element.node_end.ddl_indices[0] != -1:
		u_elem[3] = U_global[element.node_end.ddl_indices[0]]
	if element.node_end.ddl_indices[1] != -1:
		u_elem[4] = U_global[element.node_end.ddl_indices[1]]
	if element.node_end.ddl_indices[2] != -1:
		u_elem[5] = U_global[element.node_end.ddl_indices[2]]
	
	# Calcul des forces: F = k * u
	var f_elem: Array[float] = []
	f_elem.resize(6)
	
	for i in range(6):
		f_elem[i] = 0.0
		for j in range(6):
			f_elem[i] += element.k_global[i * 6 + j] * u_elem[j]
	
	return {
		"fx_start": f_elem[0],
		"fy_start": f_elem[1],
		"mz_start": f_elem[2],
		"fx_end": f_elem[3],
		"fy_end": f_elem[4],
		"mz_end": f_elem[5]
	}

# Calcule les efforts dans les éléments
func _calculate_element_forces(elements: Array[RDMElement], U_global: Array[float], ddl_mapping: Dictionary):
	element_forces.clear()
	
	for element in elements:
		var forces = _calculate_element_end_forces(element, U_global, ddl_mapping)
		
		# Calculer les efforts internes (N, V, M)
		var internal_efforts = _calculate_internal_efforts(element, forces)
		
		element_forces[str(element.id)] = {
			"end_forces": forces,
			"internal": internal_efforts
		}

# Calcule les efforts internes (normal, tranchant, moment)
func _calculate_internal_efforts(element: RDMElement, forces: Dictionary) -> Dictionary:
	# Transformation dans le repère local
	var c = cos(element.angle)
	var s = sin(element.angle)
	
	# Forces aux extrémités dans le repère local
	var N_start = forces.fx_start * c + forces.fy_start * s
	var V_start = -forces.fx_start * s + forces.fy_start * c
	var M_start = forces.mz_start
	
	var N_end = forces.fx_end * c + forces.fy_end * s
	var V_end = -forces.fx_end * s + forces.fy_end * c
	var M_end = forces.mz_end
	
	return {
		"N_start": N_start,
		"V_start": V_start,
		"M_start": M_start,
		"N_end": N_end,
		"V_end": V_end,
		"M_end": M_end
	}

# Calcule les statistiques sur les résultats
func _calculate_statistics(nodes: Array[RDMNode], elements: Array[RDMElement]):
	max_displacement = 0.0
	max_rotation = 0.0
	total_strain_energy = 0.0
	
	# Déplacements maximaux
	for node in nodes:
		var disp = sqrt(node.u * node.u + node.v * node.v)
		max_displacement = max(max_displacement, disp)
		max_rotation = max(max_rotation, abs(node.theta))
	
	# Énergie de déformation
	for element in elements:
		var element_id = str(element.id)
		if element_forces.has(element_id):
			var forces = element_forces[element_id].end_forces
			var u_elem = [element.node_start.u, element.node_start.v, element.node_start.theta,
						 element.node_end.u, element.node_end.v, element.node_end.theta]
			
			# Énergie élémentaire: U = 0.5 * u^T * k * u
			var energy = 0.0
			for i in range(6):
				for j in range(6):
					var force_key = ["fx_start", "fy_start", "mz_start", "fx_end", "fy_end", "mz_end"][i]
					energy += 0.5 * u_elem[i] * element.k_global[i * 6 + j] * u_elem[j]
			
			total_strain_energy += energy

# Export des résultats pour visualisation
func get_visualization_data() -> Dictionary:
	return {
		"max_displacement": max_displacement,
		"max_rotation": max_rotation,
		"total_strain_energy": total_strain_energy,
		"reactions": reactions,
		"element_forces": element_forces
	}

# Génère un rapport texte des résultats
func generate_report() -> String:
	var report = ""
	report += "=== RAPPORT D'ANALYSE RDM ===\n\n"
	report += "Déplacements maximaux:\n"
	report += "  - Translation: %.6f m\n" % max_displacement
	report += "  - Rotation: %.6f rad (%.2f°)\n\n" % [max_rotation, rad_to_deg(max_rotation)]
	
	report += "Énergie de déformation totale: %.6f J\n\n" % total_strain_energy
	
	if not reactions.is_empty():
		report += "Réactions aux appuis:\n"
		for node_id in reactions:
			var reaction = reactions[node_id]
			report += "  - Nœud %s: Rx=%.2f N, Ry=%.2f N, Mz=%.2f N·m\n" % [node_id, reaction.fx, reaction.fy, reaction.mz]
		report += "\n"
	
	return report
