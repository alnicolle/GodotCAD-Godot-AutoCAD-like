extends Node2D

@onready var renderer = $EntitiesRenderer
@onready var camera = $Camera2D
@onready var fps_label = $CanvasLayer/FPSLabel

const NUM_LINES = 20000

func _ready():
	# On connecte la caméra au renderer pour qu'il mette à jour l'épaisseur dynamique au zoom
	camera.zoom_changed.connect(renderer._on_camera_changed)
	
	print("Génération de %d lignes en cours..." % NUM_LINES)
	var start_time = Time.get_ticks_msec()
	
	# Désactiver le rebuild du cache à chaque ajout pour aller plus vite
	renderer.geometry_dirty = true 
	
	for i in range(NUM_LINES):
		# Création de coordonnées aléatoires dans un espace de 10000 x 10000
		var start_pos = Vector2(randf_range(-5000, 5000), randf_range(-5000, 5000))
		# Des lignes de tailles variées (entre -100 et +100 pixels)
		var end_pos = start_pos + Vector2(randf_range(-100, 100), randf_range(-100, 100))
		
		var points = PackedVector2Array([start_pos, end_pos])
		
		# On utilise ton nouveau conteneur pur
		var entity = CADEntityData.create_line(points, "CalqueTest")
		
		# On met des couleurs variées pour tester que le batching par couleur fonctionne bien
		var colors = [Color.WHITE, Color.RED, Color.GREEN, Color.CYAN, Color.YELLOW]
		entity.color = colors[randi() % colors.size()]
		
		# On ajoute directement dans le tableau pour court-circuiter les signaux inutiles au démarrage
		renderer.entities.append(entity)
		renderer._update_spatial_grid(entity)
		renderer._group_entity_by_layer(entity)
		renderer._group_entity_by_type(entity)
		
	print("Génération terminée en %d ms." % (Time.get_ticks_msec() - start_time))

func _process(delta):
	# 1. Affichage des performances en temps réel
	fps_label.text = "FPS: %d | Entités: %d" % [Engine.get_frames_per_second(), NUM_LINES]
	
	# 2. Navigation basique (Stress Test du Pan)
	var pan_speed = 2000.0 / camera.zoom.x
	var pan_dir = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_RIGHT): pan_dir.x += 1
	if Input.is_key_pressed(KEY_LEFT): pan_dir.x -= 1
	if Input.is_key_pressed(KEY_DOWN): pan_dir.y += 1
	if Input.is_key_pressed(KEY_UP): pan_dir.y -= 1
	
	if pan_dir != Vector2.ZERO:
		camera.position += pan_dir.normalized() * pan_speed * delta

	# 3. Navigation basique (Stress Test du Zoom)
	if Input.is_key_pressed(KEY_KP_ADD) or Input.is_key_pressed(KEY_PLUS):
		camera.zoom *= 1.02
		# Comme on ne passe pas par l'UI complexe, on émet le signal manuellement pour le test
		camera.zoom_changed.emit() 
	if Input.is_key_pressed(KEY_KP_SUBTRACT) or Input.is_key_pressed(KEY_MINUS):
		camera.zoom *= 0.98
		camera.zoom_changed.emit()
