shader_type canvas_item;

uniform float wobble_strength = 0.003; // Leichte Verzerrung für Wassereffekt
uniform float wobble_speed = 0.8; // Niedrigere Geschwindigkeit für bessere Performance
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;

void fragment() {
    vec2 uv = SCREEN_UV;
    // Nur eine Wobble-Richtung, um die Berechnungen zu reduzieren
    uv.y += sin(uv.x * 5.0 + TIME * wobble_speed) * wobble_strength;
    COLOR = texture(SCREEN_TEXTURE, uv) * vec4(0.8, 0.9, 1.0, 0.5); // Unterwasserfarbe
}
