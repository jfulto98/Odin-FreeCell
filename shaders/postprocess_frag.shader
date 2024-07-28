#version 330 core

in vec2 texCoords;
out vec4 color;

uniform sampler2D scene;

uniform float sFactor;
uniform int desaturate;

vec3 rgb_to_hsv(vec3 rgb);
vec3 hsv_to_rgb(vec3 hsv);


void main(){


    color = texture(scene, texCoords);

    vec3 hsv = rgb_to_hsv(color.xyz);
    hsv.y *= 1 + (sFactor*desaturate);
    //!!!! want to multiply, NOT set as absolute. (I was doing s = 0.5, which turns all the whites to red, since h just stays at 0 if s = 0)
    hsv.z *= 1 + (sFactor*0.1*desaturate);

    color = vec4(hsv_to_rgb(hsv), 1);


}

//Added an undo/redo effect where saturation is changed
//I looked at a few sources, and ended up adapting the algorithm in this book for coverting btw rgb and hsv and back
//!!!There are better versions of the same algorithms that are meant for shaders and don't have any conditionals

//https://lib.undercaffeinated.xyz/get/PDF/5588/CalibreLibrary?content_disposition=inline
//pg 321 (303 in actual book -> ch 8.6 transforming between color models)

//these are some other posts I looked at:
//https://stackoverflow.com/questions/53879537/increase-the-intensity-of-texture-in-shader-code-opengl
//https://www.chilliant.com/rgb2hsv.html
//https://www.shadertoy.com/view/4dKcWK


vec3 rgb_to_hsv(vec3 rgb){

    //note: formula assumes that rgb components are btw 0 and 1, not 0 and 255 (they are btw 0-1 in glsl anyways)
    //also note: there are a few ternary statements here, these could probably be optimized out, since 
    //conditionals can cause issues with shaders (some sources I read said they do, some say don't worry about it, 
    //just want to get it working for this project, in the future will read more into this)

    //get max and min of the three rgb components
    //min/max funcs in glsl only take 2 args
    float maxc = max(max(rgb.r, rgb.g), rgb.b);
    float minc = min(min(rgb.r, rgb.g), rgb.b);


    float cdelta = maxc - minc;

    // float rc = (maxc - rgb.r) / cdelta; 
    // float gc = (maxc - rgb.g) / cdelta; 
    // float bc = (maxc - rgb.b) / cdelta; 

    //get h, s and v

    //value
    //value is simply the max component
    float v = maxc;

    //saturation
    //s is 0 if maxc is 0 (can't divide by 0)
    //maxc == 0 -> black
    float s = maxc == 0 ? 0 : ((cdelta) / maxc);
    // float s = 0;


    //hue
    //hue depends on what color component (r, g or b) is the highest (maxc)
    //!! technically, h should be undefined if s = 0 (think of a color tool with s - 0 -> h could be any value)
    float h = 0.0;

    if(s > 0){
        if(rgb.r == maxc){
            //red is max
            //color is between yellow and magenta
            h = (rgb.g - rgb.b)/cdelta; 

        }else if(rgb.g == maxc){
            //green is max
            //color is between cyan and yellow
            h = 2 + (rgb.b - rgb.r)/cdelta; 

        }else{
            //blue is max
            //color is between magenta and cyan
            h = 4 + (rgb.r - rgb.g)/cdelta; 
        }

        h *= 60;//convert to degrees (h in btw 0-360)
        h = h < 0 ? h + 360 : h;//prevent negetive values (loop back from 360 if negetive)
    }

    return vec3(h, s, v);
    // return vec3(0);
}

vec3 hsv_to_rgb(vec3 hsv)
{
    // return vec3(0);

    float h = hsv.x;
    float s = hsv.y;
    float v = hsv.z;

    if(s == 0){
        //if saturation is 0, just return value for everything
        //in the book, they do an additional check for h == undefined, if it is, they do the return, else they throw an error
        //this seems unecessary, but either way I'm not doing it.
        return vec3(v);
    }else{


        // // /60 and sextant -> The HSV model is represented by an inverted hexagonal pyramid ('hexicone')
        // //the 6 points on the hexigon are red, yellow, green, cyan, blue, and magenta. so each sextant is the 6th of the cone
        // //between two of these colors (360/6 = 60 degrees). Look at figure 8.7 in the book (pg 320 pdf / 302 actual)

        h = mod(h, 360.0)/60.0;


        float sextant = floor(h);

        float fract = h - sextant;


        float p = v * (1 - s); 
        float q = v * (1 - (s*fract)); 
        float t = v * (1 - (s*(1-fract))); 
       
       
        vec3 rgb = vec3(0);            

        if(sextant == 0){
            rgb = vec3(v, t, p);

        }else if(sextant == 1){
            rgb = vec3(q, v, p);

        }else if(sextant == 2){
            rgb = vec3(p, v, t);

        }else if(sextant == 3){
            rgb = vec3(p, q, v);

        }else if(sextant == 4){
            rgb = vec3(t, p, v);

        }else if(sextant == 5){
            rgb = vec3(v, p, q);
        
        }

        return rgb;
    }


}