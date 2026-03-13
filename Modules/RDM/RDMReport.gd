# RDMReport.gd
# Module de post-traitement et de vérification pour le solveur MEF
class_name RDMReport
extends RefCounted

# Tolérances pour la vérification de l'équilibre
var equilibrium_tolerance: float = 1e-3

# Constructeur
func _init():
	pass

# Point d'entrée principal pour générer tous les rapports de vérification
func generate_verification_report(nodes: Array[RDMNode], elements: Array[RDMElement], results: RDMResults) -> String:
	var report = ""
	
	print("\n" + "=".repeat(60))
	print("RAPPORT DE VÉRIFICATION POST-TRAITEMENT MEF")
	print("=".repeat(60))
	
	# Vérification 1: Équilibre aux nœuds (PFS)
	print("\n1. VÉRIFICATION DU PRINCIPE FONDAMENTAL DE LA STATIQUE")
	print("-".repeat(50))
	report += verify_equilibrium_at_nodes(nodes, elements, results)
	
	# Vérification 2: Reconstruction des équations d'efforts internes
	print("\n2. RECONSTRUCTION DES ÉQUATIONS D'EFFORTS INTERNES")
	print("-".repeat(50))
	report += reconstruct_internal_efforts_equations(elements, results)
	
	print("=".repeat(60))
	print("FIN DU RAPPORT DE VÉRIFICATION")
	print("=".repeat(60) + "\n")
	
	return report

# Vérification du PFS aux nœuds
func verify_equilibrium_at_nodes(nodes: Array[RDMNode], elements: Array[RDMElement], results: RDMResults) -> String:
	var report = ""
	var equilibrium_ok = true
	
	print("Vérification de l'équilibre ΣF = 0 et ΣM = 0 à chaque nœud:")
	print("")
	
	for node in nodes:
		var equilibrium = calculate_node_equilibrium(node, elements, results)
		
		# Vérification des tolérances
		var fx_ok = abs(equilibrium.sum_fx) < equilibrium_tolerance
		var fy_ok = abs(equilibrium.sum_fy) < equilibrium_tolerance
		var mz_ok = abs(equilibrium.sum_mz) < equilibrium_tolerance
		
		var status = "ÉQUILIBRE" if (fx_ok and fy_ok and mz_ok) else "DÉSÉQUILIBRE"
		var status_symbol = "✓" if (fx_ok and fy_ok and mz_ok) else "✗"
		
		# Affichage dans la console avec format amélioré
		var console_line = "Nœud %d : ΣFx = %8.4f N, ΣFy = %8.4f N, ΣMz = %8.4f N·m %s" % [
			node.id,
			equilibrium.sum_fx,
			equilibrium.sum_fy,
			equilibrium.sum_mz,
			status_symbol
		]
		print(console_line)
		
		# Ajout au rapport
		report += console_line + "\n"
		
		# Détail des forces pour tous les nœuds (pas seulement ceux en déséquilibre)
		print("  → Détail des forces au nœud %d:" % node.id)
		print("    Forces externes:    Fx=%8.4f, Fy=%8.4f, Mz=%8.4f" % [node.fx, node.fy, node.mz])
		
		if equilibrium.reactions.has(str(node.id)):
			var reaction = equilibrium.reactions[str(node.id)]
			print("    Réactions d'appui:  Rx=%8.4f, Ry=%8.4f, Mz=%8.4f" % [reaction.fx, reaction.fy, reaction.mz])
		else:
			print("    Réactions d'appui:  Rx=%8.4f, Ry=%8.4f, Mz=%8.4f" % [0.0, 0.0, 0.0])
		
		print("    Forces internes:    Fx=%8.4f, Fy=%8.4f, Mz=%8.4f" % [equilibrium.internal_fx, equilibrium.internal_fy, equilibrium.internal_mz])
		print("    Bilan:              ΣFx=%8.4f, ΣFy=%8.4f, ΣMz=%8.4f" % [equilibrium.sum_fx, equilibrium.sum_fy, equilibrium.sum_mz])
		print("")
		
		if not (fx_ok and fy_ok and mz_ok):
			equilibrium_ok = false
	
	if equilibrium_ok:
		print("✓ Tous les nœuds respectent le principe fondamental de la statique")
	else:
		print("⚠️  ATTENTION: Certains nœuds ne sont pas en équilibre!")
	
	return report

# Calcule l'équilibre des forces à un nœud
func calculate_node_equilibrium(node: RDMNode, elements: Array[RDMElement], results: RDMResults) -> Dictionary:
	var equilibrium = {
		"sum_fx": 0.0,
		"sum_fy": 0.0,
		"sum_mz": 0.0,
		"internal_fx": 0.0,
		"internal_fy": 0.0,
		"internal_mz": 0.0,
		"reactions": {}
	}
	
	# Forces externes appliquées au nœud
	equilibrium.sum_fx += node.fx
	equilibrium.sum_fy += node.fy
	equilibrium.sum_mz += node.mz
	
	# Réactions aux appuis (si présentes)
	if results.reactions.has(str(node.id)):
		var reaction = results.reactions[str(node.id)]
		equilibrium.sum_fx += reaction.fx
		equilibrium.sum_fy += reaction.fy
		equilibrium.sum_mz += reaction.mz
		equilibrium.reactions[str(node.id)] = reaction
	
	# Forces internes des éléments connectés
	var internal_forces = calculate_internal_forces_at_node(node, elements, results)
	equilibrium.internal_fx = internal_forces.fx
	equilibrium.internal_fy = internal_forces.fy
	equilibrium.internal_mz = internal_forces.mz
	
	# Convention utilisée ici (cohérente avec le calcul des réactions dans RDMResults):
	# internal_forces = somme des forces/moments nodaux des éléments au nœud (actions des éléments sur le nœud)
	# Équilibre nodal: Forces externes + Réactions + Forces internes = 0
	equilibrium.sum_fx += internal_forces.fx
	equilibrium.sum_fy += internal_forces.fy
	equilibrium.sum_mz += internal_forces.mz
	
	return equilibrium

# Calcule les forces internes à un nœud à partir des efforts dans les éléments
func calculate_internal_forces_at_node(node: RDMNode, elements: Array[RDMElement], results: RDMResults) -> Dictionary:
	var internal_force = {"fx": 0.0, "fy": 0.0, "mz": 0.0}
	
	for element in elements:
		if element.node_start == node or element.node_end == node:
			var element_id = str(element.id)
			if results.element_forces.has(element_id):
				var element_data = results.element_forces[element_id]
				var end_forces = element_data.end_forces
				
				# Utiliser directement les efforts nodaux globaux de l'élément (end_forces)
				# afin d'être cohérent avec le calcul des réactions dans RDMResults.
				if element.node_start == node:
					internal_force.fx += end_forces.fx_start
					internal_force.fy += end_forces.fy_start
					internal_force.mz += end_forces.mz_start
				else:
					internal_force.fx += end_forces.fx_end
					internal_force.fy += end_forces.fy_end
					internal_force.mz += end_forces.mz_end
	
	return internal_force

# Reconstruction des équations d'efforts internes
func reconstruct_internal_efforts_equations(elements: Array[RDMElement], results: RDMResults) -> String:
	var report = ""
	
	print("Reconstruction des équations N(x), V(x), M(x) pour chaque poutre:")
	print("")
	
	# Reconstruction par intégration sur chaque élément avec V constant (charges nodales)
	# Hypothèse: structure 2D, et pour une poutre horizontale on reconstruit le long d'un axe x cumulatif (0 → L).
	var ordered_elements: Array = []
	ordered_elements.assign(elements)
	ordered_elements.sort_custom(func(a, b):
		var ax0 = min(a.node_start.x, a.node_end.x)
		var bx0 = min(b.node_start.x, b.node_end.x)
		return ax0 < bx0
	)
	
	var current_m_at_x0 := 0.0
	var current_x0 := 0.0
	
	for element in ordered_elements:
		var element_id = str(element.id)
		if not results.element_forces.has(element_id):
			continue
		
		var end_forces = results.element_forces[element_id].end_forces
		
		var left_is_start : bool = element.node_start.x <= element.node_end.x
		var x0 := current_x0
		var x1 : float = current_x0 + element.length
		var L : float = element.length
		
		# Efforts nodaux au nœud gauche (global). Pour une poutre horizontale: local == global.
		var N0 : float = (end_forces.fx_start if left_is_start else end_forces.fx_end)
		var V0 : float = (end_forces.fy_start if left_is_start else end_forces.fy_end)
		# Convention de coupe (cohérente avec ton PFS):
		# V(x) est l'effort tranchant dans la section, égal à la force nodale au nœud gauche
		var V_section : float = V0
		
		# N(x) constant pour charges nodales (sans unité)
		var n_equation = "%.1f" % N0
		
		# V(x) constant sur l'élément (sans unité)
		var v_equation = "%.1f" % V_section
		
		# Moment: dM/dx = -V
		# M(x) = M(x0) - V*(x - x0)
		var m_const : float = current_m_at_x0 + V_section * x0
		var m_slope : float = -V_section
		var m_equation_pretty : String
		
		# Cas simple: M(x) = slope * x
		if abs(m_const) < equilibrium_tolerance:
			m_equation_pretty = "%.1f*x" % m_slope
		elif m_slope == 0:
			m_equation_pretty = "%.1f" % m_const
		else:
			var sign_str = "+" if m_const >= 0 else "-"
			m_equation_pretty = "%.1f*x %s %.1f" % [m_slope, sign_str, abs(m_const)]
		
		print("Poutre %d (De x=%.3f à x=%.3f):" % [element.id, x0, x1])
		print("  N(x) = %s" % n_equation)
		print("  V(x) = %s" % v_equation)
		print("  M(x) = %s" % m_equation_pretty)
		print("")
		
		report += "Poutre %d (De x=%.3f à x=%.3f):\n" % [element.id, x0, x1]
		report += "  N(x) = %s\n" % n_equation
		report += "  V(x) = %s\n" % v_equation
		report += "  M(x) = %s\n\n" % m_equation_pretty
		
		# Propager le moment à l'extrémité droite
		current_m_at_x0 = current_m_at_x0 - V_section * L
		current_x0 = x1
	
	return report

# Reconstruction de l'équation de l'effort normal N(x)
func reconstruct_normal_equation(element: RDMElement, internal: Dictionary, start_pos: float = 0.0) -> String:
	# Pour les charges nodales, N(x) est constant par morceau
	var N_start = internal.N_start
	var N_end = internal.N_end
	
	# Si N_start ≈ N_end, l'effort est constant
	if abs(N_start - N_end) < equilibrium_tolerance:
		return "%.1f N" % N_start
	else:
		# Cas linéaire (rare pour charges nodales pures)
		var slope = (N_end - N_start) / element.length
		return "%.1f*x + %.1f N" % [slope, N_start]

# Reconstruction de l'équation de l'effort tranchant V(x)
func reconstruct_shear_equation(element: RDMElement, internal: Dictionary, start_pos: float = 0.0) -> String:
	# Pour les charges nodales, V(x) est constant par morceau
	var V_start = internal.V_start
	var V_end = internal.V_end
	
	# Si V_start ≈ V_end, l'effort est constant
	if abs(V_start - V_end) < equilibrium_tolerance:
		return "%.1f N" % V_start
	else:
		# Cas linéaire (présence de charges réparties)
		var slope = (V_end - V_start) / element.length
		return "%.1f*x + %.1f N" % [slope, V_start]

# Reconstruction de l'équation du moment fléchissant M(x)
func reconstruct_moment_equation(element: RDMElement, internal: Dictionary, start_pos: float = 0.0) -> String:
	var M_start = internal.M_start
	var M_end = internal.M_end
	
	# Pour les charges nodales, M(x) est linéaire
	var slope = (M_end - M_start) / element.length
	
	# Si la pente est quasi nulle, le moment est constant
	if abs(slope) < equilibrium_tolerance:
		return "%.1f N·m" % M_start
	else:
		# Équation linéaire: M(x) = slope*x + M_start
		if abs(M_start) < equilibrium_tolerance:
			return "%.1f*x N·m" % slope
		else:
			var sign = "+" if M_start > 0 else "-"
			return "%.1f*x %s %.1f N·m" % [slope, sign, abs(M_start)]

# Fonction utilitaire pour formater les nombres avec suppression des zéros insignifiants
func format_number(value: float, precision: int = 4) -> String:
	var formatted = "%.*f" % [precision, abs(value)]
	
	# Supprimer les zéros de fin et le point si nécessaire
	if formatted.contains("."):
		formatted = formatted.rstrip("0").rstrip(".")
	
	# Ajouter le signe
	if value < 0:
		return "-" + formatted
	else:
		return formatted
