extends Node

# Dictionnaire stockant les motifs.
# Format : { "NOM_DU_TYPE": [longueur_trait, longueur_espace, ...] }
var linetypes = {}

# Liste simple des noms pour les menus déroulants
var linetype_names = []

# Chemin vers le fichier de définitions
const LIN_FILE_PATH = "res://acadiso.txt"

# Échelle globale des types de ligne (LTSCALE)
# Permet d'adapter les motifs AutoCAD (mm) à l'échelle de votre monde (pixels)
var global_scale = 10.0

func _ready():
	_load_linetypes_from_file()
	
	# Ajout manuel des types "Spéciaux" qui ne sont pas dans le fichier ou qui sont procéduraux
	if not "CONTINUOUS" in linetypes:
		linetypes["CONTINUOUS"] = [] # Vide = ligne continue
		linetype_names.push_front("CONTINUOUS")
		
	# On s'assure que ISOLATION est présent dans la liste des noms
	# (Même si sa définition dans le fichier est complexe, on le gère manuellement plus tard)
	if not "ISOLATION" in linetypes:
		linetype_names.append("ISOLATION")

	GlobalLogger.info("LinetypeManager : " + str(linetypes.size()) + " types chargés.")
	
	# --- TEST TEMPORAIRE ---
	print("--- VÉRIFICATION DES TYPES ---")
	print("CACHE : ", get_pattern("CACHE"))       # Devrait afficher des chiffres (ex: [6.35, -3.175])
	print("AXES : ", get_pattern("AXES"))         # Devrait afficher une séquence plus longue
	print("BORDURE : ", get_pattern("BORDURE"))   # Autre test
	print("------------------------------")

func _load_linetypes_from_file():
	var file = FileAccess.open(LIN_FILE_PATH, FileAccess.READ)
	if not file:
		GlobalLogger.error("Impossible d'ouvrir le fichier : " + LIN_FILE_PATH)
		return

	var current_name = ""
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		
		# Ignorer les commentaires (;;) et les lignes vides
		if line.begins_with(";;") or line.is_empty():
			continue
			
		# 1. DÉFINITION DU NOM (Commence par *)
		# Exemple : *CACHE,Caché __ __ __
		if line.begins_with("*"):
			var parts = line.substr(1).split(",")
			current_name = parts[0].to_upper() # Ex: "CACHE"
			
			# On l'ajoute à la liste des noms si pas déjà présent
			if not current_name in linetype_names:
				linetype_names.append(current_name)
				
		# 2. DÉFINITION DU MOTIF (Commence par A,)
		# Exemple : A, 6.35, -3.175
		elif line.begins_with("A,") and current_name != "":
			var pattern_str = line.substr(2) # Enlever "A,"
			var tokens = pattern_str.split(",")
			var pattern_array = []
			
			for token in tokens:
				token = token.strip_edges()
				# GESTION DES FORMES COMPLEXES (ex: [BAT,ltypeshp.shx...])
				# Pour l'instant, on ignore les formes textuelles entre crochets []
				# car Godot ne peut pas lire les .shx.
				if token.begins_with("["):
					continue
				
				if token.is_valid_float():
					pattern_array.append(token.to_float())
			
			# On stocke le motif nettoyé
			linetypes[current_name] = pattern_array
			current_name = "" # Reset pour la prochaine lecture

# Fonction utilitaire pour récupérer un motif
func get_pattern(type_name: String) -> Array:
	var key = type_name.to_upper()
	if linetypes.has(key):
		return linetypes[key]
	return [] # Retourne vide (continu) si introuvable

# Vérifie si un type est procédural (dessiné par code) ou shader (pointillés)
func is_procedural_type(type_name: String) -> bool:
	return type_name.to_upper() in ["ISOLATION", "BATTING", "ZIGZAG"]
