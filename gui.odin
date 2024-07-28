package freecell

import "core:fmt"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import SDL "vendor:sdl2"

//this file contains all the setup/proc for drawing everything. The procs are meant 
//to be used in the game procs. 

initGui :: proc(){

    //!!!!REMEMBER, this proc calls procs that depend on opengl/sdl/etc being initialized already 
    //loads all the shaders/textures/levels etc, sets up the mats -> basically the setup for
    //the whole game, not just the 'game' logic, but the rendering as well.


    //moved this from main to here, since this is where the vao should be
    Vertex :: struct{
        pos: glm.vec3,
        texcoord: glm.vec2
    }

	vertices := []Vertex{
		//positions     //texcoords
        {{0.0, 0.0, 0}, {0.0, 1.0}},
		{{1.0, 1.0, 0}, {1.0, 0.0}},
		{{0.0, 1.0, 0}, {0.0, 0.0}},

        {{0.0, 0.0, 0}, {0.0, 1.0}},
		{{1.0, 0.0, 0}, {1.0, 1.0}},
		{{1.0, 1.0, 0}, {1.0, 0.0}},
    }
    
    //vbo: note-> vbo just stores all the data in a buffer, while the vao actaully defines which part of the 
    //data means what (pos, tex coord, color, etc)
    //ebo (element buffer) stores indices so you can reuse vertices)

    vbo: u32
    gl.GenBuffers(1, &vbo); 
	gl.GenVertexArrays(1, &spriteVAO); 
	
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BindVertexArray(spriteVAO)
    //!!MAKE SURE THE VAO IS BOUND BEFORE DOING ALL THE BUFFER DATA STUFF
    //otherwise nothing will render.


	gl.BufferData(gl.ARRAY_BUFFER, len(vertices)*size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)
	
    gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, texcoord))

    gl.BindVertexArray(0)



    proj = glm.mat4Ortho3d(0.0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, -1.0, 1.0)
    //checked in c++, mat4Ortho3d is the  same as glm::ortho(...
    //I guess they just wanted the naming convention to be consistent


}



drawRect :: proc(tid: u32, x, y, w, h : int, rot_deg : f32, color := glm.vec4(1.0), shader_name := "default"){

    gl.BindVertexArray(spriteVAO)
    //!!!remember to enable blend mode so alpha works
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    useShader(shader_name)
    //call use shader here since, now with particles using their own shader, need to switch

    //currently the proj mat and vertices/buffers etc are set in main. (in init game)
    //so this proc assumes everything is setup properly

    // fmt.println("drawSprite")
    model := glm.mat4(1.0)
    //the single arg constructor inits the diagonal values to the arg, everything else is 0,
    //so this is identity matrix.
    
    //!! in order for the screen dimension proj matrix to work, you have to
    //make sure the model matrix is being done (specifically the scale, so 
    //when it gets ortho projected it will get scaled back to the desired
    //size (while testing to get stuff working, I removed *proj in the shader,
    //made sure identity model was working, then put * proj back in. It wasn't working
    //because I also had all transf stuff commented, so I guess it was just infinitesimal
    model *= glm.mat4Translate( glm.vec3{cast(f32)x, cast(f32)y, 0.0})

    model *= glm.mat4Translate( glm.vec3{.5 * cast(f32)w, .5*cast(f32)h, 0.0})
    model *= glm.mat4Rotate( glm.vec3{0.0, 0.0, 1.0}, glm.radians(rot_deg)) 
    model *= glm.mat4Translate( glm.vec3{-.5 *cast(f32)w, -.5*cast(f32)h, 0.0})
    
    model *= glm.mat4Scale( glm.vec3{cast(f32)w, cast(f32)h, 1.0})

    // fmt.println("model", model)
    setUMat4fv("model", model)
    setUMat4fv("proj", proj)
    

    setUVec4("spriteColor", color)
    
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, tid)

    setUInt("texture1", 0)
    
    //actually draw
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

drawBg :: proc(x, y, w, h : int){
    //not super reusable, but thought it made sense to put this proc
    //in the gui file.

    gl.BindVertexArray(spriteVAO)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    useShader("bg")

    model := glm.mat4(1.0)

    model *= glm.mat4Translate( glm.vec3{cast(f32)x, cast(f32)y, 0.0})

    
    model *= glm.mat4Scale( glm.vec3{cast(f32)w, cast(f32)h, 1.0})

    setUMat4fv("model", model)
    setUMat4fv("proj", proj)
    
    setUVec2("resolution", glm.vec2{cast(f32)WINDOW_WIDTH, cast(f32)WINDOW_HEIGHT})

    //actually draw
    gl.DrawArrays(gl.TRIANGLES, 0, 6)

}