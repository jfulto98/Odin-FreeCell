#version 330 core

layout(location=0) in vec3 a_position;
layout(location=1) in vec2 a_coords;

out vec2 texCoords;

uniform mat4 model;
uniform mat4 proj;

void main() {	
	gl_Position = proj * model * vec4(a_position, 1.0);
	texCoords = a_coords;
}