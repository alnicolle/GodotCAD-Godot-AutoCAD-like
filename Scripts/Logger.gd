extends Node

# Ce signal sera écouté par ta ConsolePanel
signal message_sent(text: String, color: Color)

# --- FONCTIONS DE LOG ---

# Message blanc standard
func info(text: String):
	print("[INFO] " + text) # Dans l'éditeur
	message_sent.emit(text, Color.WHITE) # Dans le jeu

# Message vert (Succès)
func success(text: String):
	print("[SUCCESS] " + text)
	message_sent.emit(text, Color.GREEN)

# Message jaune (Attention)
func warning(text: String):
	print_rich("[color=yellow][WARNING] " + text + "[/color]")
	message_sent.emit(text, Color.YELLOW)

# Message rouge (Erreur)
func error(text: String):
	print_rich("[color=red][ERROR] " + text + "[/color]")
	message_sent.emit(text, Color.RED)

# Message cyan (Actions Système / Debug)
func debug(text: String):
	print("[DEBUG] " + text)
	message_sent.emit(text, Color.CYAN)
