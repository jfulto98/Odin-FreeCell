#version 330 core

in vec2 texCoords;

out vec4 o_color;


uniform sampler2D texture1;
uniform vec3 spriteColor;

void main() {

	vec4 texc =  vec4(spriteColor, 1.0) * texture(texture1, texCoords);
	o_color = texc;

	// o_color = vec4(1.0,1.0,1.0,1.0);

}