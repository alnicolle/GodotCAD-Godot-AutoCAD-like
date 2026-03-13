# RDMElement.gd
# Structure de données pour un élément de poutre dans la méthode des éléments finis
class_name RDMElement
extends RefCounted

# Propriétés géométriques
var length: float
var angle: float  # Angle par rapport à l'axe X global

# Propriétés matérielles
var E: float = 210e9  # Module d'Young (acier par défaut en Pa)
var A: float = 1e-4    # Section (m²)
var I: float = 8.33e-8 # Moment d'inertie (m^4)

# Nœuds de connexion
var node_start: RDMNode
var node_end: RDMNode

# Matrices locales
var k_local: Array[float] = []  # Matrice de raideur locale 6x6 (stockée linéairement)
var T: Array[float] = []        # Matrice de rotation 6x6

# Matrice globale (calculée)
var k_global: Array[float] = [] # Matrice de raideur globale 6x6

# ID unique pour l'élément
var id: int

# Constructeur
func _init(start_node: RDMNode, end_node: RDMNode, _id: int = -1):
	node_start = start_node
	node_end = end_node
	id = _id
	_calculate_geometry()
	_build_local_stiffness_matrix()
	_build_rotation_matrix()
	_calculate_global_stiffness_matrix()

# Calcule les propriétés géométriques
func _calculate_geometry():
	var dx = node_end.x - node_start.x
	var dy = node_end.y - node_start.y
	length = sqrt(dx * dx + dy * dy)
	angle = atan2(dy, dx)

# Construit la matrice de raideur locale pour une poutre de Bernoulli-Euler
func _build_local_stiffness_matrix():
	k_local.clear()
	k_local.resize(36)  # 6x6
	
	# Coefficients pour la matrice de raideur locale
	var EA_L = E * A / length
	var EI_L3 = E * I / (length * length * length)
	var EI_L2 = E * I / (length * length)
	var EI_L = E * I / length
	
	# Matrice de raideur locale (formule standard pour poutre 2D)
	# Ligne 1
	k_local[0] = EA_L
	k_local[1] = 0.0
	k_local[2] = 0.0
	k_local[3] = -EA_L
	k_local[4] = 0.0
	k_local[5] = 0.0
	
	# Ligne 2
	k_local[6] = 0.0
	k_local[7] = 12.0 * EI_L3
	k_local[8] = 6.0 * EI_L2
	k_local[9] = 0.0
	k_local[10] = -12.0 * EI_L3
	k_local[11] = 6.0 * EI_L2
	
	# Ligne 3
	k_local[12] = 0.0
	k_local[13] = 6.0 * EI_L2
	k_local[14] = 4.0 * EI_L
	k_local[15] = 0.0
	k_local[16] = -6.0 * EI_L2
	k_local[17] = 2.0 * EI_L
	
	# Ligne 4
	k_local[18] = -EA_L
	k_local[19] = 0.0
	k_local[20] = 0.0
	k_local[21] = EA_L
	k_local[22] = 0.0
	k_local[23] = 0.0
	
	# Ligne 5
	k_local[24] = 0.0
	k_local[25] = -12.0 * EI_L3
	k_local[26] = -6.0 * EI_L2
	k_local[27] = 0.0
	k_local[28] = 12.0 * EI_L3
	k_local[29] = -6.0 * EI_L2
	
	# Ligne 6
	k_local[30] = 0.0
	k_local[31] = 6.0 * EI_L2
	k_local[32] = 2.0 * EI_L
	k_local[33] = 0.0
	k_local[34] = -6.0 * EI_L2
	k_local[35] = 4.0 * EI_L

# Construit la matrice de rotation
func _build_rotation_matrix():
	T.clear()
	T.resize(36)  # 6x6
	
	var c = cos(angle)
	var s = sin(angle)
	
	# Matrice de rotation pour transformation local->global
	# Ligne 1
	T[0] = c;   T[1] = s;   T[2] = 0.0
	T[3] = 0.0; T[4] = 0.0; T[5] = 0.0
	
	# Ligne 2
	T[6] = -s;  T[7] = c;   T[8] = 0.0
	T[9] = 0.0; T[10] = 0.0; T[11] = 0.0
	
	# Ligne 3
	T[12] = 0.0; T[13] = 0.0; T[14] = 1.0
	T[15] = 0.0; T[16] = 0.0; T[17] = 0.0
	
	# Ligne 4
	T[18] = 0.0; T[19] = 0.0; T[20] = 0.0
	T[21] = c;   T[22] = s;   T[23] = 0.0
	
	# Ligne 5
	T[24] = 0.0; T[25] = 0.0; T[26] = 0.0
	T[27] = -s;  T[28] = c;   T[29] = 0.0
	
	# Ligne 6
	T[30] = 0.0; T[31] = 0.0; T[32] = 0.0
	T[33] = 0.0; T[34] = 0.0; T[35] = 1.0

# Calcule la matrice de raideur globale: k_global = T^T * k_local * T
func _calculate_global_stiffness_matrix():
	k_global.clear()
	k_global.resize(36)
	
	# Calcul k_temp = k_local * T
	var k_temp: Array[float] = []
	k_temp.resize(36)
	
	for i in range(6):
		for j in range(6):
			var sum = 0.0
			for k in range(6):
				sum += k_local[i * 6 + k] * T[k * 6 + j]
			k_temp[i * 6 + j] = sum
	
	# Calcul k_global = T^T * k_temp
	for i in range(6):
		for j in range(6):
			var sum = 0.0
			for k in range(6):
				sum += T[k * 6 + i] * k_temp[k * 6 + j]
			k_global[i * 6 + j] = sum

# Accesseur pour la matrice globale
func get_global_stiffness_matrix() -> Array[float]:
	return k_global

# Retourne une représentation textuelle
func _to_string() -> String:
	return "RDMElement(id=%d, length=%.3f, nodes=[%d,%d])" % [id, length, node_start.id, node_end.id]
