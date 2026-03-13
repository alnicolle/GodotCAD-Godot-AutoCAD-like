# RDMSolver.gd
# Solveur pour les systèmes linéaires [K]{U}={F}
class_name RDMSolver
extends RefCounted

# Résout le système linéaire en utilisant la méthode de Gauss
func solve_linear_system(K: Array[float], F: Array[float]) -> Dictionary:
	var n = F.size()
	
	# Vérification de la compatibilité
	if K.size() != n * n:
		return {"error": "Dimensions incompatibles: matrice %dx%d, vecteur %d" % [n, n, n]}
	
	print("Résolution du système %dx%d par élimination de Gauss..." % [n, n])
	
	var start_time = Time.get_ticks_msec()
	
	# Copier les matrices pour ne pas modifier les originales
	var A = K.duplicate(true)
	var b = F.duplicate(true)
	
	# Élimination de Gauss avec pivot partiel
	for i in range(n):
		# Recherche du pivot maximal
		var max_row = i
		var max_val = abs(A[i * n + i])
		
		for k in range(i + 1, n):
			if abs(A[k * n + i]) > max_val:
				max_val = abs(A[k * n + i])
				max_row = k
		
		# Vérifier si la matrice est singulière
		if max_val < 1e-12:
			return {"error": "Matrice singulière ou mal conditionnée à la ligne %d" % i}
		
		# Échanger les lignes si nécessaire
		if max_row != i:
			_swap_rows(A, b, i, max_row, n)
		
		# Élimination
		for k in range(i + 1, n):
			var factor = A[k * n + i] / A[i * n + i]
			
			# Mettre à jour la ligne k
			for j in range(i, n):
				A[k * n + j] -= factor * A[i * n + j]
			
			b[k] -= factor * b[i]
	
	# Substitution remontée
	var x: Array[float] = []
	x.resize(n)
	
	for i in range(n - 1, -1, -1):
		x[i] = b[i]
		
		for j in range(i + 1, n):
			x[i] -= A[i * n + j] * x[j]
		
		x[i] /= A[i * n + i]
	
	var solve_time = (Time.get_ticks_msec() - start_time) / 1000.0
	print("Système résolu en %.3f secondes" % solve_time)
	
	return {
		"solution": x,
		"solve_time": solve_time,
		"method": "gauss_elimination"
	}

# Échange deux lignes dans le système
func _swap_rows(A: Array[float], b: Array[float], i: int, j: int, n: int):
	# Échanger les lignes de la matrice A
	for k in range(n):
		var temp = A[i * n + k]
		A[i * n + k] = A[j * n + k]
		A[j * n + k] = temp
	
	# Échanger les éléments du vecteur b
	var temp_b = b[i]
	b[i] = b[j]
	b[j] = temp_b

# Résolution alternative avec décomposition LU (plus stable)
func solve_lu_decomposition(K: Array[float], F: Array[float]) -> Dictionary:
	var n = F.size()
	
	if K.size() != n * n:
		return {"error": "Dimensions incompatibles"}
	
	print("Résolution par décomposition LU...")
	
	var start_time = Time.get_ticks_msec()
	
	# Décomposition LU
	var LU = K.duplicate(true)
	var P: Array[int] = []
	P.resize(n)
	
	for i in range(n):
		P[i] = i
	
	# Décomposition
	for i in range(n):
		# Pivot partiel
		var max_row = i
		for k in range(i + 1, n):
			if abs(LU[k * n + i]) > abs(LU[max_row * n + i]):
				max_row = k
		
		# Échanger les lignes
		if max_row != i:
			_swap_rows_lu(LU, P, i, max_row, n)
		
		# Vérifier la singularité
		if abs(LU[i * n + i]) < 1e-12:
			return {"error": "Matrice singulière"}
		
		# Décomposition
		for k in range(i + 1, n):
			LU[k * n + i] /= LU[i * n + i]
			
			for j in range(i + 1, n):
				LU[k * n + j] -= LU[k * n + i] * LU[i * n + j]
	
	# Résolution Ly = Pb (substitution avant)
	var y: Array[float] = []
	y.resize(n)
	var Pb: Array[float] = []
	Pb.resize(n)
	
	# Appliquer la permutation à F
	for i in range(n):
		Pb[i] = F[P[i]]
	
	for i in range(n):
		y[i] = Pb[i]
		for k in range(i):
			y[i] -= LU[i * n + k] * y[k]
	
	# Résolution Ux = y (substitution arrière)
	var x: Array[float] = []
	x.resize(n)
	
	for i in range(n - 1, -1, -1):
		x[i] = y[i]
		for k in range(i + 1, n):
			x[i] -= LU[i * n + k] * x[k]
		x[i] /= LU[i * n + i]
	
	var solve_time = (Time.get_ticks_msec() - start_time) / 1000.0
	print("Décomposition LU terminée en %.3f secondes" % solve_time)
	
	return {
		"solution": x,
		"solve_time": solve_time,
		"method": "lu_decomposition"
	}

# Échange des lignes pour la décomposition LU
func _swap_rows_lu(LU: Array[float], P: Array[int], i: int, j: int, n: int):
	# Échanger les lignes de la matrice
	for k in range(n):
		var temp = LU[i * n + k]
		LU[i * n + k] = LU[j * n + k]
		LU[j * n + k] = temp
	
	# Échanger les indices de permutation
	var temp_p = P[i]
	P[i] = P[j]
	P[j] = temp_p
