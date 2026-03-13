extends MenuButton

var layer_manager : LayerManager
var selection_manager : Node2D # Référence au selection manager

signal layer_changed_via_ribbon(new_layer_name: String)

# Fonction d'initialisation modifiée pour recevoir SelectionManager
func setup(l_manager: LayerManager, s_manager: Node2D):
	layer_manager = l_manager
	selection_manager = s_manager
	
	# Connexions LayerManager
	layer_manager.layers_changed.connect(rebuild_menu)
	layer_manager.active_layer_changed.connect(_on_active_layer_changed)
	
	# Connexion SelectionManager (Nouveau signal)
	if selection_manager.has_signal("selection_changed"):
		selection_manager.selection_changed.connect(_on_selection_changed)
	
	# Connexion UI
	get_popup().id_pressed.connect(_on_item_pressed)
	rebuild_menu()

func rebuild_menu(_ignore = null):
	var popup = get_popup()
	popup.clear()
	
	for i in range(layer_manager.layers.size()):
		var layer = layer_manager.layers[i]
		popup.add_item(layer.name, i)
		
		var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(layer.color)
		popup.set_item_icon(i, ImageTexture.create_from_image(img))
	
	# Après rebuild, on met à jour le texte
	_update_visuals()

# QUAND ON CLIQUE SUR UN CALQUE DANS LA LISTE
func _on_item_pressed(id):
	# 1. Vérifier si on a une sélection
	var selected_items = selection_manager.get_selected_entities_list()
	
	if selected_items.size() > 0:
		# CAS A : On déplace les objets sélectionnés vers ce calque
		for ent in selected_items:
			layer_manager.move_entity_to_layer(ent, id)
		
		# Émettre le signal pour synchroniser le PropertiesPanel
		emit_signal("layer_changed_via_ribbon", layer_manager.layers[id].name)
		
		# On force une mise à jour visuelle pour montrer le changement
		_update_visuals(selected_items)
		
	else:
		# CAS B : Pas de sélection, on change le calque actif (comportement d'avant)
		layer_manager.set_active_layer(id)

# QUAND LE CALQUE ACTIF CHANGE (Globalement)
func _on_active_layer_changed(_idx):
	# On ne met à jour que s'il n'y a pas de sélection en cours
	if selection_manager.count_selected() == 0:
		_update_visuals()

# QUAND LA SÉLECTION CHANGE (Clic utilisateur)
func _on_selection_changed(selected_items):
	_update_visuals(selected_items)

# FONCTION CENTRALE DE MISE À JOUR DU BOUTON
func _update_visuals(selected_items_override = null):
	print("DEBUG: _update_visuals appelé avec selected_items_override = ", selected_items_override)
	if not layer_manager: return
	
	var items = selected_items_override
	if items == null:
		if selection_manager:
			items = selection_manager.get_selected_entities_list()
		else:
			items = []
	
	print("DEBUG: items.size() = ", items.size())
	
	# CAS 1 : RIEN DE SÉLECTIONNÉ -> On affiche le calque Actif
	if items.size() == 0:
		var current = layer_manager.get_active_layer_data()
		print("DEBUG: aucune sélection -> calque actif = ", current.name)
		_set_button_display(current.name, current.color)
		
	# CAS 2 : 1 SEUL OBJET -> On affiche son calque
	elif items.size() == 1:
		var ent = items[0]
		var parent = ent.get_parent()
		print("DEBUG: 1 objet sélectionné -> parent = ", parent.name if parent else "null")
		# On cherche quel calque correspond à ce parent
		for lay in layer_manager.layers:
			if lay.node == parent:
				print("DEBUG: trouvé calque correspondant = ", lay.name)
				_set_button_display(lay.name, lay.color)
				return
		# Si non trouvé (ex: racine)
		print("DEBUG: calque non trouvé -> affiche 'Inconnu'")
		_set_button_display("Inconnu", Color.GRAY)
		
	# CAS 3 : MULTI-SÉLECTION -> On gère le cas mixte
	else:
		var first_parent = items[0].get_parent()
		var all_same = true
		print("DEBUG: multi-sélection -> vérification parents")
		for i in range(1, items.size()):
			if items[i].get_parent() != first_parent:
				all_same = false
				break
		
		if all_same:
			# Ils sont tous sur le même calque
			for lay in layer_manager.layers:
				if lay.node == first_parent:
					print("DEBUG: multi-sélection même calque = ", lay.name)
					_set_button_display(lay.name, lay.color)
					return
		else:
			# Calques multiples mélangés
			print("DEBUG: multi-sélection calques mélangés")
			_set_button_display("---", Color.WHITE)

# Helper pour changer l'aspect du bouton
func _set_button_display(text_str: String, col: Color):
	text = "Calque: " + text_str
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(col)
	icon = ImageTexture.create_from_image(img)
