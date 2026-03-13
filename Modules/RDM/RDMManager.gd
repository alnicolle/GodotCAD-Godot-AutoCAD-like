# RDMManager.gd
# Point d'entrée principal du module RDM/MEF
class_name RDMManager
extends RefCounted

# Référence au système CAD
var cad_system: Node

# Données du problème
var nodes: Array[RDMNode] = []
var elements: Array[RDMElement] = []
var supports: Array[RDMSupport] = []
var forces: Array[RDMForce] = []

# Paramètres du solveur
var tolerance: float = 1e-6
var max_iterations: int = 1000

# État du calcul
var is_solved: bool = false
var solution_time: float = 0.0

# Constructeur
func _init(cad_ref: Node = null):
	cad_system = cad_ref

# Point d'entrée principal pour le calcul
func calculate_analysis(line_entities: Array, support_entities: Array, force_entities: Array) -> Dictionary:
	print("Démarrage de l'analyse RDM...")
	
	var start_time = Time.get_ticks_msec()
	
	# Étape 1: Conversion des entités CAD en objets RDM
	var converter = RDMConverter.new()
	var conversion_result = converter.convert_to_rdm_objects(line_entities, support_entities, force_entities, tolerance)
	
	if conversion_result.has("error"):
		return {"error": conversion_result.error}
	
	nodes = conversion_result.nodes
	elements = conversion_result.elements
	supports = conversion_result.supports
	forces = conversion_result.forces
	
	print("Conversion terminée: %d nœuds, %d éléments, %d appuis, %d forces" % [
		nodes.size(), elements.size(), supports.size(), forces.size()
	])
	
	# Étape 2: Assemblage de la matrice globale
	var assembler = RDMAssembler.new()
	var assembly_result = assembler.assemble_global_system(nodes, elements, supports, forces)
	
	if assembly_result.has("error"):
		return {"error": assembly_result.error}
	
	var K_global = assembly_result.K_global
	var F_global = assembly_result.F_global
	var ddl_mapping = assembly_result.ddl_mapping
	var total_ddls = assembly_result.total_ddls
	
	print("Assemblage terminé: %d nœuds, %d éléments" % [nodes.size(), elements.size()])
	print("Assemblage terminé: matrice %dx%d" % [total_ddls, total_ddls])
	
	# Étape 3: Résolution du système
	var solver = RDMSolver.new()
	var solve_result = solver.solve_linear_system(K_global, F_global)
	
	if solve_result.has("error"):
		return {"error": solve_result.error}
	
	var U_global = solve_result.solution
	
	# Étape 4: Récupération des résultats
	var results = RDMResults.new()
	results.extract_results(nodes, elements, U_global, ddl_mapping)
	
	# Étape 5: Génération des rapports de vérification (post-traitement)
	var report_generator = RDMReport.new()
	report_generator.generate_verification_report(nodes, elements, results)
	
	solution_time = (Time.get_ticks_msec() - start_time) / 1000.0
	is_solved = true
	
	print("Analyse terminée en %.3f secondes" % solution_time)
	
	return {
		"success": true,
		"nodes": nodes,
		"elements": elements,
		"results": results,
		"solution_time": solution_time
	}

# Validation du modèle avant calcul
func validate_model() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	
	# Vérifier qu'il y a des éléments
	if elements.is_empty():
		errors.append("Aucun élément de poutre défini")
	
	# Vérifier qu'il y a des appuis
	if supports.is_empty():
		errors.append("Aucun appui défini - système instable")
	
	# Vérifier la connectivité
	for element in elements:
		if not nodes.has(element.node_start) or not nodes.has(element.node_end):
			errors.append("Élément %d connecté à des nœuds inexistants" % element.id)
	
	# Vérifier les conditions limites
	var fixed_ddls = 0
	for node in nodes:
		if node.is_fixed_u: fixed_ddls += 1
		if node.is_fixed_v: fixed_ddls += 1
		if node.is_fixed_theta: fixed_ddls += 1
	
	var total_ddls = nodes.size() * 3
	if fixed_ddls < 3:
		warnings.append("Peu de conditions limites - possible instabilité")
	
	if fixed_ddls >= total_ddls:
		errors.append("Tous les degrés de liberté sont bloqués - système sur-contraint")
	
	return {
		"is_valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings
	}

# Réinitialisation du modèle
func reset():
	nodes.clear()
	elements.clear()
	supports.clear()
	forces.clear()
	is_solved = false
	solution_time = 0.0
	
	print("Modèle RDM réinitialisé")

# Export des résultats pour visualisation
func export_results_for_visualization() -> Dictionary:
	if not is_solved:
		return {"error": "Modèle non résolu"}
	
	var viz_data = {
		"nodes": [],
		"elements": [],
		"displacements": [],
		"reactions": []
	}
	
	# Export des nœuds avec déplacements
	for node in nodes:
		viz_data.nodes.append({
			"id": node.id,
			"x": node.x,
			"y": node.y,
			"u": node.u,
			"v": node.v,
			"theta": node.theta
		})
	
	# Export des éléments
	for element in elements:
		viz_data.elements.append({
			"id": element.id,
			"node_start": element.node_start.id,
			"node_end": element.node_end.id,
			"length": element.length
		})
	
	return viz_data

# Configuration des propriétés matérielles
func set_material_properties(E: float, A: float, I: float):
	for element in elements:
		element.E = E
		element.A = A
		element.I = I
		# Recalculer les matrices avec nouvelles propriétés
		element._build_local_stiffness_matrix()
		element._build_rotation_matrix()
		element._calculate_global_stiffness_matrix()
	
	print("Propriétés matérielles mises à jour: E=%.2e Pa, A=%.2e m², I=%.2e m⁴" % [E, A, I])
