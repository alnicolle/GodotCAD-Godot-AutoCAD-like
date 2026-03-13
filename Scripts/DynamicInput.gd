extends Control

@onready var line_edit = $PanelContainer/LineEdit
@onready var panel = $PanelContainer

# Variable pour savoir si l'utilisateur a forcé une valeur
var is_typing = false

# Signal envoyé quand l'utilisateur valide une valeur numérique
signal value_committed(value: float)
# Signal envoyé quand l'utilisateur fait Entrée sur un champ vide (pour finir la polyligne)
signal finish_requested

func _ready():
	visible = false
	
	# CORRECTION 1 : COLLISION SOURIS
	# On ignore la souris sur le container principal et le panel
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Le LineEdit garde le focus clavier mais on peut aussi l'ignorer à la souris si tu ne veux pas cliquer dessus
	# Pour l'instant on laisse Stop sur le LineEdit au cas où tu veuilles cliquer dedans, 
	# mais comme il suit la souris, c'est mieux de le mettre en Ignore aussi si tu veux dessiner "à travers".
	line_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE 

	line_edit.text_changed.connect(_on_text_changed)
	line_edit.text_submitted.connect(_on_text_submitted)
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.modulate = Color(1, 1, 1, 0.9)

func show_input(world_pos: Vector2, current_length: float, camera: Camera2D):
	visible = true
	
	# Positionnement au dessus du trait
	var screen_pos = (world_pos - camera.global_position) * camera.zoom + get_viewport_rect().size / 2.0
	position = screen_pos + Vector2(0, -30)
	
	# Mise à jour auto seulement si on ne tape pas
	if not is_typing:
		line_edit.text = String.num(current_length, 2)
		line_edit.select_all()

func hide_input():
	visible = false
	is_typing = false
	line_edit.release_focus()

# CORRECTION 4 : PREMIER CHIFFRE MANGÉ
func start_typing(initial_char: String):
	if not visible: return
	
	line_edit.grab_focus()
	is_typing = true
	
	# On remplace le texte sélectionné par le chiffre tapé
	line_edit.text = initial_char
	# On place le curseur à la fin
	line_edit.caret_column = line_edit.text.length()

func focus():
	if not line_edit.has_focus():
		line_edit.grab_focus()

func _on_text_changed(new_text):
	is_typing = true

func _on_text_submitted(new_text):
	# CORRECTION 2 : VALIDATION SI VIDE
	if new_text.strip_edges() == "":
		finish_requested.emit()
		hide_input()
		return

	if new_text.is_valid_float():
		var val = new_text.to_float()
		# On empêche les valeurs nulles ou négatives pour la longueur
		if val > 0:
			value_committed.emit(val)
			is_typing = false
			line_edit.release_focus()
			# On sélectionne tout pour la prochaine saisie
			line_edit.select_all() 
	else:
		is_typing = false
