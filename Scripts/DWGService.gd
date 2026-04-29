class_name DWGService
extends RefCounted

# Service DWG pour GodotCAD - Pont vers LibreDWG via CLI Wrapper
# Ce script gère l'importation et l'exportation de fichiers DWG en utilisant
# les utilitaires LibreDWG situés dans le dossier Outils/ du projet

# Chemins vers les exécutables LibreDWG
const DxfToDwgExe = "res://Outils/dxf2dwg.exe"
const DwgToDxfExe = "res://Outils/dwg2dxf.exe"

# Fichiers temporaires utilisés pour la conversion
const TempExportDxf = "user://temp_export.dxf"
const TempImportDxf = "user://temp_import.dxf"

# ------------------------------------------------------------------------------
# EXPORTATION DWG
# ------------------------------------------------------------------------------

# Exporte le projet actuel au format DWG
# @param chemin_final_dwg: Chemin complet où sauvegarder le fichier DWG
# @param main_node: Node principal de l'application (pour accéder aux données)
# @return: bool - true si succès, false si échec
static func export_to_dwg(chemin_final_dwg: String, main_node: Node) -> bool:
	GlobalLogger.info(Engine.get_singleton("TranslationServer").translate("MSG_EXPORT_DWG_START"))
	
	# Étape 1: Exporter d'abord en DXF temporaire
	GlobalLogger.info(Engine.get_singleton("TranslationServer").translate("MSG_EXPORT_DWG_STEP1"))
	var dxf_result = DXFService.save_dxf(TempExportDxf, main_node, true)
	if not dxf_result:
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_EXPORT_DWG_DXF_FAILED"))
		return false
	
	# Étape 2: Convertir le DXF en DWG
	GlobalLogger.info(Engine.get_singleton("TranslationServer").translate("MSG_EXPORT_DWG_STEP2"))
	var conversion_result = _convert_dxf_to_dwg(TempExportDxf, chemin_final_dwg)
	
	# Étape 3: Nettoyer le fichier temporaire
	#_cleanup_temp_file(TempExportDxf)
	
	if conversion_result:
		GlobalLogger.success(Engine.get_singleton("TranslationServer").translate("MSG_EXPORT_DWG_SUCCESS").format([chemin_final_dwg.get_file()]))
		return true
	else:
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_EXPORT_DWG_FAILED"))
		return false

# ------------------------------------------------------------------------------
# IMPORTATION DWG
# ------------------------------------------------------------------------------

# Importe un fichier DWG dans le projet
# @param chemin_input_dwg: Chemin complet du fichier DWG à importer
# @param main_node: Node principal de l'application (pour ajouter les entités)
# @return: bool - true si succès, false si échec
static func import_from_dwg(chemin_input_dwg: String, main_node: Node) -> bool:
	GlobalLogger.info(Engine.get_singleton("TranslationServer").translate("MSG_IMPORT_DWG_START").format([chemin_input_dwg.get_file()]))
	
	# Étape 1: Convertir le DWG en DXF temporaire
	GlobalLogger.info(Engine.get_singleton("TranslationServer").translate("MSG_IMPORT_DWG_STEP1"))
	var conversion_result = _convert_dwg_to_dxf(chemin_input_dwg, TempImportDxf)
	
	if not conversion_result:
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_IMPORT_DWG_CONVERSION_FAILED"))
		return false
	
	# Étape 2: Importer le DXF temporaire
	GlobalLogger.info(Engine.get_singleton("TranslationServer").translate("MSG_IMPORT_DWG_STEP2"))
	var import_result = DXFService.import_dxf(TempImportDxf, main_node)
	
	# Étape 3: Nettoyer le fichier temporaire
	_cleanup_temp_file(TempImportDxf)
	
	if import_result:
		GlobalLogger.success(Engine.get_singleton("TranslationServer").translate("MSG_IMPORT_DWG_SUCCESS").format([chemin_input_dwg.get_file()]))
		return true
	else:
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_IMPORT_DWG_FAILED"))
		return false

# ------------------------------------------------------------------------------
# FONCTIONS PRIVÉES DE CONVERSION
# ------------------------------------------------------------------------------

# Convertit un fichier DXF en DWG en utilisant dxf2dwg.exe
# @param dxf_path: Chemin du fichier DXF source
# @param dwg_path: Chemin du fichier DWG destination
# @return: bool - true si succès, false si échec
static func _convert_dxf_to_dwg(dxf_path: String, dwg_path: String) -> bool:
	# Obtenir les chemins absolus pour OS.execute()
	var exe_path = ProjectSettings.globalize_path(DxfToDwgExe)
	var abs_dxf_path = ProjectSettings.globalize_path(dxf_path)
	var abs_dwg_path = ProjectSettings.globalize_path(dwg_path)
	
	# Vérifier que l'exécutable existe
	if not FileAccess.file_exists(exe_path):
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_DXF2DWG_NOT_FOUND").format([exe_path]))
		return false
	
	# Vérifier que le fichier DXF source existe
	if not FileAccess.file_exists(abs_dxf_path):
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_DXF_SOURCE_NOT_FOUND").format([abs_dxf_path]))
		return false
	
	# Construire la commande: dxf2dwg.exe -y input.dxf -o output.dwg
	var args = ["-y", abs_dxf_path, "-o", abs_dwg_path]
	
	GlobalLogger.debug(Engine.get_singleton("TranslationServer").translate("MSG_DXF2DWG_COMMAND").format([exe_path, " ".join(args)]))
	
	# Exécuter la conversion
	var exit_code = OS.execute(exe_path, args)
	
	GlobalLogger.debug("Code de sortie dxf2dwg.exe: " + str(exit_code))
	GlobalLogger.debug("Arguments: " + str(args))
	GlobalLogger.debug("Exe path: " + exe_path)
	GlobalLogger.debug("Input DXF: " + abs_dxf_path)
	GlobalLogger.debug("Output DWG: " + abs_dwg_path)
	
	if exit_code == 0:
		GlobalLogger.success(Engine.get_singleton("TranslationServer").translate("MSG_DXF2DWG_SUCCESS"))
		return true
	else:
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_DXF2DWG_ERROR").format([str(exit_code)]))
		return false

# Convertit un fichier DWG en DXF en utilisant dwg2dxf.exe
# @param dwg_path: Chemin du fichier DWG source
# @param dxf_path: Chemin du fichier DXF destination
# @return: bool - true si succès, false si échec
static func _convert_dwg_to_dxf(dwg_path: String, dxf_path: String) -> bool:
	# Obtenir les chemins absolus pour OS.execute()
	var exe_path = ProjectSettings.globalize_path(DwgToDxfExe)
	var abs_dwg_path = ProjectSettings.globalize_path(dwg_path)
	var abs_dxf_path = ProjectSettings.globalize_path(dxf_path)
	
	# Vérifier que l'exécutable existe
	if not FileAccess.file_exists(exe_path):
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_DWG2DXF_NOT_FOUND").format([exe_path]))
		return false
	
	# Vérifier que le fichier DWG source existe
	if not FileAccess.file_exists(abs_dwg_path):
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_DWG_SOURCE_NOT_FOUND").format([abs_dwg_path]))
		return false
	
	# Construire la commande: dwg2dxf.exe -y input.dwg -o output.dxf
	var args = ["-y", abs_dwg_path, "-o", abs_dxf_path]
	
	GlobalLogger.debug(Engine.get_singleton("TranslationServer").translate("MSG_DWG2DXF_COMMAND").format([exe_path, " ".join(args)]))
	
	# Exécuter la conversion
	var exit_code = OS.execute(exe_path, args)
	
	if exit_code == 0:
		GlobalLogger.success(Engine.get_singleton("TranslationServer").translate("MSG_DWG2DXF_SUCCESS"))
		return true
	else:
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_DWG2DXF_ERROR").format([str(exit_code)]))
		return false

# ------------------------------------------------------------------------------
# UTILITAIRES
# ------------------------------------------------------------------------------

# Supprime un fichier temporaire de manière sécurisée
# @param file_path: Chemin du fichier à supprimer
static func _cleanup_temp_file(file_path: String):
	var abs_path = ProjectSettings.globalize_path(file_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
		GlobalLogger.debug(Engine.get_singleton("TranslationServer").translate("MSG_TEMP_FILE_DELETED").format([file_path.get_file()]))

# Vérifie que les outils LibreDWG sont disponibles
# @return: bool - true si tous les outils sont présents
static func check_tools_availability() -> bool:
	var dxf2dwg_path = ProjectSettings.globalize_path(DxfToDwgExe)
	var dwg2dxf_path = ProjectSettings.globalize_path(DwgToDxfExe)
	
	var tools_available = FileAccess.file_exists(dxf2dwg_path) and FileAccess.file_exists(dwg2dxf_path)
	
	if not tools_available:
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_LIBREDWG_TOOLS_MISSING"))
		GlobalLogger.error(Engine.get_singleton("TranslationServer").translate("MSG_CHECK_TOOLS_FOLDER").format([ProjectSettings.globalize_path("res://Outils/")]))
	
	return tools_available

# Retourne des informations sur les versions des outils (si disponibles)
# @return: Dictionary - informations sur les outils ou null si erreur
static func get_tools_info() -> Dictionary:
	var info = {
		"dxf2dwg_available": false,
		"dwg2dxf_available": false,
		"dxf2dwg_path": ProjectSettings.globalize_path(DxfToDwgExe),
		"dwg2dxf_path": ProjectSettings.globalize_path(DwgToDxfExe)
	}
	
	info.dxf2dwg_available = FileAccess.file_exists(info.dxf2dwg_path)
	info.dwg2dxf_available = FileAccess.file_exists(info.dwg2dxf_path)
	
	return info
