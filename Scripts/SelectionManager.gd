extends Node2D

# --- RÉFÉRENCES ---
@export var world : Node2D
@export var gui : Control
@export var export_dialog : Window
@export var import_dialog : Window
@export var btn_import : Button
@export var console : RichTextLabel
@export var top_ribbon : VBoxContainer
@export var bottom_bar : HBoxContainer
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
@export var properties_panel : Window
@export var window_properties : Window
@export var fps_label : Label
@export var btn_manage_layers : Button
@export var cad_cursor : Node2D
@export var snap_manager : HBoxContainer 
@export var layer_manager : Node
@export var camera : Camera2D 
@export var active_entities_container : Node2D

signal selection_changed(selected_list)

# --- SCRIPT CADEntity ---
const CADEntityScript = preload("res://Scripts/CADEntity.gd")

# --- ÉTATS SÉLECTION ---
enum State { IDLE, SELECTION_BOX, GRIP_EDIT }
var current_state = State.IDLE

# --- ÉTATS COMMANDES ---
enum CommandType { NONE, MOVE, COPY, PASTE, MIRROR, ROTATE, SCALE, OFFSET, TRIM, POINT }
var current_command = CommandType.NONE
var move_step = 0 # 0=Select, 1=BasePoint, 2=SecondPoint
var move_base_point = Vector2.ZERO

# NOUVEAU : Pour stocker les positions originales pendant la prévisualisation
var move_initial_data = {} 
var active_ghosts = []
var original_circle_data = { "center": Vector2.ZERO, "radius": 0.0 }

var scale_pivot = Vector2.ZERO

var clipboard = []

# --- PARAMÈTRES SÉLECTION ---
var drag_start_pos = Vector2.ZERO 
var drag_threshold = 10.0 
var color_window = Color(0.2, 0.2, 1.0, 0.2)
var color_crossing = Color(0.2, 1.0, 0.2, 0.2)

# --- GRIPS ---
var active_grip_entity : CADEntity = null
var active_grip_index : int = -1
var is_snapped_to_grip = false
var original_grip_pos = Vector2.ZERO 



var undo_redo : UndoRedo # Sera assigné par le Main

# Variables spécifiques au Mirroir
var mirror_p1 = Vector2.ZERO
var mirror_p2 = Vector2.ZERO

# Variables pour la rotation
var rotation_pivot = Vector2.ZERO
var ref_p1 = Vector2.ZERO # Pour le mode référence
var ref_p2 = Vector2.ZERO

# --- OFFSET ---
var offset_mode = "VALUE" # "VALUE" ou "VISUAL"
var offset_dist = 10.0
var offset_target_entity : Node2D = null # L'objet en cours de décalage

# --- TRIM ---
var trim_step = 0 # 0=Définition ligne virtuelle, 1=Validation
var trim_fence_start = Vector2.ZERO # Premier point de la ligne virtuelle
var trim_fence_end = Vector2.ZERO   # Second point de la ligne virtuelle
var trim_objects = [] # Objets à trimmer (trouvés par intersection)

# --- UTILITAIRE ---
func get_world_mouse() -> Vector2:
	return camera.get_global_mouse_position()

func _get_trim_highlight_world_pos(ent: Node) -> Vector2:
	if ent == null:
		return Vector2.ZERO
	if ent.get("is_circle") and ent.is_circle:
		return ent.global_position + ent.circle_center
	if ent.get("is_arc") and ent.is_arc:
		return ent.global_position + ent.arc_center
	if ent is Line2D and ent.points.size() > 0:
		var sum := Vector2.ZERO
		for p in ent.points:
			sum += ent.to_global(p)
		return sum / float(ent.points.size())
	return ent.global_position

func _ready():
	print("DEBUG SM: SelectionManager initialisé !")
	set_process_unhandled_input(true)
	set_process_input(true)
	



# --- API PUBLIQUE POUR MAIN ---

func start_offset_command():
	current_command = CommandType.OFFSET
	move_initial_data.clear()
	_clear_ghosts()
	
	# GESTION PRÉ-SÉLECTION
	offset_target_entity = null 
	
	var count = count_selected()
	if count == 1:
		var entities = get_selected_entities_list()
		offset_target_entity = entities[0]
		GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_1"))
	elif count > 1:
		GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_3"))
	
	# Étape 1 : Choix du mode
	move_step = 1
	
	# --- MODIFICATION ICI : AFFICHER LA VALEUR SAUVEGARDÉE ---
	GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_12") + str(offset_dist) + tr("MSG_CONSOLE_OFFSET_13") + str(offset_dist) + ")")
	# ---------------------------------------------------------
	
	if cad_cursor: 
		cad_cursor.show_crosshair = true 
		cad_cursor.queue_redraw()
	
	current_state = State.IDLE

func start_point_command():
	# CORRECTION : On force l'arrêt de tout outil de dessin en cours (ex: Polyligne)
	if world and world.has_method("set_tool"):
		world.set_tool(0) # 0 = NONE
		
	current_command = CommandType.POINT
	move_initial_data.clear()
	_clear_ghosts()
	
	GlobalLogger.info(tr("MSG_CONSOLE_POINT_1"))
	
	if cad_cursor:
		cad_cursor.show_crosshair = true
		cad_cursor.queue_redraw()
	
	current_state = State.IDLE


func start_trim_command():
	current_command = CommandType.TRIM
	move_initial_data.clear()
	_clear_ghosts()
	
	# Initialisation mode fence
	trim_step = 0
	trim_fence_start = Vector2.ZERO
	trim_fence_end = Vector2.ZERO
	trim_objects.clear()
	
	GlobalLogger.info(tr("MSG_CONSOLE_TRIM_1"))
	
	if cad_cursor:
		cad_cursor.show_crosshair = true
		cad_cursor.queue_redraw()
	
	current_state = State.IDLE

func start_scale_command():
	current_command = CommandType.SCALE
	move_initial_data.clear()
	
	var selected_count = count_selected()
	if selected_count > 0:
		move_step = 1
		GlobalLogger.info(tr("MSG_CONSOLE_SCALE_1"))
		if cad_cursor: cad_cursor.show_crosshair = true
	else:
		move_step = 0
		GlobalLogger.info(tr("MSG_CONSOLE_SCALE_2"))
		if cad_cursor: 
			cad_cursor.show_crosshair = false
			cad_cursor.queue_redraw()

func start_move_command():
	# On utilise la fonction générique pour éviter la duplication de logique
	_start_generic_transform_command(CommandType.MOVE, "DÉPLACER")

# NOUVELLE FONCTION COPIER
func start_copy_command():
	_start_generic_transform_command(CommandType.COPY, "COPIER")

# Factorisation pour éviter de dupliquer le code d'init
func _start_generic_transform_command(type, label: String):
	# CORRECTION : On force l'arrêt de tout outil de dessin
	if world and world.has_method("set_tool"):
		world.set_tool(0) # 0 = NONE

	# --- SÉCURITÉ FOCUS ---
	# On retire le focus du bouton cliqué pour éviter qu'il interfère avec la touche ENTRÉE ensuite
	get_viewport().gui_release_focus()
	# ----------------------

	current_command = type
	move_initial_data.clear()
	
	var selected_count = count_selected()
	if selected_count > 0:
		# Cas : Objets déjà sélectionnés -> On passe direct au point de base
		move_step = 1
		GlobalLogger.info(label + " : " + tr("MSG_CONSOLE_TRANSFORM_1"))
		if cad_cursor: cad_cursor.show_crosshair = true
	else:
		# Cas : Pas de sélection -> On demande la sélection
		move_step = 0
		GlobalLogger.info(label + " : " + tr("MSG_CONSOLE_TRANSFORM_2"))
		if cad_cursor: 
			cad_cursor.show_crosshair = false
			cad_cursor.queue_redraw()

# FONCTION MIRROIR
func start_mirror_command():
	current_command = CommandType.MIRROR
	move_initial_data.clear()
	
	var selected_count = count_selected()
	if selected_count > 0:
		move_step = 1 # On passe direct au premier point de l'axe
		GlobalLogger.info(tr("MSG_CONSOLE_MIRROR_1"))
		if cad_cursor: cad_cursor.show_crosshair = true
	else:
		move_step = 0 # Selection d'abord
		GlobalLogger.info(tr("MSG_CONSOLE_MIRROR_2"))
		if cad_cursor: 
			cad_cursor.show_crosshair = false # Carré de sélection uniquement
			cad_cursor.queue_redraw()

func cancel_command():
	# Correction BUG : On doit revert pour MOVE, ROTATE et SCALE car ils modifient les vrais objets pendant la preview
	if current_command in [CommandType.MOVE, CommandType.ROTATE, CommandType.SCALE]:
		_revert_preview_positions()
	
	# Nettoyage spécifique pour TRIM
	if current_command == CommandType.TRIM:
		trim_objects.clear()
		trim_fence_start = Vector2.ZERO
		trim_fence_end = Vector2.ZERO
		trim_step = 0
	
	current_command = CommandType.NONE
	move_step = 0
	move_initial_data.clear()
	
	_clear_ghosts()
	
	if cad_cursor: 
		cad_cursor.show_crosshair = true
		cad_cursor.queue_redraw()
	
	if snap_manager: 
		snap_manager.reset_visuals()

	queue_redraw()
	GlobalLogger.info(tr("MSG_CONSOLE_GENERAL_1"))

# --- GESTION DU PRESSE-PAPIER (CTRL+C / CTRL+V) ---
func copy_to_clipboard():
	clipboard.clear()
	var entities = _get_all_flat_entities()
	var count = 0
	
	for ent in entities:
		if ent.is_selected:
			var copy = ent.duplicate()
			_copy_custom_properties(ent, copy)
			
			# --- MODIFICATION : SAUVEGARDE DU CALQUE ---
			# On note le nom du calque d'origine (le parent) dans une métadonnée
			var source_layer_name = ent.get_parent().name
			copy.set_meta("source_layer", source_layer_name)
			if "layer_name" in copy:
				copy.layer_name = source_layer_name
			# -------------------------------------------
			
			clipboard.append(copy)
			count += 1
			
	if count > 0:
		GlobalLogger.info(tr("MSG_CONSOLE_COPY_1") + str(count))
	else:
		GlobalLogger.warning(tr("MSG_CONSOLE_COPY_2"))

func start_paste_command():
	# SUPPRIMEZ la ligne : _prepare_paste_data() qui est ici
	
	if clipboard.is_empty():
		GlobalLogger.warning("Presse-papier vide.")
		return
		
	cancel_command() # Nettoie ghosts et move_initial_data
	current_command = CommandType.PASTE
	move_step = 2
	
	GlobalLogger.info(tr("MSG_CONSOLE_PASTE_1"))
	
	# 1. Calcul du centre
	var center = _calculate_clipboard_center()
	move_base_point = center 
	
	# 2. Création des fantômes (Maintenant avec les bons IDs et Data)
	_store_ghosts_from_clipboard()
	
	# 3. Premier update
	var mouse_pos = get_world_mouse()
	# Maintenant que move_initial_data est correct, ceci va marcher :
	_apply_preview_offset(mouse_pos - move_base_point)
	queue_redraw()


func cut_to_clipboard():
	clipboard.clear()
	var entities = _get_all_flat_entities()
	var count = 0
	
	for ent in entities:
		if ent.is_selected:
			var copy = ent.duplicate()
			_copy_custom_properties(ent, copy)
			
			# --- MODIFICATION : SAUVEGARDE DU CALQUE ---
			var source_layer_name = ent.get_parent().name
			copy.set_meta("source_layer", source_layer_name)
			if "layer_name" in copy:
				copy.layer_name = source_layer_name
			# -------------------------------------------
			
			clipboard.append(copy)
			
			# Suppression de l'original
			ent.queue_free()
			count += 1
			
	if count > 0:
		active_grip_entity = null
		active_grip_index = -1
		is_snapped_to_grip = false
		if snap_manager: snap_manager.reset_visuals()
		if cad_cursor: cad_cursor.modulate = Color.WHITE
		
		GlobalLogger.info(tr("MSG_CONSOLE_TRIM_2") + str(count))
		emit_signal("selection_changed", [])
	else:
		GlobalLogger.warning(tr("MSG_CONSOLE_TRIM_3"))

#Rotation
func start_rotate_command():
	current_command = CommandType.ROTATE
	move_initial_data.clear()
	
	var selected_count = count_selected()
	if selected_count > 0:
		move_step = 1
		GlobalLogger.info(tr("MSG_CONSOLE_ROTATE_1"))
		if cad_cursor: cad_cursor.show_crosshair = true
	else:
		move_step = 0
		GlobalLogger.info(tr("MSG_CONSOLE_ROTATE_2"))
		if cad_cursor: 
			cad_cursor.show_crosshair = false
			cad_cursor.queue_redraw()

# Appelé par le Main quand l'utilisateur tape un nombre (ex: 45) + Entrée
func submit_input_value(value: float):
	# ROTATION
	if current_command == CommandType.ROTATE and (move_step == 2 or move_step == 6):
		var angle_rad = deg_to_rad(-value)
		apply_rotate_to_selection(angle_rad)
		cancel_command()
		GlobalLogger.success("Rotation de " + str(value) + "° effectuée.")
		return

	# ECHELLE (Uniquement à l'étape 6 "Facteur")
	if current_command == CommandType.SCALE and move_step == 6:
		if value <= 0.0001:
			GlobalLogger.error(tr("MSG_CONSOLE_SCALE_3"))
			return
		
		apply_scale_to_selection(value)
		cancel_command()
		GlobalLogger.success(tr("MSG_CONSOLE_SCALE_4") + str(value))
		return
		
	# CAS DECALER (Etape 1 : Saisie de la distance)
	# CAS DECALER : Validation Distance
	if current_command == CommandType.OFFSET and move_step == 11:
		if value <= 0:
			GlobalLogger.error(tr("MSG_CONSOLE_GENERAL_2"))
			return
		
		offset_dist = value
		offset_mode = "VALUE"
		
		# LOGIQUE DE TRANSITION : A-t-on déjà un objet ?
		if offset_target_entity != null:
			# OUI -> On saute la sélection, on prépare le fantôme et on passe à l'étape 3
			_store_ghost_for_offset(offset_target_entity)
			move_step = 3
			GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_4"))
			# Curseur croix pour placer
			if cad_cursor: cad_cursor.show_crosshair = true; cad_cursor.queue_redraw()
		else:
			# NON -> On demande de sélectionner
			move_step = 2
			GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_5"))
			# Curseur Pickbox (Carré seul)
			if cad_cursor: cad_cursor.show_crosshair = false; cad_cursor.queue_redraw()
			
		return

	GlobalLogger.warning(tr("MSG_CONSOLE_GENERAL_3"))


# --- INPUT HANDLING ---

func handle_input(event):
	# Méthode publique pour recevoir les événements de Main.gd
	print("DEBUG SM: handle_input appelée avec event: ", event.get_class())
	_unhandled_input(event)

func _unhandled_input(event):
	#print("DEBUG SM: _unhandled_input début - camera: ", camera != null, " world: ", world != null)
	#if not camera or not world: 
	#	print("DEBUG SM: Bloqué - camera ou world null")
	#	return
	
	var world_tool = world.get("current_tool")
	#print("DEBUG SM: world.current_tool: ", world_tool)
	#if world_tool != null and int(world_tool) != 0: 
	#	print("DEBUG SM: Bloqué - world.current_tool != 0")
	#	return 

	var mouse_pos_world = get_world_mouse()
	
	# DEBUG : Afficher seulement les clics
	#if event is InputEventMouseButton and event.pressed:
	#	print("DEBUG SM: Clic reçu - current_command: ", current_command, " current_state: ", current_state)

	# --- BLOC 1 : GESTION DES COMMANDES (PRIORITAIRE) ---
	if current_command != CommandType.NONE:
		
		# [CAS POINT] - CORRECTION DU BUG : AJOUT DE LA LOGIQUE
		if current_command == CommandType.POINT:
			# Prévisualisation (Snapping)
			if event is InputEventMouseMotion:
				var snap_pos = _get_snap_pos(mouse_pos_world, [])
				if cad_cursor: cad_cursor.global_position = snap_pos
				queue_redraw()
				return
				
			# Création au clic
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var snap_pos = _get_snap_pos(mouse_pos_world, [])
				_create_point(snap_pos)
				# On ne quitte PAS la commande, on permet de placer plusieurs points (comme AutoCAD)
				get_viewport().set_input_as_handled()
				return
		
		# [Cas PASTE]
		if current_command == CommandType.PASTE:

			# --- CORRECTION ACCROCHAGE ---
			# 1. On calcule la position snappée (accrochée)
			# On passe [] car les objets qu'on colle ne sont pas encore dans la scène
			var current_snap_pos = _get_snap_pos(mouse_pos_world, [])
			
			# 2. On calcule l'offset par rapport à ce point snappé (et non mouse_pos_world)
			var offset = current_snap_pos - move_base_point
			# -----------------------------

			if event is InputEventMouseMotion:
				_apply_preview_offset(offset)
				
				# 3. On force le curseur visuel à se mettre sur le point snappé
				if cad_cursor: cad_cursor.global_position = current_snap_pos
				
				queue_redraw()
				return 

			elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				apply_paste_from_clipboard(offset)
				cancel_command()
				get_viewport().set_input_as_handled()
				return

		# [CAS TRIM (AJUSTER/FENCE)]
		if current_command == CommandType.TRIM:
			
			# Étape 0 : Définition du premier point de la ligne virtuelle
			if trim_step == 0:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					trim_fence_start = _get_snap_pos(mouse_pos_world, [])
					trim_fence_end = trim_fence_start
					trim_step = 1
					GlobalLogger.info(tr("MSG_CONSOLE_TRIM_4"))
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
				
				elif event is InputEventMouseMotion:
					queue_redraw()
					return
			
			# Étape 1 : Définition du second point et exécution
			elif trim_step == 1:
				if event is InputEventMouseMotion:
					trim_fence_end = _get_snap_pos(mouse_pos_world, [])
					_find_objects_crossed_by_fence()
					queue_redraw()
					return
				
				elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					trim_fence_end = _get_snap_pos(mouse_pos_world, [])
					_find_objects_crossed_by_fence()
					execute_trim_fence()
					cancel_command()
					get_viewport().set_input_as_handled()
					return
			
			return

		# [CAS GÉNÉRIQUE : MOVE, COPY, MIRROR, ROTATION, SCALE, OFFSET, TRIM, POINT]
		if current_command in [CommandType.MOVE, CommandType.COPY, CommandType.MIRROR, CommandType.ROTATE, CommandType.SCALE, CommandType.OFFSET, CommandType.TRIM, CommandType.POINT]:
			
			# ==========================================================
			#                  COMMANDE DECALER (OFFSET)
			# ==========================================================
			
			# --- ÉTAPE 1 : CHOIX DU MODE ---
			if current_command == CommandType.OFFSET and move_step == 1:
				# --- NOUVEAU : VALIDATION DIRECTE DE LA VALEUR PRÉCÉDENTE (ENTRÉE) ---
				if event.is_action_pressed("ui_accept"):
					
					get_viewport().gui_release_focus()
					
					offset_mode = "VALUE"
					GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_6") + str(offset_dist) + tr("MSG_CONSOLE_OFFSET_7"))
					
					# LOGIQUE DE TRANSITION (Identique à celle de submit_input_value)
					if offset_target_entity != null:
						_store_ghost_for_offset(offset_target_entity)
						move_step = 3
						GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_4"))
						if cad_cursor: cad_cursor.show_crosshair = true; cad_cursor.queue_redraw()
					else:
						move_step = 2
						GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_5"))
						if cad_cursor: cad_cursor.show_crosshair = false; cad_cursor.queue_redraw()
					
					get_viewport().set_input_as_handled()
					return
				# ---------------------------------------------------------------------
				
				if event is InputEventKey and event.pressed:
					# OPTION DISTANCE
					if event.keycode == KEY_D:
						move_step = 11
						GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_8"))
						get_viewport().set_input_as_handled()
						return
					
					# OPTION VISUEL
					if event.keycode == KEY_V:
						offset_mode = "VISUAL"
						
						# LOGIQUE DE TRANSITION (Pareil que pour la valeur)
						if offset_target_entity != null:
							# Objet déjà là -> Step 3 direct
							_store_ghost_for_offset(offset_target_entity)
							move_step = 3
							GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_9"))
							if cad_cursor: cad_cursor.show_crosshair = true; cad_cursor.queue_redraw()
						else:
							# Pas d'objet -> Step 2
							move_step = 2
							GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_14"))
							# Curseur Pickbox (Carré seul)
							if cad_cursor: cad_cursor.show_crosshair = false; cad_cursor.queue_redraw()
						
						get_viewport().set_input_as_handled()
						return

				if event is InputEventMouseButton:
					get_viewport().set_input_as_handled()
				return 

			# --- ÉTAPE 1.5 : ATTENTE VALEUR ---
			if current_command == CommandType.OFFSET and move_step == 11:
				if event is InputEventMouseButton:
					get_viewport().set_input_as_handled()
				return

			# --- ÉTAPE 2 : SÉLECTION DE L'OBJET (Si pas de pré-sélection) ---
			if current_command == CommandType.OFFSET and move_step == 2:
				var mouse_pos = get_world_mouse()
				
				# IMPORTANT : On s'assure que le curseur est bien en mode Pickbox (Carré seul)
				# On le fait ici aussi au cas où (mouse motion) pour éviter qu'il change
				if cad_cursor and cad_cursor.show_crosshair == true:
					cad_cursor.show_crosshair = false
					cad_cursor.queue_redraw()
				
				if event is InputEventMouseMotion:
					handle_hover_logic(mouse_pos)
					if cad_cursor: cad_cursor.global_position = mouse_pos
					return
				
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					var clicked_ent = _get_entity_under_mouse(mouse_pos)
					if clicked_ent:
						offset_target_entity = clicked_ent
						_store_ghost_for_offset(clicked_ent)
						
						move_step = 3
						GlobalLogger.info(tr("MSG_CONSOLE_OFFSET_4"))
						
						# On remet le curseur Crosshair pour l'étape de placement
						if cad_cursor: 
							cad_cursor.show_crosshair = true
							cad_cursor.queue_redraw()
					else:
						GlobalLogger.warning(tr("MSG_CONSOLE_OFFSET_10"))
					
					get_viewport().set_input_as_handled()
					return

			# --- ÉTAPE 3 : CÔTÉ ET VALIDATION ---
			if current_command == CommandType.OFFSET and move_step == 3:
				var snap = _get_snap_pos(mouse_pos_world, null)
				
				if event is InputEventMouseMotion:
					_update_offset_preview(snap)
					if cad_cursor: cad_cursor.global_position = snap
					return
				
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_finalize_offset(snap)
					cancel_command()
					get_viewport().set_input_as_handled()
					return

			# ==========================================================
			#             FIN BLOC DECALER - AUTRES COMMANDES
			# ==========================================================
			
			if current_command == CommandType.MIRROR and move_step == 3:
				if event is InputEventKey and event.pressed:
					if event.keycode == KEY_O or event.keycode == KEY_Y: 
						_finalize_mirror(true)
						get_viewport().set_input_as_handled()
						return
					elif event.keycode == KEY_N or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER: 
						_finalize_mirror(false)
						get_viewport().set_input_as_handled()
						return
				# Important : Si c'est une touche mais pas O/N/Entrée, on bloque quand même 
				# pour éviter d'écrire dans le terminal par erreur
				if event is InputEventKey: 
					get_viewport().set_input_as_handled()
					return
			
			# Pour ne pas casser MOVE/COPY/etc, on met le reste dans un else ou on vérifie
			if current_command != CommandType.OFFSET and current_command != CommandType.POINT:
				# --- Étape 0 : Validation sélection (POUR LES AUTRES COMMANDES) ---) ---
				if move_step == 0:
					# A. VALIDATION (ENTRÉE)
					if event.is_action_pressed("ui_accept"):
						# 1. Si rien n'est sélectionné, on ne fait rien
						if count_selected() == 0: 
							get_viewport().set_input_as_handled()
							return
						get_viewport().gui_release_focus()
						
						# 2. On passe à l'étape suivante
						move_step = 1
						
						# 3. Gestion du Curseur
						if cad_cursor: 
							cad_cursor.show_crosshair = true
							cad_cursor.queue_redraw()
						
						# 4. Message contextuel
						var msg = tr("MSG_CONSOLE_TRANSFORM_4")
						if current_command == CommandType.ROTATE: msg = tr("MSG_CONSOLE_TRANSFORM_5")
						elif current_command == CommandType.SCALE: msg = tr("MSG_CONSOLE_TRANSFORM_5")
						elif current_command == CommandType.MIRROR: msg = tr("MSG_CONSOLE_TRANSFORM_6")
						
						GlobalLogger.info(msg)
						
						# 4. Passer à l'étape 1
						move_step = 1
						get_viewport().set_input_as_handled()
						return
					
					# B. SÉLECTION SOURIS (Clic gauche pour sélectionner)
					if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
						if event.pressed:
							current_state = State.SELECTION_BOX
							drag_start_pos = mouse_pos_world
						else:
							finish_selection(mouse_pos_world)
							current_state = State.IDLE
							queue_redraw()
					elif event is InputEventMouseMotion:
						if current_state == State.SELECTION_BOX: queue_redraw()
						else: handle_hover_logic(mouse_pos_world)
					return

				# --- Étape 1 : Premier Point (Base / Pivot) ---
				elif move_step == 1:
					var current_snap_pos = _get_snap_pos(mouse_pos_world, null)
					
					if event is InputEventMouseMotion:
						if cad_cursor: cad_cursor.global_position = current_snap_pos
						return

					elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
						if current_command == CommandType.SCALE:
							scale_pivot = current_snap_pos
							_store_initial_positions_for_preview()
							move_step = 2
							GlobalLogger.info(tr("MSG_CONSOLE_GENERAL_4"))
							
						elif current_command == CommandType.ROTATE: 
							rotation_pivot = current_snap_pos
							_store_initial_positions_for_preview()
							move_step = 2
							GlobalLogger.info(tr("MSG_CONSOLE_GENERAL_5"))
							
						elif current_command == CommandType.MIRROR:
							mirror_p1 = current_snap_pos
							_store_initial_positions_for_preview()
							move_step = 2
							GlobalLogger.info(tr("MSG_CONSOLE_MIRROR_3"))
							
						else: # MOVE / COPY
							move_base_point = current_snap_pos
							if current_command == CommandType.MOVE: _store_initial_positions_for_preview()
							elif current_command == CommandType.COPY: _store_preview_ghosts_for_copy()
							move_step = 2
							GlobalLogger.info(tr("MSG_CONSOLE_TRANSFORM_3"))
						
						get_viewport().set_input_as_handled()
						return 

				# --- Étape 2 : Choix / Preview ---
				elif move_step == 2:
					var ignore_list = []
					var current_snap_pos = _get_snap_pos(mouse_pos_world, ignore_list)

					# ORTHO
					if current_command == CommandType.MIRROR:
						current_snap_pos = _apply_ortho_constraint(mirror_p1, current_snap_pos)
					elif current_command in [CommandType.MOVE, CommandType.COPY]:
						current_snap_pos = _apply_ortho_constraint(move_base_point, current_snap_pos)

					# CAS ECHELLE (Mode Choix)
					if current_command == CommandType.SCALE:
						if event is InputEventKey and event.pressed:
							if event.keycode == KEY_F:
								move_step = 6
								GlobalLogger.info(tr("MSG_CONSOLE_GENERAL_6"))
								get_viewport().set_input_as_handled()
								return
							if event.keycode == KEY_R:
								move_step = 3
								GlobalLogger.info(tr("MSG_CONSOLE_REFERENCE_1"))
								get_viewport().set_input_as_handled()
								return
						
						if event is InputEventMouseMotion:
							if cad_cursor: cad_cursor.global_position = current_snap_pos
							return
						return 

					# CAS ROTATION (Mode Choix)
					if current_command == CommandType.ROTATE:
						if event is InputEventKey and event.pressed:
							if event.keycode == KEY_A:
								move_step = 6
								GlobalLogger.info(tr("MSG_CONSOLE_GENERAL_7"))
								get_viewport().set_input_as_handled()
								return
							if event.keycode == KEY_R:
								move_step = 3
								GlobalLogger.info(tr("MSG_CONSOLE_REFERENCE_2"))
								get_viewport().set_input_as_handled()
								return
						if event is InputEventMouseMotion:
							if cad_cursor: cad_cursor.global_position = current_snap_pos
							return
						return 

					# Move / Copy / Mirror Preview
					if event is InputEventMouseMotion:
						if current_command == CommandType.MIRROR:
							_update_mirror_ghosts_preview(mirror_p1, current_snap_pos)
						else:
							var offset = current_snap_pos - move_base_point
							_apply_preview_offset(offset)
						if cad_cursor: cad_cursor.global_position = current_snap_pos
						queue_redraw()
						return 
					
					elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
						if current_command == CommandType.MIRROR:
							mirror_p2 = current_snap_pos
							move_step = 3 
							GlobalLogger.info(tr("MSG_CONSOLE_MIRROR_4"))
							
							get_viewport().gui_release_focus()
						else:
							var offset = current_snap_pos - move_base_point
							if current_command == CommandType.MOVE:
								_revert_preview_positions()
								apply_move_to_selection(offset)
								cancel_command()
							elif current_command == CommandType.COPY:
								apply_copy_to_selection(offset)
						get_viewport().set_input_as_handled()
						return 

				# --- ÉTAPES RÉFÉRENCE (Rotation et Echelle) ---
				
				# Step 3 : Premier Point Ref
				elif move_step == 3:
					var snap = _get_snap_pos(mouse_pos_world, null)
					if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
						ref_p1 = snap
						move_step = 4
						GlobalLogger.info(tr("MSG_CONSOLE_REFERENCE_3"))
						GlobalLogger.info(tr("MSG_CONSOLE_REFERENCE_4"))
						get_viewport().set_input_as_handled()
						return

				# Step 4 : Second Point Ref
				elif move_step == 4:
					var snap = _get_snap_pos(mouse_pos_world, null)
					if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
						ref_p2 = snap
						move_step = 5
						if current_command == CommandType.SCALE: GlobalLogger.info(tr("MSG_CONSOLE_REFERENCE_6"))
						else: GlobalLogger.info(tr("MSG_CONSOLE_REFERENCE_5"))
						get_viewport().set_input_as_handled()
						return

				# Step 5 : Troisième Point Ref (Calcul)
				elif move_step == 5:
					var snap = _get_snap_pos(mouse_pos_world, null)
					
					if event is InputEventMouseMotion:
						if current_command == CommandType.SCALE:
							var dist_base = ref_p1.distance_to(ref_p2)
							var dist_new = ref_p1.distance_to(snap)
							if dist_base > 0.0001: _update_scale_ghosts_preview(dist_new / dist_base)
						elif current_command == CommandType.ROTATE:
							var angle_diff = (snap - ref_p1).angle() - (ref_p2 - ref_p1).angle()
							_update_rotate_ghosts_preview(angle_diff)
						
						if cad_cursor: cad_cursor.global_position = snap
						return

					if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
						if current_command == CommandType.SCALE:
							var dist_base = ref_p1.distance_to(ref_p2)
							var dist_new = ref_p1.distance_to(snap)
							if dist_base > 0.0001:
								apply_scale_to_selection(dist_new / dist_base)
								cancel_command()
						elif current_command == CommandType.ROTATE:
							var angle_diff = (snap - ref_p1).angle() - (ref_p2 - ref_p1).angle()
							apply_rotate_to_selection(angle_diff)
							cancel_command()
						
						get_viewport().set_input_as_handled()
						return

				# --- Étape 6 : ROTATION VISUELLE OU ECHELLE FACTEUR ---
				elif move_step == 6:
					
					# CAS ECHELLE FACTEUR (Attente de chiffre uniquement)
					if current_command == CommandType.SCALE:
						if event is InputEventMouseMotion:
							if cad_cursor: cad_cursor.global_position = mouse_pos_world
						return

					# CAS ROTATION VISUELLE
					elif current_command == CommandType.ROTATE:
						var ignore_list = get_selected_entities_list()
						var current_snap_pos = _get_snap_pos(mouse_pos_world, ignore_list)
						
						if event is InputEventMouseMotion:
							var angle = (current_snap_pos - rotation_pivot).angle()
							_update_rotate_ghosts_preview(angle)
							if cad_cursor: cad_cursor.global_position = current_snap_pos
							return

						elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
							var final_angle = (current_snap_pos - rotation_pivot).angle()
							apply_rotate_to_selection(final_angle)
							cancel_command()
							get_viewport().set_input_as_handled()
							return 

				# --- ÉTAPE MIROIR (Question) ---
				#elif current_command == CommandType.MIRROR and move_step == 3:
				#	if event is InputEventKey and event.pressed:
				#		if event.keycode == KEY_O or event.keycode == KEY_Y: 
				#			_finalize_mirror(true)
				#			get_viewport().set_input_as_handled()
				#			return
				#		elif event.keycode == KEY_N or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER: 
				#			_finalize_mirror(false)
				#			get_viewport().set_input_as_handled()
				#			return

				# --- ÉTAPE AJUSTER (TRIM/FENCE) ---
				elif current_command == CommandType.TRIM:
					print("DEBUG TRIM: trim_step = ", trim_step)
					print("DEBUG TRIM: event type = ", event.get_class())
					if event is InputEventMouseButton:
						print("DEBUG TRIM: bouton = ", event.button_index, ", pressed = ", event.pressed)
					
					# Étape 0 : Définition du premier point de la ligne virtuelle
					if trim_step == 0:
						if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
							print("DEBUG TRIM: clic gauche détecté à l'étape 0")
							trim_fence_start = _get_snap_pos(mouse_pos_world, [])
							trim_step = 1
							GlobalLogger.info(tr("MSG_CONSOLE_TRIM_4"))
							get_viewport().set_input_as_handled()
							return
						
						elif event is InputEventMouseMotion:
							# Prévisualisation de la ligne depuis le curseur
							trim_fence_start = _get_snap_pos(mouse_pos_world, [])
							queue_redraw()
							return
					
					# Étape 1 : Définition du second point et exécution
					elif trim_step == 1:
						if event is InputEventMouseMotion:
							# Prévisualisation de la ligne complète
							trim_fence_end = _get_snap_pos(mouse_pos_world, [])
							_find_objects_crossed_by_fence()
							queue_redraw()
							return
						
						elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
							print("DEBUG TRIM: clic gauche détecté à l'étape 1")
							trim_fence_end = _get_snap_pos(mouse_pos_world, [])
							_find_objects_crossed_by_fence()
							execute_trim_fence()
							cancel_command()
							get_viewport().set_input_as_handled()
							return

		# --- 2. GESTION CLAVIERS GLOBAUX ---
	if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		delete_selection()
		return

	if event.is_action_pressed("ui_cancel"):
		if current_command != CommandType.NONE:
			cancel_command()
			return
		if current_state == State.GRIP_EDIT:
			cancel_grip_edit()
			return 
		else:
			deselect_all()
		return

	# --- 3. LOGIQUE STANDARD ---
	# CORRECTION : Si aucune commande n'est active, on gère la sélection.
	# (Le return précédent dans le bloc COMMANDS empêche d'arriver ici si une commande est traitée)
	
	if current_command == CommandType.NONE: 
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_snapped_to_grip and current_state == State.IDLE: 
					start_grip_edit()
				elif current_state == State.GRIP_EDIT: 
					finish_grip_edit() 
				else: 
					# Démarrage de la boîte de sélection
					print("DEBUG SM: Démarrage sélection box")
					current_state = State.SELECTION_BOX;
					drag_start_pos = mouse_pos_world
					queue_redraw() # Important pour afficher le rectangle
			else: 
				if current_state == State.SELECTION_BOX: 
					print("DEBUG SM: Fin sélection box")
					finish_selection(mouse_pos_world); 
					current_state = State.IDLE;
					queue_redraw()
		elif event is InputEventMouseMotion:
			if current_state == State.GRIP_EDIT: _handle_grip_drag(mouse_pos_world)
			elif current_state == State.SELECTION_BOX: queue_redraw()
			else: handle_hover_logic(mouse_pos_world)
	
	# Si on est dans une commande qui nécessite un input direct (MOVE, COPY, etc.), on bloque la sélection standard
	# Mais on autorise la sélection pour POINT et les commandes qui n'ont pas d'étape de sélection
	elif current_command != CommandType.NONE and current_command not in [CommandType.POINT]:
		return

# --- LOGIQUE PRÉVISUALISATION (GHOST) ---

func _store_initial_positions_for_preview():
	move_initial_data.clear()
	_clear_ghosts() 
	
	var entities = get_selected_entities_list()
	if entities.is_empty(): return

	for ent in entities:
		# 1. On stocke TOUTES les données (Anciennes pour compatibilité + Nouvelle pour Miroir)
		var data = {
			# Pour le MIROIR (Calcul matriciel)
			"global_trans": ent.global_transform, 
			
			# Pour DEPLACER / ROTATION / ECHELLE (Compatibilité code existant)
			"node_pos": ent.position,
			"rotation": ent.rotation,
			"scale": ent.scale,
			
			# Spécifique
			"center": Vector2.ZERO,
			"radius": 0.0,
			"target": Vector2.ZERO,
			"points": [] 
		}
		
		# Sauvegarde propriétés Cercle
		if "is_circle" in ent and ent.is_circle:
			data["center"] = ent.circle_center
			data["radius"] = ent.circle_radius
					
		# Sauvegarde propriétés Arc
		elif "is_arc" in ent and ent.is_arc:
			data["center"] = ent.arc_center
			data["radius"] = ent.arc_radius
			data["start_angle"] = ent.arc_start_angle
			data["end_angle"] = ent.arc_end_angle
		
		# Sauvegarde points (si Line2D pour d'autres usages)
		if ent is Line2D:
			data["points"] = ent.points.duplicate()

		# 2. Gestion Fantômes vs Réel
		if current_command in [CommandType.ROTATE, CommandType.SCALE]:
			# On modifie l'objet réel pour ces commandes
			move_initial_data[ent.get_instance_id()] = data
		else:
			# On crée le fantôme pour MOVE / COPY / MIRROR
			var ghost = _create_ghost_from_entity(ent)
			active_ghosts.append(ghost)
			
			# IMPORTANT : On aligne parfaitement le fantôme sur l'original au départ
			ghost.global_transform = ent.global_transform
			
			# On associe les données au fantôme
			move_initial_data[ghost.get_instance_id()] = data

func _apply_preview_offset(offset: Vector2):
	# On parcourt TOUS les fantômes actifs
	for ghost in active_ghosts:
		if not is_instance_valid(ghost): continue
		
		var id = ghost.get_instance_id()
		
		# Maintenant, le PASTE aura aussi ses données ici grâce à _prepare_paste_data()
		if move_initial_data.has(id):
			var data = move_initial_data[id]
			var start_trans = data["global_trans"]
			
			if ("is_circle" in ghost and ghost.is_circle) or ("is_arc" in ghost and ghost.is_arc):
				ghost.global_transform = start_trans
				ghost.circle_center = data["center"] + offset
				ghost.circle_radius = data["radius"]
				if ghost.has_method("_mark_dirty"):
					ghost._mark_dirty()
				if ghost.has_method("update_visuals"):
					ghost.update_visuals()
				continue
				
				if "is_arc" in ghost and ghost.is_arc:
					var new_center = data["center"] + offset
					var radius = data["radius"]
					var start_angle = data.get("start_angle", 0.0)
					var end_angle = data.get("end_angle", 0.0)
					if ghost.has_method("update_arc_properties"):
						ghost.update_arc_properties(new_center, radius, start_angle, end_angle)
					else:
						ghost.arc_center = new_center
						ghost.arc_radius = radius
						ghost.arc_start_angle = start_angle
						ghost.arc_end_angle = end_angle
						ghost.queue_redraw()
					continue
			
			# Calcul simple : Position d'origine + Offset de la souris
			# Comme l'offset est le même pour tous, l'écart entre les objets est conservé !
			ghost.global_position = start_trans.origin + offset
			
			
			ghost.queue_redraw()

func _revert_preview_positions():
	# On parcourt les IDs stockés dans le dictionnaire
	for id in move_initial_data.keys():
		var data = move_initial_data[id]
		
		# On retrouve l'objet réel depuis son ID
		var ent = instance_from_id(id)
		
		if is_instance_valid(ent):
			# On restaure la Transform complète (Position, Rotation, Scale)
			ent.global_transform = data["global_trans"]
			
			# Restauration spécifique Cercle
			if "is_circle" in ent and ent.is_circle:
				ent.circle_center = data["center"]
				ent.circle_radius = data["radius"]
				ent.queue_redraw()
			
			# Restauration spécifique Arc
			elif "is_arc" in ent and ent.is_arc:
				ent.arc_center = data["center"]
				ent.arc_radius = data["radius"]
				if data.has("start_angle"):
					ent.arc_start_angle = data["start_angle"]
				if data.has("end_angle"):
					ent.arc_end_angle = data["end_angle"]
				if data.has("points") and ent is Line2D:
					ent.points = data["points"].duplicate()
				ent.queue_redraw()
	
	# Nettoyage
	_clear_ghosts()
	move_initial_data.clear()


# --- LOGIQUE MÉTIER ---

func apply_move_to_selection(offset: Vector2):
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	undo_redo.create_action("Déplacer")
	
	# SYNTAXE GODOT 4 : On utilise .bind() pour passer les arguments
	undo_redo.add_do_method(_action_move_entities.bind(entities, offset))
	undo_redo.add_undo_method(_action_move_entities.bind(entities, -offset))
	
	undo_redo.commit_action()
	
	GlobalLogger.success(tr("MSG_CONSOLE_MOVE_1"))

func count_selected() -> int:
	var c = 0
	# UTILISATION DE LA NOUVELLE FONCTION
	for ent in _get_all_flat_entities():
		if ent.is_selected: c += 1
	return c

# --- FONCTIONS UTILITAIRES EXISTANTES ---

func _handle_grip_drag(mouse_pos_world):
	if active_grip_entity:
		var target_pos = mouse_pos_world
		if snap_manager and world:
			target_pos = snap_manager.get_snapped_position(
				mouse_pos_world, 
				world.get_node("Entities"), 
				camera.zoom.x, 
				active_grip_entity,    
				active_grip_index     
			)
		active_grip_entity.move_point(active_grip_index, target_pos)
		if cad_cursor:
			cad_cursor.global_position = target_pos
			cad_cursor.modulate = Color(1, 0.5, 0)
		
		queue_redraw()

func start_grip_edit():
	current_state = State.GRIP_EDIT
	if active_grip_entity:
		original_grip_pos = active_grip_entity.get_grip_position(active_grip_index)
		
		# --- CRÉATION DU FANTÔME ---
		# On crée une copie statique de l'objet AVANT modif
		_create_ghost_from_entity(active_grip_entity)
			
	GlobalLogger.warning(tr("MSG_CONSOLE_GRIP_3"))

func finish_grip_edit():
	GlobalLogger.success(tr("MSG_CONSOLE_GRIP_2"))
	current_state = State.IDLE
	
	# --- NETTOYAGE ---
	# On supprime le fantôme car la modif est finie
	_clear_ghosts()
	
	if snap_manager: snap_manager.reset_visuals()

func cancel_grip_edit():
	GlobalLogger.info(tr("MSG_CONSOLE_GRIP_1"))
	if active_grip_entity:
		active_grip_entity.move_point(active_grip_index, original_grip_pos)
		if cad_cursor: cad_cursor.global_position = original_grip_pos
	
	current_state = State.IDLE
	
	# --- NETTOYAGE ---
	_clear_ghosts()
	
	if snap_manager: snap_manager.reset_visuals()

func deselect_all():
	if current_state == State.SELECTION_BOX:
		current_state = State.IDLE
		queue_redraw()
		return
	var entities = _get_all_flat_entities()
	var renderer = world.get_node_or_null("EntitiesRenderer") if world else null
	for ent in entities:
		ent.set_selected(false)
		# --- GESTION UNPACKING : REBAKING LORS DE LA DÉSÉLECTION ---
		if ent.has_meta("unpacked_data") and renderer:
			DXFBaker.rebake_unpacked_entity(ent, renderer)
	GlobalLogger.info(tr("MSG_CONSOLE_SELECTION_3"))
	
	# --- AJOUT SIGNAL ---
	emit_signal("selection_changed", [])

func finish_selection(end_pos_world: Vector2):
	var threshold_world = 10.0 / camera.zoom.x
	var is_click = drag_start_pos.distance_to(end_pos_world) < threshold_world
	var rect = Rect2(drag_start_pos, end_pos_world - drag_start_pos).abs()
	var entities = _get_all_flat_entities()
	var hit_something = false
	var keep_previous = Input.is_key_pressed(KEY_SHIFT) 
	
	var touched_entities = []
	for ent in entities:
		if ent.has_meta("is_ghost"): continue
		
		# Verrouillage
		if _is_entity_locked(ent): continue
		
		var touched = false
		if is_click: 
			touched = ent.hit_test(end_pos_world, threshold_world)
		else: 
			if (end_pos_world.x < drag_start_pos.x): touched = ent.is_intersecting_rect(rect)
			else: touched = ent.is_inside_rect(rect)
		if touched:
			touched_entities.append(ent)
			hit_something = true

	# ===== UNPACKING DES OBJETS VIRTUELS =====
	var renderer = world.get_node_or_null("EntitiesRenderer") if world else null
	if renderer:
		if is_click:
			var virtual_ent = renderer.get_entity_at_position(end_pos_world, threshold_world)
			if virtual_ent and not virtual_ent.is_hidden:
				# Vérification verrouillage calque optionnelle
				var is_locked = false
				if layer_manager and layer_manager.has_method("get_layer_data"):
					var l_data = layer_manager.get_layer_data(virtual_ent.layer_name)
					if l_data and l_data.locked: is_locked = true
					
				if not is_locked:
					var unpacked_node = DXFBaker.unpack_entity(virtual_ent, world, renderer)
					if unpacked_node:
						touched_entities.append(unpacked_node)
						hit_something = true
		else:
			var virtual_ents = renderer.get_entities_in_rect(rect)
			for virtual_ent in virtual_ents:
				if not virtual_ent.is_hidden:
					var is_locked = false
					if layer_manager and layer_manager.has_method("get_layer_data"):
						var l_data = layer_manager.get_layer_data(virtual_ent.layer_name)
						if l_data and l_data.locked: is_locked = true
						
					if not is_locked:
						var select_it = false
						if (end_pos_world.x < drag_start_pos.x):
							select_it = virtual_ent.intersects_rect(rect)
						else:
							select_it = virtual_ent.is_inside_rect(rect)
						
						if select_it:
							var unpacked_node = DXFBaker.unpack_entity(virtual_ent, world, renderer)
							if unpacked_node:
								touched_entities.append(unpacked_node)
								hit_something = true

	if not hit_something and is_click and not keep_previous:
		deselect_all()
		return

	for ent in touched_entities:
		if keep_previous and ent.is_selected:
			ent.set_selected(false)
			if ent.has_meta("unpacked_data") and renderer:
				DXFBaker.rebake_unpacked_entity(ent, renderer)
		else:
			ent.set_selected(true)
	
	if hit_something: 
		GlobalLogger.info(str(count_selected()) + tr("MSG_CONSOLE_SELECTION_1"))
		
	# --- AJOUT SIGNAL ---
	emit_signal("selection_changed", get_selected_entities_list())

func delete_selection():
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	var data_list = []
	for ent in entities:
		data_list.append({
			"node": ent,
			"parent": ent.get_parent()
		})
	
	undo_redo.create_action("Supprimer")
	
	# SYNTAXE GODOT 4
	undo_redo.add_do_method(_action_remove_entities.bind(data_list))
	undo_redo.add_undo_method(_action_restore_entities.bind(data_list))
	
	undo_redo.commit_action()
	
	# Reset visuel
	active_grip_entity = null
	active_grip_index = -1
	is_snapped_to_grip = false
	if snap_manager: snap_manager.reset_visuals()
	if cad_cursor: cad_cursor.modulate = Color.WHITE
	
	GlobalLogger.info(str(entities.size()) + tr("MSG_CONSOLE_SELECTION_2"))

func _draw():
	# --- DESSIN STANDARD (Sélection Box) ---
	if current_state == State.SELECTION_BOX:
		var current_pos_world = get_world_mouse()
		var start_pos_world = drag_start_pos
		
		var local_start = to_local(start_pos_world)
		var local_end = to_local(current_pos_world)
		
		var rect = Rect2(local_start, local_end - local_start)
		var abs_rect = rect.abs()
		
		var is_crossing = (current_pos_world.x < start_pos_world.x)
		var col = color_crossing if is_crossing else color_window
		var line_thick = 2.0 / camera.zoom.x
		
		draw_rect(abs_rect, col, true)
		draw_rect(abs_rect, col.lightened(0.5), false, line_thick)
	
	# --- DESSIN LIGNE FENCE (TRIM) ---
	if current_command == CommandType.TRIM and trim_step >= 0:
		var line_thick = 2.0 / camera.zoom.x
		
		if trim_step == 0:
			# Ligne depuis le curseur jusqu'au premier point
			var mouse_pos = get_world_mouse()
			var start_local = to_local(_get_snap_pos(mouse_pos, []))
			var end_local = to_local(_get_snap_pos(mouse_pos, []))
			draw_line(start_local, end_local, Color.CYAN, line_thick)
		elif trim_step == 1:
			# Ligne complète entre les deux points
			var start_local = to_local(trim_fence_start)
			var end_local = to_local(trim_fence_end)
			draw_line(start_local, end_local, Color.CYAN, line_thick)
			
			# Mettre en surbrillance les objets qui seront coupés
			for obj in trim_objects:
				if is_instance_valid(obj):
					var obj_local = to_local(_get_trim_highlight_world_pos(obj))
					draw_circle(obj_local, 10.0 / camera.zoom.x, Color.YELLOW, false, 2.0 / camera.zoom.x)
	
	# --- DESSIN POINT (PRÉVISUALISATION) ---
	if current_command == CommandType.POINT:
		var mouse_pos = get_world_mouse()
		var preview_pos = to_local(_get_snap_pos(mouse_pos, []))
		var size = 5.0 / camera.zoom.x
		var line_w = 2.0 / camera.zoom.x
		
		# Dessiner un petit "+" pour la prévisualisation avec largeur fixe
		draw_line(preview_pos + Vector2(-size, 0), preview_pos + Vector2(size, 0), Color.WHITE, line_w)
		draw_line(preview_pos + Vector2(0, -size), preview_pos + Vector2(0, size), Color.WHITE, line_w)

func handle_hover_logic(mouse_pos_world: Vector2):
	var grip_aperture = 25.0 / camera.zoom.x 
	var line_aperture = 10.0 / camera.zoom.x
	
	var entities = _get_all_flat_entities()
	
	is_snapped_to_grip = false
	active_grip_entity = null
	active_grip_index = -1
	var final_cursor_pos = mouse_pos_world
	var final_cursor_color = Color.WHITE
	var grip_found = false
	var hover_found = false
	
	# 1. GESTION DES GRIPS (Uniquement sur la sélection, donc rapide)
	for ent in entities:
		if ent.is_selected:
			var idx = ent.get_grip_index_at_position(mouse_pos_world, grip_aperture)
			if idx != -1:
				grip_found = true
				is_snapped_to_grip = true
				active_grip_entity = ent
				active_grip_index = idx
				final_cursor_pos = ent.get_grip_position(idx)
				final_cursor_color = Color(1, 0.5, 0)
				break

	# 2. GESTION DU SURVOL (HOVER) - OPTIMISÉE
	if not grip_found:
		# D'abord, on réinitialise tous les états de hover
		for ent in entities:
			if not ent.is_selected:  # On ne modifie pas le hover des objets sélectionnés
				ent.set_hover(false)
		
		# Ensuite, on cherche l'objet sous la souris
		for ent in entities:
			# On ignore les objets sélectionnés et les fantômes
			if ent.is_selected or ent.has_meta("is_ghost"):
				continue
				
			# --- OPTIMISATION ---
			# On vérifie d'abord grossièrement si on est proches (Rectangle rapide)
			if not _is_mouse_near_entity(ent, mouse_pos_world, line_aperture):
				continue
			
			# Test précis (Lent) uniquement si on est proches
			if ent.hit_test(mouse_pos_world, line_aperture):
				ent.set_hover(true)
				hover_found = true
				break  # On s'arrête au premier objet trouvé

	if cad_cursor:
		cad_cursor.global_position = final_cursor_pos
		cad_cursor.modulate = final_cursor_color


func get_selected_entities_list() -> Array:
	var list = []
	# UTILISATION DE LA NOUVELLE FONCTION
	for ent in _get_all_flat_entities():
		if ent.is_selected:
			list.append(ent)
	return list

# --- GESTION DES FANTÔMES (NODES) ---

func _create_ghost_from_entity(original_ent: Node2D):
	# 1. On duplique l'entité (copie parfaite propriétés + script)
	var ghost = original_ent.duplicate()
	
	# --- CORRECTIF CERCLE ---
	# duplicate() ne copie pas les variables de script dynamiques.
	# Il faut les transférer manuellement.
	if "is_circle" in original_ent and original_ent.is_circle:
		ghost.is_circle = true
		ghost.circle_center = original_ent.circle_center
		ghost.circle_radius = original_ent.circle_radius
	elif "is_arc" in original_ent and original_ent.is_arc:
		ghost.is_arc = true
		ghost.arc_center = original_ent.arc_center
		ghost.arc_radius = original_ent.arc_radius
		ghost.arc_start_angle = original_ent.arc_start_angle
		ghost.arc_end_angle = original_ent.arc_end_angle
	elif "is_point" in original_ent and original_ent.is_point:
		ghost.is_point = true
		ghost.point_size = original_ent.point_size
		ghost.point_style = original_ent.point_style
	# ------------------------

	# 2. On change son apparence (Gris + Transparence)
	# On s'assure que la couleur par défaut est bien grise pour le dessin interne
	if "default_color_val" in ghost:
		ghost.default_color_val = Color(0.5, 0.5, 0.5, 0.5)
		ghost.default_color = ghost.default_color_val
	
	ghost.modulate = Color(1, 1, 1, 0.6)
	
	# 3. On lui ajoute une "Méta-donnée" pour l'identifier comme fantôme
	ghost.set_meta("is_ghost", true)
	
	# 4. On l'ajoute au monde (dans Entities pour que SnapManager le voie)
	if active_entities_container:
		active_entities_container.add_child(ghost)
	
	# 5. On le stocke pour pouvoir le supprimer plus tard
	active_ghosts.append(ghost)
	
	# IMPORTANT : On force le fantôme à se redessiner immédiatement
	# (Sinon il attendrait le prochain cycle et pourrait ne pas apparaître)
	ghost.queue_redraw()
	return ghost

func _clear_ghosts():
	for ghost in active_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	active_ghosts.clear()
	# On force un redessin pour être sûr que tout disparait
	queue_redraw()
	
# Récupère tous les objets CAD, qu'ils soient à la racine ou dans des calques visibles
func _get_all_flat_entities() -> Array:
	var result = []
	if not active_entities_container: return result
		
	var root = active_entities_container
	
	for child in root.get_children():
		# Cas 1 : C'est un objet direct (héritage ou fallback)
		if child is CADEntity:
			if child.visible: result.append(child)
			
		# Cas 2 : C'est un calque (Node2D conteneur)
		elif child is Node2D:
			if not child.visible: continue # On ignore les calques cachés
			
			for grandchild in child.get_children():
				if grandchild is CADEntity and grandchild.visible:
					result.append(grandchild)
	return result

func _is_entity_locked(ent: Node2D) -> bool:
	var parent = ent.get_parent()
	if parent.has_meta("locked") and parent.get_meta("locked") == true:
		return true
	return false

# --- NOUVELLES FONCTIONS LOGIQUE COPIE ---

func _store_preview_ghosts_for_copy():
	move_initial_data.clear()
	_clear_ghosts()
	
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	for ent in entities:
		# 1. Création du fantôme
		var ghost = _create_ghost_from_entity(ent)
		active_ghosts.append(ghost)
		
		# 2. Alignement strict
		ghost.global_transform = ent.global_transform
		
		# 3. STOCKAGE DES DONNÉES (Format compatible ID + GlobalTransform)
		var data = {
			"global_trans": ent.global_transform, # Indispensable pour _apply_preview_offset
			"center": Vector2.ZERO,
			"radius": 0.0,
			"target": Vector2.ZERO
		}
		
		if "is_circle" in ent and ent.is_circle:
			data["center"] = ent.circle_center
			data["radius"] = ent.circle_radius
		elif "is_arc" in ent and ent.is_arc:
			data["center"] = ent.arc_center
			data["radius"] = ent.arc_radius
			data["start_angle"] = ent.arc_start_angle
			data["end_angle"] = ent.arc_end_angle
				
		# C'est l'ID du fantôme qui sert de clé
		move_initial_data[ghost.get_instance_id()] = data

func apply_copy_to_selection(offset: Vector2):
	var entities = _get_all_flat_entities()
	var count = 0
	
	for ent in entities:
		if ent.is_selected:
			# 1. Duplication
			var copy = ent.duplicate()
			
			# --- CORRECTION : UTILISER LA FONCTION CENTRALISÉE ---
			# On remplace tout le bloc manuel "if is_circle..." par ceci :
			_copy_custom_properties(ent, copy)
			# -----------------------------------------------------
			
			# 3. Ajout au même calque que l'original
			ent.get_parent().add_child(copy)
			
			# 4. Déplacement de la copie
			if copy.has_method("translate_entity"):
				copy.translate_entity(offset)
			else:
				# Fallback
				copy.position += offset
				if "circle_center" in copy: copy.circle_center += offset
				if "arc_center" in copy: copy.arc_center += offset
			
			# Note: La persistance couleur est déjà gérée par _copy_custom_properties maintenant
				
			count += 1
	
	GlobalLogger.success(tr("MSG_CONSOLE_COPY_1") + str(count) + tr("MSG_CONSOLE_COPY_3"))
	
	
	# --- HELPERS LOGIQUE ---

func _get_snap_pos(mouse_pos, exclude_list) -> Vector2:
	if snap_manager and active_entities_container:
		return snap_manager.get_snapped_position(
			mouse_pos, active_entities_container, camera.zoom.x, exclude_list, -1
		)
	return mouse_pos

func _copy_custom_properties(source, target):
	# Gestion Cercle
	if "is_circle" in source and source.is_circle:
		target.is_circle = true
		target.circle_center = source.circle_center
		target.circle_radius = source.circle_radius
	elif "is_arc" in source and source.is_arc:
		target.is_arc = true
		target.arc_center = source.arc_center
		target.arc_radius = source.arc_radius
		target.arc_start_angle = source.arc_start_angle
		target.arc_end_angle = source.arc_end_angle

	if "layer_name" in source:
		target.layer_name = source.layer_name
	if "linetype_scale" in source:
		target.linetype_scale = source.linetype_scale

	# Gestion Couleur (pour éviter l'orange de sélection)
	if "default_color_val" in source:
		target.default_color_val = source.default_color_val
		target.default_color = source.default_color_val
	
	# --- AJOUT CORRECTIF PROPRIÉTÉS LIGNE ---
	if "linetype" in source:
		target.linetype = source.linetype
	
	if "lineweight" in source:
		target.lineweight = source.lineweight
	# ----------------------------------------

	# --- SÉPARATION DES OBJETS CLONÉS ---
	# Si on copie un objet "Unpacked", il ne doit pas pointer vers la même donnée pure !
	if target.has_meta("unpacked_data"):
		target.remove_meta("unpacked_data")

	target.is_selected = false

# --- FONCTIONS GHOSTS ET CLIPBOARD ---

func _calculate_clipboard_center() -> Vector2:
	if clipboard.is_empty(): return Vector2.ZERO
	var min_p = Vector2(INF, INF)
	var max_p = Vector2(-INF, -INF)
	var has_points = false
	
	for item in clipboard:
		# Pour Line2D
		if item is Line2D and not item.get("is_circle"):
			for p in item.points:
				# Attention: item.points est local, item.position est l'offset
				var g_p = item.position + p
				min_p = min_p.min(g_p)
				max_p = max_p.max(g_p)
				has_points = true
		# Pour Cercle
		elif item.get("is_circle"):
			var c = item.position + item.circle_center
			min_p = min_p.min(c)
			max_p = max_p.max(c)
			has_points = true
			
	if not has_points: return Vector2.ZERO
	return (min_p + max_p) / 2.0

func _store_ghosts_from_clipboard():
	move_initial_data.clear()
	_clear_ghosts()
	
	for item in clipboard:
		var ghost = item.duplicate()
		_copy_custom_properties(item, ghost)
		
		ghost.modulate = Color(1, 1, 1, 0.6)
		ghost.set_meta("is_ghost", true)
		
		# Ajout au monde
		if active_entities_container:
			active_entities_container.add_child(ghost)
		active_ghosts.append(ghost)
		ghost.queue_redraw()
		
		# --- CORRECTION 1 : STOCKER GLOBAL_TRANS ---
		# _apply_preview_offset a besoin de "global_trans" pour fonctionner
		var data = {
			"global_trans": ghost.global_transform, # <--- AJOUT CRUCIAL
			"node_pos": ghost.position,        
			"center": Vector2.ZERO,
			"radius": 0.0,
			"target": Vector2.ZERO
		}
		
		if "is_circle" in ghost and ghost.is_circle:
			data["center"] = ghost.circle_center
			data["radius"] = ghost.circle_radius
		elif "is_arc" in ghost and ghost.is_arc:
			data["center"] = ghost.arc_center
			data["radius"] = ghost.arc_radius
			data["start_angle"] = ghost.arc_start_angle
			data["end_angle"] = ghost.arc_end_angle
		
		# --- CORRECTION 2 : UTILISER L'ID COMME CLÉ ---
		move_initial_data[ghost.get_instance_id()] = data

func apply_paste_from_clipboard(offset: Vector2):
	var count = 0
	if not active_entities_container:
		GlobalLogger.warning(tr("MSG_CONSOLE_ARC_1"))
		return
		
	var entities_root = active_entities_container 
	
	for item in clipboard:
		var new_obj = item.duplicate()
		_copy_custom_properties(item, new_obj)
		
		var target_node = entities_root 
		
		if item.has_meta("source_layer"):
			# --- CORRECTION ICI ---
			# On convertit le StringName en String classique avec str()
			var layer_name = str(item.get_meta("source_layer"))
			
			# Maintenant has_node() sera content car il reçoit une String
			if entities_root.has_node(layer_name):
				target_node = entities_root.get_node(layer_name)
				if "layer_name" in new_obj:
					new_obj.layer_name = layer_name
			else:
				GlobalLogger.warning("Calque '" + layer_name + "' introuvable. Collé à la racine.")
		# ----------------------
		
		target_node.add_child(new_obj)
		
		if new_obj.has_method("translate_entity"):
			new_obj.translate_entity(offset)
		else:
			new_obj.position += offset
			if "circle_center" in new_obj: new_obj.circle_center += offset
			if "arc_center" in new_obj: new_obj.arc_center += offset
			
		count += 1
	GlobalLogger.success("Collé " + str(count) + " objets.")

# --- FONCTIONS POUR L'HISTORIQUE (UNDO/REDO) ---

# Fonction générique pour déplacer une liste d'objets
func _action_move_entities(entities: Array, offset: Vector2):
	for ent in entities:
		if is_instance_valid(ent):
			ent.translate_entity(offset)

# Fonction pour MASQUER/RETIRER des objets (Action Supprimer)
func _action_remove_entities(data_list: Array):
	# data_list contient des dictionnaires { "node": objet, "parent": parent }
	for item in data_list:
		var ent = item["node"]
		var parent = item["parent"]
		if is_instance_valid(ent) and is_instance_valid(parent):
			# On vérifie s'il est encore dans l'arbre avant de l'enlever
			if ent.get_parent() == parent:
				parent.remove_child(ent)

	# On signale que la sélection a changé (car ils ne sont plus là)
	emit_signal("selection_changed", [])

# Fonction pour RESTAURER des objets (Action Annuler Supprimer)
func _action_restore_entities(data_list: Array):
	for item in data_list:
		var ent = item["node"]
		var parent = item["parent"]
		if is_instance_valid(ent) and is_instance_valid(parent):
			parent.add_child(ent)
			# On restaure aussi la sélection pour que l'utilisateur voit ce qui est revenu
			ent.set_selected(true)

	emit_signal("selection_changed", get_selected_entities_list())

# --- LOGIQUE MATHÉMATIQUE MIRROIR ---

func _reflect_point(pt: Vector2, axis_p1: Vector2, axis_p2: Vector2) -> Vector2:
	var axis = axis_p2 - axis_p1
	if axis.length_squared() < 0.001: return pt # Protection div par zero
	
	var axis_norm = axis.normalized()
	var to_pt = pt - axis_p1
	
	# Projection du vecteur AP sur l'axe
	var projection_length = to_pt.dot(axis_norm)
	var projected_point = axis_p1 + axis_norm * projection_length
	
	# Vecteur du point projeté vers le point réel
	var dist_vec = pt - projected_point
	
	# Le point symétrique est de l'autre côté : Projeté - Distance
	return projected_point - dist_vec

func _update_mirror_ghosts_preview(p1: Vector2, p2: Vector2):
	# Sécurité distance
	if p1.distance_squared_to(p2) < 0.001: return

	# 1. Création du repère local lié à l'axe de symétrie
	# L'axe X de ce repère est la ligne P1->P2
	var axis_angle = (p2 - p1).angle()
	var axis_transform = Transform2D(axis_angle, p1)

	# 2. Création de la matrice "Miroir" (Scale Y négatif)
	# Cela inverse tout ce qui est "au dessus" ou "en dessous" de l'axe X local
	var mirror_matrix = Transform2D.IDENTITY.scaled(Vector2(1, -1))

	for ghost in active_ghosts:
		var id = ghost.get_instance_id()
		if not move_initial_data.has(id): continue
		
		var data = move_initial_data[id]
		var original_transform = data["global_trans"]
		
		# --- LE CALCUL MATRICIEL ---
		
		# A. On passe l'objet dans le repère de l'axe (Localisation relative)
		var relative = axis_transform.affine_inverse() * original_transform
		
		# B. On applique la symétrie (Le Flip)
		var flipped_relative = mirror_matrix * relative
		
		# C. On remet le tout dans le monde (Global)
		var final_transform = axis_transform * flipped_relative
		
		# D. Application
		ghost.global_transform = final_transform
		
		# --- GESTION CERCLES ---
		if "is_circle" in ghost and ghost.is_circle:
			# Si cible visuelle globale (ex: poignée de rayon déportée)
			if data["target"] != Vector2.ZERO:
				var t_local = axis_transform.affine_inverse() * data["target"]
				# On applique le miroir sur le point local (Y inversé)
				t_local.y = -t_local.y 
				
			ghost.queue_redraw()
		else:
			ghost.queue_redraw()

func _finalize_mirror(erase_source: bool):
	var entities = get_selected_entities_list()
	if entities.is_empty(): 
		cancel_command()
		return
		
	# On nettoie la preview
	_revert_preview_positions()
	_clear_ghosts()
	
	# PREPARATION UNDO/REDO
	undo_redo.create_action("Mirroir")
	
	var created_objects = []
	var source_data = [] # Pour restauration si suppression
	
	for ent in entities:
		# 1. Calcul de la copie symétrique
		var copy = ent.duplicate()
		_copy_custom_properties(ent, copy)
		_apply_mirror_transform(copy, mirror_p1, mirror_p2)
		
		# On note le parent pour l'ajout
		var parent = ent.get_parent()
		created_objects.append({ "node": copy, "parent": parent })
		
		# Si on doit supprimer la source, on la stocke
		if erase_source:
			source_data.append({ "node": ent, "parent": parent })

	# ACTIONS DO/UNDO
	
	# DO : 
	# 1. Ajouter les copies
	undo_redo.add_do_method(_action_add_entities.bind(created_objects))
	# 2. Supprimer les sources (si demandé)
	if erase_source:
		undo_redo.add_do_method(_action_remove_entities.bind(source_data))
		
	# UNDO :
	# 1. Retirer les copies
	undo_redo.add_undo_method(_action_remove_entities.bind(created_objects))
	# 2. Restaurer les sources (si supprimées)
	if erase_source:
		undo_redo.add_undo_method(_action_restore_entities.bind(source_data))
		
	undo_redo.commit_action()
	
	if erase_source:
		GlobalLogger.success(tr("MSG_CONSOLE_MIRROR_5"))
		deselect_all() # Car les objets sélectionnés n'existent plus
	else:
		GlobalLogger.success(tr("MSG_CONSOLE_MIRROR_6"))
		cancel_command()

# Helper mathématique complet pour transfor mer l'objet final
func _apply_mirror_transform(ent: Node2D, p1: Vector2, p2: Vector2):
	if ent.is_circle:
		ent.circle_center = _reflect_point(ent.circle_center, p1, p2)
	elif ent is Line2D:
		# Pour une ligne, on doit refléter chaque point individuellement
		for i in range(ent.get_point_count()):
			var global_pt = ent.to_global(ent.points[i])
			var reflected_global = _reflect_point(global_pt, p1, p2)
			ent.set_point_position(i, ent.to_local(reflected_global))

# --- HELPERS UNDO REDO SUPPLÉMENTAIRES ---

func _action_add_entities(data_list: Array):
	for item in data_list:
		item["parent"].add_child(item["node"])
		# Copie des propriétés de persistance couleur si besoin
		if "default_color_val" in item["node"]:
			item["node"].default_color = item["node"].default_color_val
			item["node"].is_selected = false

# --- LOGIQUE ROTATION ---
# Fonction utilitaire mathématique
func _rotate_point_around_pivot(point: Vector2, pivot: Vector2, angle: float) -> Vector2:
	return pivot + (point - pivot).rotated(angle)

# Mise à jour VISUELLE (Fantômes ou Objets)
func _update_rotate_ghosts_preview(angle_diff):
	# On parcourt via les IDs stockés
	for id in move_initial_data.keys():
		var ent = instance_from_id(id)
		if not is_instance_valid(ent): continue
		
		var data = move_initial_data[id]
		var start_trans = data["global_trans"] # Transform initiale
		var start_pos = start_trans.origin
		var start_rot = start_trans.get_rotation()
		
		# IMPORTANT:
		# Les cercles/arcs stockent leurs données (centre/angles) en coordonnées MONDE.
		# Si on applique aussi une rotation au Node2D (global_transform), on double-rotat(e) la géométrie.
		# Donc:
		# - Lignes/polylignes: on transforme le Node2D (comme avant)
		# - Cercles/arcs: on garde le Node2D sur sa transform initiale et on modifie uniquement les données de géométrie
		if ("is_circle" in ent and ent.is_circle) or ("is_arc" in ent and ent.is_arc):
			ent.global_transform = start_trans
			
			if "is_circle" in ent and ent.is_circle:
				ent.circle_center = _rotate_point_around_pivot(data["center"], rotation_pivot, angle_diff)
				ent.circle_radius = data["radius"]
				if data.has("target") and data["target"] != Vector2.ZERO and data["target"] != Vector2.ZERO:
									ent._mark_dirty()
				ent.update_visuals()
				continue
			
			if "is_arc" in ent and ent.is_arc:
				var new_arc_center = _rotate_point_around_pivot(data["center"], rotation_pivot, angle_diff)
				var new_start_angle = data["start_angle"] + angle_diff
				var new_end_angle = data["end_angle"] + angle_diff
				
				ent.arc_center = new_arc_center
				ent.arc_radius = data["radius"]
				ent.arc_start_angle = new_start_angle
				ent.arc_end_angle = new_end_angle
				
				# Régénérer les points (utile pour certains outils basés sur points)
				var start_point = new_arc_center + Vector2(cos(new_start_angle), sin(new_start_angle)) * data["radius"]
				var end_point = new_arc_center + Vector2(cos(new_end_angle), sin(new_end_angle)) * data["radius"]
				var mid_angle = (new_start_angle + new_end_angle) / 2.0
				var middle_point = new_arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * data["radius"]
				var arc_info = ArcGeometry.three_points_to_arc(start_point, middle_point, end_point)
				if arc_info:
					ent.points = ArcGeometry.generate_arc_points(arc_info, 64)
				
				ent._mark_dirty()
				ent.update_visuals()
				continue
		
		# 1. Calcul de la nouvelle position par rapport au PIVOT
		# Formule : Pivot + (Vecteur Pivot->Objet).rotated(angle)
		var vec_from_pivot = start_pos - rotation_pivot
		ent.global_position = rotation_pivot + vec_from_pivot.rotated(angle_diff)
		
		# 2. Calcul de la nouvelle rotation
		ent.global_rotation = start_rot + angle_diff

# Helper Undo/Redo (Action Finale)
func _action_rotate_entities(entities: Array, pivot: Vector2, angle: float):
	for ent in entities:
		if is_instance_valid(ent):
			
			if "is_circle" in ent and ent.is_circle:
				# Rotation du CENTRE du cercle (coordonnées monde)
				ent.circle_center = _rotate_point_around_pivot(ent.circle_center, pivot, angle)
				ent._mark_dirty()
				ent.update_visuals()
			
			elif "is_arc" in ent and ent.is_arc:
				# Rotation de l'arc (coordonnées monde)
				var new_arc_center = _rotate_point_around_pivot(ent.arc_center, pivot, angle)
				var new_start_angle = ent.arc_start_angle + angle
				var new_end_angle = ent.arc_end_angle + angle
				
				ent.arc_center = new_arc_center
				ent.arc_start_angle = new_start_angle
				ent.arc_end_angle = new_end_angle
				
				var start_point = new_arc_center + Vector2(cos(new_start_angle), sin(new_start_angle)) * ent.arc_radius
				var end_point = new_arc_center + Vector2(cos(new_end_angle), sin(new_end_angle)) * ent.arc_radius
				var mid_angle = (new_start_angle + new_end_angle) / 2.0
				var middle_point = new_arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * ent.arc_radius
				var arc_info = ArcGeometry.three_points_to_arc(start_point, middle_point, end_point)
				if arc_info:
					ent.points = ArcGeometry.generate_arc_points(arc_info, 64)
				
				ent._mark_dirty()
				ent.update_visuals()
			
			else:
				# Rotation du NODE
				ent.position = _rotate_point_around_pivot(ent.position, pivot, angle)
				ent.rotation += angle

func apply_rotate_to_selection(angle_rad: float):
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	_revert_preview_positions() # On remet propre avant d'appliquer via UndoRedo
	
	undo_redo.create_action("Rotation")
	
	# On passe le pivot et l'angle
	undo_redo.add_do_method(_action_rotate_entities.bind(entities, rotation_pivot, angle_rad))
	undo_redo.add_undo_method(_action_rotate_entities.bind(entities, rotation_pivot, -angle_rad))
	
	undo_redo.commit_action()
	GlobalLogger.success(tr("MSG_CONSOLE_ROTATE_3"))


# Force la position target à être alignée horizontalement ou verticalement avec base
# Force le point 'target' à s'aligner si le mode Ortho est actif
func _apply_ortho_constraint(base: Vector2, target: Vector2) -> Vector2:
	var ortho_active = false
	
	# 1. Vérification du bouton UI "CheckOrtho" dans le snap_manager
	if snap_manager and snap_manager.has_node("CheckOrtho"):
		if snap_manager.get_node("CheckOrtho").button_pressed:
			ortho_active = true
			
	# 2. Override Clavier (Shift maintient temporairement l'ortho, ou l'inverse)
	# On peut décider que Shift inverse l'état du bouton, ou force l'activation.
	# Ici, je fais : Si Shift est appuyé, on force l'Ortho (comportement standard)
	if Input.is_key_pressed(KEY_SHIFT):
		ortho_active = true

	if ortho_active: 
		var diff = target - base
		# Si le mouvement est plus horizontal que vertical -> on force Y à base.y
		if abs(diff.x) > abs(diff.y):
			return Vector2(target.x, base.y) 
		else:
			return Vector2(base.x, target.y)
			
	return target

# --- NOUVELLES FONCTIONS LOGIQUES ECHELLE ---

func _scale_point_around_pivot(point: Vector2, pivot: Vector2, factor: float) -> Vector2:
	# Formule homothétie : P' = C + (P - C) * k
	return pivot + (point - pivot) * factor

func _update_scale_ghosts_preview(scale_ratio):
	if abs(scale_ratio) < 0.0001: return

	for id in move_initial_data.keys():
		var ent = instance_from_id(id)
		if not is_instance_valid(ent): continue
		
		var data = move_initial_data[id]
		var start_trans = data["global_trans"]
		var start_pos = start_trans.origin
		var start_scale = start_trans.get_scale()
		
		# IMPORTANT:
		# Cercles/arcs: leurs données de géométrie sont stockées en coordonnées MONDE.
		# Si on applique aussi un scale au Node2D, on double-applique l'échelle.
		# Donc on garde le Node2D sur sa transform initiale et on met à jour uniquement la géométrie.
		if ("is_circle" in ent and ent.is_circle) or ("is_arc" in ent and ent.is_arc):
			ent.global_transform = start_trans
			
			if "is_circle" in ent and ent.is_circle:
				ent.circle_center = _scale_point_around_pivot(data["center"], scale_pivot, scale_ratio)
				ent.circle_radius = data["radius"] * scale_ratio
				ent._mark_dirty()
				ent.update_visuals()
				continue
			
			if "is_arc" in ent and ent.is_arc:
				var new_arc_center = _scale_point_around_pivot(data["center"], scale_pivot, scale_ratio)
				var new_radius = data["radius"] * scale_ratio
				var new_start_angle = data["start_angle"]
				var new_end_angle = data["end_angle"]
				
				ent.arc_center = new_arc_center
				ent.arc_radius = new_radius
				ent.arc_start_angle = new_start_angle
				ent.arc_end_angle = new_end_angle
				
				var start_point = new_arc_center + Vector2(cos(new_start_angle), sin(new_start_angle)) * new_radius
				var end_point = new_arc_center + Vector2(cos(new_end_angle), sin(new_end_angle)) * new_radius
				var mid_angle = (new_start_angle + new_end_angle) / 2.0
				var middle_point = new_arc_center + Vector2(cos(mid_angle), sin(mid_angle)) * new_radius
				var arc_info = ArcGeometry.three_points_to_arc(start_point, middle_point, end_point)
				if arc_info:
					ent.points = ArcGeometry.generate_arc_points(arc_info, 64)
				
				ent._mark_dirty()
				ent.update_visuals()
				continue
		
		# 1. Calcul de la nouvelle position par rapport au PIVOT
		# L'objet s'éloigne ou se rapproche du pivot selon le ratio
		var vec_from_pivot = start_pos - scale_pivot
		ent.global_position = scale_pivot + (vec_from_pivot * scale_ratio)
		
		# 2. Mise à jour de l'échelle locale
		ent.scale = start_scale * scale_ratio
		
		# 3. Gestion Cercle
		if "is_circle" in ent and ent.is_circle:
			ent.circle_radius = data["radius"] * scale_ratio
			ent.queue_redraw()
		
		# 4. Gestion Arc
		elif "is_arc" in ent and ent.is_arc:
			# Mise à l'échelle du centre et du rayon
			var new_arc_center = _scale_point_around_pivot(data["center"], scale_pivot, scale_ratio)
			var new_radius = data["radius"] * scale_ratio
			# Les angles ne changent pas lors d'une mise à l'échelle uniforme
			ent.update_arc_properties(new_arc_center, new_radius, data["start_angle"], data["end_angle"])

func apply_scale_to_selection(factor: float):
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	_revert_preview_positions()
	
	undo_redo.create_action("Echelle")
	undo_redo.add_do_method(_action_scale_entities.bind(entities, scale_pivot, factor))
	# Undo : on applique l'inverse (1.0 / factor)
	if factor != 0:
		undo_redo.add_undo_method(_action_scale_entities.bind(entities, scale_pivot, 1.0 / factor))
	
	undo_redo.commit_action()

# Helper Undo/Redo
func _action_scale_entities(entities: Array, pivot: Vector2, factor: float):
	for ent in entities:
		if ("is_circle" in ent and ent.is_circle) or ("is_arc" in ent and ent.is_arc):
			# Mise à l'échelle du centre et du rayon
			ent.arc_center = _scale_point_around_pivot(ent.arc_center, pivot, factor)
			ent.arc_radius *= factor
			# Les angles ne changent pas lors d'une mise à l'échelle uniforme
			ent.update_arc_properties(ent.arc_center, ent.arc_radius, ent.arc_start_angle, ent.arc_end_angle)
			ent._mark_dirty()
			ent.update_visuals()
			
		elif ent is Line2D:
			# 1. Scale Node Position
			ent.position = _scale_point_around_pivot(ent.position, pivot, factor)
			# 2. Scale Internal Points
			for i in range(ent.get_point_count()):
				ent.points[i] *= factor

func _get_entity_under_mouse(pos: Vector2) -> Node2D:
	var aperture = 10.0 / camera.zoom.x
	
	# 1. Vérifier les objets physiques d'abord
	var entities = _get_all_flat_entities()
	for ent in entities:
		if ent.hit_test(pos, aperture):
			return ent
			
	# 2. Vérifier les objets virtuels
	var renderer = world.get_node_or_null("EntitiesRenderer") if world else null
	if renderer:
		var virtual_ent = renderer.get_entity_at_position(pos, aperture)
		if virtual_ent and not virtual_ent.is_hidden:
			# Extraire et le rendre physique pour que la commande Offset/Trim l'utilise!
			var unpacked_node = DXFBaker.unpack_entity(virtual_ent, world, renderer)
			if unpacked_node:
				unpacked_node.set_selected(true) # On le force en sélection pour que le rebake finisse par le re-cuire
				return unpacked_node
				
	return null

func _store_ghost_for_offset(ent: Node2D):
	move_initial_data.clear()
	_clear_ghosts()
	
	var ghost = _create_ghost_from_entity(ent)
	
	# On stocke les données brutes
	var data = { "node_pos": ent.position, "rotation": ent.rotation }
	
	if "is_circle" in ent and ent.is_circle:
		data["center"] = ent.circle_center
		data["radius"] = ent.circle_radius
	elif "is_arc" in ent and ent.is_arc:
		data["center"] = ent.arc_center
		data["radius"] = ent.arc_radius
		data["start_angle"] = ent.arc_start_angle
		data["end_angle"] = ent.arc_end_angle
	elif ent is Line2D:
		# IMPORTANT : On stocke les points originaux pour repartir de zéro à chaque frame
		data["points"] = ent.points.duplicate()
		
	move_initial_data[ent] = data
	active_ghosts.append(ghost) # On track le fantôme

func _update_offset_preview(mouse_pos: Vector2):
	if active_ghosts.is_empty(): return
	var ghost = active_ghosts[0]
	var original = offset_target_entity
	if not original: return
	
	var data = move_initial_data[original]
	
	# A. CERCLES
	if "is_circle" in original and original.is_circle:
		var center_global = original.circle_center # Supposé global ou ajusté
		if original.get_parent(): center_global += original.position # Si position relative
		
		var dist_mouse = center_global.distance_to(mouse_pos)
		var old_radius = data["radius"]
		var new_radius = old_radius
		
		if offset_mode == "VISUAL":
			new_radius = dist_mouse
		else:
			# Valeur fixe : on détermine si on agrandit ou rétrécit
			if dist_mouse < old_radius:
				new_radius = old_radius - offset_dist
			else:
				new_radius = old_radius + offset_dist
		
		ghost.circle_radius = max(0.001, new_radius)
		ghost.queue_redraw()
		
	# B. POLYLIGNES (Le gros morceau)
	elif "is_arc" in original and original.is_arc:
		var center_global = original.arc_center
		var dist_mouse = center_global.distance_to(mouse_pos)
		var old_radius = data["radius"]
		var new_radius = old_radius
		
		if offset_mode == "VISUAL":
			new_radius = dist_mouse
		else:
			if dist_mouse < old_radius:
				new_radius = old_radius - offset_dist
			else:
				new_radius = old_radius + offset_dist
		
		ghost.is_arc = true
		ghost.arc_center = center_global
		ghost.arc_radius = max(0.001, new_radius)
		ghost.arc_start_angle = data["start_angle"]
		ghost.arc_end_angle = data["end_angle"]
		if ghost.has_method("update_arc_properties"):
			ghost.update_arc_properties(ghost.arc_center, ghost.arc_radius, ghost.arc_start_angle, ghost.arc_end_angle)
		ghost.queue_redraw()
	
	elif original is Line2D:
		var raw_points = data["points"]
		if raw_points.size() < 2: return
		
		# 1. Déterminer le signe (Gauche/Droite)
		# On trouve le segment le plus proche de la souris pour savoir de quel coté on est
		var local_mouse = original.to_local(mouse_pos)
		var side_sign = _get_polyline_side(raw_points, local_mouse)
		
		var dist_to_apply = 0.0
		if offset_mode == "VISUAL":
			# Distance projetée sur la normale du segment le plus proche
			dist_to_apply = _get_distance_to_polyline(raw_points, local_mouse) * side_sign
		else:
			dist_to_apply = offset_dist * side_sign
			
		# 2. Calculer la nouvelle géométrie parallèle
		var new_points = _calculate_offset_polyline(raw_points, dist_to_apply)
		
		ghost.points = new_points
		ghost.queue_redraw()

func _finalize_offset(mouse_pos: Vector2):
	if not offset_target_entity or active_ghosts.is_empty(): return
	var ghost = active_ghosts[0]
	
	undo_redo.create_action("Decaler")
	
	var new_ent = offset_target_entity.duplicate()
	_copy_custom_properties(offset_target_entity, new_ent)
	
	if "is_circle" in new_ent and new_ent.is_circle:
		new_ent.circle_radius = ghost.circle_radius
	elif "is_arc" in new_ent and new_ent.is_arc:
		new_ent.arc_center = ghost.arc_center
		new_ent.arc_radius = ghost.arc_radius
		new_ent.arc_start_angle = ghost.arc_start_angle
		new_ent.arc_end_angle = ghost.arc_end_angle
		if new_ent.has_method("update_arc_properties"):
			new_ent.update_arc_properties(new_ent.arc_center, new_ent.arc_radius, new_ent.arc_start_angle, new_ent.arc_end_angle)
	elif new_ent is Line2D:
		new_ent.points = ghost.points.duplicate()
	
	new_ent.is_selected = false
	var parent = offset_target_entity.get_parent()
	undo_redo.add_do_method(parent.add_child.bind(new_ent))
	undo_redo.add_undo_method(parent.remove_child.bind(new_ent))
	undo_redo.commit_action()
	
	GlobalLogger.success(tr("MSG_CONSOLE_OFFSET_11"))
	_clear_ghosts()




# Détermine si la souris est à "Gauche" (+1) ou à "Droite" (-1) de la polyligne
func _get_polyline_side(points: PackedVector2Array, local_point: Vector2) -> float:
	var best_dist = INF
	var best_sign = 1.0
	
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i+1]
		var closest = Geometry2D.get_closest_point_to_segment(local_point, p1, p2)
		var d = local_point.distance_to(closest)
		
		if d < best_dist:
			best_dist = d
			# Produit vectoriel (Cross Product 2D) pour savoir le coté
			var vec_seg = p2 - p1
			var vec_pt = local_point - p1
			var cross = vec_seg.x * vec_pt.y - vec_seg.y * vec_pt.x
			best_sign = 1.0 if cross >= 0 else -1.0
			
	return best_sign

func _get_distance_to_polyline(points: PackedVector2Array, local_point: Vector2) -> float:
	var best_dist = INF
	for i in range(points.size() - 1):
		var closest = Geometry2D.get_closest_point_to_segment(local_point, points[i], points[i+1])
		var d = local_point.distance_to(closest)
		if d < best_dist: best_dist = d
	return best_dist

# ALGORITHME DE DÉCALAGE DE POLYLIGNE (MITER OFFSET)
func _calculate_offset_polyline(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var new_pts = PackedVector2Array()
	var count = points.size()
	
	# Pour chaque point, on calcule la normale moyenne (Miter)
	for i in range(count):
		var p_curr = points[i]
		var tangent = Vector2.ZERO
		
		# Vecteur Arrivée (p_prev -> p_curr)
		var v_in = Vector2.ZERO
		if i > 0:
			v_in = (p_curr - points[i-1]).normalized()
			
		# Vecteur Départ (p_curr -> p_next)
		var v_out = Vector2.ZERO
		if i < count - 1:
			v_out = (points[i+1] - p_curr).normalized()
			
		# Cas Extrémités (Ligne ouverte)
		if i == 0:
			tangent = v_out
		elif i == count - 1:
			tangent = v_in
		else:
			# Sommet interne : Moyenne des vecteurs
			tangent = (v_in + v_out).normalized()
		
		# Normale (Perpendiculaire)
		# Godot 2D : (-y, x) est la normale "Gauche" standard
		var normal = Vector2(-tangent.y, tangent.x)
		
		# Ajustement Miter (Pour les coins pointus)
		var miter_len = distance
		if i > 0 and i < count - 1:
			# Produit scalaire pour trouver l'angle
			# Normal du segment entrant
			var n_in = Vector2(-v_in.y, v_in.x)
			# Le vecteur Miter est la bissectrice.
			# Longueur = distance / dot(miter_dir, n_in)
			# Simplification robuste :
			var cross = v_in.x * v_out.y - v_in.y * v_out.x
			if abs(cross) > 0.001: # Si ce n'est pas plat
				# Calcul du vecteur miter exact
				var miter = (Vector2(-v_in.y, v_in.x) + Vector2(-v_out.y, v_out.x)).normalized()
				var dot = miter.dot(Vector2(-v_in.y, v_in.x))
				if abs(dot) > 0.01:
					miter_len = distance / dot
		
		# Limiter la longueur des pointes extrêmes (optionnel mais recommandé)
		if abs(miter_len) > abs(distance) * 5.0:
			miter_len = distance * 5.0 * sign(miter_len)

		new_pts.append(p_curr + normal * miter_len)
		
	return new_pts


# --- GESTION PROPRIÉTÉS ---

func set_current_linetype(type_name: String):
	var entities = get_selected_entities_list()
	if entities.is_empty(): 
		GlobalLogger.info("Aucune sélection. Le prochain objet sera : " + type_name)
		# TODO: Dire au DrawingManager de changer le défaut
		return
		
	undo_redo.create_action("Changer Type Ligne")
	undo_redo.add_do_method(_action_set_property_and_emit.bind(entities, "linetype", type_name))
	
	# Pour le Undo, on doit stocker l'état précédent de chaque objet.
	# Simplification : On suppose qu'ils avaient "ByLayer" ou l'ancien état.
	# Idéalement, il faudrait une fonction _action_restore_properties, mais faisons simple :
	# On triche un peu pour le Undo en remettant "ByLayer" ou on accepte que le Undo soit partiel ici pour l'instant.
	# Pour bien faire, il faudrait lire la valeur actuelle de chaque entité.
	
	# Approche robuste Undo : On capture les anciennes valeurs
	var old_values = []
	for ent in entities:
		old_values.append(ent.linetype)
	undo_redo.add_undo_method(_action_restore_property_list_and_emit.bind(entities, "linetype", old_values))
	
	undo_redo.commit_action()
	GlobalLogger.success("Type de ligne appliqué : " + type_name)

func set_current_lineweight(weight: float):
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	undo_redo.create_action("Changer Epaisseur")
	undo_redo.add_do_method(_action_set_property_and_emit.bind(entities, "lineweight", weight))
	
	var old_values = []
	for ent in entities:
		old_values.append(ent.lineweight)
	undo_redo.add_undo_method(_action_restore_property_list_and_emit.bind(entities, "lineweight", old_values))
	
	undo_redo.commit_action()
	GlobalLogger.success("Épaisseur appliquée : " + str(weight))

func set_current_layer(layer_name: String):
	var entities = get_selected_entities_list()
	if entities.is_empty(): 
		GlobalLogger.info("Aucune sélection. Le prochain objet sera sur : " + layer_name)
		return
	
	undo_redo.create_action("Changer Calque")
	undo_redo.add_do_method(_action_set_property_and_emit.bind(entities, "layer_name", layer_name))
	
	var old_values = []
	for ent in entities:
		old_values.append(ent.layer_name)
	undo_redo.add_undo_method(_action_restore_property_list_and_emit.bind(entities, "layer_name", old_values))
	
	undo_redo.commit_action()
	GlobalLogger.success("Calque appliqué : " + layer_name)


# --- HELPERS PROPRIETES ---

func _action_set_property(entities: Array, property_name: String, value):
	for ent in entities:
		if is_instance_valid(ent):
			ent.set(property_name, value)
			# APPEL CRUCIAL pour recalculer le shader ou la visibilité
			if ent.has_method("update_visuals"):
				ent.update_visuals() 
			ent.queue_redraw()

func _action_set_property_and_emit(entities: Array, property_name: String, value):
	for ent in entities:
		if is_instance_valid(ent):
			ent.set(property_name, value)
			# APPEL CRUCIAL pour recalculer le shader ou la visibilité
			if ent.has_method("update_visuals"):
				ent.update_visuals() 
			ent.queue_redraw()
	
	# Émettre le signal pour synchroniser l'UI
	emit_signal("selection_changed", entities)
	
	# Si on change le calque, on informe le LayerManager pour qu'il déplace l'entité
	if property_name == "layer_name" and layer_manager:
		for ent in entities:
			if is_instance_valid(ent):
				layer_manager.move_entity_to_layer_by_name(ent, value)

func _action_restore_property_list(entities: Array, property_name: String, old_values: Array):
	for i in range(entities.size()):
		var ent = entities[i]
		if is_instance_valid(ent):
			ent.set(property_name, old_values[i])
			if ent.has_method("update_visuals"):
				ent.update_visuals()
			ent.queue_redraw()

func _action_restore_property_list_and_emit(entities: Array, property_name: String, old_values: Array):
	for i in range(entities.size()):
		var ent = entities[i]
		if is_instance_valid(ent):
			ent.set(property_name, old_values[i])
			if ent.has_method("update_visuals"):
				ent.update_visuals()
			ent.queue_redraw()
	
	# Émettre le signal pour synchroniser l'UI
	emit_signal("selection_changed", entities)

func _is_mouse_near_entity(ent, mouse_pos: Vector2, margin: float) -> bool:
	# Cas Cercle
	if ent.get("is_circle"):
		var c = ent.position # Position du Node
		if "circle_center" in ent: c += ent.circle_center # Ajout du centre local
		var r = ent.circle_radius
		return c.distance_squared_to(mouse_pos) < (r + margin) ** 2

	# Cas Polyligne
	elif "points" in ent and ent.points.size() > 0:
		var local_mouse = ent.to_local(mouse_pos)
		
		# Bounding Box rapide
		var min_x = ent.points[0].x
		var max_x = ent.points[0].x
		var min_y = ent.points[0].y
		var max_y = ent.points[0].y
		
		for p in ent.points:
			if p.x < min_x: min_x = p.x
			if p.x > max_x: max_x = p.x
			if p.y < min_y: min_y = p.y
			if p.y > max_y: max_y = p.y
			
		var rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		return rect.grow(margin).has_point(local_mouse)
		
	return false


# --- API PROPRIÉTÉS GÉNÉRIQUES (POUR LE PROPERTIES PANEL) ---

func modify_selection_property(property_name: String, value):
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	undo_redo.create_action("Modifier Propriété")
	
	# DO : Appliquer la nouvelle valeur
	undo_redo.add_do_method(_action_set_property_and_emit.bind(entities, property_name, value))
	
	# UNDO : Restaurer les anciennes valeurs (Individuel par objet)
	var old_values = []
	for ent in entities:
		old_values.append(ent.get(property_name))
		
	undo_redo.add_undo_method(_action_restore_property_list_and_emit.bind(entities, property_name, old_values))
	
	undo_redo.commit_action()
	GlobalLogger.info("Propriété modifiée : " + property_name)

func modify_selection_geometry(axis: String, value: float):
	var entities = get_selected_entities_list()
	if entities.is_empty(): return
	
	# Note : Pour l'instant, on ne gère la géométrie via le panneau que pour 1 seul objet
	if entities.size() > 1: return
	var ent = entities[0]
	
	undo_redo.create_action("Modifier Géométrie")
	
	# On capture l'état avant modif pour le Undo
	var old_state = _capture_entity_geometry(ent)
	
	# On définit l'action DO
	undo_redo.add_do_method(_action_apply_geometry_change.bind(ent, axis, value))
	
	# On définit l'action UNDO
	undo_redo.add_undo_method(_action_restore_geometry.bind(ent, old_state))
	
	undo_redo.commit_action()

# --- FONCTIONS SPÉCIFIQUES POLYLIGNE ---

func modify_polyline_vertex(polyline: Line2D, vertex_index: int, new_local_pos: Vector2):
	if vertex_index < 0 or vertex_index >= polyline.points.size(): return
	
	undo_redo.create_action("Modifier Sommet Polyligne")
	
	# Capturer l'ancienne position
	var old_pos = polyline.points[vertex_index]
	
	# Action DO
	undo_redo.add_do_method(_action_set_polyline_vertex.bind(polyline, vertex_index, new_local_pos))
	
	# Action UNDO
	undo_redo.add_undo_method(_action_set_polyline_vertex.bind(polyline, vertex_index, old_pos))
	
	undo_redo.commit_action()
	
	# Émettre le signal pour mettre à jour l'UI
	emit_signal("selection_changed", get_selected_entities_list())

func toggle_polyline_closed(polyline: Line2D, should_close: bool):
	if polyline.points.size() < 3: return
	
	undo_redo.create_action("Fermer/Ouvrir Polyligne")
	
	# Capturer l'état actuel
	var old_points = polyline.points.duplicate()
	
	# Action DO
	undo_redo.add_do_method(_action_toggle_polyline_closed.bind(polyline, should_close))
	
	# Action UNDO
	undo_redo.add_undo_method(_action_restore_polyline_points.bind(polyline, old_points))
	
	undo_redo.commit_action()
	
	# Émettre le signal pour mettre à jour l'UI
	emit_signal("selection_changed", get_selected_entities_list())

# --- FONCTIONS SPÉCIFIQUES CERCLE ---

func modify_circle_center(circle, new_local_center: Vector2):
	undo_redo.create_action("Modifier Centre Cercle")
	
	# Capturer l'ancien centre
	var old_center = circle.circle_center
	
	# Action DO
	undo_redo.add_do_method(_action_set_circle_center.bind(circle, new_local_center))
	
	# Action UNDO
	undo_redo.add_undo_method(_action_set_circle_center.bind(circle, old_center))
	
	undo_redo.commit_action()
	
	# Émettre le signal pour mettre à jour l'UI
	emit_signal("selection_changed", get_selected_entities_list())

func modify_circle_radius(circle, new_radius: float):
	undo_redo.create_action("Modifier Rayon Cercle")
	
	# Capturer l'ancien rayon
	var old_radius = circle.circle_radius
	
	# Action DO
	undo_redo.add_do_method(_action_set_circle_radius.bind(circle, new_radius))
	
	# Action UNDO
	undo_redo.add_undo_method(_action_set_circle_radius.bind(circle, old_radius))
	
	undo_redo.commit_action()
	
	# Émettre le signal pour mettre à jour l'UI
	emit_signal("selection_changed", get_selected_entities_list())

# Helper pour capturer l'état géométrique (Undo)
func _capture_entity_geometry(ent):
	if "is_circle" in ent and ent.is_circle:
		var data := {
			"kind": "CIRCLE",
			"pos": ent.position,
			"center": ent.circle_center,
			"radius": ent.circle_radius,
			"target": Vector2.ZERO
		}
		return data
	if "is_arc" in ent and ent.is_arc:
		var data := {
			"kind": "ARC",
			"pos": ent.position,
			"center": ent.arc_center,
			"radius": ent.arc_radius,
			"start_angle": ent.arc_start_angle,
			"end_angle": ent.arc_end_angle,
			"ccw": true,
			"points": ent.points.duplicate() if (ent is Line2D) else PackedVector2Array()
		}
		return data
	if ent is Line2D:
		return { "kind": "POLYLINE", "pos": ent.position, "points": ent.points.duplicate() }
	return { "kind": "UNKNOWN" }

# Helper pour appliquer le changement (Do)
func _action_apply_geometry_change(ent, axis, value):
	if "is_circle" in ent and ent.is_circle:
		# On calcule la position GLOBALE actuelle
		var global_pos = ent.position + ent.circle_center
		
		if axis == "x":
			# On déplace le noeud ou le centre ?
			# Simplification : On déplace le cercle entier pour que son centre soit à X
			var diff = value - global_pos.x
			ent.position.x += diff
		elif axis == "y":
			var diff = value - global_pos.y
			ent.position.y += diff
		elif axis == "radius":
			ent.circle_radius = value
			
	elif ent is Line2D:
		# Pour une ligne, changer X/Y du "Départ" signifie déplacer toute la ligne
		if ent.points.size() > 0:
			var start_global = ent.to_global(ent.points[0])
			if axis == "x":
				var diff = value - start_global.x
				ent.position.x += diff
			elif axis == "y":
				var diff = value - start_global.y
				ent.position.y += diff
	
	if ent.has_method("update_visuals"): ent.update_visuals()
	ent.queue_redraw()

func _trim_norm_angle(a: float) -> float:
	return fposmod(a, TAU)

func _trim_angle_ccw(a: float, b: float) -> float:
	return fposmod(b - a, TAU)

func _trim_is_angle_in_ccw_interval(x: float, a: float, b: float, eps: float = 0.0001) -> bool:
	var ab = _trim_angle_ccw(a, b)
	var ax = _trim_angle_ccw(a, x)
	return ax <= ab + eps

func _trim_choose_closest_point(points: Array, ref: Vector2) -> Variant:
	if points.is_empty():
		return null
	var best = points[0]
	var best_d = best.distance_squared_to(ref)
	for p in points:
		var d = p.distance_squared_to(ref)
		if d < best_d:
			best_d = d
			best = p
	return best

func _trim_dedupe_sorted_floats(vals: Array, eps: float = 0.0005) -> Array:
	if vals.is_empty():
		return []
	var out: Array = [vals[0]]
	for i in range(1, vals.size()):
		if abs(vals[i] - out[out.size() - 1]) > eps:
			out.append(vals[i])
	return out

func _trim_collect_cut_points_world(target: Node2D) -> Array:
	var pts: Array = []
	var entities = _get_all_flat_entities()
	for other in entities:
		if other == target:
			continue
		if not is_instance_valid(other):
			continue
		if other.has_meta("is_ghost"):
			continue
		if other.get("is_point") and other.is_point:
			continue
		
		var inter = snap_manager._get_intersections(target, other)
		for p in inter:
			pts.append(p)
	
	return pts

func _trim_make_fence_line() -> Line2D:
	var fence_line = Line2D.new()
	fence_line.points = [trim_fence_start, trim_fence_end]
	return fence_line

func _action_add_child(parent: Node, child: Node):
	if is_instance_valid(parent) and is_instance_valid(child):
		if child.get_parent() != parent:
			parent.add_child(child)

func _action_remove_child(parent: Node, child: Node):
	if is_instance_valid(parent) and is_instance_valid(child):
		if child.get_parent() == parent:
			parent.remove_child(child)

func _trim_build_arc_geom_data(ent: Node2D, center_local: Vector2, radius: float, start_angle: float, end_angle: float) -> Dictionary:
	# Important: CADEntity.update_arc_properties suppose un interval CCW avec end_angle >= start_angle
	var sa = start_angle
	var ea = end_angle
	if ea < sa:
		ea += TAU
	return {
		"kind": "ARC",
		"pos": ent.position,
		"center": center_local,
		"radius": radius,
		"start_angle": start_angle,
		"end_angle": ea,
		"ccw": true,
		"points": PackedVector2Array()
	}

func _trim_lift_angle_into_range(angle: float, start_angle: float, end_angle: float) -> float:
	var a = fposmod(angle, TAU)
	while a < start_angle:
		a += TAU
	while a > end_angle:
		a -= TAU
	return a

func _trim_build_polyline_geom_data(ent: Line2D, points: PackedVector2Array) -> Dictionary:
	return {
		"kind": "POLYLINE",
		"pos": ent.position,
		"points": points
	}

func _trim_polyline_total_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total

func _trim_polyline_param_for_world_point(polyline: Line2D, p_world: Vector2, tol: float = 1.0) -> float:
	var local_p = polyline.to_local(p_world)
	var best_s := -1.0
	var best_d := INF
	var acc := 0.0
	for i in range(polyline.points.size() - 1):
		var a = polyline.points[i]
		var b = polyline.points[i + 1]
		var seg_len = a.distance_to(b)
		if seg_len < 0.0001:
			continue
		var closest = Geometry2D.get_closest_point_to_segment(local_p, a, b)
		var d = closest.distance_to(local_p)
		if d < best_d:
			best_d = d
			var t = a.distance_to(closest) / seg_len
			best_s = acc + seg_len * clamp(t, 0.0, 1.0)
		acc += seg_len
	if best_s < 0.0:
		return -1.0
	if best_d > tol:
		return -1.0
	return best_s

func _trim_polyline_piece(points: PackedVector2Array, s_from: float, s_to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if s_to - s_from < 0.0005:
		return out
	var acc := 0.0
	var started := false
	for i in range(points.size() - 1):
		var a = points[i]
		var b = points[i + 1]
		var seg_len = a.distance_to(b)
		if seg_len < 0.0001:
			continue
		var seg_start = acc
		var seg_end = acc + seg_len
		if seg_end < s_from - 0.0005:
			acc = seg_end
			continue
		if seg_start > s_to + 0.0005:
			break
		var t0 := 0.0
		var t1 := 1.0
		if s_from > seg_start:
			t0 = (s_from - seg_start) / seg_len
		if s_to < seg_end:
			t1 = (s_to - seg_start) / seg_len
		t0 = clamp(t0, 0.0, 1.0)
		t1 = clamp(t1, 0.0, 1.0)
		var p0 = a.lerp(b, t0)
		var p1 = a.lerp(b, t1)
		if not started:
			out.append(p0)
			started = true
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p1) > 0.0001:
			out.append(p1)
		if s_to <= seg_end + 0.0005:
			break
		acc = seg_end
	return out

func _trim_build_operation(ent: Node2D, fence_line: Line2D) -> Dictionary:
	var original_data = _capture_entity_geometry(ent)
	var fence_inters = snap_manager._get_intersections(ent, fence_line)
	
	if fence_inters.is_empty():
		return {}
	var pick_ref = trim_fence_end
	var pick_point = _trim_choose_closest_point(fence_inters, pick_ref)
	if pick_point == null:
		return {}
	
	if ent.get("is_circle") and ent.is_circle:
		var center_world = ent.global_position + ent.circle_center
		var cut_pts = _trim_collect_cut_points_world(ent)
		
		var angles: Array = []
		for p in cut_pts:
			var angle = _trim_norm_angle((p - center_world).angle())
			angles.append(angle)
		
		angles.sort()
		angles = _trim_dedupe_sorted_floats(angles)
		
		if angles.size() >= 2 and abs((angles[0] + TAU) - angles[angles.size() - 1]) < 0.0005:
			angles.pop_back()
		
		if angles.size() < 2:
			return {}
		var x = _trim_norm_angle((pick_point - center_world).angle())
		for i in range(angles.size()):
			var a = angles[i]
			var b = angles[(i + 1) % angles.size()]
			if _trim_is_angle_in_ccw_interval(x, a, b):
				var sa = b
				var ea = b + _trim_angle_ccw(b, a)
				var do_geom = _trim_build_arc_geom_data(ent, ent.circle_center, ent.circle_radius, sa, ea)
				return {
					"do_geom": do_geom,
					"undo_geom": original_data
				}
		return {}
	
	if ent.get("is_arc") and ent.is_arc:
		var center_world = ent.global_position + ent.arc_center
		var start_a = fposmod(ent.arc_start_angle, TAU)
		var end_a = fposmod(ent.arc_end_angle, TAU)
		if end_a < start_a:
			end_a += TAU
		
		var pick_raw = (pick_point - center_world).angle()
		var pick_a = _trim_lift_angle_into_range(pick_raw, start_a, end_a)
		
		if pick_a < start_a - 0.0005 or pick_a > end_a + 0.0005:
			GlobalLogger.debug("TRIM ARC: pick hors arc (start=" + str(start_a) + " end=" + str(end_a) + " pick=" + str(pick_a) + ")")
			return {}
		
		var cut_pts = _trim_collect_cut_points_world(ent)
		var bounds: Array = [start_a]
		
		for p in cut_pts:
			var a = _trim_lift_angle_into_range((p - center_world).angle(), start_a, end_a)
			bounds.append(a)
		
		bounds.sort()
		bounds = _trim_dedupe_sorted_floats(bounds)
		bounds.append(end_a)
		
		for i in range(bounds.size() - 1):
			var a0 = bounds[i]
			var a1 = bounds[i + 1]
			if pick_a >= a0 - 0.0005 and pick_a <= a1 + 0.0005:
				var left_len = a0 - start_a
				var right_len = end_a - a1
				
				if left_len < 0.0005 and right_len < 0.0005:
					GlobalLogger.debug("TRIM ARC: rien à couper (bounds=" + str(bounds) + ")")
					# Debug ciblé: comprendre pourquoi on n'a que start/end comme bornes
					var entities = _get_all_flat_entities()
					for other in entities:
						if other == ent:
							continue
						if not is_instance_valid(other):
							continue
						if other.has_meta("is_ghost"):
							continue
						if other.get("is_point") and other.is_point:
							continue
						if (other.get("is_arc") and other.is_arc) or (other.get("is_circle") and other.is_circle):
							var inter_dbg = snap_manager._get_intersections(ent, other)
							if not inter_dbg.is_empty():
								GlobalLogger.debug("TRIM ARC: intersections avec obj circlelike=" + str(inter_dbg.size()))
					return {}
				if left_len < 0.0005:
					var do_geom = _trim_build_arc_geom_data(ent, ent.arc_center, ent.arc_radius, a1, end_a)
					return { "do_geom": do_geom, "undo_geom": original_data }
				if right_len < 0.0005:
					var do_geom = _trim_build_arc_geom_data(ent, ent.arc_center, ent.arc_radius, start_a, a0)
					return { "do_geom": do_geom, "undo_geom": original_data }
				
				var do_geom = _trim_build_arc_geom_data(ent, ent.arc_center, ent.arc_radius, start_a, a0)
				var new_ent = ent.duplicate()
				_copy_custom_properties(ent, new_ent)
				new_ent.is_selected = false
				var new_geom = _trim_build_arc_geom_data(new_ent, ent.arc_center, ent.arc_radius, a1, end_a)
				return {
					"do_geom": do_geom,
					"undo_geom": original_data,
					"new_ent": new_ent,
					"new_parent": ent.get_parent(),
					"new_do_geom": new_geom
				}
		
		GlobalLogger.debug("TRIM ARC: aucun intervalle trouvé (start=" + str(start_a) + " end=" + str(end_a) + " pick=" + str(pick_a) + " bounds=" + str(bounds) + ")")
		return {}
	
	if ent is Line2D and ent.points.size() >= 2:
		var pick_s = _trim_polyline_param_for_world_point(ent, pick_point, 1.0)
		if pick_s < 0.0:
			return {}
		var total = _trim_polyline_total_length(ent.points)
		var cut_pts = _trim_collect_cut_points_world(ent)
		var s_vals: Array = []
		for p in cut_pts:
			var s = _trim_polyline_param_for_world_point(ent, p, 1.0)
			if s >= 0.0:
				s_vals.append(s)
		s_vals.append(0.0)
		s_vals.append(total)
		s_vals.sort()
		s_vals = _trim_dedupe_sorted_floats(s_vals)
		for i in range(s_vals.size() - 1):
			var s0 = s_vals[i]
			var s1 = s_vals[i + 1]
			if pick_s >= s0 - 0.0005 and pick_s <= s1 + 0.0005:
				var prefix = _trim_polyline_piece(ent.points, 0.0, s0)
				var suffix = _trim_polyline_piece(ent.points, s1, total)
				var prefix_ok = prefix.size() >= 2
				var suffix_ok = suffix.size() >= 2
				if not prefix_ok and not suffix_ok:
					return {}
				if prefix_ok and not suffix_ok:
					var do_geom = _trim_build_polyline_geom_data(ent, prefix)
					return { "do_geom": do_geom, "undo_geom": original_data }
				if suffix_ok and not prefix_ok:
					var do_geom = _trim_build_polyline_geom_data(ent, suffix)
					return { "do_geom": do_geom, "undo_geom": original_data }
				var do_geom = _trim_build_polyline_geom_data(ent, prefix)
				var new_ent = ent.duplicate()
				_copy_custom_properties(ent, new_ent)
				new_ent.is_selected = false
				var new_geom = _trim_build_polyline_geom_data(new_ent, suffix)
				return {
					"do_geom": do_geom,
					"undo_geom": original_data,
					"new_ent": new_ent,
					"new_parent": ent.get_parent(),
					"new_do_geom": new_geom
				}
		return {}
	
	return {}

# Helper pour restaurer (Undo)
func _action_restore_geometry(ent, data):
	var kind = data.get("kind", "")
	if kind == "CIRCLE":
		ent.position = data.get("pos", ent.position)
		if "is_circle" in ent: ent.is_circle = true
		if "is_arc" in ent: ent.is_arc = false
		if "is_point" in ent: ent.is_point = false
		ent.circle_center = data.get("center", ent.circle_center)
		ent.circle_radius = data.get("radius", ent.circle_radius)
		if ent.has_method("_mark_dirty"): ent._mark_dirty()
		if ent.has_method("update_visuals"): ent.update_visuals()
		ent.queue_redraw()
		return
	
	if kind == "ARC":
		ent.position = data.get("pos", ent.position)
		if "is_arc" in ent: ent.is_arc = true
		if "is_circle" in ent: ent.is_circle = false
		if "is_point" in ent: ent.is_point = false
		ent.arc_center = data.get("center", ent.arc_center)
		ent.arc_radius = data.get("radius", ent.arc_radius)
		ent.arc_start_angle = data.get("start_angle", ent.arc_start_angle)
		ent.arc_end_angle = data.get("end_angle", ent.arc_end_angle)
		if ent.has_method("update_arc_properties"):
			ent.update_arc_properties(ent.arc_center, ent.arc_radius, ent.arc_start_angle, ent.arc_end_angle)
		elif ent is Line2D and data.has("points"):
			ent.points = data.get("points", ent.points)
		if ent.has_method("_mark_dirty"): ent._mark_dirty()
		if ent.has_method("update_visuals"): ent.update_visuals()
		ent.queue_redraw()
		return
	
	if ent is Line2D and kind == "POLYLINE":
		ent.position = data.get("pos", ent.position)
		if "is_circle" in ent: ent.is_circle = false
		if "is_arc" in ent: ent.is_arc = false
		if "is_point" in ent: ent.is_point = false
		ent.points = data.get("points", ent.points)
		if ent.has_method("update_visuals"): ent.update_visuals()
		ent.queue_redraw()
		return
	
	if ent.has_method("update_visuals"): ent.update_visuals()
	ent.queue_redraw()

func _create_point(position: Vector2):
	# Créer un vrai point avec le nouveau type d'objet
	var point = Line2D.new()
	point.set_script(CADEntityScript)
	
	# Configurer comme point
	point.is_point = true
	point.point_size = 5.0
	point.point_style = "CROSS"  # Par défaut, mais peut être changé
	
	# Pas de points pour un Line2D normal (le dessin se fait dans _draw_standard_point)
	point.points = PackedVector2Array()
	
	# Ajouter au calque actif
	if layer_manager:
		var layer_node = layer_manager.get_active_layer_node()
		var layer_data = layer_manager.get_active_layer_data()
		
		if layer_node:
			# Positionner le point (la position est en coordonnées mondiales)
			layer_node.add_child(point)
			point.global_position = position
			
			# Configurer les propriétés
			point.layer_name = layer_data.name
			point.linetype = "ByLayer"
			point.lineweight = -1.0
			point.default_color_val = Color.WHITE
			point.update_visuals()
			
			GlobalLogger.success("Point créé à " + str(position))
		else:
			GlobalLogger.error("Calque actif non trouvé")
	else:
		GlobalLogger.error("LayerManager non trouvé")

# --- FONCTIONS TRIM (AJUSTER) ---

func _find_objects_crossed_by_fence():
	trim_objects.clear()
	
	# Créer une ligne temporaire pour la fence
	var fence_line = Line2D.new()
	fence_line.points = [trim_fence_start, trim_fence_end]
	
	# Parcourir tous les objets dans la scène
	var all_entities = _get_all_flat_entities()
	for ent in all_entities:
		if not is_instance_valid(ent):
			continue
		
		# Vérifier si l'objet est traversé par la fence
		if _is_entity_crossed_by_line(ent, fence_line):
			trim_objects.append(ent)
	
	# Nettoyer la ligne temporaire
	fence_line.queue_free()

func _is_entity_crossed_by_line(entity, line):
	# Pour les cercles et arcs
	if entity.get("is_circle") and entity.is_circle:
		return _line_intersects_circle(line, entity)
	elif entity.get("is_arc") and entity.is_arc:
		return _line_intersects_arc(line, entity)
	# Pour les polylignes
	elif entity is Line2D and entity.points.size() >= 2:
		return _line_intersects_polyline(line, entity)
	
	return false

func _line_intersects_circle(line, circle):
	var center = circle.global_position + circle.circle_center
	var radius = circle.circle_radius
	
	# Distance du centre à la ligne
	var p1 = line.points[0]
	var p2 = line.points[1]
	
	var line_vec = p2 - p1
	var center_vec = center - p1
	
	var line_len_sq = line_vec.length_squared()
	if line_len_sq == 0:
		var dist = center.distance_to(p1)
		return dist <= radius
	
	var t = max(0, min(1, center_vec.dot(line_vec) / line_len_sq))
	var closest_point = p1 + t * line_vec
	var dist = center.distance_to(closest_point)
	
	return dist <= radius

func _line_intersects_arc(line, arc):
	# Essayer d'abord avec les intersections précises
	var inters = snap_manager._get_intersections(arc, line)
	if not inters.is_empty():
		# Vérifier qu'au moins une intersection est sur le segment de fence
		var p1 = line.points[0]
		var p2 = line.points[1]
		
		for inter in inters:
			# Vérifier si le point d'intersection est sur le segment de fence
			var t = _get_parameter_on_segment(p1, p2, inter)
			if t >= 0.0 and t <= 1.0:
				return true
	
	# Fallback: utiliser la logique de distance (comme pour les cercles)
	# pour éviter la régression quand snap_manager échoue
	return _line_intersects_circle(line, arc)

func _get_parameter_on_segment(p1, p2, point):
	var seg_vec = p2 - p1
	var seg_len_sq = seg_vec.length_squared()
	if seg_len_sq == 0:
		return 0.0
	var point_vec = point - p1
	return point_vec.dot(seg_vec) / seg_len_sq

func _line_intersects_polyline(line, polyline):
	var p1 = line.points[0]
	var p2 = line.points[1]
	
	# Vérifier l'intersection avec chaque segment de la polyligne
	for i in range(polyline.points.size() - 1):
		var seg_start = polyline.to_global(polyline.points[i])
		var seg_end = polyline.to_global(polyline.points[i + 1])
		
		if _segments_intersect(p1, p2, seg_start, seg_end):
			return true
	
	return false

func _segments_intersect(p1, p2, p3, p4):
	var d1 = _orientation(p3, p4, p1)
	var d2 = _orientation(p3, p4, p2)
	var d3 = _orientation(p1, p2, p3)
	var d4 = _orientation(p1, p2, p4)
	
	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
		return true
	
	if d1 == 0 and _on_segment(p3, p4, p1): return true
	if d2 == 0 and _on_segment(p3, p4, p2): return true
	if d3 == 0 and _on_segment(p1, p2, p3): return true
	if d4 == 0 and _on_segment(p1, p2, p4): return true
	
	return false

func _orientation(p, q, r):
	return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)

func _on_segment(p, q, r):
	return r.x >= min(p.x, q.x) and r.x <= max(p.x, q.x) and r.y >= min(p.y, q.y) and r.y <= max(p.y, q.y)

func execute_trim():
	# Cette fonction n'est plus utilisée avec le mode fence
	pass

func execute_trim_fence():
	if trim_objects.is_empty():
		GlobalLogger.info("AJUSTER : Aucun objet traversé par la ligne de coupe.")
		return
	
	var fence_line = _trim_make_fence_line()
	undo_redo.create_action("Ajuster (TRIM/FENCE)")
	
	var trimmed_count := 0
	for obj_to_trim in trim_objects:
		if not is_instance_valid(obj_to_trim):
			continue
		var op = _trim_build_operation(obj_to_trim, fence_line)
		if op.is_empty():
			GlobalLogger.debug("TRIM: Opération vide pour l'objet")
			continue
		trimmed_count += 1
		
		var do_geom: Dictionary = op.get("do_geom", {})
		var undo_geom: Dictionary = op.get("undo_geom", {})
		if not do_geom.is_empty() and not undo_geom.is_empty():
			undo_redo.add_do_method(_action_restore_geometry.bind(obj_to_trim, do_geom))
			undo_redo.add_undo_method(_action_restore_geometry.bind(obj_to_trim, undo_geom))
		
		if op.has("new_ent") and op.has("new_parent") and op.has("new_do_geom"):
			var new_ent: Node = op["new_ent"]
			var new_parent: Node = op["new_parent"]
			var new_do_geom: Dictionary = op["new_do_geom"]
			undo_redo.add_do_method(_action_add_child.bind(new_parent, new_ent))
			undo_redo.add_do_method(_action_restore_geometry.bind(new_ent, new_do_geom))
			undo_redo.add_undo_method(_action_remove_child.bind(new_parent, new_ent))
	
	undo_redo.commit_action()
	fence_line.queue_free()
	if trimmed_count == 0:
		GlobalLogger.info("AJUSTER : Aucun objet n'a pu être ajusté.")
	else:
		GlobalLogger.success("AJUSTER : " + str(trimmed_count) + " objet(s) coupé(s).")

func _trim_arc_with_fence(arc):
	var center = arc.global_position + arc.arc_center
	
	# Calculer les intersections avec la ligne de fence
	var fence_line = Line2D.new()
	fence_line.points = [trim_fence_start, trim_fence_end]
	
	var intersections = []
	var fence_intersections = snap_manager._get_intersections(arc, fence_line)
	for pt in fence_intersections:
		intersections.append(pt)
	
	# Si pas d'intersection, ne rien faire
	if intersections.is_empty():
		fence_line.queue_free()
		return
	
	# Trouver l'intersection la plus proche du début de l'arc
	var start_point = center + Vector2(cos(arc.arc_start_angle), sin(arc.arc_start_angle)) * arc.arc_radius
	
	var closest_intersection = null
	var min_dist = INF
	
	for pt in intersections:
		var dist = pt.distance_to(start_point)
		if dist < min_dist:
			min_dist = dist
			closest_intersection = pt
	
	if closest_intersection:
		# Calculer le nouvel angle de fin
		var new_end_angle = (closest_intersection - center).angle()
		arc.arc_end_angle = new_end_angle
		arc.update_arc_properties(arc.arc_center, arc.arc_radius, arc.arc_start_angle, new_end_angle)
	
	fence_line.queue_free()

func _trim_polyline_with_fence(polyline):
	var new_points = []
	var points = polyline.points
	
	# Créer la ligne de fence
	var fence_line = Line2D.new()
	fence_line.points = [trim_fence_start, trim_fence_end]
	
	# Pour chaque segment de la polyligne
	for i in range(points.size() - 1):
		var p1 = polyline.to_global(points[i])
		var p2 = polyline.to_global(points[i + 1])
		
		var segment_intersections = []
		
		# Calculer les intersections avec la fence
		var fence_intersections = snap_manager._get_intersections(fence_line, polyline)
		for pt in fence_intersections:
			# Vérifier si l'intersection est sur ce segment
			var dist_to_p1 = pt.distance_to(p1)
			var dist_to_p2 = pt.distance_to(p2)
			var seg_length = p1.distance_to(p2)
			
			if dist_to_p1 + dist_to_p2 <= seg_length + 0.1:  # Tolérance
				segment_intersections.append(pt)
		
		# Si pas d'intersection, garder le segment
		if segment_intersections.is_empty():
			new_points.append(points[i])
			if i == points.size() - 2:  # Dernier point
				new_points.append(points[i + 1])
		else:
			# Trier les intersections le long du segment
			segment_intersections.sort_custom(func(a, b): return a.distance_to(p1) < b.distance_to(p1))
			
			# Ajouter le point de départ
			new_points.append(points[i])
			
			# Ajouter les intersections converties en local
			for pt in segment_intersections:
				new_points.append(polyline.to_local(pt))
			
			# Si c'est le dernier segment et qu'il y a des intersections, 
			# ne pas ajouter le point final (il sera coupé)
	
	# Appliquer les nouveaux points
	polyline.points = new_points
	
	fence_line.queue_free()

func _trim_arc(arc):
	# Cette fonction n'est plus utilisée avec le mode fence
	pass

func _trim_polyline(polyline):
	var new_points = []
	var points = polyline.points
	
	# Créer la ligne de fence
	var fence_line = Line2D.new()
	fence_line.points = [trim_fence_start, trim_fence_end]
	
	# Pour chaque segment de la polyligne
	for i in range(points.size() - 1):
		var p1 = polyline.to_global(points[i])
		var p2 = polyline.to_global(points[i + 1])
		
		var segment_intersections = []
		
		# Calculer les intersections avec la fence
		var fence_intersections = snap_manager._get_intersections(fence_line, polyline)
		for pt in fence_intersections:
			# Vérifier si l'intersection est sur ce segment
			var dist_to_p1 = pt.distance_to(p1)
			var dist_to_p2 = pt.distance_to(p2)
			var seg_length = p1.distance_to(p2)
			
			if dist_to_p1 + dist_to_p2 <= seg_length + 0.1:  # Tolérance
				segment_intersections.append(pt)
		
		# Si pas d'intersection, garder le segment
		if segment_intersections.is_empty():
			new_points.append(points[i])
			if i == points.size() - 2:  # Dernier point
				new_points.append(points[i + 1])
		else:
			# Trier les intersections le long du segment
			segment_intersections.sort_custom(func(a, b): return a.distance_to(p1) < b.distance_to(p1))
			
			# Ajouter le point de départ
			new_points.append(points[i])
			
			# Ajouter les intersections converties en local
			for pt in segment_intersections:
				new_points.append(polyline.to_local(pt))
			
			# Si c'est le dernier segment et qu'il y a des intersections, 
			# ne pas ajouter le point final (il sera coupé)
	
	# Appliquer les nouveaux points
	polyline.points = new_points
	
	fence_line.queue_free()

# --- ACTIONS SPÉCIFIQUES POLYLIGNE ---

func _action_set_polyline_vertex(polyline: Line2D, vertex_index: int, new_pos: Vector2):
	if is_instance_valid(polyline) and vertex_index >= 0 and vertex_index < polyline.points.size():
		polyline.points[vertex_index] = new_pos
		polyline.queue_redraw()

func _action_restore_polyline_points(polyline: Line2D, old_points: Array):
	if is_instance_valid(polyline):
		polyline.points = old_points.duplicate()
		polyline.queue_redraw()

func _action_toggle_polyline_closed(polyline: Line2D, should_close: bool):
	if not is_instance_valid(polyline) or polyline.points.size() < 3: return
	
	if should_close:
		# Fermer : ajouter le premier point à la fin
		if not polyline.points[0].is_equal_approx(polyline.points[polyline.points.size() - 1]):
			polyline.points.append(polyline.points[0])
	else:
		# Ouvrir : supprimer le dernier point s'il est identique au premier
		if polyline.points.size() > 2 and polyline.points[0].is_equal_approx(polyline.points[polyline.points.size() - 1]):
			polyline.points.remove_at(polyline.points.size() - 1)
	
	polyline.queue_redraw()

# --- ACTIONS SPÉCIFIQUES CERCLE ---

func _action_set_circle_center(circle, new_center: Vector2):
	if is_instance_valid(circle):
		circle.circle_center = new_center
		if circle.has_method("update_visuals"): circle.update_visuals()
		circle.queue_redraw()

func _action_set_circle_radius(circle, new_radius: float):
	if is_instance_valid(circle):
		circle.circle_radius = new_radius
		if circle.has_method("update_visuals"): circle.update_visuals()
		circle.queue_redraw()
