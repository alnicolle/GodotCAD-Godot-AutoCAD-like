# RDMSupport.gd
# Représente une condition limite (appui) dans la méthode des éléments finis
class_name RDMSupport
extends RefCounted

# Types d'appuis possibles
enum SupportType {
	SIMPLE,        # Appui simple (bloque v uniquement)
	ARTICULATION,  # Articulation (bloque u et v)
	ENCASTREMENT   # Encastrement (bloque u, v et θ)
}

# Nœud sur lequel l'appui est appliqué
var node: RDMNode

# Type d'appui
var type: SupportType

# ID unique
var id: int

# Constructeur
func _init(target_node: RDMNode, support_type: String = "simple", _id: int = -1):
	node = target_node
	id = _id
	
	# Conversion du string en enum
	match support_type.to_lower():
		"simple":
			type = SupportType.SIMPLE
		"articulation":
			type = SupportType.ARTICULATION
		"encastrement":
			type = SupportType.ENCASTREMENT
		_:
			type = SupportType.SIMPLE

# Applique les conditions limites au nœud
func apply_to_node():
	match type:
		SupportType.SIMPLE:
			node.is_fixed_v = true
		SupportType.ARTICULATION:
			node.is_fixed_u = true
			node.is_fixed_v = true
		SupportType.ENCASTREMENT:
			node.is_fixed_u = true
			node.is_fixed_v = true
			node.is_fixed_theta = true

# Retourne le nombre de degrés de liberté bloqués
func get_blocked_ddls() -> int:
	match type:
		SupportType.SIMPLE:
			return 1
		SupportType.ARTICULATION:
			return 2
		SupportType.ENCASTREMENT:
			return 3
		_:
			return 0

# Vérifie si un DDL spécifique est bloqué
func is_ddl_blocked(ddl_index: int) -> bool:
	match type:
		SupportType.SIMPLE:
			return ddl_index == 1  # v bloqué
		SupportType.ARTICULATION:
			return ddl_index == 0 or ddl_index == 1  # u et v bloqués
		SupportType.ENCASTREMENT:
			return ddl_index == 0 or ddl_index == 1 or ddl_index == 2  # u, v et θ bloqués
		_:
			return false

# Retourne une représentation textuelle
func _to_string() -> String:
	var type_str = ""
	match type:
		SupportType.SIMPLE:
			type_str = "Simple"
		SupportType.ARTICULATION:
			type_str = "Articulation"
		SupportType.ENCASTREMENT:
			type_str = "Encastrement"
	
	return "RDMSupport(id=%d, type=%s, node=%d)" % [id, type_str, node.id]
