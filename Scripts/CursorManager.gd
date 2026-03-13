extends Node

# Gestionnaire de curseurs pour l'interface
# S'assure que le curseur système est affiché sur tous les éléments d'interface

var cad_cursor: Node2D
var is_over_ui = false
var ui_elements = []

func _ready():
	# Trouver le curseur CAD
	cad_cursor = get_node_or_null("../GUI/CADCursor")
	if not cad_cursor:
		print("ERREUR: Curseur CAD non trouvé dans CursorManager")
		return
	
	# Initialiser le curseur système sur l'interface
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Collecter tous les éléments d'interface
	_collect_ui_elements()

func _collect_ui_elements():
	ui_elements.clear()
	
	# Parcourir récursivement tous les contrôles UI
	_collect_ui_controls(get_node("../GUI"))

func _collect_ui_controls(node: Node):
	if node is Control:
		ui_elements.append(node)
		# Forcer le curseur système sur tous les contrôles
		if node.has_signal("mouse_entered"):
			node.mouse_entered.connect(_on_ui_mouse_entered)
		if node.has_signal("mouse_exited"):
			node.mouse_exited.connect(_on_ui_mouse_exited)
	
	# Parcourir les enfants
	for child in node.get_children():
		_collect_ui_controls(child)

func _on_ui_mouse_entered():
	if not is_over_ui:
		is_over_ui = true
		_set_system_cursor()

func _on_ui_mouse_exited():
	if is_over_ui:
		is_over_ui = false
		_set_cad_cursor()

func _set_system_cursor():
	#print("CURSOR MANAGER: Passage au curseur système")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if cad_cursor:
		cad_cursor.visible = false
	# Forcer le curseur système plusieurs fois pour s'assurer qu'il est appliqué
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _set_cad_cursor():
	#print("CURSOR MANAGER: Passage au curseur CAD")
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if cad_cursor:
		cad_cursor.visible = true
	# Forcer le curseur CAD avec un délai
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _process(_delta):
	# Vérification principale avec gui_get_hovered_control (plus fiable)
	var hovered_control = get_viewport().gui_get_hovered_control()
	var should_be_over_ui = hovered_control != null
	
	if should_be_over_ui != is_over_ui:
		if should_be_over_ui:
			_on_ui_mouse_entered()
		else:
			_on_ui_mouse_exited()

# Fonction publique pour rafraîchir les éléments UI (si l'interface change)
func refresh_ui_elements():
	_collect_ui_elements()
