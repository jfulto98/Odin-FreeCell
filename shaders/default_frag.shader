#version 330 core

in vec2 texCoords;

out vec4 o_color;


uniform sampler2D texture1;
uniform vec4 spriteColor;

void main() {

	vec4 texc = spriteColor * texture(texture1, texCoords);
	o_color = texc;

	// o_color = vec4(1.0,1.0,1.0,1.0);

}