# RDMNode.gd
# Structure de données pour un nœud dans la méthode des éléments finis
class_name RDMNode
extends RefCounted

# Position du nœud dans l'espace 2D
var x: float
var y: float

# Indices des degrés de liberté (DDL) dans la matrice globale
# ddl_indices[0] = indice pour u (déplacement horizontal)
# ddl_indices[1] = indice pour v (déplacement vertical)  
# ddl_indices[2] = indice pour θ (rotation)
var ddl_indices: Array[int] = [-1, -1, -1]

# Résultats du calcul
var u: float = 0.0  # Déplacement horizontal
var v: float = 0.0  # Déplacement vertical
var theta: float = 0.0  # Rotation

# Forces nodales appliquées
var fx: float = 0.0  # Force horizontale
var fy: float = 0.0  # Force verticale
var mz: float = 0.0  # Moment

# Conditions limites
var is_fixed_u: bool = false  # Bloqué en u
var is_fixed_v: bool = false  # Bloqué en v
var is_fixed_theta: bool = false  # Bloqué en θ

# ID unique pour le nœud
var id: int

# Constructeur
func _init(_x: float, _y: float, _id: int = -1):
	x = _x
	y = _y
	id = _id

# Distance euclidienne à un autre point
func distance_to(other_x: float, other_y: float) -> float:
	return sqrt((x - other_x) * (x - other_x) + (y - other_y) * (y - other_y))

# Vérifie si ce nœud est à la même position qu'un autre (tolérance)
func is_at_position(other_x: float, other_y: float, tolerance: float = 1e-6) -> bool:
	return distance_to(other_x, other_y) <= tolerance

# Réinitialise les résultats
func reset_results():
	u = 0.0
	v = 0.0
	theta = 0.0

# Réinitialise les forces
func reset_forces():
	fx = 0.0
	fy = 0.0
	mz = 0.0

# Retourne une représentation textuelle
func _to_string() -> String:
	return "RDMNode(id=%d, pos=(%.3f, %.3f), ddl=[%d,%d,%d])" % [id, x, y, ddl_indices[0], ddl_indices[1], ddl_indices[2]]
