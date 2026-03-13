extends Node
class_name LayerManager

# Signaux
signal layers_changed 
signal active_layer_changed(new_layer_index)

# Référence au conteneur principal (assignée par Main)
@export var entities_root : Node2D :
	set(value):
		entities_root = value
		# Si la liste est encore vide, on initialise le calque par défaut tout de suite
		if layers.is_empty():
			create_layer("0", Color.WHITE)

# Structure : { "name":String, "color":Color, "visible":bool, "locked":bool, "node":Node2D, "linetype":String, "lineweight":float }
var layers : Array = []
var active_layer_index : int = 0

func _ready():
	pass

# --- GESTION DES CALQUES ---

func create_layer(layer_name: String, color: Color) -> void:
	# Vérification doublon
	for lay in layers:
		if lay.name == layer_name: return

	# 1. Création du Noeud physique
	var layer_node = Node2D.new()
	layer_node.name = layer_name
	
	# INITIALISATION META
	layer_node.set_meta("locked", false)
	
	# Ajout au monde (si entities_root est connu)
	if entities_root:
		entities_root.add_child(layer_node)
	
	# 2. Ajout des données
	var new_layer = {
		"name": layer_name,
		"color": color,
		"visible": true,
		"locked": false,
		"node": layer_node,
		"linetype": "CONTINUOUS",    # Valeur par défaut
		"lineweight": 0.25           # Épaisseur par défaut
	}
	
	layers.append(new_layer)
	emit_signal("layers_changed")
	GlobalLogger.info("Calque créé : " + layer_name)

func set_active_layer(index: int):
	if index >= 0 and index < layers.size():
		active_layer_index = index
		emit_signal("active_layer_changed", index)

func get_active_layer_data() -> Dictionary:
	if layers.is_empty(): 
		return {"name": "Erreur", "color": Color.MAGENTA, "node": null}
	return layers[active_layer_index]

func get_active_layer_node() -> Node2D:
	if layers.is_empty(): return null
	return layers[active_layer_index]["node"]

func toggle_visibility(index: int):
	if index >= 0 and index < layers.size():
		var lay = layers[index]
		lay.visible = !lay.visible
		if is_instance_valid(lay.node):
			lay.node.visible = lay.visible
			
		emit_signal("layers_changed")

func toggle_lock(index: int):
	if index >= 0 and index < layers.size():
		var lay = layers[index]
		lay.locked = !lay.locked
		
		if is_instance_valid(lay.node):
			lay.node.set_meta("locked", lay.locked)
			
		emit_signal("layers_changed")

func delete_layer(index: int):
	if index == 0:
		GlobalLogger.error("Impossible de supprimer le calque 0.")
		return
	if index == active_layer_index:
		GlobalLogger.error("Impossible de supprimer le calque actif.")
		return
		
	if index > 0 and index < layers.size():
		var lay = layers[index]
		
		if is_instance_valid(lay.node):
			lay.node.queue_free()
			
		layers.remove_at(index)
		
		if active_layer_index > index:
			active_layer_index -= 1
			
		emit_signal("layers_changed")

func move_entity_to_layer(entity: Node2D, target_layer_index: int):
	if target_layer_index < 0 or target_layer_index >= layers.size():
		return

	var target_layer_data = layers[target_layer_index]
	var target_node = target_layer_data.node
	
	# Si l'objet est déjà dans le bon noeud parent, on ne fait rien
	if entity.get_parent() == target_node:
		return 
		
	# Changement de parent (Déplacement physique dans l'arbre)
	entity.reparent(target_node)
	
	# Mise à jour des propriétés de l'entité
	if entity.has_method("update_visuals"):
		# 1. On dit à l'entité : "Ton nouveau propriétaire est ce calque"
		entity.layer_name = target_layer_data.name
		
		# 2. On force l'entité à relire les propriétés du calque (Couleur, Type...)
		# Cela mettra à jour l'apparence immédiatement si elle est en "DuCalque"
		entity.update_visuals()
	
	# Gestion de compatibilité (si ce n'est pas une CADEntity)
	else:
		var new_color = target_layer_data.color
		if entity is Line2D: entity.default_color = new_color
		elif "default_color" in entity: entity.set("default_color", new_color)
		
	GlobalLogger.info("Objet déplacé vers le calque : " + target_layer_data.name)

func move_entity_to_layer_by_name(entity: Node2D, layer_name: String):
	for i in range(layers.size()):
		if layers[i].name == layer_name:
			move_entity_to_layer(entity, i)
			return
	GlobalLogger.warning("Calque introuvable : " + layer_name)


# --- NOUVELLES FONCTIONS (NÉCESSAIRES POUR LAYERDIALOG & CADENTITY) ---

# Trouve un calque par son nom et renvoie son type de ligne
func get_layer_linetype(layer_name: String) -> String:
	for lay in layers:
		if lay.name == layer_name:
			return lay.get("linetype", "CONTINUOUS")
	return "CONTINUOUS"

# Trouve un calque par son nom et renvoie son épaisseur
func get_layer_lineweight(layer_name: String) -> float:
	for lay in layers:
		if lay.name == layer_name:
			return lay.get("lineweight", 0.25)
	return 0.25

# Trouve un calque par son nom et modifie une propriété
func set_layer_property(layer_name: String, property: String, value):
	for lay in layers:
		if lay.name == layer_name:
			lay[property] = value
			emit_signal("layers_changed")
			return

func _enter_tree():
	# Enregistrement vital pour être trouvé par les entités
	if not is_in_group("LayerManager_Global"):
		add_to_group("LayerManager_Global")
