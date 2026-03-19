class_name DXFService
extends RefCounted

const DEBUG_DXF_ARC = true

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
				_finalize_current_entity(main_node, current_entity, temp_points, c_center, c_radius, entity_layer, entity_linetype, entity_lineweight, entity_linetype_scale, current_arc_data)
			current_section = "NONE"
			continue

		# TABLES (CALQUES)
		if current_section == "TABLES":
			if code == "0" and value == "TABLE": continue
			if code == "2" and value == "LAYER": current_table = "LAYER"; continue
			if code == "0" and value == "ENDTAB":
				if current_table == "LAYER" and reading_layer_name != "":
					_create_imported_layer(layer_manager, reading_layer_name, reading_layer_color)
					reading_layer_name = ""
				current_table = "NONE"
				continue
			
			if current_table == "LAYER":
				if code == "0" and value == "LAYER":
					if reading_layer_name != "": _create_imported_layer(layer_manager, reading_layer_name, reading_layer_color)
					reading_layer_name = ""; reading_layer_color = 7
				if code == "2": reading_layer_name = value.strip_edges()
				if code == "62": reading_layer_color = abs(int(value))

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
					_finalize_current_entity(main_node, current_entity, temp_points, c_center, c_radius, entity_layer, entity_linetype, entity_lineweight, entity_linetype_scale, current_arc_data)
					temp_points = []; c_center = Vector2.ZERO; c_radius = 0.0
					entity_layer = "0"; entity_linetype = "ByLayer"; entity_lineweight = -1.0; entity_linetype_scale = 1.0

				current_entity = next_type
				if current_entity == "LINE": temp_points = [Vector2.ZERO, Vector2.ZERO]
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
					if code == "10": temp_points.append(Vector2(float(value), 0))
					if code == "20" and temp_points.size() > 0: temp_points[-1].y = -float(value)
				elif current_entity == "VERTEX":
					if temp_points.size() > 0:
						if code == "10": temp_points[-1].x = float(value)
						if code == "20": temp_points[-1].y = -float(value)

	file.close()
	GlobalLogger.success("Import terminé.")

# ------------------------------------------------------------------------------
# EXPORTATION (Safe Mode R12)
# ------------------------------------------------------------------------------
static func save_dxf_r12(filepath: String, main_node: Node):
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file: return

	# 1. HEADER (Minimaliste)
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("HEADER")
	file.store_line("9"); file.store_line("$ACADVER")
	# R12 = AC1009. AutoCAD est beaucoup plus tolérant avec ce format.
	file.store_line("1"); file.store_line("AC1009")
	file.store_line("9"); file.store_line("$INSBASE") # Point de base 0,0,0
	file.store_line("10"); file.store_line("0.0")
	file.store_line("20"); file.store_line("0.0")
	file.store_line("30"); file.store_line("0.0")
	file.store_line("0"); file.store_line("ENDSEC")

	# 2. TABLES
	file.store_line("0"); file.store_line("SECTION")
	file.store_line("2"); file.store_line("TABLES")
	
	# Table LTYPE (R12 strict)
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LTYPE")
	
	# Pour maximiser la compatibilité, on exporte uniquement CONTINUOUS.
	# Les BYLAYER/BYBLOCK peuvent être utilisés en entité, mais ne sont pas nécessaires ici.
	file.store_line("70"); file.store_line("1")
	file.store_line("0"); file.store_line("LTYPE")
	file.store_line("2"); file.store_line("CONTINUOUS")
	file.store_line("70"); file.store_line("0")
	file.store_line("3"); file.store_line("Solid line")
	file.store_line("72"); file.store_line("65")
	file.store_line("73"); file.store_line("0")
	file.store_line("40"); file.store_line("0.0")
	file.store_line("0"); file.store_line("ENDTAB")

	# Table LAYER (toujours inclure le calque 0)
	file.store_line("0"); file.store_line("TABLE")
	file.store_line("2"); file.store_line("LAYER")
	
	var layers = []
	if main_node.layer_manager: layers = main_node.layer_manager.layers
	# +1 pour le calque 0
	file.store_line("70"); file.store_line(str(layers.size() + 1))
	file.store_line("0"); file.store_line("LAYER")
	file.store_line("2"); file.store_line("0")
	file.store_line("70"); file.store_line("0")
	file.store_line("62"); file.store_line("7")
	file.store_line("6"); file.store_line("CONTINUOUS")
	for layer in layers:
		var lname = _sanitize_name(layer.name)
		if lname == "0":
			continue
		file.store_line("0"); file.store_line("LAYER")
		file.store_line("2"); file.store_line(lname)
		file.store_line("70"); file.store_line("0")
		file.store_line("62"); file.store_line(str(_color_to_aci(layer.color)))
		file.store_line("6"); file.store_line("CONTINUOUS")
	file.store_line("0"); file.store_line("ENDTAB")
	file.store_line("0"); file.store_line("ENDSEC")

	# 2.5 BLOCKS (minimal) - souvent attendu par AutoCAD même si ENTITIES suffit.
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

	# 3. ENTITIES
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
	# Type de ligne safe
	var lt = "CONTINUOUS"
	if "linetype" in ent:
		# On force CONTINUOUS dans le fichier pour éviter toute dépendance de table LTYPE.
		lt = "CONTINUOUS"

	# R12 : éviter les group codes non supportés (48, 370) car certains lecteurs rejettent.
	# On garde les entités simples avec couche + type.

	if ent.is_circle:
		var center = ent.circle_center + ent.position
		file.store_line("0"); file.store_line("CIRCLE")
		file.store_line("8"); file.store_line(layer_name)
		file.store_line("6"); file.store_line(lt)
		file.store_line("62"); file.store_line("256") # DuCalque
		file.store_line("10"); file.store_line(_f(center.x))
		file.store_line("20"); file.store_line(_f(-center.y))
		file.store_line("30"); file.store_line("0.0")
		file.store_line("40"); file.store_line(_f(ent.circle_radius))
	elif ent.is_arc:
		var center = ent.arc_center + ent.position
		file.store_line("0"); file.store_line("ARC")
		file.store_line("8"); file.store_line(layer_name)
		file.store_line("6"); file.store_line(lt)
		file.store_line("62"); file.store_line("256") # DuCalque
		file.store_line("10"); file.store_line(_f(center.x))
		file.store_line("20"); file.store_line(_f(-center.y))  # Inverser Y pour DXF [cite: 25]
		file.store_line("30"); file.store_line("0.0")
		file.store_line("40"); file.store_line(_f(ent.arc_radius))

		# 1. Récupération des angles Godot
		var start_rad: float = ent.arc_start_angle
		var end_rad: float = ent.arc_end_angle
		var delta_rad: float = end_rad - start_rad

		# 2. Conversion basique pour AutoCAD (Inversion du signe de l'angle car Y est inversé) 
		var dxf_start = fposmod(rad_to_deg(-start_rad), 360.0)
		var dxf_end = fposmod(rad_to_deg(-end_rad), 360.0)

		var final_start: float
		var final_end: float

		# 3. Choix des angles selon le sens de dessin original
		if delta_rad > 0:
			# Godot a tracé en CW (Y-down). 
			# Pour tracer la même forme en CCW (AutoCAD), on inverse les bornes.
			final_start = dxf_end
			final_end = dxf_start
		else:
			# Godot a tracé en CCW. 
			# L'ordre originel correspond déjà à la norme AutoCAD.
			final_start = dxf_start
			final_end = dxf_end

		# 4. Sécurité pour les arcs quasi-complets (DXF rejette Start == End)
		var dxf_span = fposmod(final_end - final_start, 360.0)
		if dxf_span < 0.5 and abs(rad_to_deg(delta_rad)) > 180.0:
			final_end = fposmod(final_start + 359.99, 360.0)

		if DEBUG_DXF_ARC:
			print("[DXF ARC] layer=", layer_name,
				" center=", center,
				" start_rad=", start_rad,
				" end_rad=", end_rad,
				" dxf_start=", final_start,
				" dxf_end=", final_end)

		file.store_line("50"); file.store_line(_f(final_start))
		file.store_line("51"); file.store_line(_f(final_end))
	else:
		if ent.get_point_count() < 2: return
		
		# Calcul largeur
		var w = 0.0
		if "lineweight" in ent and ent.lineweight > 0: w = ent.lineweight
		
		# R12 natif : POLYLINE + VERTEX + SEQEND
		file.store_line("0"); file.store_line("POLYLINE")
		file.store_line("8"); file.store_line(layer_name)
		file.store_line("6"); file.store_line(lt)
		file.store_line("62"); file.store_line("256") # DuCalque
		file.store_line("66"); file.store_line("1")
		file.store_line("10"); file.store_line("0.0")
		file.store_line("20"); file.store_line("0.0")
		file.store_line("30"); file.store_line("0.0")
		file.store_line("70"); file.store_line("0")
		# Largeur globale (optionnelle)
		if w > 0:
			file.store_line("40"); file.store_line(_f(w))
			file.store_line("41"); file.store_line(_f(w))
		for i in range(ent.get_point_count()):
			var pt = ent.points[i]
			if ent is Node2D: pt = ent.to_global(pt)
			file.store_line("0"); file.store_line("VERTEX")
			file.store_line("8"); file.store_line(layer_name)
			file.store_line("10"); file.store_line(_f(pt.x))
			file.store_line("20"); file.store_line(_f(-pt.y))
			file.store_line("30"); file.store_line("0.0")
			if w > 0:
				file.store_line("40"); file.store_line(_f(w))
				file.store_line("41"); file.store_line(_f(w))
		file.store_line("0"); file.store_line("SEQEND")
		file.store_line("8"); file.store_line(layer_name)

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

static func _create_imported_layer(manager, name, aci_color):
	for l in manager.layers:
		if l.name.nocasecmp_to(name) == 0: return 
	var col = _aci_to_color(aci_color)
	manager.create_layer(name, col)

static func _finalize_current_entity(main_node, type, points, center, radius, layer_name, l_type, l_weight, l_scale, arc_data = {}):
	if type == "CIRCLE":
		_spawn_on_layer(main_node, "CIRCLE", points, center, radius, layer_name, l_type, l_weight, l_scale)
	elif type == "ARC":
		_spawn_on_layer(main_node, "ARC", points, arc_data, arc_data.get("radius", 0.0), layer_name, l_type, l_weight, l_scale)
	elif type in ["LINE", "LWPOLYLINE", "POLYLINE"]:
		if points.size() >= 2:
			_spawn_on_layer(main_node, "POLYLINE", points, center, radius, layer_name, l_type, l_weight, l_scale)

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
		elif l_type.to_upper() == "BYLAYER": ent.linetype = "ByLayer"
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
