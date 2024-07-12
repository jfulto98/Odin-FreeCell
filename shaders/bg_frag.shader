// based on examples from https://thebookofshaders.com/
#version 330 core

uniform vec2 resolution;
uniform float time;
//-> resolution is to get normalized coordinates st, 
//(in main function)
//gl_fragcoord comes in in screen space coords, lower left origin,
//the size of the viewport. Want to normalize these coords, divide by 
//the actual screen resolution


void main() {
	vec2 st = gl_FragCoord.xy/resolution.xy;
	//st gives you these coords:
	//0,1---1,1
	// |	 |
	//0,0---1,0
	//0,0 = bottom of viewport, 1,1 is top of viewport

	float dist = distance(st, vec2(0.5));
	
	vec3 color1 = vec3(.055, .55, .065);
	vec3 color2 = vec3(0.1, .4, .03);

	//max dist is in the corners (sqrt(.5) = .707), so you want the
	//gradient to end clost to there
	//smoothstep(a, b, c) returns 0 if c<a, 1 if c>b, and a value between 0
	//and 1 if c is between a and b (but that value is 'smoothed' -> look online for
	//visual function

	//so the smoothstep below gives you a solid color for dist < .3, then
	//a smooth gradient btw dist = .3, .65, then the other solid color for
	//dist > .65
	//(a and b are currently .3 and .65, respectively)

	//mix is just lerp: (a(1-c) + b(c))
	vec3 gradientColor = mix(color1, color2, smoothstep(.3, .65, dist));

	gl_FragColor = vec4(gradientColor, 1.0);

	// gl_FragColor = vec4(st.x, st.y, 0.0, 1.0);
	// gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
	

}