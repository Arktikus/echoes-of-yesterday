shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform vec3 underwater_color : source_color = vec3(0.0, 0.4, 0.6); // Unterwasser-Farbton
uniform float fog_density : hint_range(0.0, 1.0) = 0.3;  // Stärke des Nebels
uniform float wave_distortion : hint_range(0.0, 10.0) = 1.0; // Stärke der Verzerrung (kleinerer Wert)
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0; // Geschwindigkeit der Verzerrung
uniform sampler2D noise_texture; // Noise-Textur für Wellenbewegung

void fragment() {
    // Berechne Noise-Offset für die Wellenbewegung (geringerer Wert für subtilere Verzerrung)
    vec2 uv = FRAGCOORD.xy / SCREEN_PIXEL_SIZE;
    vec2 noise_offset = vec2(
        sin(TIME * wave_speed + uv.y * wave_distortion) * 0.002, // Reduziert auf 0.002 für subtilere Verzerrung
        cos(TIME * wave_speed + uv.x * wave_distortion) * 0.002
    );
    
    // Hole die Originalfarbe des Bildschirms mit reduzierter Verzerrung
    vec3 original_color = texture(SCREEN_TEXTURE, SCREEN_UV + noise_offset).rgb;

    // Simuliere Nebeleffekt basierend auf Bildschirmhöhe
    float fog_factor = 1.0 - (FRAGCOORD.y / SCREEN_PIXEL_SIZE.y);
    fog_factor = exp(-fog_factor * fog_density);
    fog_factor = clamp(fog_factor, 0.0, 1.0);
    
    // Mische Unterwasserfarbe stärker in den Effekt
    vec3 fog_color = mix(underwater_color, original_color, fog_factor * 0.7);

    COLOR = vec4(fog_color, 1.0);
}
