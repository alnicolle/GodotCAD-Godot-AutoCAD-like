shader_type canvas_item;
render_mode blend_mix;

// --- PARAMÈTRES ---
uniform float pattern[20];
uniform int pattern_count;
uniform float linetype_scale = 1.0;
uniform float line_length = 100.0;
uniform vec4 color : source_color;

void fragment() {
    // 1. Couleur de base (Ligne pleine par défaut)
    COLOR = color;

    // 2. Si on a un motif valide, on applique la logique de transparence
    if (pattern_count > 0) {

        // Calcul de la position le long de la ligne (en pixels monde)
        float dist = UV.x * line_length;

        // Calculer la longueur totale d'un cycle
        float total_pattern_len = 0.0;
        for (int i = 0; i < pattern_count; i++) {
            total_pattern_len += pattern[i] * linetype_scale;
        }

        // Sécurité pour éviter la division par zéro
        if (total_pattern_len > 0.001) {

            // Position dans le cycle actuel (Modulo)
            float pos = mod(dist, total_pattern_len);

            // Vérifier si on est dans un "Trait" ou un "Espace"
            float current_accum = 0.0;

            for (int i = 0; i < pattern_count; i++) {
                float segment_len = pattern[i] * linetype_scale;

                if (pos < current_accum + segment_len) {
                    // Si l'index est IMPAIR (1, 3, 5...), c'est un ESPACE -> Transparent
                    if (i % 2 != 0) {
                        discard;
                    }
                    // Si PAIR, on ne fait rien (on garde la couleur définie au début)
                    break;
                }
                current_accum += segment_len;
            }
        }
    }
}