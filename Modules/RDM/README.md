# Module RDM/MEF pour GodotCAD

## Architecture

Ce module implémente la Méthode des Éléments Finis (MEF) pour le calcul de résistance des matériaux dans GodotCAD.

### Structure des fichiers

- **RDMNode.gd**: Structure de données pour les nœuds du maillage
- **RDMElement.gd**: Structure de données pour les éléments de poutre
- **RDMSupport.gd**: Représentation des conditions limites (appuis)
- **RDMForce.gd**: Représentation des forces et moments appliqués
- **RDMConverter.gd**: Convertit les entités CAD en objets MEF
- **RDMAssembler.gd**: Assemble la matrice de raideur globale
- **RDMSolver.gd**: Solveur pour systèmes linéaires
- **RDMResults.gd**: Extraction et gestion des résultats
- **RDMManager.gd**: Point d'entrée principal du module

## Utilisation

### Intégration dans Main.gd

```gdscript
# Chargement à la demande
func _on_rdm_tab_pressed():
    if rdm_manager == null:
        rdm_manager = RDMManager.new(self)
    
    # Lancer l'analyse
    var lines = get_visible_line_entities()
    var supports = get_support_entities()
    var forces = get_force_entities()
    
    var result = rdm_manager.calculate_analysis(lines, supports, forces)
    
    if result.has("success"):
        print("Analyse réussie!")
        # Traiter les résultats...
    else:
        print("Erreur: ", result.error)
```

### Format des entités

#### Appuis
Les entités d'appui doivent avoir:
- Position globale (`global_position`)
- Métadonnée `support_type` avec valeurs: "simple", "articulation", "encastrement"

#### Forces
Les entités de force doivent avoir:
- Position globale (`global_position`)
- Métadonnées optionnelles:
  - `force_value`: Vector2(Fx, Fy)
  - `moment_value`: float (Mz)

## Propriétés par défaut

- Module d'Young: E = 210 GPa (acier)
- Section: A = 1×10⁻⁴ m²
- Inertie: I = 8.33×10⁻⁸ m⁴

## Tolérances

- Fusion des nœuds: 1×10⁻³ m (1 mm)
- Stabilité numérique: 1×10⁻¹²

## Méthodes de résolution

1. Élimination de Gauss avec pivot partiel
2. Décomposition LU (plus stable)

## Validation

Le module inclut une validation automatique du modèle:
- Vérification de la connectivité
- Stabilité des conditions limites
- Détection de sur-contrainte

## Performance

- Optimisé pour les systèmes de taille moyenne (< 1000 DDL)
- Allocation mémoire minimale
- Algorithmes O(n³) pour la résolution
