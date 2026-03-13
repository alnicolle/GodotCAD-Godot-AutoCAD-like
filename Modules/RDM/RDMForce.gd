# RDMForce.gd
# Représente une force ou un moment appliqué à un nœud
class_name RDMForce
extends RefCounted

# Nœud sur lequel la force est appliquée
var node: RDMNode

# Composantes de la force
var fx: float = 0.0  # Force horizontale (N)
var fy: float = 0.0  # Force verticale (N)
var mz: float = 0.0  # Moment (N·m)

# ID unique
var id: int

# Constructeur
func _init(target_node: RDMNode, _fx: float = 0.0, _fy: float = 0.0, _mz: float = 0.0, _id: int = -1):
	node = target_node
	fx = _fx
	fy = _fy
	mz = _mz
	id = _id

# Applique la force au nœud
func apply_to_node():
	node.fx += fx
	node.fy += fy
	node.mz += mz

# Retourne l'intensité totale de la force
func get_magnitude() -> float:
	return sqrt(fx * fx + fy * fy)

# Retourne l'angle de la force (en radians)
func get_angle() -> float:
	return atan2(fy, fx)

# Vérifie si la force est nulle
func is_zero() -> bool:
	return abs(fx) < 1e-10 and abs(fy) < 1e-10 and abs(mz) < 1e-10

# Retourne une représentation textuelle
func _to_string() -> String:
	return "RDMForce(id=%d, node=%d, F=(%.1f, %.1f), M=%.1f)" % [id, node.id, fx, fy, mz]
