extends Window

# --- NOEUDS RELIÉS ---
@export var tree : Tree
@export var input_name : LineEdit
@export var color_picker : ColorPickerButton
@export var btn_add : Button
@export var btn_delete : Button
@export var btn_close : Button

# --- LOGIQUE ---
var layer_manager : LayerManager
var color_popup : PopupPanel
var picker_control : ColorPicker

# MENUS DÉROULANTS (Nouveaux)
var popup_linetype : PopupMenu
var popup_lineweight : PopupMenu

# ETAT
var picking_layer_index : int = -1 # Index du calque en cours de modif
var current_editing_layer_name = "" # Pour savoir quel calque on modifie via le popup

signal cursor_entered_ui
signal cursor_exited_ui
var is_hovering_window = false

func _ready():
	size = Vector2(700, 400) 
	
	if tree:
		tree.columns = 6 
		tree.set_column_title(0, "Vis.")
		tree.set_column_title(1, "Nom")
		tree.set_column_title(2, "Coul.")
		tree.set_column_title(3, "Ver.")
		tree.set_column_title(4, "Type de Ligne")
		tree.set_column_title(5, "Épaisseur")
		tree.set_column_titles_visible(true)
		
		tree.set_column_expand(0, false); tree.set_column_custom_minimum_width(0, 40)
		tree.set_column_expand(2, false); tree.set_column_custom_minimum_width(2, 60)
		tree.set_column_expand(3, false); tree.set_column_custom_minimum_width(3, 40)
		tree.set_column_custom_minimum_width(4, 150) # Plus large
		tree.set_column_custom_minimum_width(5, 100) # Plus large
		
		tree.item_activated.connect(_on_item_activated)
		tree.button_clicked.connect(_on_item_button_clicked)

	# --- 1. POPUP COULEUR ---
	color_popup = PopupPanel.new()
	picker_control = ColorPicker.new()
	picker_control.deferred_mode = true
	picker_control.color_changed.connect(_on_picker_color_changed)
	color_popup.add_child(picker_control)
	add_child(color_popup)
	
	# --- 2. POPUP TYPE DE LIGNE (NOUVEAU) ---
	popup_linetype = PopupMenu.new()
	popup_linetype.id_pressed.connect(_on_linetype_selected)
	# CORRECTION TAILLE : Largeur 1000, Hauteur 300
	popup_linetype.max_size = Vector2i(1000, 300) 
	add_child(popup_linetype)
	
	# --- 3. POPUP ÉPAISSEUR (NOUVEAU) ---
	popup_lineweight = PopupMenu.new()
	popup_lineweight.id_pressed.connect(_on_lineweight_selected)
	# CORRECTION TAILLE
	popup_lineweight.max_size = Vector2i(1000, 300) 
	add_child(popup_lineweight)
	
	# Remplissage statique des épaisseurs
	var weights = [0.00, 0.05, 0.09, 0.13, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.53, 0.60, 0.70, 0.80, 0.90, 1.00, 1.06, 1.20, 1.40, 1.58, 2.00, 2.11]
	for i in range(weights.size()):
		var w = weights[i]
		popup_lineweight.add_item("%.2f mm" % w, i)
		popup_lineweight.set_item_metadata(i, w)

	# BOUTONS
	if btn_close: btn_close.pressed.connect(hide)
	if btn_add: btn_add.pressed.connect(_on_add_pressed)
	if btn_delete: btn_delete.pressed.connect(_on_delete_pressed)
	close_requested.connect(hide)

# --- DETECTION SOURIS ---
func _process(_delta):
	if not visible: return
	var local_mouse = get_mouse_position()
	var margin = 5.0
	var is_in = (local_mouse.x >= -margin and local_mouse.x <= size.x + margin and local_mouse.y >= -40 and local_mouse.y <= size.y + margin)
	
	if is_in and not is_hovering_window:
		is_hovering_window = true
		emit_signal("cursor_entered_ui")
	elif not is_in and is_hovering_window:
		is_hovering_window = false
		emit_signal("cursor_exited_ui")

func setup(manager: LayerManager):
	layer_manager = manager
	if layer_manager.layers_changed.is_connected(refresh_list): layer_manager.layers_changed.disconnect(refresh_list)
	if layer_manager.active_layer_changed.is_connected(refresh_list): layer_manager.active_layer_changed.disconnect(refresh_list)
	layer_manager.layers_changed.connect(refresh_list)
	layer_manager.active_layer_changed.connect(refresh_list)
	refresh_list()

func refresh_list(_ignore = null):
	if not tree or not layer_manager: return
	tree.clear()
	var root = tree.create_item()
	
	for i in range(layer_manager.layers.size()):
		var layer = layer_manager.layers[i]
		var l_type = layer.get("linetype", "CONTINUOUS")
		var l_weight = layer.get("lineweight", 0.25)
		var l_name = layer.name
		
		var item = tree.create_item(root)
		item.set_metadata(0, i) 
		
		# VISIBILITÉ
		var tex_vis = _get_icon("res://Ressources/oeil_ouvert.png") if layer.visible else _get_icon("res://Ressources/oeil_fermé.png")
		if tex_vis == null: tex_vis = _create_color_texture(Color.GREEN if layer.visible else Color.RED)
		item.add_button(0, tex_vis, -1, false, "Visibilité")
		item.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		
		# NOM
		item.set_text(1, l_name)
		if i == layer_manager.active_layer_index: item.set_custom_color(1, Color.GREEN)
			
		# COULEUR
		var tex_col = _create_color_texture(layer.color)
		item.add_button(2, tex_col, -1, false, "Couleur")
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
		
		# LOCK
		var tex_lock = _create_color_texture(Color.ORANGE) if layer.locked else _create_color_texture(Color.TRANSPARENT)
		item.add_button(3, tex_lock, -1, false, "Lock")
		item.set_text(3, "L" if layer.locked else "") 
		item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)
		
		# TYPE (Avec icone Edit)
		item.set_text(4, l_type)
		item.add_button(4, get_theme_icon("GuiOptionArrow", "EditorIcons"), 0, false, "Choisir Type")

		# EPAISSEUR (Avec icone Edit)
		item.set_text(5, "%.2f mm" % l_weight)
		item.add_button(5, get_theme_icon("GuiOptionArrow", "EditorIcons"), 1, false, "Choisir Epaisseur")

# --- INTERACTION ---

func _on_item_button_clicked(item, column, _id, _mouse_button_index):
	var index = item.get_metadata(0)
	var layer_name = item.get_text(1)
	
	if column == 0: layer_manager.toggle_visibility(index)
	elif column == 3: layer_manager.toggle_lock(index)
	
	elif column == 2: # Couleur
		picking_layer_index = index
		picker_control.color = layer_manager.layers[index].color
		_popup_at_mouse(color_popup)
	
	elif column == 4: # Type -> Ouvre le Popup
		current_editing_layer_name = layer_name
		_show_linetype_menu()
	
	elif column == 5: # Epaisseur -> Ouvre le Popup
		current_editing_layer_name = layer_name
		_show_lineweight_menu()

# --- LOGIQUE POPUP ---

func _popup_at_mouse(control: Window):
	var mouse_pos = Vector2i(get_viewport().get_mouse_position())
	control.position = position + mouse_pos 
	control.popup()

func _show_linetype_menu():
	popup_linetype.clear()
	# On récupère les types depuis le LinetypeManager s'il existe
	if LinetypeManager:
		for type_name in LinetypeManager.linetype_names:
			popup_linetype.add_item(type_name)
	else:
		popup_linetype.add_item("CONTINUOUS")
		popup_linetype.add_item("CACHE")
		
	_popup_at_mouse(popup_linetype)

func _show_lineweight_menu():
	_popup_at_mouse(popup_lineweight)

# --- CALLBACKS SELECTION ---

func _on_linetype_selected(id):
	if current_editing_layer_name == "": return
	var index = popup_linetype.get_item_index(id)
	var type_name = popup_linetype.get_item_text(index)
	layer_manager.set_layer_property(current_editing_layer_name, "linetype", type_name)

func _on_lineweight_selected(id):
	if current_editing_layer_name == "": return
	var index = popup_lineweight.get_item_index(id)
	var weight_val = popup_lineweight.get_item_metadata(index)
	layer_manager.set_layer_property(current_editing_layer_name, "lineweight", weight_val)

func _on_picker_color_changed(new_col):
	if picking_layer_index >= 0 and picking_layer_index < layer_manager.layers.size():
		layer_manager.layers[picking_layer_index].color = new_col
		layer_manager.emit_signal("layers_changed")

# --- UTILS ---
func _create_color_texture(col: Color) -> ImageTexture:
	var img = Image.create(24, 16, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)

func _get_icon(path: String):
	if ResourceLoader.exists(path): return load(path)
	return null

func _on_item_activated():
	var item = tree.get_selected()
	if item: layer_manager.set_active_layer(item.get_metadata(0))

func _on_add_pressed():
	var name = input_name.text.strip_edges()
	if name == "": return
	layer_manager.create_layer(name, color_picker.color)
	input_name.text = "" 

func _on_delete_pressed():
	var item = tree.get_selected()
	if item: layer_manager.delete_layer(item.get_metadata(0))
