extends Node
class_name RDMController

# --- RÉFÉRENCES ---
# À lier dans l'inspecteur Godot en glissant ton nœud Main (ou World) ici
@export var main_node: Node2D 

# --- VARIABLES D'ÉTAT RDM ---
var rdm_manager
var distributed_force_start: Vector2 = Vector2.INF
var is_creating_distributed_force: bool = false
var rdm_place_mode: String = ""
var rdm_place_support_type: String = ""
var rdm_place_force_value: Vector2 = Vector2.ZERO
var rdm_consume_left_release: bool = false

func _ready():
	# Initialisation retardée du manager si nécessaire
	pass

# --- GESTION DES ÉTATS DE PLACEMENT ---

func start_placement(mode: String, support_type: String = "", force_val: Vector2 = Vector2.ZERO):
	rdm_place_mode = mode
	rdm_place_support_type = support_type
	rdm_place_force_value = force_val
	
	if mode == "distributed_start":
		is_creating_distributed_force = true
		GlobalLogger.info(tr("MSG_RDM_LOAD_1"))
	elif mode == "support":
		GlobalLogger.info(tr("MSG_RDM_SUPPORT_1") + support_type)
	elif mode == "force":
		GlobalLogger.info("RDM: cliquez pour placer une force ponctuelle")
		
	# Activer le curseur pour le snap
	if main_node and main_node.cad_cursor:
		main_node.cad_cursor.show_crosshair = true
		main_node.cad_cursor.queue_redraw()

func cancel_placement():
	rdm_place_mode = ""
	rdm_consume_left_release = false
	distributed_force_start = Vector2.INF
	is_creating_distributed_force = false
	GlobalLogger.info(tr("MSG_RDM_GENERAL_1"))
	
	if main_node and main_node.cad_cursor:
		main_node.cad_cursor.show_crosshair = true
		main_node.cad_cursor.queue_redraw()

func is_placement_active() -> bool:
	return rdm_place_mode != ""

# --- GESTION DES ENTRÉES (Appelé par Main.gd) ---

func handle_input(event: InputEvent) -> bool:
	if not is_placement_active():
		return false
		
	# Consommer le relâchement du clic gauche
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if rdm_consume_left_release:
			rdm_consume_left_release = false
			return true # Entrée gérée
			
	# Prévisualisation snap + curseur
	if event is InputEventMouseMotion:
		if main_node and main_node.camera:
			var pos_preview = main_node.camera.get_global_mouse_position()
			if main_node.snap_manager and main_node.snap_manager.has_method("get_snapped_position") and main_node.world.has_node("Entities"):
				pos_preview = main_node.snap_manager.get_snapped_position(pos_preview, main_node.world.get_node("Entities"), main_node.camera.zoom.x)
			
			if main_node.cad_cursor:
				main_node.cad_cursor.global_position = pos_preview
				main_node.cad_cursor.queue_redraw()
		return true
		
	# Placement au clic gauche
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not main_node or not main_node.camera: return true
		
		var pos = main_node.camera.get_global_mouse_position()
		if main_node.snap_manager and main_node.snap_manager.has_method("get_snapped_position") and main_node.world.has_node("Entities"):
			pos = main_node.snap_manager.get_snapped_position(pos, main_node.world.get_node("Entities"), main_node.camera.zoom.x)
			
		match rdm_place_mode:
			"support":
				create_support(pos, rdm_place_support_type)
				rdm_place_mode = ""
			"force":
				create_force(pos, rdm_place_force_value)
				rdm_place_mode = ""
			"distributed_start":
				distributed_force_start = pos
				rdm_place_mode = "distributed_end"
				GlobalLogger.info(tr("MSG_RDM_LOAD_2"))
			"distributed_end":
				create_distributed_force(distributed_force_start, pos, -1000.0)
				distributed_force_start = Vector2.INF
				rdm_place_mode = ""
				is_creating_distributed_force = false
				
		if rdm_place_mode == "" and main_node.cad_cursor:
			main_node.cad_cursor.show_crosshair = true
			main_node.cad_cursor.queue_redraw()
			
		rdm_consume_left_release = true
		return true
		
	return true # Bloque les autres interactions pendant le mode RDM

# --- CRÉATION D'ENTITÉS RDM ---

func create_support(position: Vector2, support_type: String = "simple"):
	print("DEBUG: Création support %s à position %s" % [support_type, position])
	var support = CADEntity.new()
	support.global_position = position
	support.set_meta("support_type", support_type)
	support.is_point = true
	support.point_size = 8.0
	support.point_style = "CROSS"
	support.points = PackedVector2Array()
	support.update_visuals()
	
	# Assurez-vous que RDMVisual est accessible globalement ou importé
	var visual = RDMVisual.create_support_visual(Vector2.ZERO, support_type)
	support.add_child(visual)
	
	if main_node and main_node.world and main_node.world.has_node("Entities"):
		main_node.world.get_node("Entities").add_child(support)
		GlobalLogger.info(tr("MSG_RDM_SUPPORT_2") + str([support_type, position]))
	else:
		print("ERROR: main_node, world ou Entities non trouvé")
	return support

func create_force(position: Vector2, force_value: Vector2 = Vector2(0, -1000), moment_value: float = 0.0):
	var force = CADEntity.new()
	force.global_position = position
	force.set_meta("force_value", force_value)
	force.set_meta("moment_value", moment_value)
	force.is_point = true
	force.point_size = 8.0
	force.point_style = "CROSS"
	force.points = PackedVector2Array()
	force.update_visuals()
	
	var visual = RDMVisual.create_force_visual(Vector2.ZERO, force_value)
	force.add_child(visual)
	
	if main_node and main_node.world and main_node.world.has_node("Entities"):
		main_node.world.get_node("Entities").add_child(force)
		GlobalLogger.info(tr("MSG_RDM_FORCE_1") + str([force_value, moment_value, position]))
	return force

func create_distributed_force(start_pos: Vector2, end_pos: Vector2, force_per_meter: float = -1000.0):
	var distributed_force = CADEntity.new()
	distributed_force.global_position = start_pos
	distributed_force.set_meta("force_type", "distributed")
	distributed_force.set_meta("start_pos", start_pos)
	distributed_force.set_meta("end_pos", end_pos)
	distributed_force.set_meta("force_per_meter", force_per_meter)
	
	distributed_force.add_point(Vector2.ZERO)
	distributed_force.add_point(end_pos - start_pos)
	distributed_force.width = 2.0
	distributed_force.default_color = Color.RED
	
	var visual = RDMVisual.create_distributed_force_visual(Vector2.ZERO, end_pos - start_pos, force_per_meter)
	distributed_force.add_child(visual)
	
	if main_node and main_node.world and main_node.world.has_node("Entities"):
		main_node.world.get_node("Entities").add_child(distributed_force)
		GlobalLogger.info(tr("MSG_RDM_FORCE_2") + str([force_per_meter, start_pos, end_pos]))
	return distributed_force

func create_test_structure():
	var line = CADEntity.new()
	line.add_point(Vector2(100, 200))
	line.add_point(Vector2(400, 200))
	if main_node and main_node.world and main_node.world.has_node("Entities"):
		main_node.world.get_node("Entities").add_child(line)
	
	create_support(Vector2(100, 200), "articulation")
	create_support(Vector2(400, 200), "simple")
	create_force(Vector2(250, 200), Vector2(0, 5000))
	GlobalLogger.info(tr("MSG_RDM_STRUCTURE_1"))

# --- CALCUL RDM ---

func calculate_rdm():
	if rdm_manager == null:
		rdm_manager = RDMManager.new(main_node)
		
	var all_entities = []
	var supports = []
	var forces = []
	
	if main_node and main_node.world:
		_find_entities_recursively(main_node.world, all_entities, supports, forces)
		
	print("DEBUG: Entités trouvées - Lignes: %d, Supports: %d, Forces: %d" % [all_entities.size(), supports.size(), forces.size()])
	GlobalLogger.info("RDM: %d lignes, %d supports, %d forces" % [all_entities.size(), supports.size(), forces.size()])
	
	var result = rdm_manager.calculate_analysis(all_entities, supports, forces)
	
	if result.has("success"):
		GlobalLogger.success(tr("MSG_RDM_CALCULATION_1") + str(result.solution_time))
	else:
		GlobalLogger.error(tr("MSG_RDM_ERROR_1") + result.get("error", ""))

func _find_entities_recursively(node: Node, all_entities: Array, supports: Array, forces: Array):
	for child in node.get_children():
		if child is CADEntity:
			if child.has_meta("support_type"):
				supports.append(child)
			elif child.has_meta("force_value") or child.has_meta("moment_value") or child.has_meta("force_type"):
				forces.append(child)
			else:
				all_entities.append(child)
		_find_entities_recursively(child, all_entities, supports, forces)
