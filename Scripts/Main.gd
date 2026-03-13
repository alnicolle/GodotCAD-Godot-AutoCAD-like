extends Node2D

@export var world : Node2D
@export var gui : CanvasLayer
@export var export_dialog : FileDialog
@export var import_dialog : FileDialog
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

# Référence à la caméra
@onready var camera = $World/Camera2D


var ui_hover_counter = 0
var undo_redo = UndoRedo.new()

var rdm_manager: RDMManager
var distributed_force_start: Vector2 = Vector2.INF
var is_creating_distributed_force: bool = false
var rdm_place_mode: String = ""
var rdm_place_support_type: String = ""
var rdm_place_force_value: Vector2 = Vector2.ZERO
var rdm_consume_left_release: bool = false

func _ready():
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
			rdm_place_mode = "support"
			rdm_place_support_type = "simple"
			GlobalLogger.info("RDM: cliquez pour placer un appui simple")
			# Activer le curseur pour le snap
			if cad_cursor:
				cad_cursor.show_crosshair = true
				cad_cursor.queue_redraw()
		)
	else:
		print("WARNING: btn_support_simple non trouvé")
		
	if btn_support_articulation:
		btn_support_articulation.pressed.connect(func(): 
			rdm_place_mode = "support"
			rdm_place_support_type = "articulation"
			GlobalLogger.info("RDM: cliquez pour placer un appui articulation")
			# Activer le curseur pour le snap
			if cad_cursor:
				cad_cursor.show_crosshair = true
				cad_cursor.queue_redraw()
		)
	else:
		print("WARNING: btn_support_articulation non trouvé")
		
	if btn_support_encastrement:
		btn_support_encastrement.pressed.connect(func(): 
			rdm_place_mode = "support"
			rdm_place_support_type = "encastrement"
			GlobalLogger.info("RDM: cliquez pour placer un encastrement")
			# Activer le curseur pour le snap
			if cad_cursor:
				cad_cursor.show_crosshair = true
				cad_cursor.queue_redraw()
		)
	else:
		print("WARNING: btn_support_encastrement non trouvé")
		
	if btn_force_ponctuelle:
		btn_force_ponctuelle.pressed.connect(func(): 
			rdm_place_mode = "force"
			rdm_place_force_value = Vector2(0, -1000)
			GlobalLogger.info("RDM: cliquez pour placer une force ponctuelle")
			# Activer le curseur pour le snap
			if cad_cursor:
				cad_cursor.show_crosshair = true
				cad_cursor.queue_redraw()
		)
	else:
		print("WARNING: btn_force_ponctuelle non trouvé")
	
	# Ajouter un bouton pour force répartie
	if btn_force_distributed:
		btn_force_distributed.pressed.connect(func():
			rdm_place_mode = "distributed_start"
			GlobalLogger.info("RDM: cliquez pour définir le début de la force répartie")
			# Activer le curseur pour le snap
			if cad_cursor:
				cad_cursor.show_crosshair = true
				cad_cursor.queue_redraw()
		)
	else:
		print("WARNING: btn_force_distributed non trouvé")

	
	
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

# Signal du ExportDialog
func _on_export_dialog_file_selected(path):
	# On appelle le service en lui passant le chemin ET le monde (pour qu'il trouve les entités)
	DXFService.save_dxf_r12(path, self)
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
			create_test_rdm_structure()
			console.log_message("Structure de test RDM créée.", Color.GREEN)
			
		"RDM_SUPPORT_SIMPLE":
			create_rdm_support(get_global_mouse_position(), "simple")
			console.log_message("Support simple créé.", Color.GREEN)
			
		"RDM_SUPPORT_ARTICULATION":
			create_rdm_support(get_global_mouse_position(), "articulation")
			console.log_message("Articulation créée.", Color.GREEN)
			
		"RDM_SUPPORT_ENCASTREMENT":
			create_rdm_support(get_global_mouse_position(), "encastrement")
			console.log_message("Encastrement créé.", Color.GREEN)
			
		"RDM_FORCE":
			create_rdm_force(get_global_mouse_position(), Vector2(0, -1000))
			console.log_message("Force ponctuelle créée.", Color.GREEN)
			
		"RDM_DISTRIBUTED":
			if not is_creating_distributed_force:
				_start_distributed_force()
			else:
				_finish_distributed_force(get_global_mouse_position())
			console.log_message("Force répartie créée.", Color.GREEN)
			
		"RDM_CALCUL", "CALCUL_RDM":
			_on_calculate_rdm_pressed()
			
		_: 
			console.log_message("Commande inconnue : " + cmd, Color.RED)
			
func _input(event):
	# --- RDM : PLACEMENT PRIORITAIRE (BLOQUE LA SÉLECTION/GRIPS) ---
	if ui_hover_counter <= 0 and rdm_place_mode != "":
		# Consommer aussi le relâchement (sinon SelectionManager fait finish_selection)
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if rdm_consume_left_release:
				rdm_consume_left_release = false
				get_viewport().set_input_as_handled()
				return
		
		# Prévisualisation snap + consommation du mouvement pour éviter hover/grips
		if event is InputEventMouseMotion:
			var pos_preview = camera.get_global_mouse_position()
			if snap_manager and snap_manager.has_method("get_snapped_position") and world and world.has_node("Entities") and camera:
				pos_preview = snap_manager.get_snapped_position(pos_preview, world.get_node("Entities"), camera.zoom.x)
			if cad_cursor:
				cad_cursor.global_position = pos_preview
				cad_cursor.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		
		# Placement au clic gauche (press)
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var pos = camera.get_global_mouse_position()
			if snap_manager and snap_manager.has_method("get_snapped_position") and world and world.has_node("Entities") and camera:
				pos = snap_manager.get_snapped_position(pos, world.get_node("Entities"), camera.zoom.x)
			match rdm_place_mode:
				"support":
					create_rdm_support(pos, rdm_place_support_type)
					rdm_place_mode = ""
				"force":
					create_rdm_force(pos, rdm_place_force_value)
					rdm_place_mode = ""
				"distributed_start":
					distributed_force_start = pos
					rdm_place_mode = "distributed_end"
					GlobalLogger.info("RDM: cliquez pour définir la fin de la force répartie")
				"distributed_end":
					create_rdm_distributed_force(distributed_force_start, pos, -1000.0)
					distributed_force_start = Vector2.INF
					rdm_place_mode = ""
			# Désactiver le curseur si on a terminé le placement
			if rdm_place_mode == "" and cad_cursor:
				cad_cursor.show_crosshair = true
				cad_cursor.queue_redraw()
			rdm_consume_left_release = true
			get_viewport().set_input_as_handled()
			return
		
		# Bloquer tout autre événement pendant le mode RDM
		get_viewport().set_input_as_handled()
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
				rdm_place_mode = ""
				rdm_consume_left_release = false
				distributed_force_start = Vector2.INF
				is_creating_distributed_force = false
				GlobalLogger.info("RDM: création annulée")
				# Désactiver le curseur de snap
				if cad_cursor:
					cad_cursor.show_crosshair = true
					cad_cursor.queue_redraw()
	
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
	if event is InputEventKey and event.keycode == KEY_ESCAPE and rdm_place_mode != "":
		rdm_place_mode = ""
		rdm_consume_left_release = false
		distributed_force_start = Vector2.INF
		is_creating_distributed_force = false
		GlobalLogger.info("RDM: création annulée")
		if cad_cursor:
			cad_cursor.show_crosshair = true
			cad_cursor.queue_redraw()
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




func _on_calculate_rdm_pressed():
	if rdm_manager == null:
		rdm_manager = RDMManager.new(self)
	
	# Récupérer toutes les entités récursivement dans tous les calques
	var all_entities = []
	var supports = []
	var forces = []
	
	# Chercher dans le monde récursivement
	if world:
		_find_entities_recursively(world, all_entities, supports, forces)
	
	print("DEBUG: Entités trouvées - Lignes: %d, Supports: %d, Forces: %d" % [all_entities.size(), supports.size(), forces.size()])
	
	# Afficher les détails pour debug
	for i in range(all_entities.size()):
		print("  Ligne %d: %s (parent: %s)" % [i, all_entities[i].name, all_entities[i].get_parent().name])
	for i in range(supports.size()):
		print("  Support %d: %s (%s) (parent: %s)" % [i, supports[i].name, supports[i].get_meta("support_type"), supports[i].get_parent().name])
	for i in range(forces.size()):
		print("  Force %d: %s (parent: %s)" % [i, forces[i].name, forces[i].get_parent().name])
	
	var result = rdm_manager.calculate_analysis(all_entities, supports, forces)

# Fonction récursive pour chercher dans tous les noeuds
func _find_entities_recursively(node: Node, all_entities: Array, supports: Array, forces: Array):
	for child in node.get_children():
		# Vérifier si c'est un CADEntity
		if child is CADEntity:
			# Vérifier si c'est un support
			if child.has_meta("support_type"):
				supports.append(child)
			# Vérifier si c'est une force
			elif child.has_meta("force_value") or child.has_meta("moment_value") or child.has_meta("force_type"):
				forces.append(child)
			# Sinon, c'est une poutre (ligne)
			else:
				all_entities.append(child)
		
		# Continuer la recherche récursive
		_find_entities_recursively(child, all_entities, supports, forces)

# --- UTILITAIRES POUR TESTS RDM ---

# Crée un support simple à la position donnée
func create_rdm_support(position: Vector2, support_type: String = "simple"):
	print("DEBUG: Création support %s à position %s" % [support_type, position])
	
	var support = CADEntity.new()
	
	support.global_position = position
	
	support.set_meta("support_type", support_type)
	support.is_point = true
	support.point_size = 8.0
	support.point_style = "CROSS"
	support.points = PackedVector2Array()
	support.update_visuals()
	
	# Ajouter le visuel RDM
	var visual = RDMVisual.create_support_visual(Vector2.ZERO, support_type)
	support.add_child(visual)
	
	# Ajouter au monde
	if world and world.has_node("Entities"):
		world.get_node("Entities").add_child(support)
		GlobalLogger.info("Support %s créé à %s" % [support_type, position])
		print("DEBUG: Support ajouté au monde avec succès")
	else:
		print("ERROR: world ou Entities non trouvé")
	
	return support

# Crée une force à la position donnée
func create_rdm_force(position: Vector2, force_value: Vector2 = Vector2(0, -1000), moment_value: float = 0.0):
	var force = CADEntity.new()
	force.global_position = position
	force.set_meta("force_value", force_value)
	force.set_meta("moment_value", moment_value)
	force.is_point = true
	force.point_size = 8.0
	force.point_style = "CROSS"
	force.points = PackedVector2Array()
	force.update_visuals()
	
	# Ajouter le visuel RDM
	var visual = RDMVisual.create_force_visual(Vector2.ZERO, force_value)
	force.add_child(visual)
	
	# Ajouter au monde
	if world and world.has_node("Entities"):
		world.get_node("Entities").add_child(force)
		GlobalLogger.info("Force %s N, moment %s N·m créé à %s" % [force_value, moment_value, position])
	
	return force

# Crée une force répartie (linéique) sur une poutre
func create_rdm_distributed_force(start_pos: Vector2, end_pos: Vector2, force_per_meter: float = -1000.0):
	var distributed_force = CADEntity.new()
	distributed_force.global_position = start_pos
	distributed_force.set_meta("force_type", "distributed")
	distributed_force.set_meta("start_pos", start_pos)
	distributed_force.set_meta("end_pos", end_pos)
	distributed_force.set_meta("force_per_meter", force_per_meter)
	
	# Ajouter une ligne pour rendre le CADEntity visible et sélectionnable
	distributed_force.add_point(Vector2.ZERO)
	distributed_force.add_point(end_pos - start_pos)
	distributed_force.width = 2.0
	distributed_force.default_color = Color.RED
	
	# Ajouter le visuel RDM
	var visual = RDMVisual.create_distributed_force_visual(Vector2.ZERO, end_pos - start_pos, force_per_meter)
	distributed_force.add_child(visual)
	
	# Ajouter au monde
	if world and world.has_node("Entities"):
		world.get_node("Entities").add_child(distributed_force)
		GlobalLogger.info("Force répartie %.1f N/m créée de %s à %s" % [force_per_meter, start_pos, end_pos])
	
	return distributed_force

# Test rapide avec une structure simple
func create_test_rdm_structure():
	# Créer une poutre simple (2 points)
	var line = CADEntity.new()
	line.add_point(Vector2(100, 200))
	line.add_point(Vector2(400, 200))
	if world and world.has_node("Entities"):
		world.get_node("Entities").add_child(line)
	
	# Ajouter 2 appuis
	create_rdm_support(Vector2(100, 200), "articulation")
	create_rdm_support(Vector2(400, 200), "simple")
	
	# Ajouter une force au milieu (sur la poutre, pas sur un nœud existant)
	create_rdm_force(Vector2(250, 200), Vector2(0, 5000))
	
	GlobalLogger.info("Structure de test RDM créée")

# --- FONCTIONS POUR FORCES RÉPARTIES ---

func _start_distributed_force():
	distributed_force_start = get_global_mouse_position()
	is_creating_distributed_force = true
	GlobalLogger.info("Cliquez pour définir la fin de la force répartie")

func _finish_distributed_force(end_pos: Vector2):
	if distributed_force_start != Vector2.INF:
		create_rdm_distributed_force(distributed_force_start, end_pos, -1000)
		distributed_force_start = Vector2.INF
		is_creating_distributed_force = false
