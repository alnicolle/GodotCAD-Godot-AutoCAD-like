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
	GlobalLogger.success("Import terminé.")

# ------------------------------------------------------------------------------
# EXPORTATION (Point d'entrée principal)
# ------------------------------------------------------------------------------
static func save_dxf(filepath: String, main_node: Node, use_2000_format: bool = true):
	if use_2000_format:
		save_dxf_2000(filepath, main_node)
	else:
		save_dxf_r12_legacy(filepath, main_node)

# ------------------------------------------------------------------------------
# EXPORTATION (Format DXF 2000+)
# ------------------------------------------------------------------------------

# Gestionnaire de handles global pour l'exportation DXF
class HandleManager:
	var current_handle_int: int = 1
	
	func get_new_handle() -> String:
		var hex_string = "%X" % current_handle_int
		current_handle_int += 1
		return hex_string

static func save_dxf_2000(filepath: String, main_node: Node):
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file: return

	var handle_mgr = HandleManager.new()

	# 1. PRÉ-GÉNÉRATION DES HANDLES CLÉS (pour garantir la cohérence des pointeurs)
	var handle_root_dict = handle_mgr.get_new_handle()
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
	
	var handle_block_record_model = handle_mgr.get_new_handle()
	var handle_block_model = handle_mgr.get_new_handle()
	var handle_endblk_model = handle_mgr.get_new_handle()
	var handle_block_record_paper = handle_mgr.get_new_handle()
	var handle_block_paper = handle_mgr.get_new_handle()
	var handle_endblk_paper = handle_mgr.get_new_handle()

	# 2. HEADER (DXF 2000+ = AC1015) complet
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("HEADER")
	file.store_line("9"); file.store_line("$ACADVER")
	file.store_line("1"); file.store_line("AC1015")  # DXF 2000+
	file.store_line("9"); file.store_line("$HANDSEED")
	file.store_line("5"); file.store_line("FFFF")
	file.store_line("9"); file.store_line("$INSBASE")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$EXTMIN")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("9"); file.store_line("$EXTMAX")
	file.store_line("10"); file.store_line("1000.0")
	file.store_line("20"); file.store_line("1000.0")
	file.store_line("30"); file.store_line("0.0")
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
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("VPORT")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
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
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table LTYPE
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LTYPE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("5")  # 5 types obligatoires
	
	# 1. ByLayer (Obligatoire)
	file.store_line("0"); file.store_line("LTYPE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")
	file.store_line("100"); file.store_line("AcDbLinetypeTableRecord")
	file.store_line("2"); file.store_line("ByLayer")  # Respecter la casse exacte
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("")
	file.store_line("72"); file.store_line("65")
	file.store_line("73"); file.store_line("0")
	file.store_line("40"); file.store_line("0.0")

	# 2. ByBlock (Obligatoire)
	file.store_line("0"); file.store_line("LTYPE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")
	file.store_line("100"); file.store_line("AcDbLinetypeTableRecord")
	file.store_line("2"); file.store_line("ByBlock")  # Respecter la casse exacte
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("")
	file.store_line("72"); file.store_line("65")
	file.store_line("73"); file.store_line("0")
	file.store_line("40"); file.store_line("0.0")

	# 3. CONTINUOUS
	file.store_line("0"); file.store_line("LTYPE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")
	file.store_line("100"); file.store_line("AcDbLinetypeTableRecord")
	file.store_line("2"); file.store_line("CONTINUOUS")
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("Solid line")
	file.store_line("72"); file.store_line("65")
	file.store_line("73"); file.store_line("0")
	file.store_line("40"); file.store_line("0.0")
	
	# 4. ACAD_ISO02W100
	file.store_line("0"); file.store_line("LTYPE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")
	file.store_line("100"); file.store_line("AcDbLinetypeTableRecord")
	file.store_line("2"); file.store_line("ACAD_ISO02W100")
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("ISO dash __ __ __ __ __ __ __ __ __ __ __ __ __ __ _")
	file.store_line("72"); file.store_line("65")
	file.store_line("73"); file.store_line("2")
	file.store_line("40"); file.store_line("12.0")
	file.store_line("49"); file.store_line("6.0")
	file.store_line("74"); file.store_line("0")
	file.store_line("49"); file.store_line("-6.0")
	file.store_line("74"); file.store_line("0")
	
	# 5. ACAD_ISO03W100
	file.store_line("0"); file.store_line("LTYPE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")
	file.store_line("100"); file.store_line("AcDbLinetypeTableRecord")
	file.store_line("2"); file.store_line("ACAD_ISO03W100")
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("ISO dash space __ __ __ __ __ __ __ __ __ __ __ __ __")
	file.store_line("72"); file.store_line("65")
	file.store_line("73"); file.store_line("2")
	file.store_line("40"); file.store_line("12.0")
	file.store_line("49"); file.store_line("8.0")
	file.store_line("74"); file.store_line("0")
	file.store_line("49"); file.store_line("-4.0")
	file.store_line("74"); file.store_line("0")
	
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table LAYER avec propriétés complètes
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LAYER")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	
	var layers = []
	if main_node.layer_manager: layers = main_node.layer_manager.layers
	file.store_line("70"); file.store_line(str(layers.size() + 1))
	
	# Calque 0 par défaut
	file.store_line("0"); file.store_line("LAYER")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbLayerTableRecord")
	file.store_line("2"); file.store_line("0")
	file.store_line("70"); file.store_line("0")
	file.store_line("62"); file.store_line("7")
	file.store_line("6"); file.store_line("CONTINUOUS")
	file.store_line("370"); file.store_line("-3")
	file.store_line("390"); file.store_line(handle_placeholder)  # Pointeur dynamique vers ACDBPLACEHOLDER
	
	# Calques personnalisés avec leurs propriétés
	for layer in layers:
		var lname = layer.name
		if lname == "0": continue
		
		file.store_line("0"); file.store_line("LAYER")
		file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
		file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
		file.store_line("100"); file.store_line("AcDbLayerTableRecord")
		file.store_line("2"); file.store_line(lname)  # Garder la casse originale
		file.store_line("70"); file.store_line("0")
		file.store_line("62"); file.store_line(str(_color_to_aci(layer.color)))
		
		# Type de ligne
		var lt = "CONTINUOUS"
		if layer.has("linetype"): lt = layer.linetype
		file.store_line("6"); file.store_line(lt)
		
		# Épaisseur
		var lw = -3  # Par défaut
		if layer.has("lineweight"): lw = _godot_weight_to_dxf(layer.lineweight)
		file.store_line("370"); file.store_line(str(lw))
		file.store_line("390"); file.store_line(handle_placeholder)  # Pointeur dynamique vers ACDBPLACEHOLDER
	
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table STYLE
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("STYLE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("STYLE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
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
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("0")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table UCS
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("UCS")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("0")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table APPID
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("APPID")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("APPID")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbRegAppTableRecord")
	file.store_line("2"); file.store_line("ACAD")
	file.store_line("70"); file.store_line("0")
	file.store_line("0"); file.store_line("ENDTAB")
	
	# Table DIMSTYLE
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("DIMSTYLE")
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("1")
	file.store_line("100"); file.store_line("AcDbDimStyleTable")  # Classe de la table
	file.store_line("0"); file.store_line("DIMSTYLE")
	file.store_line("105"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTableRecord")  # Classe mère
	file.store_line("100"); file.store_line("AcDbDimStyleTableRecord")
	file.store_line("2"); file.store_line("STANDARD")
	file.store_line("70"); file.store_line("0")
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
	file.store_line("5"); file.store_line(handle_mgr.get_new_handle())
	file.store_line("100"); file.store_line("AcDbSymbolTable")
	file.store_line("70"); file.store_line("2")
	
	# Model Space
	file.store_line("0"); file.store_line("BLOCK_RECORD")
	file.store_line("5"); file.store_line(handle_block_record_model)
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
			for child in layer_node.get_children():
				if child is CADEntity: 
					handle_mgr.current_handle_int = _write_entity_2000(file, child, layer_name, handle_mgr.current_handle_int, handle_block_record_model)
		elif layer_node is CADEntity:
			handle_mgr.current_handle_int = _write_entity_2000(file, layer_node, "0", handle_mgr.current_handle_int, handle_block_record_model)

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
	file.store_line("100"); file.store_line("AcDbLayout")  # Ensuite le Layout
	file.store_line("1"); file.store_line("Model")
	file.store_line("70"); file.store_line("1")
	file.store_line("71"); file.store_line("0")
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("11"); file.store_line("420.0")
	file.store_line("21"); file.store_line("297.0")
	file.store_line("12"); file.store_line("0.0")
	file.store_line("22"); file.store_line("0.0")
	file.store_line("13"); file.store_line("0.0")
	file.store_line("23"); file.store_line("0.0")
	file.store_line("14"); file.store_line("210.0")
	file.store_line("24"); file.store_line("148.5")
	file.store_line("15"); file.store_line("0.0")
	file.store_line("25"); file.store_line("0.0")
	file.store_line("16"); file.store_line("0.0")
	file.store_line("26"); file.store_line("0.0")
	file.store_line("17"); file.store_line("0.0")
	file.store_line("27"); file.store_line("0.0")
	file.store_line("90"); file.store_line("7")
	file.store_line("146"); file.store_line("0.0")
	file.store_line("13"); file.store_line("0.0")
	file.store_line("23"); file.store_line("0.0")
	file.store_line("70"); file.store_line("64768")
	file.store_line("71"); file.store_line("3")
	file.store_line("40"); file.store_line("0.0")
	file.store_line("41"); file.store_line("0.0")
	file.store_line("42"); file.store_line("0.0")
	file.store_line("43"); file.store_line("0.0")
	file.store_line("70"); file.store_line("0")
	file.store_line("71"); file.store_line("0")
	file.store_line("72"); file.store_line("0")
	file.store_line("73"); file.store_line("0")
	file.store_line("74"); file.store_line("0")
	file.store_line("75"); file.store_line("0")
	file.store_line("76"); file.store_line("0")
	file.store_line("77"); file.store_line("0")
	file.store_line("78"); file.store_line("0")  # Integer, pas float
	file.store_line("281"); file.store_line("0")
	file.store_line("65"); file.store_line("1")
	file.store_line("74"); file.store_line("0")
	file.store_line("110"); file.store_line("0.0")
	file.store_line("120"); file.store_line("0.0")
	file.store_line("130"); file.store_line("0.0")
	file.store_line("111"); file.store_line("0.0")
	file.store_line("121"); file.store_line("0.0")
	file.store_line("131"); file.store_line("0.0")
	file.store_line("112"); file.store_line("0.0")
	file.store_line("122"); file.store_line("0.0")
	file.store_line("132"); file.store_line("0.0")
	# Pas de pointeur 340 ici (supprimé)
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

static func _write_entity_2000(file: FileAccess, ent, layer_name, current_handle_int: int, model_space_handle: String) -> int:
	# Récupérer les propriétés de l'entité
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
		if lt.to_upper() != "BYLAYER":
			file.store_line("6"); file.store_line(lt)
		if lw != -3:  # -3 correspond à l'épaisseur ByLayer en DXF
			file.store_line("370"); file.store_line(str(lw))
		# (On ignore volontairement le code 62 pour la couleur ByLayer)
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
		if lt.to_upper() != "BYLAYER":
			file.store_line("6"); file.store_line(lt)
		if lw != -3:  # -3 correspond à l'épaisseur ByLayer en DXF
			file.store_line("370"); file.store_line(str(lw))
		# (On ignore volontairement le code 62 pour la couleur ByLayer)
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
		if lt.to_upper() != "BYLAYER":
			file.store_line("6"); file.store_line(lt)
		if lw != -3:  # -3 correspond à l'épaisseur ByLayer en DXF
			file.store_line("370"); file.store_line(str(lw))
		# (On ignore volontairement le code 62 pour la couleur ByLayer)
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
		if l_type.to_upper() == "CONTINUOUS": ent.linetype = "Continuous"
		elif l_type.to_upper() == "BYLAYER": ent.linetype = "ByLayer"  # On remet pour Godot
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
	var min_dist = 999.0
	var best_aci = 7
	for aci in ACI_COLORS:
		var ref_col = ACI_COLORS[aci]
		var d = (ref_col.r - col.r)**2 + (ref_col.g - col.g)**2 + (ref_col.b - col.b)**2
		if d < min_dist: min_dist = d; best_aci = aci
	return best_aci

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
	if not file: return

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
		file.store_line("6"); file.store_line(lt)
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
