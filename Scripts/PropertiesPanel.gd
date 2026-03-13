extends PanelContainer

# 1. On déclare un signal personnalisé "vers l'extérieur"
signal property_color_changed(new_color)
signal property_layer_changed(new_layer_name)

# --- RÉFÉRENCES UI (Doivent correspondre aux noms dans votre scène) ---
# Section Général
@onready var opt_layer = find_child("ValueLayer")
@onready var picker_color = find_child("ValueColor")
@onready var opt_linetype = find_child("ValueLinetype")
@onready var opt_lineweight = find_child("ValueLineweight")
@onready var spin_lt_scale = find_child("ValueLinetypeScale")

# Section Géométrie
@onready var container_geo = find_child("GridGeometry")
@onready var lbl_x = find_child("LblGeoX")
@onready var spin_x = find_child("ValueGeoX")
@onready var lbl_y = find_child("LblGeoY")
@onready var spin_y = find_child("ValueGeoY")
@onready var lbl_r = find_child("LblGeoRadius")
@onready var spin_r = find_child("ValueGeoRadius")

# Section Polyligne (créée dynamiquement)
var polyline_section = null
var opt_vertex_selector = null
var spin_vertex_x = null
var spin_vertex_y = null
var spin_total_length = null   # SpinBox pour la longueur totale (non modifiable)
var chk_closed = null
var spin_area = null          # SpinBox pour l'aire (non modifiable)

# Section Cercle (créée dynamiquement)
var circle_section = null
var spin_circle_x = null
var spin_circle_y = null
var spin_circle_radius = null  # Nouveau SpinBox pour le rayon
var spin_diameter = null        # SpinBox pour le diamètre (non modifiable)
var spin_circumference = null   # SpinBox pour la circonférence (non modifiable)
var spin_circle_area = null     # SpinBox pour l'aire (non modifiable)


# --- VARIABLES INTERNES ---
var selection_manager = null # Sera injecté par le Main
var layer_manager = null     # Sera injecté par le Main
var is_updating_ui = false   # Verrou pour empêcher les boucles de signaux
var current_entity = null     # Entité actuellement sélectionnée pour la géométrie

func _ready():
	# Connexion des signaux UI
	if opt_layer: opt_layer.item_selected.connect(_on_layer_changed)
	if opt_linetype: opt_linetype.item_selected.connect(_on_linetype_changed)
	if opt_lineweight: opt_lineweight.item_selected.connect(_on_lineweight_changed)
	if spin_lt_scale: spin_lt_scale.value_changed.connect(_on_lt_scale_changed)
	
	# Géométrie
	if spin_x: spin_x.value_changed.connect(_on_geo_value_changed.bind("x"))
	if spin_y: spin_y.value_changed.connect(_on_geo_value_changed.bind("y"))
	if spin_r: spin_r.value_changed.connect(_on_geo_value_changed.bind("radius"))
	
	# 3. On connecte le signal interne du bouton à une fonction locale
	if picker_color:
		picker_color.color_changed.connect(_on_internal_color_changed)
	
	# Initialisation
	refresh_linetypes_list()
	refresh_lineweight_list()
	clear_interface()

# Fonction d'initialisation appelée par Main.gd
func setup(sel_man, lay_man):
	selection_manager = sel_man
	layer_manager = lay_man
	
	# On s'abonne aux changements de sélection
	if selection_manager:
		if not selection_manager.selection_changed.is_connected(_on_selection_updated):
			selection_manager.selection_changed.connect(_on_selection_updated)
			
	# On remplit la liste des calques au démarrage
	refresh_layers_list()

# --- LOGIQUE DE MISE À JOUR (SELECTION -> PANEL) ---

func _on_selection_updated(selected_list):
	# Verrouillage pour ne pas déclencher les signaux "Changed" pendant qu'on remplit
	is_updating_ui = true
	
	if selected_list.is_empty():
		clear_interface()
		is_updating_ui = false
		return

	# 1. Mise à jour des listes dynamiques (Calques/Linetypes/Lineweights)
	refresh_layers_list()
	refresh_linetypes_list()
	refresh_lineweight_list()

	# 2. Analyse des propriétés communes (Général)
	var first = selected_list[0]
	
	# VALEURS PAR DÉFAUT (du premier objet)
	var common_layer = first.layer_name
	var common_color = first.default_color_val
	var common_ltype = first.linetype
	var common_lweight = first.lineweight
	var common_scale = first.linetype_scale
	
	# GÉOMÉTRIE (Uniquement si 1 seul objet pour l'instant)
	var show_geo = (selected_list.size() == 1)
	
	# Si plusieurs objets, on vérifie s'ils ont les mêmes valeurs
	if selected_list.size() > 1:
		for i in range(1, selected_list.size()):
			var ent = selected_list[i]
			if ent.layer_name != common_layer: common_layer = "" # "" = VARIES
			if ent.default_color_val != common_color: common_color = Color(0,0,0,0) # Alpha 0 = VARIES
			if ent.linetype != common_ltype: common_ltype = ""
			if not is_equal_approx(ent.lineweight, common_lweight): common_lweight = -999.0
			if not is_equal_approx(ent.linetype_scale, common_scale): common_scale = -1.0

	# 3. Application aux champs UI
	
	# LAYER
	_select_option_item(opt_layer, common_layer)
	
	# COLOR
	if common_color.a == 0 and selected_list.size() > 1:
		picker_color.color = Color.GRAY # Indication visuelle "Mixte"
	else:
		picker_color.color = common_color
		
	# LINETYPE
	_select_option_item(opt_linetype, common_ltype)
	
	# LINEWEIGHT
	_select_weight_item(common_lweight)
	
	# SCALE
	if common_scale < 0: spin_lt_scale.get_line_edit().text = "VARIES" # Astuce visuelle
	else: spin_lt_scale.value = common_scale

	# 4. Gestion Section Géométrie
	if show_geo:
		_update_geometry_section(first)
	else:
		container_geo.visible = false

	is_updating_ui = false

func _update_geometry_section(ent):
	current_entity = ent
	container_geo.visible = true
	
	# Cacher les anciens éléments statiques X/Y/Rayon
	lbl_x.visible = false; spin_x.visible = false
	lbl_y.visible = false; spin_y.visible = false
	lbl_r.visible = false; spin_r.visible = false
	
	# Cas CERCLE
	if "is_circle" in ent and ent.is_circle:
		_hide_polyline_section()
		_show_circle_section(ent)
		
	# Cas LIGNE/POLYLIGNE
	elif ent is Line2D:
		_hide_circle_section()
		if ent.points.size() > 1:
			_show_polyline_section(ent)
		else:
			_show_simple_line_geometry(ent)
	else:
		container_geo.visible = false

func clear_interface():
	# Désactive ou grise tout quand rien n'est sélectionné
	if picker_color: picker_color.color = Color.WHITE
	if spin_lt_scale: spin_lt_scale.value = 1.0
	if container_geo: container_geo.visible = false
	
	# Afficher le calque actif quand il n'y a pas de sélection
	if opt_layer and layer_manager:
		var active = layer_manager.get_active_layer_data()
		_select_option_item(opt_layer, active.name)

func refresh_layers_list():
	if not opt_layer or not layer_manager: return
	opt_layer.clear()
	
	# On récupère les layers depuis le manager
	# On suppose que layer_manager a une liste 'layers'
	if "layers" in layer_manager:
		for lay in layer_manager.layers:
			opt_layer.add_item(lay.name)

func refresh_linetypes_list():
	if not opt_linetype: return
	opt_linetype.clear()
	
	# Types standards
	opt_linetype.add_item("DuCalque")    # ID 0
	opt_linetype.add_item("DuBloc")      # ID 1
	opt_linetype.add_item("CONTINUOUS")  # ID 2
	opt_linetype.add_separator()
	
	# Ajout dynamique depuis LinetypeManager
	if LinetypeManager:
		for type_name in LinetypeManager.linetype_names:
			if type_name != "CONTINUOUS":
				opt_linetype.add_item(type_name)
	
	opt_linetype.add_separator()
	opt_linetype.add_item("Autre...") 
	
	# --- CORRECTION UX : LIMITE HAUTEUR AVEC SCROLL ---
	var popup = opt_linetype.get_popup()
	popup.max_size = Vector2i(1000, 400)

func refresh_lineweight_list():
	if not opt_lineweight: return
	opt_lineweight.clear()
	
	# Types standards
	opt_lineweight.add_item("DuCalque") 
	opt_lineweight.add_item("DuBloc")   
	opt_lineweight.add_separator()
	opt_lineweight.add_item("Défaut")   
	
	var weights = [0.00, 0.05, 0.09, 0.13, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.53, 0.60, 0.70, 0.80, 0.90, 1.00, 1.06, 1.20, 1.40, 1.58, 2.00, 2.11]
	
	for w in weights:
		var text = "%.2f mm" % w
		opt_lineweight.add_item(text)
	
	# --- CORRECTION UX ---
	var popup = opt_lineweight.get_popup()
	popup.max_size = Vector2i(1000, 400)

# --- LOGIQUE D'APPLICATION (PANEL -> SELECTION) ---

func _apply_property(property_name, value):
	if is_updating_ui: return # STOP si c'est une mise à jour interne
	if not selection_manager: return
	
	# Appel à une nouvelle fonction générique du SelectionManager
	selection_manager.modify_selection_property(property_name, value)

func _on_layer_changed(index):
	var layer_name = opt_layer.get_item_text(index)
	_apply_property("layer_name", layer_name)
	emit_signal("property_layer_changed", layer_name)

func _on_color_changed(color):
	# Pour la couleur, c'est spécial car CADEntity utilise "default_color_val" pour la persistance
	# Mais "default_color" est la propriété interne de Line2D.
	# Le mieux est de cibler "default_color_val" dans votre CADEntity.
	_apply_property("default_color_val", color)

func _on_linetype_changed(index):
	var txt = opt_linetype.get_item_text(index)
	
	if txt == "Autre...":
		# TODO: Ouvrir la fenêtre de gestion des types de ligne
		GlobalLogger.warning("Gestionnaire de types de ligne non implémenté")
		return
	
	# Mapping UI -> Valeur interne
	if txt == "DuCalque": txt = "ByLayer"
	elif txt == "DuBloc": txt = "ByBlock"
	_apply_property("linetype", txt)

func _on_lineweight_changed(index):
	var txt = opt_lineweight.get_item_text(index)
	var val = -1.0
	if txt == "DuCalque": val = -1.0
	elif txt == "Défaut": val = 0.25
	else: val = txt.replace(" mm", "").to_float()
	_apply_property("lineweight", val)

func _on_lt_scale_changed(value):
	_apply_property("linetype_scale", value)

func _on_geo_value_changed(value, axis):
	if is_updating_ui: return
	if not selection_manager: return
	
	# Pour la géométrie, c'est plus complexe, on passe par une méthode dédiée
	selection_manager.modify_selection_geometry(axis, value)

# --- UTILITAIRES UI ---

func _select_option_item(opt: OptionButton, text_value: String):
	if text_value == "": 
		opt.selected = -1 # "VARIES" ou inconnu
		return
		
	# Tentative de mapping inverse (ByLayer -> DuCalque) pour l'UI
	var ui_text = text_value
	if text_value == "ByLayer": ui_text = "DuCalque"
	elif text_value == "ByBlock": ui_text = "DuBloc"
	
	for i in range(opt.item_count):
		if opt.get_item_text(i) == ui_text or opt.get_item_text(i) == text_value:
			opt.selected = i
			return
	
	# Si pas trouvé (ex: type de ligne custom chargé), on l'ajoute temporairement ?
	# Pour l'instant on désélectionne
	opt.selected = -1

func _select_weight_item(val: float):
	if val == -999.0: 
		opt_lineweight.selected = -1
		return
		
	for i in range(opt_lineweight.item_count):
		var txt = opt_lineweight.get_item_text(i)
		var item_val = -999.0
		if txt == "DuCalque": item_val = -1.0
		elif txt == "Défaut": item_val = 0.25
		else: item_val = txt.replace(" mm", "").to_float()
		
		if is_equal_approx(item_val, val):
			opt_lineweight.selected = i
			return
	opt_lineweight.selected = -1


func _on_internal_color_changed(color: Color):
	# On crie le signal vers le Main : "Eh ! La couleur a changé !"
	emit_signal("property_color_changed", color)

# --- FONCTIONS POUR LA SECTION POLYLIGNE ---

func _create_polyline_section():
	if polyline_section:
		return # Déjà créée
	
	polyline_section = VBoxContainer.new()
	polyline_section.name = "PolylineSection"
	
	# Séparateur
	var separator = HSeparator.new()
	polyline_section.add_child(separator)
	
	# Titre
	var title = Label.new()
	title.text = "POLYLIGNE"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.CYAN)
	polyline_section.add_child(title)
	
	# Sélecteur de sommet
	var vertex_container = HBoxContainer.new()
	var lbl_vertex = Label.new()
	lbl_vertex.text = "Sommet courant :"
	lbl_vertex.custom_minimum_size.x = 100
	opt_vertex_selector = OptionButton.new()
	opt_vertex_selector.custom_minimum_size.x = 150
	vertex_container.add_child(lbl_vertex)
	vertex_container.add_child(opt_vertex_selector)
	polyline_section.add_child(vertex_container)
	
	# Coordonnées du sommet
	var coord_container = HBoxContainer.new()
	var lbl_vx = Label.new()
	lbl_vx.text = "X :"
	lbl_vx.custom_minimum_size.x = 30
	spin_vertex_x = SpinBox.new()
	spin_vertex_x.custom_minimum_size.x = 100
	spin_vertex_x.step = 0.1
	spin_vertex_x.allow_greater = true
	spin_vertex_x.allow_lesser = true
	var lbl_vy = Label.new()
	lbl_vy.text = "Y :"
	lbl_vy.custom_minimum_size.x = 30
	spin_vertex_y = SpinBox.new()
	spin_vertex_y.custom_minimum_size.x = 100
	spin_vertex_y.step = 0.1
	spin_vertex_y.allow_greater = true
	spin_vertex_y.allow_lesser = true
	coord_container.add_child(lbl_vx)
	coord_container.add_child(spin_vertex_x)
	coord_container.add_child(lbl_vy)
	coord_container.add_child(spin_vertex_y)
	polyline_section.add_child(coord_container)
	
	# Longueur totale
	var length_container = HBoxContainer.new()
	var lbl_length = Label.new()
	lbl_length.text = "Longueur totale :"
	lbl_length.custom_minimum_size.x = 100
	spin_total_length = SpinBox.new()
	spin_total_length.custom_minimum_size.x = 150
	spin_total_length.step = 0.01
	spin_total_length.allow_greater = true
	spin_total_length.allow_lesser = true
	spin_total_length.editable = false  # Non modifiable
	length_container.add_child(lbl_length)
	length_container.add_child(spin_total_length)
	polyline_section.add_child(length_container)
	
	# Case "Fermé"
	var closed_container = HBoxContainer.new()
	var lbl_closed = Label.new()
	lbl_closed.text = "Fermé :"
	lbl_closed.custom_minimum_size.x = 100
	chk_closed = CheckBox.new()
	closed_container.add_child(lbl_closed)
	closed_container.add_child(chk_closed)
	polyline_section.add_child(closed_container)
	
	# Aire
	var area_container = HBoxContainer.new()
	var lbl_area_title = Label.new()
	lbl_area_title.text = "Aire :"
	lbl_area_title.custom_minimum_size.x = 100
	spin_area = SpinBox.new()
	spin_area.custom_minimum_size.x = 150
	spin_area.step = 0.01
	spin_area.allow_greater = true
	spin_area.allow_lesser = true
	spin_area.editable = false  # Non modifiable
	area_container.add_child(lbl_area_title)
	area_container.add_child(spin_area)
	polyline_section.add_child(area_container)
	
	# Connecter les signaux
	opt_vertex_selector.item_selected.connect(_on_vertex_selected)
	spin_vertex_x.value_changed.connect(_on_vertex_coord_changed)
	spin_vertex_y.value_changed.connect(_on_vertex_coord_changed)
	chk_closed.toggled.connect(_on_closed_toggled)
	
	# Ajouter à la section géométrie
	container_geo.add_child(polyline_section)

func _show_polyline_section(ent):
	if not polyline_section:
		_create_polyline_section()
	
	polyline_section.visible = true
	
	# Mettre à jour le sélecteur de sommets
	opt_vertex_selector.clear()
	for i in range(ent.points.size()):
		opt_vertex_selector.add_item("Sommet " + str(i + 1))
	
	if ent.points.size() > 0:
		opt_vertex_selector.selected = 0
		_update_vertex_display(ent, 0)
	
	# Mettre à jour la case "Fermé"
	var is_closed = _is_polyline_closed(ent)
	chk_closed.button_pressed = is_closed
	
	# Mettre à jour la longueur totale
	var length = _calculate_polyline_length(ent)
	spin_total_length.value = length
	
	# Mettre à jour l'aire
	if is_closed:
		var area = _calculate_polyline_area(ent)
		spin_area.value = area
		spin_area.get_parent().visible = true
	else:
		spin_area.get_parent().visible = false

func _hide_polyline_section():
	if polyline_section:
		polyline_section.visible = false

func _show_circle_section(ent):
	if not circle_section:
		_create_circle_section()
	
	circle_section.visible = true
	
	# Mettre à jour les coordonnées du centre
	var global_c = ent.position + ent.circle_center
	spin_circle_x.value = global_c.x
	spin_circle_y.value = global_c.y
	
	# Mettre à jour le rayon
	spin_circle_radius.value = ent.circle_radius
	
	# Mettre à jour les propriétés calculées
	var radius = ent.circle_radius
	spin_diameter.value = radius * 2
	spin_circumference.value = 2 * PI * radius
	spin_circle_area.value = PI * radius * radius

func _hide_circle_section():
	if circle_section:
		circle_section.visible = false

func _show_simple_line_geometry(ent):
	lbl_x.text = "Départ X"
	lbl_y.text = "Départ Y"
	
	if ent.points.size() > 0:
		var start_global = ent.to_global(ent.points[0])
		spin_x.value = start_global.x
		spin_y.value = start_global.y
	
	lbl_x.visible = true; spin_x.visible = true
	lbl_y.visible = true; spin_y.visible = true

# --- FONCTIONS DE LOGIQUE POLYLIGNE ---

func _on_vertex_selected(index: int):
	if current_entity and current_entity is Line2D:
		_update_vertex_display(current_entity, index)

func _on_vertex_coord_changed(value):
	if is_updating_ui or not current_entity: return
	
	var vertex_index = opt_vertex_selector.selected
	if vertex_index < 0 or vertex_index >= current_entity.points.size(): return
	
	is_updating_ui = true
	
	# Convertir les coordonnées globales en locales
	var new_global_pos = Vector2(spin_vertex_x.value, spin_vertex_y.value)
	var new_local_pos = current_entity.to_local(new_global_pos)
	
	# Modifier le point via le SelectionManager pour supporter l'undo/redo
	if selection_manager and selection_manager.has_method("modify_polyline_vertex"):
		selection_manager.modify_polyline_vertex(current_entity, vertex_index, new_local_pos)
	
	is_updating_ui = false

func _on_closed_toggled(pressed: bool):
	if is_updating_ui or not current_entity: return
	
	if selection_manager and selection_manager.has_method("toggle_polyline_closed"):
		selection_manager.toggle_polyline_closed(current_entity, pressed)

func _update_vertex_display(ent: Line2D, vertex_index: int):
	if vertex_index < 0 or vertex_index >= ent.points.size(): return
	
	var local_pos = ent.points[vertex_index]
	var global_pos = ent.to_global(local_pos)
	
	is_updating_ui = true
	spin_vertex_x.value = global_pos.x
	spin_vertex_y.value = global_pos.y
	is_updating_ui = false

func _is_polyline_closed(ent: Line2D) -> bool:
	if ent.points.size() < 3: return false
	var first = ent.points[0]
	var last = ent.points[ent.points.size() - 1]
	return first.is_equal_approx(last)

func _calculate_polyline_length(ent: Line2D) -> float:
	if ent.points.size() < 2: return 0.0
	
	var total_length = 0.0
	for i in range(1, ent.points.size()):
		var p1 = ent.points[i - 1]
		var p2 = ent.points[i]
		total_length += p1.distance_to(p2)
	
	return total_length

func _calculate_polyline_area(ent: Line2D) -> float:
	if ent.points.size() < 3: return 0.0
	
	# Utiliser la formule de l'aire d'un polygone (Shoelace formula)
	var area = 0.0
	var n = ent.points.size()
	
	for i in range(n):
		var j = (i + 1) % n
		area += ent.points[i].x * ent.points[j].y
		area -= ent.points[j].x * ent.points[i].y
	
	return abs(area) / 2.0

# --- FONCTIONS POUR LA SECTION CERCLE ---

func _create_circle_section():
	if circle_section:
		return # Déjà créée
	
	circle_section = VBoxContainer.new()
	circle_section.name = "CircleSection"
	
	# Séparateur
	var separator = HSeparator.new()
	circle_section.add_child(separator)
	
	# Titre
	var title = Label.new()
	title.text = "CERCLE"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.CYAN)
	circle_section.add_child(title)
	
	# Coordonnées du centre (Y en dessous de X)
	var center_x_container = HBoxContainer.new()
	var lbl_center_x = Label.new()
	lbl_center_x.text = "Centre X :"
	lbl_center_x.custom_minimum_size.x = 80
	spin_circle_x = SpinBox.new()
	spin_circle_x.custom_minimum_size.x = 150
	spin_circle_x.step = 0.1
	spin_circle_x.allow_greater = true
	spin_circle_x.allow_lesser = true
	center_x_container.add_child(lbl_center_x)
	center_x_container.add_child(spin_circle_x)
	circle_section.add_child(center_x_container)
	
	var center_y_container = HBoxContainer.new()
	var lbl_center_y = Label.new()
	lbl_center_y.text = "Centre Y :"
	lbl_center_y.custom_minimum_size.x = 80
	spin_circle_y = SpinBox.new()
	spin_circle_y.custom_minimum_size.x = 150
	spin_circle_y.step = 0.1
	spin_circle_y.allow_greater = true
	spin_circle_y.allow_lesser = true
	center_y_container.add_child(lbl_center_y)
	center_y_container.add_child(spin_circle_y)
	circle_section.add_child(center_y_container)
	
	# Rayon
	var radius_container = HBoxContainer.new()
	var lbl_radius = Label.new()
	lbl_radius.text = "Rayon :"
	lbl_radius.custom_minimum_size.x = 80
	spin_circle_radius = SpinBox.new()
	spin_circle_radius.custom_minimum_size.x = 100
	spin_circle_radius.step = 0.1
	spin_circle_radius.allow_greater = true
	spin_circle_radius.allow_lesser = true
	radius_container.add_child(lbl_radius)
	radius_container.add_child(spin_circle_radius)
	circle_section.add_child(radius_container)
	
	# Diamètre
	var diameter_container = HBoxContainer.new()
	var lbl_diameter_title = Label.new()
	lbl_diameter_title.text = "Diamètre :"
	lbl_diameter_title.custom_minimum_size.x = 80
	spin_diameter = SpinBox.new()
	spin_diameter.custom_minimum_size.x = 150
	spin_diameter.step = 0.01
	spin_diameter.allow_greater = true
	spin_diameter.allow_lesser = true
	spin_diameter.editable = true  # Maintenant modifiable
	diameter_container.add_child(lbl_diameter_title)
	diameter_container.add_child(spin_diameter)
	circle_section.add_child(diameter_container)
	
	# Circonférence
	var circumference_container = HBoxContainer.new()
	var lbl_circumference_title = Label.new()
	lbl_circumference_title.text = "Circonférence :"
	lbl_circumference_title.custom_minimum_size.x = 80
	spin_circumference = SpinBox.new()
	spin_circumference.custom_minimum_size.x = 150
	spin_circumference.step = 0.01
	spin_circumference.allow_greater = true
	spin_circumference.allow_lesser = true
	spin_circumference.editable = false  # Non modifiable
	circumference_container.add_child(lbl_circumference_title)
	circumference_container.add_child(spin_circumference)
	circle_section.add_child(circumference_container)
	
	# Aire
	var area_container = HBoxContainer.new()
	var lbl_area_title = Label.new()
	lbl_area_title.text = "Aire :"
	lbl_area_title.custom_minimum_size.x = 80
	spin_circle_area = SpinBox.new()
	spin_circle_area.custom_minimum_size.x = 150
	spin_circle_area.step = 0.01
	spin_circle_area.allow_greater = true
	spin_circle_area.allow_lesser = true
	spin_circle_area.editable = false  # Non modifiable
	area_container.add_child(lbl_area_title)
	area_container.add_child(spin_circle_area)
	circle_section.add_child(area_container)
	
	# Connecter les signaux
	spin_circle_x.value_changed.connect(_on_circle_coord_changed)
	spin_circle_y.value_changed.connect(_on_circle_coord_changed)
	spin_circle_radius.value_changed.connect(_on_circle_radius_changed)
	spin_diameter.value_changed.connect(_on_circle_diameter_changed)
	
	# Ajouter à la section géométrie
	container_geo.add_child(circle_section)

# --- FONCTIONS DE LOGIQUE CERCLE ---

func _on_circle_coord_changed(value):
	if is_updating_ui or not current_entity: return
	
	if not ("is_circle" in current_entity and current_entity.is_circle): return
	
	is_updating_ui = true
	
	# Convertir les coordonnées globales en locales pour le centre
	var new_global_pos = Vector2(spin_circle_x.value, spin_circle_y.value)
	var new_local_center = new_global_pos - current_entity.position
	
	# Modifier le centre via le SelectionManager pour supporter l'undo/redo
	if selection_manager and selection_manager.has_method("modify_circle_center"):
		selection_manager.modify_circle_center(current_entity, new_local_center)
	
	is_updating_ui = false

func _on_circle_radius_changed(value):
	if is_updating_ui or not current_entity: return
	
	if not ("is_circle" in current_entity and current_entity.is_circle): return
	
	# Modifier le rayon via le SelectionManager pour supporter l'undo/redo
	if selection_manager and selection_manager.has_method("modify_circle_radius"):
		selection_manager.modify_circle_radius(current_entity, value)
	
	# Mettre à jour les propriétés calculées
	is_updating_ui = true
	if spin_diameter:
		spin_diameter.value = value * 2
	if spin_circumference and spin_circle_area:
		spin_circumference.value = 2 * PI * value
		spin_circle_area.value = PI * value * value
	is_updating_ui = false

func _on_circle_diameter_changed(value):
	if is_updating_ui or not current_entity: return
	
	if not ("is_circle" in current_entity and current_entity.is_circle): return
	
	# Calculer le rayon correspondant
	var radius = value / 2.0
	
	# Modifier le rayon via le SelectionManager pour supporter l'undo/redo
	if selection_manager and selection_manager.has_method("modify_circle_radius"):
		selection_manager.modify_circle_radius(current_entity, radius)
	
	# Mettre à jour les autres propriétés
	is_updating_ui = true
	spin_circle_radius.value = radius
	if spin_circumference and spin_circle_area:
		spin_circumference.value = 2 * PI * radius
		spin_circle_area.value = PI * radius * radius
	is_updating_ui = false
