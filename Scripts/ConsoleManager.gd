extends PanelContainer

# Signal envoyé au Main quand l'utilisateur valide (Entrée)
signal command_entered(text)

@export var history_label : RichTextLabel
@export var input_line : LineEdit

func _ready():
	# On connecte le signal "text_submitted" du LineEdit (touche Entrée)
	input_line.text_submitted.connect(_on_text_submitted)
	
	# Message de bienvenue
	log_message("Bienvenue dans GodotCAD 1.0")
	log_message("Tapez 'POLYLIGNE', 'IMPORT', ou 'EXPORT'.")

func _on_text_submitted(new_text: String):
	if new_text.strip_edges() == "": return
	
	# 1. On affiche la commande tapée dans l'historique (en gris par exemple)
	log_message("> " + new_text.to_upper(), Color.LIGHT_GRAY)
	
	# 2. On envoie la commande au cerveau (Main)
	command_entered.emit(new_text)
	
	# 3. On vide la ligne de saisie
	input_line.clear()

# Fonction pour ajouter du texte dans l'historique
func log_message(text: String, color: Color = Color.WHITE):
	# On utilise du BBCode pour la couleur
	var hex_color = color.to_html()
	history_label.append_text("[color=#%s]%s[/color]\n" % [hex_color, text])
	# Scroll automatique vers le bas (pour voir le dernier message)
	# Note : scroll_to_line fonctionne bien si le label est configuré correctement
	# Sinon, une astuce simple est d'attendre la frame suivante :
	await get_tree().process_frame
	history_label.scroll_to_line(history_label.get_line_count() - 1)
