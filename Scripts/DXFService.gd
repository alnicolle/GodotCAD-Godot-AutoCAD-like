class_name DXFService
extends RefCounted

const DEBUG_DXF_ARC = false

# --- COULEURS AUTOCAD (ACI) ---
const ACI_COLORS = {
	1: Color.RED, 2: Color.YELLOW, 3: Color.GREEN, 4: Color.CYAN,
	5: Color.BLUE, 6: Color.MAGENTA, 7: Color.WHITE,
	8: Color(0.5, 0.5, 0.5), 9: Color(0.75, 0.75, 0.75),
	250: Color(0.2, 0.2, 0.2), 251: Color(0.3, 0.3, 0.3),
	252: Color(0.4, 0.4, 0.4), 253: Color(0.6, 0.6, 0.6),
	254: Color(0.8, 0.8, 0.8), 255: Color.WHITE
}

# ------------------------------------------------------------------------------
# IMPORTATION (Votre code fonctionnel adapté)
# ------------------------------------------------------------------------------
static func import_dxf(filepath: String, main_node: Node):
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		GlobalLogger.error("Impossible d'ouvrir : " + filepath)
		return

	GlobalLogger.info("Import DXF : " + filepath.get_file())
	var layer_manager = main_node.layer_manager
	if not layer_manager: return

	var current_section = "NONE"
	var current_table = "NONE"
	var current_entity = "NONE"
	
	var temp_points = [] 
	var c_center = Vector2.ZERO
	var c_radius = 0.0
	var arc_center = Vector2.ZERO
	var arc_radius = 0.0
	var arc_start_angle = 0.0
	var arc_end_angle = 0.0
	var current_arc_data = {}  # Pour stocker les données de l'arc courant
	var entity_layer = "0"
	var entity_linetype = "ByLayer"
	var entity_lineweight = -1.0
	var entity_linetype_scale = 1.0
	
	var reading_layer_name = ""
	var reading_layer_color = 7
	var reading_layer_linetype = "Continuous"
	var reading_layer_lineweight = -3
	var current_lwpline_width = 0.0
	var current_lwpline_flags = 0
	var skip_xdict_entries = false  # Pour ignorer les entrées XDictionary complexes
	
	while not file.eof_reached():
		var line = file.get_line()
		var code = line.strip_edges()
		var value = file.get_line().strip_edges()
		
		if code == "EOF": break
		
		# SECTIONS
		if code == "0" and value == "SECTION": continue
		if code == "2" and (value == "HEADER" or value == "TABLES" or value == "ENTITIES"):
			current_section = value
			continue
		if code == "0" and value == "ENDSEC":
			if current_section == "ENTITIES" and current_entity != "NONE":
				_finalize_current_entity(main_node, current_entity, temp_points, c_center, c_radius, entity_layer, entity_linetype, entity_lineweight, entity_linetype_scale, current_arc_data, current_lwpline_width)
			current_section = "NONE"
			continue

		# TABLES (CALQUES)
		if current_section == "TABLES":
			if code == "0" and value == "TABLE": continue
			if code == "2" and value == "LAYER": current_table = "LAYER"; continue
			if code == "0" and value == "ENDTAB":
				if current_table == "LAYER" and reading_layer_name != "":
					_create_imported_layer_v2000(layer_manager, reading_layer_name, reading_layer_color, reading_layer_linetype, reading_layer_lineweight)
					reading_layer_name = ""
				current_table = "NONE"
				continue
			
			if current_table == "LAYER":
				if code == "0" and value == "LAYER":
					if reading_layer_name != "": 
						_create_imported_layer_v2000(layer_manager, reading_layer_name, reading_layer_color, reading_layer_linetype, reading_layer_lineweight)
					reading_layer_name = ""; reading_layer_color = 7; reading_layer_linetype = "Continuous"; reading_layer_lineweight = -3; skip_xdict_entries = false
				if code == "2": reading_layer_name = value.strip_edges()
				if code == "62": reading_layer_color = abs(int(value))
				if code == "6": reading_layer_linetype = value.strip_edges()
				if code == "370": reading_layer_lineweight = int(value)
				# Gestion des XDictionary - on ignore ces métadonnées complexes
				if code == "102" and value == "{ACAD_XDICTIONARY": skip_xdict_entries = true
				if code == "102" and value == "}": skip_xdict_entries = false
				# Ignorer toutes les entrées dans un XDictionary
				if skip_xdict_entries: continue

		# ENTITIES
		if current_section == "ENTITIES":
			if code == "0":
				var next_type = value
				if next_type == "SEQEND":
					if temp_points.size() >= 2:
						_spawn_on_layer(main_node, "POLYLINE", temp_points, Vector2.ZERO, 0, entity_layer, entity_linetype, entity_lineweight, entity_linetype_scale)
					temp_points = []; current_entity = "NONE"; continue
				if next_type == "VERTEX":
					temp_points.append(Vector2.ZERO); current_entity = "VERTEX"; continue

				if current_entity != "VERTEX" and current_entity != "NONE":
					_finalize_current_entity(main_node, current_entity, temp_points, c_center, c_radius, entity_layer, entity_linetype, entity_lineweight, entity_linetype_scale, current_arc_data, current_lwpline_width)
					temp_points = []; c_center = Vector2.ZERO; c_radius = 0.0
					entity_layer = "0"; entity_linetype = "ByLayer"; entity_lineweight = -1.0; entity_linetype_scale = 1.0
					current_lwpline_width = 0.0; current_lwpline_flags = 0

				current_entity = next_type
				if current_entity == "LINE": temp_points = [Vector2.ZERO, Vector2.ZERO]
				elif current_entity == "LWPOLYLINE": 
					temp_points = []
					current_lwpline_width = 0.0
					current_lwpline_flags = 0
			else:
				if code == "8": entity_layer = value.strip_edges()
				if code == "6": entity_linetype = value.strip_edges()
				if code == "48": entity_linetype_scale = float(value)
				if code == "370": entity_lineweight = _dxf_weight_to_godot(int(value))
				elif code == "40" and current_entity == "POLYLINE": entity_lineweight = float(value) # Largeur polyline comme fallback

				if current_entity == "CIRCLE":
					if code == "10": c_center.x = float(value)
					if code == "20": c_center.y = -float(value)
					if code == "40": c_radius = float(value)
				
				elif current_entity == "ARC":
					if code == "10": arc_center.x = float(value)
					if code == "20": arc_center.y = -float(value)  # Inverser Y pour Godot
					if code == "40": arc_radius = float(value)
					if code == "50": arc_start_angle = -float(value)  # Inverser angle pour Godot
					if code == "51": arc_end_angle = -float(value)    # Inverser angle pour Godot
					# Stocker les données de l'arc
					current_arc_data = {
						"center": arc_center,
						"radius": arc_radius,
						"start_angle": arc_start_angle,
						"end_angle": arc_end_angle
					}
				elif current_entity == "LINE":
					if code == "10": temp_points[0].x = float(value)
					if code == "20": temp_points[0].y = -float(value)
					if code == "11": temp_points[1].x = float(value)
					if code == "21": temp_points[1].y = -float(value)
				elif current_entity == "LWPOLYLINE":
					if code == "90": # Nombre de points (ignoré, on gère dynamiquement)
						pass
					if code == "70": current_lwpline_flags = int(value) # Flags (0=closed, 1=open)
					if code == "43": current_lwpline_width = float(value) # Largeur constante
					if code == "10": 
						temp_points.append(Vector2(float(value), 0))
					if code == "20" and temp_points.size() > 0: 
						temp_points[-1].y = -float(value)
				elif current_entity == "VERTEX":
					if temp_points.size() > 0:
						if code == "10": temp_points[-1].x = float(value)
						if code == "20": temp_points[-1].y = -float(value)

	file.close()

	# Appel au DXFBaker (en imaginant que EntitiesRenderer est dans ton World)
	var renderer = main_node.world.get_node_or_null("EntitiesRenderer")
	var is_new_renderer = false
	if not renderer:
		GlobalLogger.warning("EntitiesRenderer introuvable dans World. Création automatique en cours...")
		renderer = Node2D.new()
		renderer.name = "EntitiesRenderer"
		renderer.set_script(load("res://Scripts/EntitiesRenderer.gd"))
		is_new_renderer = true
		
	# Mettre à jour les dépendances AVANT l'add_child
	if renderer.get("camera") == null and main_node.get("camera") != null:
		renderer.set("camera", main_node.camera)
		if not is_new_renderer and not main_node.camera.is_connected("zoom_changed", renderer._on_camera_changed):
			main_node.camera.connect("zoom_changed", renderer._on_camera_changed)
			
	if renderer.get("layer_manager") == null and main_node.get("layer_manager") != null:
		renderer.set("layer_manager", main_node.layer_manager)
		if not is_new_renderer and not main_node.layer_manager.is_connected("layers_changed", renderer._on_layers_changed):
			main_node.layer_manager.connect("layers_changed", renderer._on_layers_changed)
			
	if renderer.get("selection_manager") == null and main_node.get("selection_manager") != null:
		renderer.set("selection_manager", main_node.selection_manager)
		
	if is_new_renderer:
		main_node.world.add_child(renderer)
		
	DXFBaker.bake_imported_scene(main_node.world, renderer)
	GlobalLogger.success("Import terminé.")

# ------------------------------------------------------------------------------
# EXPORTATION (Point d'entrée principal)
# ------------------------------------------------------------------------------
static func save_dxf(filepath: String, main_node: Node, use_2000_format: bool = true):
	if use_2000_format:
		return save_dxf_2000(filepath, main_node)
	else:
		return save_dxf_r12_legacy(filepath, main_node)

# ------------------------------------------------------------------------------
# EXPORTATION (Format DXF 2000+)
# ------------------------------------------------------------------------------

# --- PARSEUR DE TYPES DE LIGNES DYNAMIQUES ---
static func _load_acadiso_linetypes(filepath: String) -> Dictionary:
	var defs = {
		"BYLAYER": {"desc": "", "length": 0.0, "elements": []},
		"BYBLOCK": {"desc": "", "length": 0.0, "elements": []},
		"CONTINUOUS": {"desc": "Solid line", "length": 0.0, "elements": []}
	}
	
	if not FileAccess.file_exists(filepath):
		GlobalLogger.error("acadiso.txt introuvable à : " + filepath)
		return defs
		
	var file = FileAccess.open(filepath, FileAccess.READ)
	var current_name = ""
	var current_desc = ""
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with(";;") or line.is_empty(): continue
		
		# Lecture du nom et description (ex: *AXES,Centre ____ _ ____)
		if line.begins_with("*"):
			var parts = line.split(",", true, 1)
			current_name = parts[0].substr(1).strip_edges().to_upper()
			current_desc = parts[1].strip_edges() if parts.size() > 1 else ""
			
		# Lecture de la géométrie (ex: A, 31.75, -6.35, 6.35, -6.35)
		elif line.to_upper().begins_with("A,") and current_name != "":
			var elements_str = line.substr(2).split(",")
			var elements = []
			var length = 0.0
			
			for e in elements_str:
				var e_str = e.strip_edges()
				if e_str.begins_with("["): 
					# ASTUCE : C'est une forme complexe. Pour éviter le crash d'AutoCAD, 
					# on la remplace par un espace vide standard (-2.54)
					elements.append(-2.54)
					length += 2.54
					continue
				var val = e_str.to_float()
				elements.append(val)
				length += abs(val)
			
			defs[current_name] = {"desc": current_desc, "length": length, "elements": elements}
			current_name = ""
	file.close()
	return defs

# Gestionnaire de handles global pour l'exportation DXF
class HandleManager:
	# On démarre à 4096 (0x1000) pour esquiver la mémoire de LibreDWG
	var current_handle_int: int = 4096 
	
	func get_new_handle() -> String:
		var hex_string = "%X" % current_handle_int
		current_handle_int += 1
		return hex_string

static func save_dxf_2000(filepath: String, main_node: Node):
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file: 
		return false

	var handle_mgr = HandleManager.new()

	# 1. PRÉ-GÉNÉRATION DES HANDLES CLÉS (pour garantir la cohérence des pointeurs)
	var handle_root_dict = "C"  # Standard AutoCAD
	var handle_dict_acad_group = handle_mgr.get_new_handle()
	var handle_dict_acad_layout = handle_mgr.get_new_handle()
	var handle_dict_acad_mlinestyle = handle_mgr.get_new_handle()
	var handle_dict_acad_plotsettings = handle_mgr.get_new_handle()
	var handle_dict_acad_plotstylename = handle_mgr.get_new_handle()
	
	var handle_layout_model = handle_mgr.get_new_handle()
	var handle_layout_paper = handle_mgr.get_new_handle()  # Layout pour Paper Space
	var handle_mline_dict = handle_mgr.get_new_handle()
	var handle_mline_standard = handle_mgr.get_new_handle()
	var handle_plotstyle_dict = handle_mgr.get_new_handle()
	var handle_placeholder = handle_mgr.get_new_handle()  # Placeholder obligatoire
	
	var handle_block_record_model = "1F" 
	var handle_block_record_paper = "1E"
	var handle_endblk_model = handle_mgr.get_new_handle()
	var handle_block_model = handle_mgr.get_new_handle()
	var handle_block_paper = handle_mgr.get_new_handle()  # Variable manquante ajoutée
	var handle_endblk_paper = handle_mgr.get_new_handle()

	# 2. HEADER (DXF 2000+ = AC1015) complet
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("HEADER")
	file.store_line("9"); file.store_line("$ACADVER")
	file.store_line("1"); file.store_line("AC1015")  # DXF 2000+

	file.store_line("9"); file.store_line("$HANDSEED")
	file.store_line("5"); file.store_line("10000")
	
	file.store_line("9"); file.store_line("$INSBASE")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")

	# --- AJOUT DES VARIABLES GLOBALES SCU (MODEL & PAPER) ---
	file.store_line("9"); file.store_line("$UCSORG")
	file.store_line("10"); file.store_line("0.0"); file.store_line("20"); file.store_line("0.0"); file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$UCSXDIR")
	file.store_line("10"); file.store_line("1.0"); file.store_line("20"); file.store_line("0.0"); file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$UCSYDIR")
	file.store_line("10"); file.store_line("0.0"); file.store_line("20"); file.store_line("1.0"); file.store_line("30"); file.store_line("0.0")
	
	# INDISPENSABLE POUR ÉVITER LE BUG "AXE Y NON UNITAIRE"
	file.store_line("9"); file.store_line("$PUCSORG")
	file.store_line("10"); file.store_line("0.0"); file.store_line("20"); file.store_line("0.0"); file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$PUCSXDIR")
	file.store_line("10"); file.store_line("1.0"); file.store_line("20"); file.store_line("0.0"); file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$PUCSYDIR")
	file.store_line("10"); file.store_line("0.0"); file.store_line("20"); file.store_line("1.0"); file.store_line("30"); file.store_line("0.0")

	# --- AJOUT DES VARIABLES GLOBALES SCU POUR LIBREDWG/AUTOCAD ---
	file.store_line("9"); file.store_line("$UCSORG")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$UCSXDIR")
	file.store_line("10"); file.store_line("1.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$UCSYDIR")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("1.0")
	file.store_line("30"); file.store_line("0.0")
	
	# --- AJOUT DES VARIABLES PAR DÉFAUT POUR LIBREDWG ---
	file.store_line("9"); file.store_line("$CELTSCALE"); file.store_line("40"); file.store_line("1.0")
	file.store_line("9"); file.store_line("$LTSCALE"); file.store_line("40"); file.store_line("1.0")
	file.store_line("9"); file.store_line("$LUNITS"); file.store_line("70"); file.store_line("2")
	file.store_line("9"); file.store_line("$MAXACTVP"); file.store_line("70"); file.store_line("64")
	file.store_line("9"); file.store_line("$SPLINETYPE"); file.store_line("70"); file.store_line("6")
	file.store_line("9"); file.store_line("$SURFTAB1"); file.store_line("70"); file.store_line("6")
	file.store_line("9"); file.store_line("$SURFTAB2"); file.store_line("70"); file.store_line("6")
	file.store_line("9"); file.store_line("$SURFTYPE"); file.store_line("70"); file.store_line("6")
	file.store_line("9"); file.store_line("$SURFU"); file.store_line("70"); file.store_line("6")
	file.store_line("9"); file.store_line("$SURFV"); file.store_line("70"); file.store_line("6")
	file.store_line("9"); file.store_line("$DIMTFAC"); file.store_line("40"); file.store_line("1.0")
	file.store_line("9"); file.store_line("$DIMALTF"); file.store_line("40"); file.store_line("25.4")
	file.store_line("9"); file.store_line("$DIMLFAC"); file.store_line("40"); file.store_line("1.0")
	file.store_line("9"); file.store_line("$DIMTXT"); file.store_line("40"); file.store_line("0.18")
	file.store_line("9"); file.store_line("$DIMALTU"); file.store_line("70"); file.store_line("2")
	# ----------------------------------------------------
	
	file.store_line("9"); file.store_line("$EXTMIN")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$EXTMAX")
	file.store_line("10"); file.store_line("1000.0")
	file.store_line("20"); file.store_line("1000.0")
	file.store_line("30"); file.store_line("0.0")
	
	# --- CORRECTION DES VARIABLES D'EN-TÊTE POUR LIBREDWG (Évite l'erreur UXAREA/UXDWG) ---
	file.store_line("9"); file.store_line("$LIMMIN")
	file.store_line("10"); file.store_line("0.0"); file.store_line("20"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$LIMMAX")
	file.store_line("10"); file.store_line("1000.0"); file.store_line("20"); file.store_line("1000.0")
	file.store_line("9"); file.store_line("$TDCREATE"); file.store_line("40"); file.store_line("2459000.0")
	file.store_line("9"); file.store_line("$TDUPDATE"); file.store_line("40"); file.store_line("2459000.0")
	file.store_line("9"); file.store_line("$TDINDWG"); file.store_line("40"); file.store_line("0.0")
	# ------------------------------------------------------------------------------------
	
	file.store_line("0"); file.store_line("ENDSEC")

	# 3. CLASSES (obligatoire en AC1015)
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("CLASSES")
	file.store_line("0"); file.store_line("CLASS")
	file.store_line("1"); file.store_line("ACDBDICTIONARYWDFLT")
	file.store_line("2"); file.store_line("AcDbDictionaryWithDefault")
	file.store_line("3"); file.store_line("ObjectDBX Dictionary")
	file.store_line("90"); file.store_line("0")
	file.store_line("280"); file.store_line("0")
	file.store_line("281"); file.store_line("0")
	file.store_line("0"); file.store_line("CLASS")
	file.store_line("1"); file.store_line("ACDBDICTIONARYVAR")
	file.store_line("2"); file.store_line("AcDbDictionaryVar")
	file.store_line("3"); file.store_line("ObjectDBX Dictionary Variable")
	file.store_line("90"); file.store_line("0")
	file.store_line("280"); file.store_line("0")
	file.store_line("281"); file.store_line("0")
	file.store_line("0"); file.store_line("ENDSEC")

	# 4. TABLES (complètes)
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("TABLES")
	
	# Table VPORT
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("VPORT")
	file.store_line("5"); file.store_line("1")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("VPORT")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("330"); file.store_line("1")  # Propriétaire : table VPORT
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbViewportTableRecord")
	file.store_line("2"); file.store_line("*Active")
	file.store_line("70"); file.store_line("0")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("11"); file.store_line("1.0")
	file.store_line("21"); file.store_line("1.0")
	file.store_line("12"); file.store_line("0.0")
	file.store_line("22"); file.store_line("0.0")
	file.store_line("13"); file.store_line("0.0")
	file.store_line("23"); file.store_line("0.0")
	file.store_line("14"); file.store_line("10.0")
	file.store_line("24"); file.store_line("10.0")
	file.store_line("15"); file.store_line("10.0")
	file.store_line("25"); file.store_line("10.0")
	file.store_line("16"); file.store_line("0.0")
	file.store_line("26"); file.store_line("0.0")
	file.store_line("36"); file.store_line("1.0")
	file.store_line("17"); file.store_line("0.0")
	file.store_line("27"); file.store_line("0.0")
	file.store_line("37"); file.store_line("0.0")
	file.store_line("40"); file.store_line("297.0")
	file.store_line("41"); file.store_line("1.0")
	file.store_line("42"); file.store_line("50.0")
	file.store_line("43"); file.store_line("0.0")
	file.store_line("44"); file.store_line("0.0")
	file.store_line("50"); file.store_line("0.0")
	file.store_line("51"); file.store_line("0.0")
	file.store_line("71"); file.store_line("0")
	file.store_line("72"); file.store_line("100")
	file.store_line("73"); file.store_line("1")
	file.store_line("74"); file.store_line("3")
	file.store_line("75"); file.store_line("1")
	file.store_line("76"); file.store_line("1")
	file.store_line("77"); file.store_line("0")
	file.store_line("78"); file.store_line("0")

	# --- AXES SCU UNIQUES (Désactive la popup AutoCAD) ---
	file.store_line("110"); file.store_line("0.0") 
	file.store_line("120"); file.store_line("0.0") 
	file.store_line("130"); file.store_line("0.0") 
	file.store_line("111"); file.store_line("1.0") 
	file.store_line("121"); file.store_line("0.0") 
	file.store_line("131"); file.store_line("0.0") 
	file.store_line("112"); file.store_line("0.0") 
	file.store_line("122"); file.store_line("1.0") 
	file.store_line("132"); file.store_line("0.0") 
	file.store_line("79"); file.store_line("0")
	
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table LTYPE (Générée dynamiquement)
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LTYPE")
	file.store_line("5"); file.store_line("2")
	file.store_line("330"); file.store_line("0")
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	
	# --- CHARGEMENT DU FICHIER ACADISO ---
	# (MODIFIE LE CHEMIN SELON OÙ SE TROUVE TON FICHIER DANS LE JEU)
	var acadiso_path = "res://acadiso.txt" # ou "user://acadiso.txt"
	var linetype_defs = _load_acadiso_linetypes(acadiso_path)
	
	var active_ltypes = {"BYLAYER": true, "BYBLOCK": true, "CONTINUOUS": true}
	
	# Scan dynamique global (Calques)
	if main_node.layer_manager:
		for layer in main_node.layer_manager.layers:
			if layer.has("linetype"):
				var lt_name = layer.linetype.to_upper()
				if lt_name == "GODOT_ISO02": lt_name = "ACAD_ISO02W100"
				elif lt_name == "GODOT_ISO03": lt_name = "ACAD_ISO03W100"
				if linetype_defs.has(lt_name): active_ltypes[lt_name] = true

	# Scan dynamique global (Entités)
	var root_for_ltypes = main_node.world.get_node("Entities")
	for layer_node in root_for_ltypes.get_children():
		for child in layer_node.get_children():
			if child is CADEntity and "linetype" in child:
				var lt_name = child.linetype.to_upper()
				if lt_name == "GODOT_ISO02": lt_name = "ACAD_ISO02W100"
				elif lt_name == "GODOT_ISO03": lt_name = "ACAD_ISO03W100"
				if linetype_defs.has(lt_name): active_ltypes[lt_name] = true
	
	file.store_line("70"); file.store_line(str(active_ltypes.size()))
	
	# Assignation de handles fixes pour éviter les doublons générés par LibreDWG
	var ltype_handles = {"BYLAYER": "14", "BYBLOCK": "15", "CONTINUOUS": "16"}
	
	for lt_name in active_ltypes.keys():
		var def = linetype_defs[lt_name]
		file.store_line("0"); file.store_line("LTYPE")
		
		# On utilise le handle fixe s'il existe, sinon on en génère un nouveau
		var lt_handle = ltype_handles[lt_name] if ltype_handles.has(lt_name) else handle_mgr.get_new_handle()
		file.store_line("5"); file.store_line(lt_handle)  
		
		file.store_line("330"); file.store_line("2")



		file.store_line("100"); file.store_line("AcDbSymbolTableRecord")
		file.store_line("100"); file.store_line("AcDbLinetypeTableRecord")
		file.store_line("2"); file.store_line(lt_name) # Nom toujours en majuscule
		file.store_line("70"); file.store_line("0")
		file.store_line("3"); file.store_line(def["desc"])
		file.store_line("72"); file.store_line("65")
		file.store_line("73"); file.store_line(str(def["elements"].size()))
		file.store_line("40"); file.store_line(str(def["length"]))
		
		for el in def["elements"]:
			file.store_line("49"); file.store_line(str(el))
			file.store_line("74"); file.store_line("0")
			
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table LAYER avec propriétés complètes
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LAYER")
	file.store_line("5"); file.store_line("3")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	
	var custom_layers = []
	if main_node.layer_manager: 
		for l in main_node.layer_manager.layers:
			if l.name != "0": custom_layers.append(l)
	
	# Le "+1" est strictement réservé au calque "0" (AutoCAD panique si le compte est faux)
	file.store_line("70"); file.store_line(str(custom_layers.size() + 1))
	
	var layers = []
	if main_node.layer_manager: layers = main_node.layer_manager.layers
	
	# Calque 0 par défaut
	file.store_line("0"); file.store_line("LAYER")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("330"); file.store_line("3")  # Propriétaire : table LAYER
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbLayerTableRecord")
	file.store_line("2"); file.store_line("0")
	file.store_line("70"); file.store_line("0")
	file.store_line("62"); file.store_line("7")
	file.store_line("6"); file.store_line("Continuous")
	file.store_line("370"); file.store_line("-3")
	file.store_line("390"); file.store_line(handle_placeholder) # <--- LIGNE VITALE À AJOUTER
	
	# Calques personnalisés avec leurs propriétés
	for layer in layers:
		var lname = layer.name
		if lname == "0": continue
		
		file.store_line("0"); file.store_line("LAYER")
		file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
		file.store_line("330"); file.store_line("3")  # Propriétaire : table LAYER
		file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
		file.store_line("100"); file.store_line("AcDbLayerTableRecord")
		file.store_line("2"); file.store_line(lname)  # Garder la casse originale
		file.store_line("70"); file.store_line("0")
		
		# 1. Sécurité sur la couleur (256 est interdit pour un calque)
		var color_index = _color_to_aci(layer.color)
		var c_index = color_index if color_index != 256 else 7
		file.store_line("62"); file.store_line(str(c_index))
		
		# 2. Sécurité sur le mapping du type de ligne
		var layer_lt = "CONTINUOUS"
		if layer.has("linetype"): layer_lt = layer.linetype
		var write_ltype = layer_lt.to_upper()
		
		# On traduit l'identifiant interne de Godot vers le standard ISO d'AutoCAD
		if write_ltype == "GODOT_ISO02": write_ltype = "ACAD_ISO02W100"
		elif write_ltype == "GODOT_ISO03": write_ltype = "ACAD_ISO03W100"
		
		# --- FILET DE SÉCURITÉ ---
		# Si le type de ligne n'est pas dans l'en-tête, on force CONTINUOUS pour éviter le crash
		if not active_ltypes.has(write_ltype) and write_ltype != "BYLAYER":
			write_ltype = "CONTINUOUS"
		
		file.store_line("6"); file.store_line(write_ltype)
		
		# Épaisseur
		var lw = -3.0  # Par défaut avec valeur de secours correcte
		if layer.has("lineweight"): lw = _godot_weight_to_dxf(layer.lineweight)
		file.store_line("370"); file.store_line(str(lw))
		file.store_line("390"); file.store_line(handle_placeholder)
		
	# === LIGNE CRUCIALE POUR ÉVITER LE CRASH ACDBLAYERTABLE ===
	file.store_line("0"); file.store_line("ENDTAB")
	# ==========================================================

	# Table STYLE
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("STYLE")
	file.store_line("5"); file.store_line("4")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("STYLE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("330"); file.store_line("4")  # Propriétaire : table STYLE
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbTextStyleTableRecord")
	file.store_line("2"); file.store_line("STANDARD")
	file.store_line("70"); file.store_line("0")
	file.store_line("40"); file.store_line("0.0")
	file.store_line("41"); file.store_line("1.0")
	file.store_line("50"); file.store_line("0.0")
	file.store_line("71"); file.store_line("0")
	file.store_line("42"); file.store_line("2.5")
	file.store_line("3"); file.store_line("txt")
	file.store_line("4"); file.store_line("")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table VIEW
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("VIEW")
	file.store_line("5"); file.store_line("5")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("0")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table UCS
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("UCS")
	file.store_line("5"); file.store_line("6")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("0")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table APPID
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("APPID")
	file.store_line("5"); file.store_line("7")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("APPID")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("330"); file.store_line("7")  # Propriétaire : table APPID
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbRegAppTableRecord")
	file.store_line("2"); file.store_line("ACAD")
	file.store_line("70"); file.store_line("0")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table DIMSTYLE
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("DIMSTYLE")
	file.store_line("5"); file.store_line("8")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("100"); file.store_line("AcDbDimStyleTable")  # Classe de la table
	file.store_line("0"); file.store_line("DIMSTYLE")
	file.store_line("105"); file.store_line("10") # Handle officiel
	file.store_line("330"); file.store_line("8")  # Propriétaire : table DIMSTYLE
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbDimStyleTableRecord")
	file.store_line("2"); file.store_line("Standard")
	file.store_line("70"); file.store_line("0")
	file.store_line("143"); file.store_line("25.4") # <--- AJOUTEZ CETTE LIGNE ICI POUR CORRIGER DIMALTF
	file.store_line("41"); file.store_line("2.5")
	file.store_line("42"); file.store_line("2.5")
	file.store_line("43"); file.store_line("0.625")
	file.store_line("44"); file.store_line("0.625")
	file.store_line("40"); file.store_line("2.5")
	file.store_line("140"); file.store_line("2.5")
	file.store_line("147"); file.store_line("0.09")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table BLOCK_RECORD (obligatoire en AC1015)
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("BLOCK_RECORD")
	file.store_line("5"); file.store_line("9")  # Standard AutoCAD
	file.store_line("330"); file.store_line("0")  # Propriétaire : base de données globale
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("2")
	
	# Model Space
	file.store_line("0"); file.store_line("BLOCK_RECORD")
	file.store_line("5"); file.store_line(handle_block_record_model)
	file.store_line("330"); file.store_line("9")  # Propriétaire : table BLOCK_RECORD
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbBlockTableRecord")
	file.store_line("2"); file.store_line("*Model_Space")
	file.store_line("340"); file.store_line(handle_layout_model)  # Pointe vers le bon Layout !
	file.store_line("70"); file.store_line("0")
	file.store_line("280"); file.store_line("1")
	file.store_line("281"); file.store_line("0")
	
	# Paper Space
	file.store_line("0"); file.store_line("BLOCK_RECORD")
	file.store_line("5"); file.store_line(handle_block_record_paper)
	file.store_line("330"); file.store_line("9")  # Propriétaire : table BLOCK_RECORD
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbBlockTableRecord")
	file.store_line("2"); file.store_line("*Paper_Space")
	file.store_line("340"); file.store_line(handle_layout_paper)  # Pointe vers le Layout Paper Space
	file.store_line("70"); file.store_line("0")
	file.store_line("280"); file.store_line("1")
	file.store_line("281"); file.store_line("0")
	
	file.store_line("0"); file.store_line("ENDTAB")
	file.store_line("0"); file.store_line("ENDSEC")

	# 5. BLOCKS (obligatoire en AC1015)
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("BLOCKS")
	
	# Model Space block
	file.store_line("0"); file.store_line("BLOCK")
	file.store_line("5"); file.store_line(handle_block_model)
	file.store_line("330"); file.store_line(handle_block_record_model)  # Pointe vers le Block Record !
	file.store_line("100"); file.store_line("AcDbEntity")
	file.store_line("8"); file.store_line("0")
	file.store_line("100"); file.store_line("AcDbBlockBegin")
	file.store_line("2"); file.store_line("*Model_Space")
	file.store_line("70"); file.store_line("0")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("3"); file.store_line("*Model_Space")
	file.store_line("1"); file.store_line("")
	
	file.store_line("0"); file.store_line("ENDBLK")
	file.store_line("5"); file.store_line(handle_endblk_model)
	file.store_line("330"); file.store_line(handle_block_record_model)  # Pointe vers le Block Record !
	file.store_line("100"); file.store_line("AcDbEntity")
	file.store_line("8"); file.store_line("0")
	file.store_line("100"); file.store_line("AcDbBlockEnd")
	
	# Paper Space block
	file.store_line("0"); file.store_line("BLOCK")
	file.store_line("5"); file.store_line(handle_block_paper)
	file.store_line("330"); file.store_line(handle_block_record_paper)  # Pointe vers le Block Record !
	file.store_line("100"); file.store_line("AcDbEntity")
	file.store_line("8"); file.store_line("0")
	file.store_line("100"); file.store_line("AcDbBlockBegin")
	file.store_line("2"); file.store_line("*Paper_Space")
	file.store_line("70"); file.store_line("0")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("3"); file.store_line("*Paper_Space")
	file.store_line("1"); file.store_line("")
	
	file.store_line("0"); file.store_line("ENDBLK")
	file.store_line("5"); file.store_line(handle_endblk_paper)
	file.store_line("330"); file.store_line(handle_block_record_paper)  # Pointe vers le Block Record !
	file.store_line("100"); file.store_line("AcDbEntity")
	file.store_line("8"); file.store_line("0")
	file.store_line("100"); file.store_line("AcDbBlockEnd")
	
	file.store_line("0"); file.store_line("ENDSEC")

	# 6. ENTITIES avec LWPOLYLINE
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("ENTITIES")

	var root_entities = main_node.world.get_node("Entities")
	for layer_node in root_entities.get_children():
		if layer_node is Node2D and not (layer_node is CADEntity):
			var layer_name = layer_node.name
			
			# Trouver la couleur de base du calque pour éviter de forcer l'entité
			var layer_col = Color.WHITE
			if main_node.layer_manager:
				for l in main_node.layer_manager.layers:
					if l.name == layer_name:
						layer_col = l.color; break
			
			for child in layer_node.get_children():
				if child is CADEntity: 
					handle_mgr.current_handle_int = _write_entity_2000(file, child, layer_name, layer_col, active_ltypes, handle_mgr.current_handle_int, handle_block_record_model)
		elif layer_node is CADEntity:
			# Ajout de Color.WHITE comme couleur par défaut pour le calque "0"
			handle_mgr.current_handle_int = _write_entity_2000(file, layer_node, "0", Color.WHITE, active_ltypes, handle_mgr.current_handle_int, handle_block_record_model)

	file.store_line("0"); file.store_line("ENDSEC")

	# 7. OBJECTS (minimaliste et cohérent)
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("OBJECTS")
	
	# Dictionnaire racine minimaliste
	file.store_line("0"); file.store_line("DICTIONARY")
	file.store_line("5"); file.store_line(handle_root_dict)
	file.store_line("330"); file.store_line("0")
	file.store_line("100"); file.store_line("AcDbDictionary")
	file.store_line("281"); file.store_line("1")
	file.store_line("3"); file.store_line("ACAD_GROUP")
	file.store_line("350"); file.store_line(handle_dict_acad_group)  # Pointeur cohérent !
	file.store_line("3"); file.store_line("ACAD_LAYOUT")
	file.store_line("350"); file.store_line(handle_dict_acad_layout)  # Pointeur cohérent !
	file.store_line("3"); file.store_line("ACAD_MLINESTYLE")
	file.store_line("350"); file.store_line(handle_mline_dict)  # Pointeur cohérent !
	file.store_line("3"); file.store_line("ACAD_PLOTSETTINGS")
	file.store_line("350"); file.store_line(handle_dict_acad_plotsettings)  # Pointeur cohérent !
	file.store_line("3"); file.store_line("ACAD_PLOTSTYLENAME")
	file.store_line("350"); file.store_line(handle_dict_acad_plotstylename)  # Pointeur cohérent !
	
	# Dictionnaire ACAD_GROUP (vide mais cohérent)
	file.store_line("0"); file.store_line("DICTIONARY")
	file.store_line("5"); file.store_line(handle_dict_acad_group)
	file.store_line("330"); file.store_line(handle_root_dict)  # Point vers le dictionnaire racine
	file.store_line("100"); file.store_line("AcDbDictionary")
	file.store_line("281"); file.store_line("1")
	
	# Dictionnaire ACAD_LAYOUT avec Model et Paper Space
	file.store_line("0"); file.store_line("DICTIONARY")
	file.store_line("5"); file.store_line(handle_dict_acad_layout)
	file.store_line("330"); file.store_line(handle_root_dict)  # Point vers le dictionnaire racine
	file.store_line("100"); file.store_line("AcDbDictionary")
	file.store_line("281"); file.store_line("1")
	file.store_line("3"); file.store_line("Model")
	file.store_line("350"); file.store_line(handle_layout_model)  # Pointeur cohérent !
	file.store_line("3"); file.store_line("Layout1")
	file.store_line("350"); file.store_line(handle_layout_paper)  # Pointeur cohérent !
	
	# Layout pour Model_Space
	file.store_line("0"); file.store_line("LAYOUT")
	file.store_line("5"); file.store_line(handle_layout_model)  # Handle cohérent !
	file.store_line("330"); file.store_line(handle_dict_acad_layout)
	file.store_line("100"); file.store_line("AcDbPlotSettings")  # Héritage obligatoire !
	file.store_line("1"); file.store_line("")  # Vide pour Model
	file.store_line("2"); file.store_line("none_device")  # Paramètres par défaut
	file.store_line("4"); file.store_line("")
	file.store_line("6"); file.store_line("")
	file.store_line("40"); file.store_line("0.0")
	file.store_line("41"); file.store_line("0.0")
	file.store_line("42"); file.store_line("0.0")
	file.store_line("43"); file.store_line("0.0")
	file.store_line("44"); file.store_line("0.0")
	file.store_line("45"); file.store_line("0.0")
	file.store_line("46"); file.store_line("0.0")
	file.store_line("47"); file.store_line("0.0")
	file.store_line("48"); file.store_line("0.0")
	file.store_line("49"); file.store_line("0.0")
	file.store_line("140"); file.store_line("0.0")
	file.store_line("141"); file.store_line("0.0")
	file.store_line("142"); file.store_line("1.0")
	file.store_line("143"); file.store_line("1.0")
	file.store_line("70"); file.store_line("688")
	file.store_line("72"); file.store_line("0")
	file.store_line("73"); file.store_line("0")
	file.store_line("74"); file.store_line("5")
	file.store_line("7"); file.store_line("")
	file.store_line("75"); file.store_line("16")
	file.store_line("147"); file.store_line("1.0")
	file.store_line("148"); file.store_line("0.0")
	file.store_line("149"); file.store_line("0.0")
	file.store_line("100"); file.store_line("AcDbLayout")
	file.store_line("1"); file.store_line("Model")
	file.store_line("70"); file.store_line("1")
	file.store_line("71"); file.store_line("0")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("11"); file.store_line("420.0")
	file.store_line("21"); file.store_line("297.0")
	file.store_line("12"); file.store_line("0.0")
	file.store_line("22"); file.store_line("0.0")
	file.store_line("32"); file.store_line("0.0")
	file.store_line("14"); file.store_line("210.0")
	file.store_line("24"); file.store_line("148.5")
	file.store_line("34"); file.store_line("0.0")
	file.store_line("15"); file.store_line("0.0")
	file.store_line("25"); file.store_line("0.0")
	file.store_line("35"); file.store_line("0.0")
	file.store_line("146"); file.store_line("0.0")
	file.store_line("13"); file.store_line("0.0")
	file.store_line("23"); file.store_line("0.0")
	file.store_line("33"); file.store_line("0.0")
	file.store_line("16"); file.store_line("1.0")
	file.store_line("26"); file.store_line("0.0")
	file.store_line("36"); file.store_line("0.0")
	file.store_line("17"); file.store_line("0.0")
	file.store_line("27"); file.store_line("1.0")
	file.store_line("37"); file.store_line("0.0")
	file.store_line("76"); file.store_line("0")
	file.store_line("330"); file.store_line(handle_block_record_model)  # Pointeur vers Model_Space
	
	# Layout pour Paper Space
	file.store_line("0"); file.store_line("LAYOUT")
	file.store_line("5"); file.store_line(handle_layout_paper)  # Handle cohérent !
	file.store_line("330"); file.store_line(handle_dict_acad_layout)
	file.store_line("100"); file.store_line("AcDbPlotSettings")
	file.store_line("1"); file.store_line("Layout1")
	file.store_line("2"); file.store_line("none_device")
	file.store_line("4"); file.store_line("")
	file.store_line("6"); file.store_line("")
	file.store_line("40"); file.store_line("0.0")
	file.store_line("41"); file.store_line("0.0")
	file.store_line("42"); file.store_line("0.0")
	file.store_line("43"); file.store_line("0.0")
	file.store_line("44"); file.store_line("0.0")
	file.store_line("45"); file.store_line("0.0")
	file.store_line("46"); file.store_line("0.0")
	file.store_line("47"); file.store_line("0.0")
	file.store_line("48"); file.store_line("0.0")
	file.store_line("49"); file.store_line("0.0")
	file.store_line("140"); file.store_line("0.0")
	file.store_line("141"); file.store_line("0.0")
	file.store_line("142"); file.store_line("1.0")
	file.store_line("143"); file.store_line("1.0")
	file.store_line("70"); file.store_line("688")
	file.store_line("72"); file.store_line("0")
	file.store_line("73"); file.store_line("0")
	file.store_line("74"); file.store_line("5")
	file.store_line("7"); file.store_line("")
	file.store_line("75"); file.store_line("16")
	file.store_line("147"); file.store_line("1.0")
	file.store_line("148"); file.store_line("0.0")
	file.store_line("149"); file.store_line("0.0")
	file.store_line("100"); file.store_line("AcDbLayout")
	file.store_line("1"); file.store_line("Layout1")
	file.store_line("70"); file.store_line("1")
	file.store_line("71"); file.store_line("1")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("11"); file.store_line("12.0")
	file.store_line("21"); file.store_line("9.0")
	file.store_line("12"); file.store_line("0.0")
	file.store_line("22"); file.store_line("0.0")
	file.store_line("32"); file.store_line("0.0")
	file.store_line("14"); file.store_line("0.0")
	file.store_line("24"); file.store_line("0.0")
	file.store_line("34"); file.store_line("0.0")
	file.store_line("15"); file.store_line("0.0")
	file.store_line("25"); file.store_line("0.0")
	file.store_line("35"); file.store_line("0.0")
	file.store_line("146"); file.store_line("0.0")
	file.store_line("13"); file.store_line("0.0")
	file.store_line("23"); file.store_line("0.0")
	file.store_line("33"); file.store_line("0.0")
	file.store_line("16"); file.store_line("1.0")
	file.store_line("26"); file.store_line("0.0")
	file.store_line("36"); file.store_line("0.0")
	file.store_line("17"); file.store_line("0.0")
	file.store_line("27"); file.store_line("1.0")
	file.store_line("37"); file.store_line("0.0")
	file.store_line("76"); file.store_line("0")
	file.store_line("330"); file.store_line(handle_block_record_paper)  # Point vers le BLOCK_RECORD *Paper_Space
	
	# Dictionnaire ACAD_MLINESTYLE (minimaliste)
	file.store_line("0"); file.store_line("DICTIONARY")
	file.store_line("5"); file.store_line(handle_mline_dict)
	file.store_line("330"); file.store_line(handle_root_dict)  # Point vers le dictionnaire racine
	file.store_line("100"); file.store_line("AcDbDictionary")
	file.store_line("281"); file.store_line("1")
	file.store_line("3"); file.store_line("Standard")
	file.store_line("350"); file.store_line(handle_mline_standard)  # Pointeur cohérent !
	
	# MLINESTYLE Standard
	file.store_line("0"); file.store_line("MLINESTYLE")
	file.store_line("5"); file.store_line(handle_mline_standard)  # Handle cohérent !
	file.store_line("330"); file.store_line(handle_mline_dict)  # Point vers le dictionnaire
	file.store_line("100"); file.store_line("AcDbMlineStyle")
	file.store_line("2"); file.store_line("STANDARD")
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("")
	file.store_line("62"); file.store_line("256")
	file.store_line("51"); file.store_line("90.0")
	file.store_line("52"); file.store_line("90.0")
	file.store_line("71"); file.store_line("2")
	file.store_line("49"); file.store_line("0.5")
	file.store_line("62"); file.store_line("256")
	file.store_line("6"); file.store_line("BYLAYER")
	file.store_line("49"); file.store_line("-0.5")
	file.store_line("62"); file.store_line("256")
	file.store_line("6"); file.store_line("BYLAYER")
	
	# Dictionnaire ACAD_PLOTSETTINGS (vide)
	file.store_line("0"); file.store_line("DICTIONARY")
	file.store_line("5"); file.store_line(handle_dict_acad_plotsettings)
	file.store_line("330"); file.store_line(handle_root_dict)  # Point vers le dictionnaire racine
	file.store_line("100"); file.store_line("AcDbDictionary")
	file.store_line("281"); file.store_line("1")
	
	# Dictionnaire ACAD_PLOTSTYLENAME (minimaliste)
	file.store_line("0"); file.store_line("ACDBDICTIONARYWDFLT")
	file.store_line("5"); file.store_line(handle_dict_acad_plotstylename)
	file.store_line("330"); file.store_line(handle_root_dict)  # Point vers le dictionnaire racine
	file.store_line("100"); file.store_line("AcDbDictionary")
	file.store_line("281"); file.store_line("1")
	file.store_line("3"); file.store_line("Normal")
	file.store_line("350"); file.store_line(handle_placeholder)  # Pointeur cohérent !
	file.store_line("100"); file.store_line("AcDbDictionaryWithDefault")
	file.store_line("340"); file.store_line(handle_placeholder)
	
	# ACDBPLACEHOLDER obligatoire
	file.store_line("0"); file.store_line("ACDBPLACEHOLDER")
	file.store_line("5"); file.store_line(handle_placeholder)  # Handle cohérent !
	file.store_line("330"); file.store_line(handle_dict_acad_plotstylename)  # Point vers le dictionnaire
	
	file.store_line("0"); file.store_line("ENDSEC")
	
	# 8. EOF obligatoire
	file.store_line("0"); file.store_line("EOF")
	file.close()
	GlobalLogger.success("Export DXF 2000+ terminé.")
	return true

static func _write_entity_2000(file: FileAccess, ent, layer_name, layer_col: Color, active_ltypes: Dictionary, current_handle_int: int, model_space_handle: String) -> int:
	var lt = "CONTINUOUS"
	if "linetype" in ent: lt = ent.linetype
	var lw = -3
	if "lineweight" in ent: lw = _godot_weight_to_dxf(ent.lineweight)

	if ent.is_circle:
		var center = ent.circle_center + ent.position
		file.store_line("0"); file.store_line("CIRCLE")
		file.store_line("5"); file.store_line("%X" % current_handle_int); current_handle_int += 1
		file.store_line("330"); file.store_line(model_space_handle)
		file.store_line("100"); file.store_line("AcDbEntity")
		file.store_line("8"); file.store_line(layer_name)
		
		# --- Propriétés de style corrigées ---
		var write_lt = lt.to_upper()
		if write_lt == "GODOT_ISO02": write_lt = "ACAD_ISO02W100"
		elif write_lt == "GODOT_ISO03": write_lt = "ACAD_ISO03W100"
		
		# --- FILET DE SÉCURITÉ ABSOLU ---
		# Si le type de ligne n'existe pas dans le DXF, l'entité suit le calque.
		if not active_ltypes.has(write_lt):
			write_lt = "BYLAYER"
		
		if write_lt != "BYLAYER":
			file.store_line("6"); file.store_line(write_lt)
			
		if lw != -3: 
			file.store_line("370"); file.store_line(str(lw))
			
		# Gestion de la couleur (Code 62) - Calcul strict par index entier
		var aci = 256 # 256 = "ByLayer" par défaut
		var ent_col = null
		if "default_color" in ent: ent_col = ent.default_color
		elif "default_color_val" in ent: ent_col = ent.default_color_val
		
		if ent_col != null and typeof(ent_col) == TYPE_COLOR:
			var computed_aci = _color_to_aci(ent_col)
			var layer_aci = _color_to_aci(layer_col)
			
			# On filtre strictement la couleur du calque ET le gris de défaut Godot (250)
			if computed_aci != layer_aci and computed_aci != 250:
				aci = computed_aci
				
		if aci != 256:
			file.store_line("62"); file.store_line(str(aci))
		# -------------------------------------
		
		file.store_line("100"); file.store_line("AcDbCircle")
		file.store_line("10"); file.store_line(_f(center.x))
		file.store_line("20"); file.store_line(_f(-center.y))
		file.store_line("30"); file.store_line("0.0")
		file.store_line("40"); file.store_line(_f(ent.circle_radius))
	elif ent.is_arc:
		var center = ent.arc_center + ent.position
		file.store_line("0"); file.store_line("ARC")
		file.store_line("5"); file.store_line("%X" % current_handle_int); current_handle_int += 1
		file.store_line("330"); file.store_line(model_space_handle)
		file.store_line("100"); file.store_line("AcDbEntity")
		file.store_line("8"); file.store_line(layer_name)
		
		# --- Propriétés de style corrigées ---
		var write_lt = lt.to_upper()
		if write_lt == "GODOT_ISO02": write_lt = "ACAD_ISO02W100"
		elif write_lt == "GODOT_ISO03": write_lt = "ACAD_ISO03W100"
		
		# --- FILET DE SÉCURITÉ ABSOLU ---
		# Si le type de ligne n'existe pas dans le DXF, l'entité suit le calque.
		if not active_ltypes.has(write_lt):
			write_lt = "BYLAYER"
		
		if write_lt != "BYLAYER":
			file.store_line("6"); file.store_line(write_lt)
		
		if lw != -3: 
			file.store_line("370"); file.store_line(str(lw))
			
		# Gestion de la couleur (Code 62) - Calcul strict par index entier
		var aci = 256 # 256 = "ByLayer" par défaut
		var ent_col = null
		if "default_color" in ent: ent_col = ent.default_color
		elif "default_color_val" in ent: ent_col = ent.default_color_val
		
		if ent_col != null and typeof(ent_col) == TYPE_COLOR:
			var computed_aci = _color_to_aci(ent_col)
			var layer_aci = _color_to_aci(layer_col)
			
			# On filtre strictement la couleur du calque ET le gris de défaut Godot (250)
			if computed_aci != layer_aci and computed_aci != 250:
				aci = computed_aci
				
		if aci != 256:
			file.store_line("62"); file.store_line(str(aci))
		# -------------------------------------
		
		# 1. Héritage de la classe Cercle (Obligatoire pour le centre et le rayon)
		file.store_line("100"); file.store_line("AcDbCircle")
		file.store_line("10"); file.store_line(_f(center.x))
		file.store_line("20"); file.store_line(_f(-center.y))
		file.store_line("30"); file.store_line("0.0")
		file.store_line("40"); file.store_line(_f(ent.arc_radius))
		
		# 2. Sous-classe spécifique à l'Arc (Obligatoire pour les angles)
		file.store_line("100"); file.store_line("AcDbArc")

		# Conversion des angles pour AutoCAD
		var start_rad: float = ent.arc_start_angle
		var end_rad: float = ent.arc_end_angle
		var delta_rad: float = end_rad - start_rad

		var dxf_start = fposmod(rad_to_deg(-start_rad), 360.0)
		var dxf_end = fposmod(rad_to_deg(-end_rad), 360.0)

		var final_start: float
		var final_end: float

		if delta_rad > 0:
			final_start = dxf_end
			final_end = dxf_start
		else:
			final_start = dxf_start
			final_end = dxf_end

		var dxf_span = fposmod(final_end - final_start, 360.0)
		if dxf_span < 0.5 and abs(rad_to_deg(delta_rad)) > 180.0:
			final_end = fposmod(final_start + 359.99, 360.0)

		file.store_line("50"); file.store_line(_f(final_start))
		file.store_line("51"); file.store_line(_f(final_end))
	else:
		if ent.get_point_count() < 2: return current_handle_int
		
		# LWPOLYLINE format 2000+
		file.store_line("0"); file.store_line("LWPOLYLINE")
		file.store_line("5"); file.store_line("%X" % current_handle_int); current_handle_int += 1
		file.store_line("330"); file.store_line(model_space_handle)
		file.store_line("100"); file.store_line("AcDbEntity")
		file.store_line("8"); file.store_line(layer_name)
		
		# --- Propriétés de style corrigées ---
		var write_lt = lt.to_upper()
		if write_lt == "GODOT_ISO02": write_lt = "ACAD_ISO02W100"
		elif write_lt == "GODOT_ISO03": write_lt = "ACAD_ISO03W100"
		
		# --- FILET DE SÉCURITÉ ABSOLU ---
		# Si le type de ligne n'existe pas dans le DXF, l'entité suit le calque.
		if not active_ltypes.has(write_lt):
			write_lt = "BYLAYER"
		
		if write_lt != "BYLAYER":
			file.store_line("6"); file.store_line(write_lt)
			
		if lw != -3: 
			file.store_line("370"); file.store_line(str(lw))
			
		# Gestion de la couleur (Code 62) - Calcul strict par index entier
		var aci = 256 # 256 = "ByLayer" par défaut
		var ent_col = null
		if "default_color" in ent: ent_col = ent.default_color
		elif "default_color_val" in ent: ent_col = ent.default_color_val
		
		if ent_col != null and typeof(ent_col) == TYPE_COLOR:
			var computed_aci = _color_to_aci(ent_col)
			var layer_aci = _color_to_aci(layer_col)
			
			# On filtre strictement la couleur du calque ET le gris de défaut Godot (250)
			if computed_aci != layer_aci and computed_aci != 250:
				aci = computed_aci
				
		if aci != 256:
			file.store_line("62"); file.store_line(str(aci))
		# -------------------------------------
		
		file.store_line("100"); file.store_line("AcDbPolyline")
		file.store_line("90"); file.store_line(str(ent.get_point_count()))
		file.store_line("70"); file.store_line("0")
		
		if lw > 0:
			file.store_line("43"); file.store_line(_f(float(lw) / 100.0))
		
		for i in range(ent.get_point_count()):
			var pt = ent.points[i]
			if ent is Node2D: pt = ent.to_global(pt)
			file.store_line("10"); file.store_line(_f(pt.x))
			file.store_line("20"); file.store_line(_f(-pt.y))
	
	return current_handle_int

# --- UTILS & HELPERS ---

static func _sanitize_name(name: String) -> String:
	# Enlève les espaces et caractères spéciaux pour compatibilité R12 stricte
	var allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-$"
	var clean = ""
	for i in range(name.length()):
		var c = name[i]
		if allowed.contains(c): clean += c
		elif c == " ": clean += "_"
		else: clean += "_"
	return clean

static func _f(val: float) -> String:
	# Force le format décimal point (pas de virgule selon locale)
	return String.num(val, 6)

static func _create_imported_layer_v2000(manager, name, aci_color, linetype, lineweight):
	for l in manager.layers:
		if l.name.nocasecmp_to(name) == 0: return 
	var col = _aci_to_color(aci_color)
	manager.create_layer(name, col)
	var new_layer = manager.layers[-1]
	# Appliquer les propriétés supplémentaires du calque (modification directe du dictionnaire)
	new_layer.linetype = linetype
	new_layer.lineweight = _dxf_weight_to_godot(lineweight)

static func _create_imported_layer(manager, name, aci_color):
	# Version legacy pour compatibilité
	_create_imported_layer_v2000(manager, name, aci_color, "Continuous", -3)

static func _finalize_current_entity(main_node, type, points, center, radius, layer_name, l_type, l_weight, l_scale, arc_data = {}, lwpline_width = 0.0):
	if type == "CIRCLE":
		_spawn_on_layer(main_node, "CIRCLE", points, center, radius, layer_name, l_type, l_weight, l_scale)
	elif type == "ARC":
		_spawn_on_layer(main_node, "ARC", points, arc_data, arc_data.get("radius", 0.0), layer_name, l_type, l_weight, l_scale)
	elif type in ["LINE", "LWPOLYLINE", "POLYLINE"]:
		if points.size() >= 2:
			# Utiliser la largeur de la LWPOLYLINE si disponible, sinon celle de l'entité
			var final_weight = l_weight
			if type == "LWPOLYLINE" and lwpline_width > 0:
				final_weight = lwpline_width
			_spawn_on_layer(main_node, "POLYLINE", points, center, radius, layer_name, l_type, final_weight, l_scale)

static func _spawn_on_layer(main_node, type, points, center, radius, layer_name, l_type, l_weight, l_scale, start_angle = 0.0, end_angle = 0.0):
	# Réutilisation de votre logique existante mais nettoyée
	layer_name = layer_name.strip_edges()
	var target_node = main_node.world.get_node("Entities")
	var target_color = Color.WHITE
	var real_layer_name = "0"
	var layer_found = false
	
	if main_node.layer_manager:
		for l in main_node.layer_manager.layers:
			if l.name.nocasecmp_to(layer_name) == 0:
				target_node = l.node
				target_color = l.color
				real_layer_name = l.name
				layer_found = true
				break
	
	if not layer_found and layer_name != "0":
		main_node.layer_manager.create_layer(layer_name, Color.WHITE)
		var new_layer = main_node.layer_manager.layers[-1]
		target_node = new_layer.node
		target_color = new_layer.color
		real_layer_name = new_layer.name
	
	var ent = null
	if type == "CIRCLE":
		ent = main_node.drawing_manager.spawn_circle(center, radius, false)
	elif type == "ARC":
		# Créer un arc à partir des données DXF
		if center is Dictionary:
			ent = _spawn_arc_from_dxf(main_node, center.center, center.radius, center.start_angle, center.end_angle)
		else:
			# Fallback si ce n'est pas un dictionnaire
			ent = null
	else:
		ent = main_node.drawing_manager.spawn_polyline(false)
		ent.points = PackedVector2Array(points)
		
	if ent:
		ent.reparent(target_node)
		ent.layer_name = real_layer_name
		ent.default_color = target_color
		if "default_color_val" in ent: ent.default_color_val = target_color
		
		# Mapping Linetype import
		if l_type.to_upper() == "CONTINUOUS": ent.linetype = "CONTINUOUS"
		elif l_type.to_upper() == "BYLAYER": ent.linetype = "ByLayer"  # On remet pour Godot
		elif l_type.to_upper() == "ACAD_ISO02W100": ent.linetype = "GODOT_ISO02" 
		elif l_type.to_upper() == "ACAD_ISO03W100": ent.linetype = "GODOT_ISO03" 
		else: ent.linetype = l_type 
		
		if "linetype_scale" in ent:
			ent.linetype_scale = l_scale
		
		ent.lineweight = l_weight
		if ent.has_method("update_visuals"): ent.update_visuals()

static func _aci_to_color(aci: int) -> Color:
	var idx = abs(aci)
	if ACI_COLORS.has(idx): return ACI_COLORS[idx]
	return Color.WHITE 

static func _color_to_aci(col: Color) -> int:
	var r = int(col.r * 255); var g = int(col.g * 255); var b = int(col.b * 255)
	
	# 1. Nuances de gris exactes
	if r == g and g == b:
		if r >= 250: return 7  # Blanc
		if r <= 5: return 250  # Noir absolu
		if r > 200: return 254
		if r > 150: return 9
		if r > 100: return 8
		if r > 50: return 251
		return 250
	
	# 2. Couleurs primaires pures (Rouge, Jaune, Vert, Cyan, Bleu, Magenta)
	if r > 200 and g < 50 and b < 50: return 1
	if r > 200 and g > 200 and b < 50: return 2
	if r < 50 and g > 200 and b < 50: return 3
	if r < 50 and g > 200 and b > 200: return 4
	if r < 50 and g < 50 and b > 200: return 5
	if r > 200 and g < 50 and b > 200: return 6
	
	# 3. Calcul par découpage de la roue des teintes (HLS -> ACI)
	var h = col.h * 24.0 # AutoCAD divise sa roue en 24 secteurs
	var hue_idx = int(round(h)) % 24
	
	var v = col.v
	var s = col.s
	
	# Détermination de la clarté (5 niveaux d'AutoCAD)
	var light_idx = 0
	if v > 0.8: light_idx = 0 if s > 0.5 else 1
	elif v > 0.6: light_idx = 2 if s > 0.5 else 3
	else: light_idx = 4
	
	# La roue commence à l'index 10, chaque secteur compte 10 index
	var aci = 10 + (hue_idx * 10) + light_idx
	return clampi(aci, 1, 255)

static func _dxf_weight_to_godot(val_int: int) -> float:
	if val_int < 0: return -1.0
	return float(val_int) / 100.0

static func _godot_weight_to_dxf(val: float) -> int:
	if val <= 0.0:
		return -1
	return int(round(val * 100.0))

# --- FONCTIONS SPÉCIFIQUES AUX ARCS ---

static func _spawn_arc_from_dxf(main_node, center: Vector2, radius: float, start_angle_deg: float, end_angle_deg: float) -> Line2D:
	# Convertir les angles de degrés en radians pour Godot
	# Note: les angles DXF sont déjà dans le bon système pour AutoCAD
	var start_angle = deg_to_rad(start_angle_deg)
	var end_angle = deg_to_rad(end_angle_deg)
	
	# Créer l'arc via le DrawingManager
	return main_node.drawing_manager.spawn_arc(center, radius, start_angle, end_angle, false)

# ------------------------------------------------------------------------------
# EXPORTATION LEGACY R12 (pour compatibilité)
# ------------------------------------------------------------------------------
static func save_dxf_r12_legacy(filepath: String, main_node: Node):
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file: 
		return false

	# Header R12
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("HEADER")
	file.store_line("9"); file.store_line("$ACADVER")
	file.store_line("1"); file.store_line("AC1009")  # R12
	file.store_line("9"); file.store_line("$INSBASE")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("0"); file.store_line("ENDSEC")

	# Tables R12
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("TABLES")
	
	# LTYPE
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LTYPE")
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("LTYPE")
	file.store_line("2"); file.store_line("CONTINUOUS")
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("Solid line")
	file.store_line("72"); file.store_line("65")
	file.store_line("73"); file.store_line("0")
	file.store_line("40"); file.store_line("0.0")
	file.store_line("0"); file.store_line("ENDTAB")

	# LAYER
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LAYER")
	var layers = []
	if main_node.layer_manager: layers = main_node.layer_manager.layers
	file.store_line("70"); file.store_line(str(layers.size() + 1))
	file.store_line("0"); file.store_line("LAYER")
	file.store_line("2"); file.store_line("0")
	file.store_line("70"); file.store_line("0")
	file.store_line("62"); file.store_line("7")
	file.store_line("6"); file.store_line("CONTINUOUS")

	for layer in layers:
		var lname = _sanitize_name(layer.name)
		if lname == "0": continue
		file.store_line("0"); file.store_line("LAYER")
		file.store_line("2"); file.store_line(lname)
		file.store_line("70"); file.store_line("0")
		file.store_line("62"); file.store_line(str(_color_to_aci(layer.color)))
		file.store_line("6"); file.store_line("CONTINUOUS")
	file.store_line("0"); file.store_line("ENDTAB")
	file.store_line("0"); file.store_line("ENDSEC")

	# Blocks
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("BLOCKS")
	file.store_line("0"); file.store_line("BLOCK")
	file.store_line("8"); file.store_line("0")
	file.store_line("2"); file.store_line("$MODEL_SPACE")
	file.store_line("70"); file.store_line("0")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("3"); file.store_line("$MODEL_SPACE")
	file.store_line("1"); file.store_line("")
	file.store_line("0"); file.store_line("ENDBLK")
	file.store_line("0"); file.store_line("BLOCK")
	file.store_line("8"); file.store_line("0")
	file.store_line("2"); file.store_line("$PAPER_SPACE")
	file.store_line("70"); file.store_line("0")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("3"); file.store_line("$PAPER_SPACE")
	file.store_line("1"); file.store_line("")
	file.store_line("0"); file.store_line("ENDBLK")
	file.store_line("0"); file.store_line("ENDSEC")

	# Entities R12 (POLYLINE/VERTEX)
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("ENTITIES")

	var root_entities = main_node.world.get_node("Entities")
	for layer_node in root_entities.get_children():
		if layer_node is Node2D and not (layer_node is CADEntity):
			var layer_name = _sanitize_name(layer_node.name)
			for child in layer_node.get_children():
				if child is CADEntity: _write_entity_r12(file, child, layer_name)
		elif layer_node is CADEntity:
			_write_entity_r12(file, layer_node, "0")

	file.store_line("0"); file.store_line("ENDSEC")
	file.store_line("0"); file.store_line("EOF")
	file.close()
	GlobalLogger.success("Export R12 terminé.")
	return true

static func _write_entity_r12(file: FileAccess, ent, layer_name):
	var lt = "CONTINUOUS"
	if "linetype" in ent: lt = "CONTINUOUS"  # Forcé pour R12

	if ent.is_circle:
		var center = ent.circle_center + ent.position
		file.store_line("0"); file.store_line("CIRCLE")
		file.store_line("8"); file.store_line(layer_name)
		file.store_line("6"); file.store_line(lt)
		file.store_line("62"); file.store_line("256")
		file.store_line("10"); file.store_line(_f(center.x))
		file.store_line("20"); file.store_line(_f(-center.y))
		file.store_line("30"); file.store_line("0.0")
		file.store_line("40"); file.store_line(_f(ent.circle_radius))
	elif ent.is_arc:
		var center = ent.arc_center + ent.position
		file.store_line("0"); file.store_line("ARC")
		file.store_line("8"); file.store_line(layer_name)
		file.store_line("6"); file.store_line(lt)
		file.store_line("62"); file.store_line("256")
		file.store_line("10"); file.store_line(_f(center.x))
		file.store_line("20"); file.store_line(_f(-center.y))
		file.store_line("30"); file.store_line("0.0")
		file.store_line("40"); file.store_line(_f(ent.arc_radius))

		var start_rad: float = ent.arc_start_angle
		var end_rad: float = ent.arc_end_angle
		var delta_rad: float = end_rad - start_rad

		var dxf_start = fposmod(rad_to_deg(-start_rad), 360.0)
		var dxf_end = fposmod(rad_to_deg(-end_rad), 360.0)

		var final_start: float
		var final_end: float

		if delta_rad > 0:
			final_start = dxf_end
			final_end = dxf_start
		else:
			final_start = dxf_start
			final_end = dxf_end

		var dxf_span = fposmod(final_end - final_start, 360.0)
		if dxf_span < 0.5 and abs(rad_to_deg(delta_rad)) > 180.0:
			final_end = fposmod(final_start + 359.99, 360.0)

		file.store_line("50"); file.store_line(_f(final_start))
		file.store_line("51"); file.store_line(_f(final_end))
	else:
		if ent.get_point_count() < 2: return
		
		# POLYLINE R12
		file.store_line("0"); file.store_line("POLYLINE")
		file.store_line("8"); file.store_line(layer_name)
		var polyline_lt = "CONTINUOUS"
		if ent.has("linetype"): polyline_lt = ent.linetype
		file.store_line("6"); file.store_line(polyline_lt)
		file.store_line("62"); file.store_line("256")
		file.store_line("66"); file.store_line("1")
		file.store_line("10"); file.store_line("0.0")
		file.store_line("20"); file.store_line("0.0")
		file.store_line("30"); file.store_line("0.0")
		file.store_line("70"); file.store_line("0")
		
		for i in range(ent.get_point_count()):
			var pt = ent.points[i]
			if ent is Node2D: pt = ent.to_global(pt)
			file.store_line("0"); file.store_line("VERTEX")
			file.store_line("8"); file.store_line(layer_name)
			file.store_line("10"); file.store_line(_f(pt.x))
			file.store_line("20"); file.store_line(_f(-pt.y))
			file.store_line("30"); file.store_line("0.0")
		file.store_line("0"); file.store_line("SEQEND")
		file.store_line("8"); file.store_line(layer_name)
