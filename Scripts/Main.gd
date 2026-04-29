extends Node2D

@export var world : Node2D
@export var gui : CanvasLayer
@export var export_dialog : FileDialog
@export var import_dialog : FileDialog
@export var dwg_export_dialog : FileDialog
@export var dwg_import_dialog : FileDialog
@export var btn_import : Button
@export var console : PanelContainer
@export var top_ribbon : Panel
@export var bottom_bar : PanelContainer
@export var btn_move : Button
@export var btn_copy : Button
@export var btn_mirror : Button
@export var btn_rotate : Button
@export var btn_scale : Button
@export var btn_offset : Button
@export var btn_trim : Button
@export var btn_linetype : OptionButton
@export var btn_lineweight : OptionButton
@export var btn_arc : Button
@export var btn_support_simple : Button
@export var btn_support_articulation : Button
@export var btn_support_encastrement : Button
@export var btn_force_ponctuelle : Button
@export var btn_force_distributed : Button
@export var btn_export_dwg : Button
@export var btn_import_dwg : Button
@export var properties_panel : PanelContainer
@export var window_properties : Window

@export var fps_label : Label
@export var btn_manage_layers : Button

@export var cad_cursor : Node2D

@export var snap_manager : HBoxContainer 
@export var selection_manager : Node2D
@export var drawing_manager : Node2D
@export var layer_manager : LayerManager
@onready var layer_dialog = $GUI/LayerDialog
@onready var layer_menu = $GUI/Layout/TopRibbon/VBoxContainer/TabContainer/Dessin2D/Calques/CalquesCol2/HBoxContainer/BtnLayerQuick
@onready var cursor_manager = $CursorManager

# Espace CAO Objet
@onready var camera = $World/Camera2D

# Espace CAO Présentation
@onready var tab_bar = $GUI/Layout/BottomBar/HBoxContainer/SpacerLeft/VBoxContainer/WorkspaceTabBar
@onready var workspace_paper = $WorkspacePaper
@onready var layout_camera = $WorkspacePaper/LayoutCamera
@onready var presentation_viewport = $WorkspacePaper/CADViewportPanel/SubViewportContainer/SubViewport
@onready var paper_sheet = $WorkspacePaper/PaperSheet


var ui_hover_counter = 0
var undo_redo = UndoRedo.new()

var rdm_controller: RDMController

# --- VARIABLES DESSIN DE FENETRE PSPACE ---
var is_drawing_viewport := false
var viewport_start_pos := Vector2.ZERO
var viewport_preview: ReferenceRect = null
const CADViewportEntityClass = preload("res://Scripts/CADViewportEntity.gd")
var has_framed_paper_once = false

func _set_visibility_layer_recursive(node: Node, layer: int):
	if node is CanvasItem:
		node.visibility_layer = layer
	for child in node.get_children():
		# On ne veut pas affecter l'intérieur de CADLayoutViewport car 
		# le panneau est le contenant qui est en Layer 3, mais le SubViewport à l'intérieur
		# vit dans son propre rendering space (et si on le change, on casse sa vue)
		if child is SubViewportContainer or child is SubViewport:
			continue
		_set_visibility_layer_recursive(child, layer)



func _ready():
	# Initialiser le RDMController
	rdm_controller = RDMController.new()
	rdm_controller.main_node = self
	add_child(rdm_controller)
	
	# Magie AutoCAD (Partage du monde physique 2D)
	if presentation_viewport and world:
		presentation_viewport.world_2d = world.get_viewport().world_2d
		
	# Espace Papier: Création d'un container métier pour les entités (Viewports, cartouches)
	if workspace_paper and not workspace_paper.has_node("Entities"):
		var ws_entities = Node2D.new()
		ws_entities.name = "Entities"
		workspace_paper.add_child(ws_entities)
		
	# Isolation Visuelle du WorkspacePaper (Layer 3 binaire v=4)
	if workspace_paper:
		_set_visibility_layer_recursive(workspace_paper, 4)
	
	if tab_bar:
		tab_bar.tab_changed.connect(_on_tab_bar_tab_changed)
		
	# État initial Espace Objet
	if selection_manager:
		selection_manager.active_entities_container = world.get_node("Entities")
	if workspace_paper:
		workspace_paper.visible = false
	if camera:
		camera.make_current()
	
	# Connexions existantes
	camera.zoom_changed.connect(world.update_lines_width)
	console.command_entered.connect(_on_console_command)
	GlobalLogger.message_sent.connect(console.log_message)
	
	if btn_move:
		btn_move.pressed.connect(_on_move_pressed)
	if btn_copy:
		btn_copy.pressed.connect(_on_copy_pressed)
	if btn_mirror:
		btn_mirror.pressed.connect(_on_mirror_pressed)
	if btn_rotate:
		btn_rotate.pressed.connect(_on_rotate_pressed)
	if btn_scale:
		btn_scale.pressed.connect(_on_scale_pressed)
	if btn_offset:
		btn_offset.pressed.connect(_on_offset_pressed)
	if btn_trim:
		btn_trim.pressed.connect(_on_trim_pressed)
	if properties_panel:
		properties_panel.setup(selection_manager, layer_manager)
	if btn_arc:
		btn_arc.pressed.connect(func(): 
			drawing_manager.set_tool(drawing_manager.Tool.ARC)
			GlobalLogger.info("Outil ARC activé")
		)
	
	# Connexions des boutons RDM
	if btn_support_simple:
		btn_support_simple.pressed.connect(func(): 
			rdm_controller.start_placement("support", "simple")
		)
	else:
		print("WARNING: btn_support_simple non trouvé")
		
	if btn_support_articulation:
		btn_support_articulation.pressed.connect(func(): 
			rdm_controller.start_placement("support", "articulation")
		)
	else:
		print("WARNING: btn_support_articulation non trouvé")
		
	if btn_support_encastrement:
		btn_support_encastrement.pressed.connect(func(): 
			rdm_controller.start_placement("support", "encastrement")
		)
	else:
		print("WARNING: btn_support_encastrement non trouvé")
		
	if btn_force_ponctuelle:
		btn_force_ponctuelle.pressed.connect(func(): 
			rdm_controller.start_placement("force", "", Vector2(0, -1000))
		)
	else:
		print("WARNING: btn_force_ponctuelle non trouvé")
	
	# Ajouter un bouton pour force répartie
	if btn_force_distributed:
		btn_force_distributed.pressed.connect(func():
			rdm_controller.start_placement("distributed_start")
		)
	else:
		print("WARNING: btn_force_distributed non trouvé")

	# Connexions des boutons DWG
	if btn_export_dwg:
		btn_export_dwg.pressed.connect(_on_export_dwg_pressed)
	else:
		print("WARNING: btn_export_dwg non trouvé")
		
	if btn_import_dwg:
		btn_import_dwg.pressed.connect(_on_import_dwg_pressed)
	else:
		print("WARNING: btn_import_dwg non trouvé")
	
	
	# 1. On récupère l'écran sur lequel se trouve actuellement la fenêtre de GodotCAD
	var ecran_actuel = DisplayServer.window_get_current_screen()
	
	# 2. On demande à Windows quel est le taux de rafraîchissement de cet écran
	var taux_rafraichissement = DisplayServer.screen_get_refresh_rate(ecran_actuel)
	
	# 3. Sécurité : Parfois Windows renvoie 0.0 si c'est un écran virtuel ou mal détecté
	if taux_rafraichissement > 0.0:
		# On bride Godot exactement à la fréquence de l'écran
		Engine.max_fps = int(taux_rafraichissement)
		print("Écran détecté à ", int(taux_rafraichissement), "Hz. FPS bridés.")
	else:
		# Valeur de secours par défaut
		Engine.max_fps = 60
		print("Taux non détecté. FPS bridés à 60 par défaut.")
		
	# 4. Le combo ultime pour un logiciel CAO : 
	# Godot s'endort si on ne touche pas à la souris !
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 2000

	
	
	_setup_properties_ui()
	
	

	# --- CONNEXION INTELLIGENTE SOURIS ---
	var ui_containers_to_check = [
		$GUI/Layout/TopRibbon,
		$GUI/Layout/BottomBar,
		
	]
	
	# On passe la référence de undo_redo au SelectionManager
	if selection_manager:
		selection_manager.undo_redo = undo_redo # <--- IMPORTANT
		if not selection_manager.selection_changed.is_connected(_on_selection_changed):
			selection_manager.selection_changed.connect(_on_selection_changed)
	
	for container in ui_containers_to_check:
		if container:
			_connect_ui_signals_recursive(container)
	
	# 2. GESTION SPÉCIFIQUE : FENÊTRE PROPRIÉTÉS
	# On connecte le cadre de la fenêtre (Titre, croix, bords)
	if window_properties:
		if not window_properties.mouse_entered.is_connected(_on_ui_mouse_entered):
			window_properties.mouse_entered.connect(_on_ui_mouse_entered)
		if not window_properties.mouse_exited.is_connected(_on_ui_mouse_exited):
			window_properties.mouse_exited.connect(_on_ui_mouse_exited)

	# 3. GESTION SPÉCIFIQUE : CONTENU DU PANNEAU
	# On connecte l'intérieur (Champs, sliders, boutons)
	if properties_panel:
		_connect_ui_signals_recursive(properties_panel)

	_connect_popup_signals(export_dialog)
	_connect_popup_signals(import_dialog)

	# État initial
	_update_cursor_mode()
	
	# Init Calques
	if world and world.has_node("Entities"):
		layer_manager.entities_root = world.get_node("Entities")
	layer_dialog.setup(layer_manager)
	layer_menu.setup(layer_manager, selection_manager)
	
	if not layer_dialog or not layer_manager:
		GlobalLogger.error("ERREUR MAIN : Manque LayerDialog/Manager")
		return
	
	btn_manage_layers.pressed.connect(func(): layer_dialog.popup_centered())
	
	layer_dialog.cursor_entered_ui.connect(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if cad_cursor: cad_cursor.visible = false
	)
	
	layer_dialog.cursor_exited_ui.connect(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN) 
		if cad_cursor: cad_cursor.visible = true
	)

	
	if not layer_dialog or not layer_manager:
		GlobalLogger.error("ERREUR MAIN : Manque LayerDialog/Manager")
		return
	
	# Connexion du bouton "Gérer les calques"
	btn_manage_layers.pressed.connect(func(): layer_dialog.popup_centered())
	
	# --- GESTION CURSEUR (NOUVEAU) ---
	# Quand la souris entre sur la fenêtre des calques
	layer_dialog.cursor_entered_ui.connect(func():
		# 1. On montre la souris système
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# 2. On cache le curseur CAD personnalisé
		if cad_cursor: cad_cursor.visible = false
	)
	
	# Quand la souris sort de la fenêtre des calques
	layer_dialog.cursor_exited_ui.connect(func():
		# 1. On cache la souris système (si c'est votre comportement habituel)
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN) 
		# 2. On réaffiche le curseur CAD
		if cad_cursor: cad_cursor.visible = true
	)
	
	GlobalLogger.success("GodotCAD Initialisé. Prêt.")
	

	# --- FOCUS DÉMARRAGE ---
	# --- CORRECTION DÉMARRAGE (Version Douce) ---
	# On demande juste UNE SEULE FOIS au moteur de regarder la fenêtre principale.
	# On ne force pas brutalement le focus système.
	get_tree().create_timer(0.1).timeout.connect(func():
		get_viewport().gui_release_focus()
	)


func _on_tab_bar_tab_changed(tab: int) -> void:
	match tab:
		0: # Objet
			if workspace_paper:
				workspace_paper.visible = false
			if camera:
				camera.make_current()
			if selection_manager:
				selection_manager.active_entities_container = world.get_node("Entities")
				selection_manager.camera = camera
		1: # Présentation
			if workspace_paper:
				workspace_paper.visible = true
			if layout_camera:
				layout_camera.make_current()
			if selection_manager:
				selection_manager.active_entities_container = workspace_paper.get_node("Entities")
				selection_manager.camera = layout_camera
				
				# Cadrage parfait automatique de la feuille (Une seule fois !)
				if paper_sheet and not has_framed_paper_once:
					has_framed_paper_once = true
					var pt_size = paper_sheet.size
					var pt_pos = paper_sheet.position
					var center = pt_pos + pt_size / 2.0
					layout_camera.global_position = center
					
					var screen_size = get_viewport().get_visible_rect().size
					var scale_x = screen_size.x / (pt_size.x * 1.1)
					var scale_y = screen_size.y / (pt_size.y * 1.1)
					var min_scale = min(scale_x, scale_y)
					layout_camera.zoom = Vector2(min_scale, min_scale)
					if layout_camera.has_user_signal("zoom_changed") or layout_camera.has_signal("zoom_changed"):
						layout_camera.emit_signal("zoom_changed", min_scale)

func _setup_properties_ui():
	# --- 1. BOUTON TYPE DE LIGNE ---
	if btn_linetype:
		btn_linetype.clear()
		
		# Types standards
		btn_linetype.add_item("DuCalque")    # ID 0
		btn_linetype.add_item("DuBloc")      # ID 1
		btn_linetype.add_item("CONTINUOUS")  # ID 2
		btn_linetype.add_separator()
		
		# Ajout dynamique
		if LinetypeManager:
			for type_name in LinetypeManager.linetype_names:
				if type_name != "CONTINUOUS":
					btn_linetype.add_item(type_name)
		
		btn_linetype.add_separator()
		btn_linetype.add_item("Autre...") 
		
		# --- CORRECTION UX : LIMITE HAUTEUR AVEC SCROLL ---
		var popup = btn_linetype.get_popup()
		# On met une largeur large (1000) pour ne pas couper le texte
		# On met une hauteur max (400) pour forcer le scroll
		popup.max_size = Vector2i(1000, 400)
		# --------------------------------------------------

		if btn_linetype.item_selected.is_connected(_on_linetype_selected):
			btn_linetype.item_selected.disconnect(_on_linetype_selected)
		btn_linetype.item_selected.connect(_on_linetype_selected)

	# --- 2. BOUTON ÉPAISSEUR ---
	if btn_lineweight:
		btn_lineweight.clear()
		btn_lineweight.add_item("DuCalque") 
		btn_lineweight.add_item("DuBloc")   
		btn_lineweight.add_separator()
		btn_lineweight.add_item("Défaut")   
		
		var weights = [0.00, 0.05, 0.09, 0.13, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.53, 0.60, 0.70, 0.80, 0.90, 1.00, 1.06, 1.20, 1.40, 1.58, 2.00, 2.11]
		
		for w in weights:
			var text = "%.2f mm" % w
			btn_lineweight.add_item(text)
		
		# --- CORRECTION UX ---
		var popup = btn_lineweight.get_popup()
		popup.max_size = Vector2i(1000, 400)
		# ---------------------
			
		if btn_lineweight.item_selected.is_connected(_on_lineweight_selected):
			btn_lineweight.item_selected.disconnect(_on_lineweight_selected)
		btn_lineweight.item_selected.connect(_on_lineweight_selected)
		
		
		# --- CONNEXION DU SIGNAL RELAIS ---
		if properties_panel:
			# On connecte le signal PERSONNALISÉ créé à l'étape 1
			if not properties_panel.is_connected("property_color_changed", _on_property_color_changed):
				properties_panel.connect("property_color_changed", _on_property_color_changed)
			if not properties_panel.is_connected("property_layer_changed", _on_property_layer_changed):
				properties_panel.connect("property_layer_changed", _on_property_layer_changed)
		
		# Connexion du ruban vers le PropertiesPanel
		if layer_menu:
			if not layer_menu.is_connected("layer_changed_via_ribbon", _on_layer_changed_via_ribbon):
				layer_menu.connect("layer_changed_via_ribbon", _on_layer_changed_via_ribbon)


# --- FONCTION RÉCURSIVE POUR DETECTER LES BOUTONS/PANELS ---
func _connect_ui_signals_recursive(node: Node):
	# Si c'est un élément d'interface (Control)
	if node is Control:
		# On connecte les signaux de survol
		if not node.mouse_entered.is_connected(_on_ui_mouse_entered):
			node.mouse_entered.connect(_on_ui_mouse_entered)
		if not node.mouse_exited.is_connected(_on_ui_mouse_exited):
			node.mouse_exited.connect(_on_ui_mouse_exited)
			
		# ASTUCE : Pour être sûr que les zones vides entre les boutons soient détectées
		# comme de l'interface (ex: le fond gris du TopRibbon), on s'assure
		# qu'ils ne sont pas en mode IGNORE.
		if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			# Attention : ne pas changer le filtre des Labels ou autres items purement visuels
			# si cela gêne, mais pour un PanelContainer, PASS ou STOP est requis.
			node.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# On descend dans les enfants (Boutons, Textes, etc.)
	for child in node.get_children():
		_connect_ui_signals_recursive(child)

func _connect_popup_signals(node: Window):
	if node:
		if not node.mouse_entered.is_connected(_on_ui_mouse_entered):
			node.mouse_entered.connect(_on_ui_mouse_entered)
		if not node.mouse_exited.is_connected(_on_ui_mouse_exited):
			node.mouse_exited.connect(_on_ui_mouse_exited)

# --- LOGIQUE COMPTEUR DE SURVOL ---

func _on_ui_mouse_entered():
	ui_hover_counter += 1
	_update_cursor_mode()

func _on_ui_mouse_exited():
	ui_hover_counter -= 1
	if ui_hover_counter < 0: ui_hover_counter = 0
	_update_cursor_mode()
	
func _on_move_pressed():
	if selection_manager:
		selection_manager.start_move_command()

func _update_cursor_mode():
	# [cite_start]On récupère le curseur CAD via le selection_manager [cite: 47]
	var cad_cursor = null
	if selection_manager and "cad_cursor" in selection_manager:
		cad_cursor = selection_manager.cad_cursor
	
	if ui_hover_counter > 0:
		# --- MODE INTERFACE (Souris Normale) ---
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if cad_cursor: cad_cursor.visible = false
	else:
		# --- MODE DESSIN (Curseur CAD) ---
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if cad_cursor: 
			cad_cursor.visible = true
			# IMPORTANT : On force la position du curseur sur la souris ici
			# au cas où il aurait disparu ou décalé
			cad_cursor.global_position = get_global_mouse_position()


func _on_polyligne_pressed():
	world.set_tool(world.Tool.POLYLINE)

func _on_circle_pressed():
	world.set_tool(world.Tool.CIRCLE)
	console.log_message("Outil CERCLE activé.", Color.GREEN)

func _on_arc_pressed():
	world.set_tool(world.Tool.ARC)
	console.log_message("Outil ARC activé.", Color.GREEN)

func _on_export_pressed():
	# Ouvre la fenêtre de SAUVEGARDE
	export_dialog.popup_centered()

func _on_import_pressed():
	# Ouvre la fenêtre d'OUVERTURE
	import_dialog.popup_centered()

func _on_export_dwg_pressed():
	# Ouvre la fenêtre de SAUVEGARDE DWG
	dwg_export_dialog.popup_centered()

func _on_import_dwg_pressed():
	# Ouvre la fenêtre d'OUVERTURE DWG
	dwg_import_dialog.popup_centered()

# Signal du ExportDialog
func _on_export_dialog_file_selected(path):
	# On appelle le service en lui passant le chemin ET le monde (pour qu'il trouve les entités)
	DXFService.save_dxf(path, self)  # Utilise le nouveau format DXF 2000+ par défaut
	# Pour forcer l'ancien format R12: DXFService.save_dxf(path, self, false)
	# Le code original [cite: 31] est maintenant délégué
	
	# Gestion du curseur (inchangée)
	ui_hover_counter = 0 
	_update_cursor_mode()

# Signal du ImportDialog
func import_dxf(filepath: String):
	# On réinitialise l'état du curseur
	ui_hover_counter = 0
	_update_cursor_mode()
	
	# On délègue toute la logique complexe au service
	# On passe 'world' pour qu'il puisse faire 'world.spawn_circle' etc.
	DXFService.import_dxf(filepath, self)

# Signal du DWG Export Dialog
func _on_dwg_export_dialog_file_selected(path: String) -> void:
	DWGService.export_to_dwg(path, self)

# Signal du DWG Import Dialog  
func _on_dwg_import_dialog_file_selected(path: String) -> void:
	DWGService.import_from_dwg(path, self)


# --- LOGIQUE DE COMMANDE ---
func _on_console_command(text: String):
	# On nettoie et on met en majuscules
	var cmd = text.strip_edges().to_upper()
	
	get_viewport().gui_release_focus()
	
	# --- 1. GESTION DES VALEURS NUMÉRIQUES (ANGLES / DISTANCES) ---
	# On accepte "45", "45.5", "-90", etc.
	if cmd.is_valid_float():
		var value = cmd.to_float()
		if selection_manager and selection_manager.has_method("submit_input_value"):
			selection_manager.submit_input_value(value)
			return 
	# -------------------------------------------------------------
	
	match cmd:
		"POLYLIGNE", "PL", "LINE":
			_on_polyligne_pressed()
			console.log_message("Commande POLYLIGNE activée.", Color.GREEN)
			
		"CERCLE", "CIRCLE", "C":
			_on_circle_pressed()
		
		"ARC", "A":
			_on_arc_pressed()
			console.log_message("Commande ARC activée.", Color.GREEN)
			
		"POINT", "PO":
			_on_point_pressed()
			console.log_message("Commande POINT activée.", Color.GREEN)
			
		# --- AJOUT DE LA COMMANDE SUPPRIMER ---
		"SUPPRIMER", "DELETE", "DEL", "EFFACER":
			# On vérifie que le manager existe (sécurité)
			if selection_manager:
				selection_manager.delete_selection()
				# Le message de succès est déjà géré par le GlobalLogger dans le SelectionManager
				# Mais on peut confirmer l'action ici si on veut :
				console.log_message("Commande de suppression exécutée.", Color.CYAN)

		"EXPORT_DXF":
			_on_export_pressed()
			console.log_message("Ouverture fenêtre Export...", Color.CYAN)
			
		"IMPORT_DXF":
			_on_import_pressed()
			console.log_message("Ouverture fenêtre Import...", Color.CYAN)
			
		"FMULT", "MVIEW":
			if tab_bar.current_tab == 1:
				start_drawing_viewport()
				console.log_message("Spécifiez le premier coin de la fenêtre...", Color.GREEN)
			else:
				console.log_message("Vous devez être dans l'espace Présentation pour créer une fenêtre.", Color.RED)
			
		"ZOOM_ETENDU", "ZE":
			$World/Camera2D.zoom_extents() 
			console.log_message("Zoom Étendu effectué.", Color.GREEN)
			
		"QUITTER", "EXIT":
			get_tree().quit()
		
		"DEPLACER", "MOVE", "M":
			_on_move_pressed()
			console.log_message("Commande DÉPLACER.", Color.CYAN)
			
		"CALQUE", "LAYER":
			layer_dialog.popup_centered()
			console.log_message("Commande CALQUE.", Color.CYAN)
			
		"COPIER", "COPY", "CP", "CO":
			_on_copy_pressed()
		
		"MIROIR", "MIRROR", "MI":
			_on_mirror_pressed()
			
		"ROTATION", "ROTATE", "RO":
			_on_rotate_pressed()
		
		"ECHELLE", "SCALE", "SC":
			_on_scale_pressed()
		
		"DECALER", "OFFSET", "O":
			_on_offset_pressed()
			
		# --- COMMANDES RDM ---
		"RDM_TEST", "TEST_RDM":
			rdm_controller.create_test_structure()
			console.log_message("Structure de test RDM créée.", Color.GREEN)
			
		"RDM_SUPPORT_SIMPLE":
			rdm_controller.create_support(get_global_mouse_position(), "simple")
			console.log_message("Support simple créé.", Color.GREEN)
			
		"RDM_SUPPORT_ARTICULATION":
			rdm_controller.create_support(get_global_mouse_position(), "articulation")
			console.log_message("Articulation créée.", Color.GREEN)
			
		"RDM_SUPPORT_ENCASTREMENT":
			rdm_controller.create_support(get_global_mouse_position(), "encastrement")
			console.log_message("Encastrement créé.", Color.GREEN)
			
		"RDM_FORCE":
			rdm_controller.create_force(get_global_mouse_position(), Vector2(0, -1000))
			console.log_message("Force ponctuelle créée.", Color.GREEN)
			
		"RDM_DISTRIBUTED":
			if not rdm_controller.is_creating_distributed_force:
				rdm_controller.distributed_force_start = get_global_mouse_position()
				rdm_controller.is_creating_distributed_force = true
				GlobalLogger.info("RDM: cliquez pour définir la fin de la force répartie")
			else:
				rdm_controller.create_distributed_force(rdm_controller.distributed_force_start, get_global_mouse_position(), -1000.0)
				rdm_controller.is_creating_distributed_force = false
			console.log_message("Force répartie créée.", Color.GREEN)
			
		"RDM_CALCUL", "CALCUL_RDM":
			rdm_controller.calculate_rdm()
			
		_: 
			console.log_message("Commande inconnue : " + cmd, Color.RED)
			
func _input(event):
	# --- GESTION CREATION DE FENETRE DE PRESENTATION (FMULT) ---
	if is_drawing_viewport and tab_bar.current_tab == 1:
		# Echap pour annuler
		if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
			is_drawing_viewport = false
			if viewport_preview:
				viewport_preview.queue_free()
				viewport_preview = null
			console.log_message("Création de fenêtre annulée.", Color.ORANGE)
			get_viewport().set_input_as_handled()
			return
			
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if viewport_preview == null:
				viewport_start_pos = layout_camera.get_global_mouse_position()
				viewport_preview = ReferenceRect.new()
				viewport_preview.editor_only = false
				viewport_preview.border_color = Color(0.8, 0.8, 0.8)
				viewport_preview.border_width = 2.0
				workspace_paper.add_child(viewport_preview)
				viewport_preview.position = viewport_start_pos
				viewport_preview.size = Vector2.ZERO
			else:
				var end_pos = layout_camera.get_global_mouse_position()
				is_drawing_viewport = false
				create_viewport_at(viewport_start_pos, end_pos)
				if viewport_preview:
					viewport_preview.queue_free()
					viewport_preview = null
			get_viewport().set_input_as_handled()
			return
			
		elif event is InputEventMouseMotion and viewport_preview != null:
			var current_pos = layout_camera.get_global_mouse_position()
			var rect = Rect2(viewport_start_pos, Vector2.ZERO).expand(current_pos)
			viewport_preview.position = rect.position
			viewport_preview.size = rect.size
			get_viewport().set_input_as_handled()
			return

	# --- RDM : PLACEMENT PRIORITAIRE (BLOQUE LA SÉLECTION/GRIPS) ---
	if ui_hover_counter <= 0 and rdm_controller and rdm_controller.is_placement_active():
		if rdm_controller.handle_input(event):
			return
	
	# DEBUG : Afficher seulement les clics
	if event is InputEventMouseButton and event.pressed:
		print("DEBUG: Clic détecté à ", get_global_mouse_position())
	
	# --- GESTION DE LA SÉLECTION ---
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if ui_hover_counter <= 0:
				selection_manager.cancel_selection()
			# Annuler la création RDM en cours
			if rdm_controller:
				rdm_controller.cancel_placement()
	
	# Gérer le focus de la console
	if event is InputEventMouseButton and event.pressed:
		if console:
			var input_line = console.get_node_or_null("VBoxContainer/CommandLine")
			if input_line and input_line.has_focus():
				input_line.release_focus()
		var prop_focus = window_properties.gui_get_focus_owner()
		if prop_focus:
			prop_focus.release_focus()


func _unhandled_input(event):
	if event is InputEventKey and event.keycode == KEY_ESCAPE and rdm_controller and rdm_controller.is_placement_active():
		rdm_controller.cancel_placement()
		get_viewport().set_input_as_handled()
		return
	
	# --- GESTION RACCOURCIS CLAVIER (Ctrl+C / Ctrl+V / Ctrl+X) ---
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_C:
					if selection_manager:
						selection_manager.copy_to_clipboard()
						get_viewport().set_input_as_handled()
						return
				KEY_V:
					if selection_manager:
						selection_manager.start_paste_command()
						get_viewport().set_input_as_handled()
						return
				# --- AJOUT DU COUPER (CTRL+X) ---
				KEY_X:
					if selection_manager:
						selection_manager.cut_to_clipboard()
						get_viewport().set_input_as_handled()
						return
	# -----------------------------------------------------
	# --- GESTION UNDO / REDO (CTRL+Z / CTRL+Y ou CTRL+SHIFT+Z) ---
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_Z:
					if event.shift_pressed: # Ctrl + Shift + Z
						_redo()
					else: # Ctrl + Z
						_undo()
					get_viewport().set_input_as_handled()
					return
				KEY_Y: # Ctrl + Y (Alternative classique pour Redo)
					_redo()
					get_viewport().set_input_as_handled()
					return
	
	# Si on appuie sur Echap
	if event.is_action_pressed("ui_cancel"):
		
		# 1. D'abord, on vérifie si le DrawingManager a quelque chose à annuler (tracé en cours)
		# On regarde si l'outil n'est PAS "NONE" (0)
		if world.current_tool != 0:
			# On laisse le DrawingManager gérer l'annulation du tracé
			# (Il le fait déjà dans son propre _unhandled_input)
			return 
		
		# 2. Si on est en mode Neutre (Outil NONE), alors Echap sert à DÉSÉLECTIONNER
		selection_manager.deselect_all()
		
	# Raccourci F3 pour le Snapping
	if event.is_action_pressed("ui_focus_next"): # F3 est souvent mappé ici, sinon crée une action "toggle_snap"
		# Ou test direct de la touche :
		pass
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		snap_manager.check_box.button_pressed = !snap_manager.check_box.button_pressed
	
	
	# 3. AUTO-FOCUS CONSOLE
	if event is InputEventKey and event.pressed and not event.is_echo():
		
		# On ignore la touche SUPPR (gérée par SelectionManager)
		if event.keycode == KEY_DELETE: return 
		# On ignore les touches de contrôle (Ctrl+Z, Alt+F4...)
		if event.ctrl_pressed or event.alt_pressed: return

		# Si on tape un caractère imprimable
		if event.unicode > 0:
			var character = char(event.unicode)

			# --- FILTRE NUMÉRIQUE POUR DYNAMIC INPUT ---
			# Si c'est un chiffre (0-9) OU un séparateur (. ou ,)
			# On quitte la fonction pour laisser le DrawingManager gérer la longueur du trait.
			if character.is_valid_int() or character == "." or character == ",":
				return
			# -------------------------------------------

			# On récupère la ligne de commande via le ConsoleManager (plus sûr)
			# Assure-toi que ton script ConsoleManager a bien la variable 'input_line'
			var target_input = console.input_line
			
			if target_input and not target_input.has_focus():
				target_input.grab_focus()
				
				# On injecte la lettre
				target_input.text += character
				# On met le curseur à la fin
				target_input.caret_column = target_input.text.length()
				
				get_viewport().set_input_as_handled()


# --- FONCTIONS DE CREATION DE FENETRE PSPACE ---
func start_drawing_viewport():
	is_drawing_viewport = true

func create_viewport_at(p1: Vector2, p2: Vector2):
	var rect = Rect2(p1, Vector2.ZERO).expand(p2)
	if rect.size.x < 10 or rect.size.y < 10:
		console.log_message("Fenêtre trop petite, annulée.", Color.RED)
		return
		
	var vp = CADViewportEntityClass.new()
	
	# Construction des points : 4 sommets + 1er point répété pour fermer la polyligne
	# (CADEntity._draw() utilise draw_polyline qui n'a pas de mode "closed"
	# -> on duplique le 1er point pour fermer visuellement, et draw_grips n'en affiche que 4)
	vp.points = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
		rect.position  # Fermeture
	])
	
	# Force la géométrie à se dessiner
	vp.default_color = Color.WHITE
	
	# Insertion dans le dossier CAO dédié de Paper Space
	var entities_node = workspace_paper.get_node_or_null("Entities")
	if entities_node:
		entities_node.add_child(vp)
	else:
		workspace_paper.add_child(vp)
	
	# Magie AutoCAD: on connecte la vue !
	if vp.viewport_panel:
		var internal_viewport = vp.viewport_panel.get_node_or_null("SubViewportContainer/SubViewport")
		if internal_viewport:
			internal_viewport.world_2d = world.get_viewport().world_2d
		
	console.log_message("Fenêtre de présentation créée.", Color.GREEN)

	
func _process(delta):
	# 1. Mise à jour FPS (si existant)
	if fps_label:
		fps_label.text = "FPS: " + str(Engine.get_frames_per_second())

	# 2. GESTION DU CURSEUR CENTRALISÉE
	
	# A. Est-ce qu'on est sur l'UI classique (Boutons, Rubans...) ?
	var is_on_ui = (ui_hover_counter > 0)
	
	# B. Est-ce qu'on est sur la fenêtre Propriétés ?
	var is_on_prop_window = _is_mouse_over_window(window_properties)
	
	# C. Est-ce qu'on est sur la fenêtre des Calques ? (AJOUT ICI)
	var is_on_layer_window = _is_mouse_over_window(layer_dialog)
	
	# LOGIQUE FINALE :
	# Si on est sur n'importe quelle interface (UI classique OU Propriétés OU Calques)
	if is_on_ui or is_on_prop_window or is_on_layer_window:
		# --- MODE SOURIS SYSTÈME ---
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if selection_manager and selection_manager.cad_cursor:
			selection_manager.cad_cursor.visible = false
			
	else:
		# --- MODE DESSIN (Curseur CAD) ---
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		if selection_manager and selection_manager.cad_cursor:
			var cursor = selection_manager.cad_cursor
			cursor.visible = true
			cursor.global_position = cursor.get_global_mouse_position()

func _on_copy_pressed():
	if selection_manager:
		selection_manager.start_copy_command()
		console.log_message("Commande COPIER.", Color.CYAN)

# --- HELPERS UNDO/REDO ---
func _undo():
	if undo_redo.has_undo():
		undo_redo.undo()
		console.log_message("Annuler", Color.ORANGE)
		# On force un redraw du monde au cas où
		world.queue_redraw()
	else:
		GlobalLogger.warning("Rien à annuler.")

func _redo():
	if undo_redo.has_redo():
		undo_redo.redo()
		console.log_message("Rétablir", Color.ORANGE)
		world.queue_redraw()
	else:
		GlobalLogger.warning("Rien à rétablir.")


func _on_mirror_pressed() -> void:
	if selection_manager:
		selection_manager.start_mirror_command()
		console.log_message("Commande MIROIR.", Color.CYAN)


func _on_rotate_pressed() -> void:
	if selection_manager:
		selection_manager.start_rotate_command()
		console.log_message("Commande ROTATION.", Color.CYAN)


func _on_scale_pressed() -> void:
	if selection_manager:
		selection_manager.start_scale_command()
		console.log_message("Commande ECHELLE.", Color.CYAN)


func _on_offset_pressed() -> void:
	if selection_manager:
		selection_manager.start_offset_command()

func _on_trim_pressed() -> void:
	if selection_manager:
		selection_manager.start_trim_command()

func _on_point_pressed() -> void:
	if selection_manager:
		selection_manager.start_point_command()


func _on_linetype_selected(index: int) -> void:
	var text = btn_linetype.get_item_text(index)
	
	if text == "Autre...":
		# TODO: Ouvrir la fenêtre de gestion des types de ligne
		console.log_message("Ouvrir gestionnaire types de ligne...", Color.YELLOW)
		# On remet la sélection sur l'élément précédent pour ne pas rester sur "Autre"
		# (Logique à affiner plus tard)
		return

	# Mapping UI -> Valeur interne
	if text == "DuCalque": text = "ByLayer"
	elif text == "DuBloc": text = "ByBlock"
	
	# Appliquer le changement au SelectionManager pour les nouveaux objets
	if selection_manager and selection_manager.has_method("set_current_linetype"):
		selection_manager.set_current_linetype(text)
	
	# Appliquer le changement aux objets sélectionnés
	if selection_manager and selection_manager.has_method("modify_selection_property"):
		selection_manager.modify_selection_property("linetype", text)
	
	console.log_message("Type de ligne choisi : " + text, Color.CYAN)


func _on_lineweight_selected(index: int) -> void:
	var text = btn_lineweight.get_item_text(index)

	# Extraction de la valeur numérique (ex: "0.25 mm" -> 0.25)
	var weight_val = -1.0 # -1 = ByLayer

	if text == "DuCalque": weight_val = -1.0
	elif text == "DuBloc": weight_val = -2.0
	elif text == "Défaut": weight_val = 0.25 # Valeur par défaut standard
	else:
		# On enlève " mm" et on convertit
		weight_val = text.replace(" mm", "").to_float()

	# Appliquer le changement au SelectionManager pour les nouveaux objets
	if selection_manager and selection_manager.has_method("set_current_lineweight"):
		selection_manager.set_current_lineweight(weight_val)
	
	# Appliquer le changement aux objets sélectionnés
	if selection_manager and selection_manager.has_method("modify_selection_property"):
		selection_manager.modify_selection_property("lineweight", weight_val)

	console.log_message("Épaisseur choisie : " + str(weight_val), Color.CYAN)

# --- MISE À JOUR UI SUR SÉLECTION ---

# Dans Main.gd

func _on_selection_changed(items = null):
	if not selection_manager: return
	
	# CORRECTION ICI :
	# Si le signal nous envoie la liste (items), on l'utilise.
	# Sinon (si items est null), on va la chercher manuellement via la bonne fonction.
	if items == null:
		items = selection_manager.get_selected_entities_list()
	
	# Cas 1 : Rien de sélectionné (Désélection via Echap)
	# On remet les valeurs par défaut "DuCalque" pour être prêt à dessiner
	if items.is_empty():
		_update_property_buttons("ByLayer", -1.0)
		return

	# Cas 2 : Un ou plusieurs objets sélectionnés
	var first_item = items[0]
	
	# Sécurité : est-ce bien une entité CAD ?
	if not "linetype" in first_item: return
	
	var common_type = first_item.linetype
	var common_weight = first_item.lineweight
	
	# Si on a plusieurs objets, on vérifie s'ils sont identiques (Gestion du "VARIES")
	for i in range(1, items.size()):
		var item = items[i]
		if "linetype" in item and item.linetype != common_type:
			common_type = "" # Mélange détecté
		if "lineweight" in item and item.lineweight != common_weight:
			common_weight = -999.0 # Mélange détecté
			
	# On met à jour l'interface avec les valeurs trouvées
	_update_property_buttons(common_type, common_weight)

# À ajouter à la fin du script Main.gd

func _update_property_buttons(l_type: String, l_weight: float):
	# --- 1. BOUTON TYPE DE LIGNE ---
	if btn_linetype:
		var type_idx = -1
		
		if l_type != "":
			# Mapping des noms internes vers Interface
			var ui_name = l_type
			if l_type == "ByLayer": ui_name = "DuCalque"
			elif l_type == "ByBlock": ui_name = "DuBloc"
			
			# On cherche l'index correspondant dans la liste déroulante
			for i in range(btn_linetype.item_count):
				if btn_linetype.get_item_text(i) == ui_name:
					type_idx = i
					break
			
			# Si pas trouvé par nom UI, on cherche le nom exact (pour les types chargés comme CACHE)
			if type_idx == -1:
				for i in range(btn_linetype.item_count):
					if btn_linetype.get_item_text(i) == l_type:
						type_idx = i
						break
		
		# Si type_idx est -1, cela désélectionne (affiche vide), ce qui est correct pour "VARIES"
		btn_linetype.selected = type_idx

	# --- 2. BOUTON ÉPAISSEUR ---
	if btn_lineweight:
		var weight_idx = -1
		
		# Si l_weight n'est pas le code "VARIES" (-999)
		if l_weight != -999.0:
			for i in range(btn_lineweight.item_count):
				var text = btn_lineweight.get_item_text(i)
				var val = -999.0
				
				# Conversion inverse Texte -> Float pour comparer
				if text == "DuCalque": val = -1.0
				elif text == "DuBloc": val = -2.0
				elif text == "Défaut": val = 0.25
				else:
					# On enlève " mm" et on convertit
					val = text.replace(" mm", "").to_float()
				
				# Comparaison avec petite tolérance (car float)
				if is_equal_approx(val, l_weight):
					weight_idx = i
					break
					
		btn_lineweight.selected = weight_idx

# Vérifie si la souris est au-dessus d'une fenêtre (y compris sa barre de titre)
func _is_mouse_over_window(win: Window) -> bool:
	if not win or not win.visible: return false
	
	# Position de la souris dans le Viewport (l'écran de jeu)
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Position et taille de la fenêtre
	var win_pos = Vector2(win.position)
	var win_size = Vector2(win.size)
	
	# Marge pour la barre de titre (ex: 40px au-dessus)
	var title_height = 40.0
	
	# Rectangle global (Fenêtre + Titre)
	var total_rect = Rect2(
		win_pos.x, 
		win_pos.y - title_height, 
		win_size.x, 
		win_size.y + title_height
	)
	
	return total_rect.has_point(mouse_pos)


# Cette fonction est appelée par le signal du PropertiesPanel
func _on_property_color_changed(new_color: Color) -> void:
	if not selection_manager: return
	
	# 1. Récupération de la sélection
	var items = selection_manager.get_selected_entities_list()
	if items.is_empty(): return
	
	# 2. Identification des calques à modifier
	var layers_to_update = {}
	for item in items:
		if "layer_name" in item:
			layers_to_update[item.layer_name] = true
	
	# 3. Application au LayerManager
	for l_name in layers_to_update.keys():
		if layer_manager:
			layer_manager.set_layer_property(l_name, "color", new_color)
			
	GlobalLogger.success("Couleur du calque modifiée.")

func _on_property_layer_changed(new_layer_name: String) -> void:
	print("DEBUG: _on_property_layer_changed appelé avec new_layer_name = '", new_layer_name, "'")
	# Forcer la mise à jour du ruban (LayerMenu) quand le calque change via le PropertiesPanel
	if layer_menu:
		print("DEBUG: appel de layer_menu._update_visuals")
		# Forcer la sélection à jour avant de passer au ruban
		var selected = selection_manager.get_selected_entities_list()
		layer_menu._update_visuals(selected)
		# Forcer aussi le calque actif si pas de sélection
		if selection_manager.count_selected() == 0:
			print("DEBUG: pas de sélection -> mise à jour calque actif vers ", new_layer_name)
			for i in range(layer_manager.layers.size()):
				if layer_manager.layers[i].name == new_layer_name:
					layer_manager.set_active_layer(i)
					break
		else:
			print("DEBUG: sélection présente, nb = ", selection_manager.count_selected())
			# Forcer une deuxième mise à jour un frame plus tard pour laisser le temps au déplacement
			call_deferred("_deferred_update_ribbon_after_layer_change")

func _on_layer_changed_via_ribbon(new_layer_name: String) -> void:
	# Forcer la mise à jour du PropertiesPanel quand le calque change via le ruban
	if properties_panel:
		properties_panel._on_selection_updated(selection_manager.get_selected_entities_list())

func _deferred_update_ribbon_after_layer_change():
	print("DEBUG: _deferred_update_ribbon_after_layer_change appelé")
	if layer_menu:
		var selected = selection_manager.get_selected_entities_list()
		print("DEBUG: sélection différée -> ", selected.size(), " objets")
		for ent in selected:
			print("  - parent = ", ent.get_parent().name if ent.get_parent() else "null")
		layer_menu._update_visuals(selected)


func _on_btn_arc_pressed() -> void:
	pass # Replace with function body.
