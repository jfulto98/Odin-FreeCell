package freecell

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import "core:fmt"
import "base:intrinsics"


pp_msfbo, pp_fbo, pp_rbo : u32
pp_texture : u32
pp_vao : u32

pp_clearFramebuffer := true

pp_saturation_factor : f32
pp_desaturate : i32


initPostProcessor :: proc(){

    //notes on framebuffer: the framebuffers basically a collection of other buffers
    //render buffers and textures can be assigned to framebuffers
    //renderbuffers are meant to be used with framebuffers, they are optimized to be rendered to,
    //but are not meant to be sampled from.

    //SETUP FRAMEBUFFERS

    gl.GenFramebuffers(1, &pp_msfbo)
    gl.GenFramebuffers(1, &pp_fbo)
    gl.GenRenderbuffers(1, &pp_rbo)

    gl.BindFramebuffer(gl.FRAMEBUFFER, pp_msfbo)
    gl.BindRenderbuffer(gl.RENDERBUFFER, pp_rbo)

    //allocate storage for render buffer object
    gl.RenderbufferStorageMultisample(gl.RENDERBUFFER, 4, gl.RGB, WINDOW_WIDTH, WINDOW_HEIGHT)
    //attach ms render buffer to our framebuffer
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, pp_rbo)


    if(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE){
        fmt.eprintln("Failed to initialize postprocessor MSFBO")
    }

    //initialize the regular non multi sampled fbo with the texture to blit the msfbo
    //this fbo is the one that will have post processing effects done to it
    gl.BindFramebuffer(gl.FRAMEBUFFER, pp_fbo)
    

    //SETUP TEXTURE
    //generate the texture for the framebuffer
    //gl.RGB is based on https://github.com/JoeyDeVries/LearnOpenGL/blob/master/src/7.in_practice/3.2d_game/0.full_source/texture.cpp
    //they're not using stb_image, and the default value for format in the member initializer list is gl.RBG for their Texture class
    pp_texture = generateTexture(WINDOW_WIDTH, WINDOW_HEIGHT, gl.RGB, nil, gl.REPEAT)
    
    //attach the texture to the framebuffer as its color attachment 
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, pp_texture,0)

    if(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE){
        fmt.eprintln("Failed to initialize postprocessor FBO")
    }

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    //SETUP DATA AND UNIFORMS
    //I guess the idea is to do this once for this shader, since these values won't change for
    //any draw calls
    initRenderDataPostProcessor()

    useShader("pp")
    setUInt("scene", 0)

    offset : f32= 1.0/300.0
    offsets := [18]f32{
        -offset,  offset ,  // top-left
         0.0 ,    offset ,  // top-center
         offset,  offset ,  // top-right
        -offset,  0.0    ,  // center-left
         0.0 ,    0.0    ,  // center-center
         offset,  0.0    ,  // center - right
        -offset, -offset ,  // bottom-left
         0.0 ,   -offset ,  // bottom-center
         offset, -offset    // bottom-right
    }
    //(can't just use the uniform wrappers, since this is an array of vector 2s, not going 
    //to bother making wrappers for these)
    //!!!ALSO, I changed offsets from a [9][2]f32 to an [18]f32, since Uniform2fv
    //expects a multipointer to the flattened data anyways, and I don't yet know how
    //to convert properly
    gl.Uniform2fv(getUniformLocation("offsets"), 9, raw_data(&offsets))

    edge_kernel := [9]i32{
        -1, -1, -1,
        -1,  8, -1,
        -1, -1, -1
    }
    gl.Uniform1iv(getUniformLocation("edge_kernel"), 9, raw_data(&edge_kernel))

    blur_kernel := [9]f32 {
        1.0 / 16.0, 2.0 / 16.0, 1.0 / 16.0,
        2.0 / 16.0, 4.0 / 16.0, 2.0 / 16.0,
        1.0 / 16.0, 2.0 / 16.0, 1.0 / 16.0
    }
    gl.Uniform1fv(getUniformLocation("blur_kernel"), 9, raw_data(&blur_kernel))    

}

beginRenderPostProcessor :: proc(){

    gl.BindFramebuffer(gl.FRAMEBUFFER, pp_msfbo)


    if pp_clearFramebuffer{
        gl.ClearColor(0.0, 0.0, 0.0, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
    }

    //!!!Note: for the win effect, turn off clearcolor/clear hear, and there can't be a background texture (will have to 
    //have multiple framebuffers, and then composite them together, eg one for bg, one for the cards/cells/empties.

}

endRenderPostProcessor :: proc(){

    gl.BindFramebuffer(gl.READ_FRAMEBUFFER, pp_msfbo)
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, pp_fbo)
    

    gl.BlitFramebuffer(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, gl.COLOR_BUFFER_BIT, gl.NEAREST)
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    //bind both read and wrtie framebuffer to the default framebuffer
}


renderPostProcessor :: proc(dt:f32){
    // fmt.println("pp render")
    
    
    useShader("pp")

    setUFloat("sFactor", pp_saturation_factor)
    setUInt("desaturate", pp_desaturate)


    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, pp_texture)

    gl.BindVertexArray(pp_vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
    gl.BindVertexArray(0)

}

initRenderDataPostProcessor :: proc(){
    
    ppVertex :: struct{
        vertex: glm.vec4
    }

    ppQuad := []ppVertex{
        {{-1.0, -1.0, 0.0, 0.0}},
        {{1.0, 1.0, 1.0, 1.0}},
        {{-1.0, 1.0, 0.0, 1.0}},

        {{-1.0, -1.0, 0.0, 0.0}},
        {{1.0, -1.0, 1.0, 0.0}},
        {{1.0, 1.0, 1.0, 1.0}}
    }

    pp_vbo : u32

    gl.GenBuffers(1, &pp_vbo)
    gl.GenVertexArrays(1, &pp_vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, pp_vbo)
    gl.BindVertexArray(pp_vao)

    gl.BufferData(gl.ARRAY_BUFFER, len(ppQuad) * size_of(ppQuad[0]), raw_data(ppQuad), gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, size_of(ppVertex), offset_of(ppVertex, vertex))
    
    
    gl.BindVertexArray(0)

}