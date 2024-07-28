package freecell

import "core:fmt"
import "core:strings"


import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"
// import "vendor:sdl2/ttf"
// import stbtt "vendor:stb/truetype"

import img "vendor:sdl2/image"
import FT "shared:odin-freetype"
//https://github.com/englerj/odin-freetype?tab=readme-ov-file

//the idea is to generate a bitmap and metrics for each glyph
//to render them, you use the metrics to generate a mesh,
//and then use the bitmap as a texture

tr_vao, tr_vbo : u32
Character :: struct{
    texID : u32, //id handle of glyph texture
    size : glm.ivec2, //size of glyph
    bearing : glm.ivec2,// oofset from baseline to left/top of glyph
    advance : u32//horizontal offset to advance to next glyph
}

characters := make(map[rune]Character)

initTextRenderer :: proc(){

    //!!! init SDL_ttf
    // if ttf.Init()<0{
    //     fmt.println("failed to initialize SDL_ttf, error:", ttf.GetError())
    //     return
    // }


    //setup voa/vbo -> the actual vbo data will change per char (see renderText proc)
    //but the number of verts/layout remains the same, so do this here.
    useShader("text")
    setUMat4fv("projection", glm.mat4Ortho3d(0.0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, -1.0, 1.0))
    setUInt("text", 0)

    gl.GenVertexArrays(1, &tr_vao)
    gl.GenBuffers(1, &tr_vbo)

    gl.BindVertexArray(tr_vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, tr_vbo)
    
    gl.BufferData(gl.ARRAY_BUFFER, size_of(f32)*6*4, nil, gl.DYNAMIC_DRAW)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)
    
    gl.BindVertexArray(0)
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)



}

loadTextRenderer :: proc(path : string, fontSize : u32){

    clear(&characters)

    // loadedFont := ttf.OpenFont(strings.clone_to_cstring(fontPath), fontSize)
    // if loadedFont == nil{
    //     fmt.eprintfln("could not open/load font at path:", fontPath)
    //     return
    // }

    // fmt.println("loadedFont:", loadedFont)


    ft : FT.Library
    if FT.init_free_type(&ft) != .Ok{
        fmt.eprintln("Could not init Freetype Library")
    }
 
    face : FT.Face

        
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))

    if FT.new_face(ft, cstr, 0, &face) != .Ok{
        fmt.eprintln("Could not load freetype font")

    }

    FT.set_pixel_sizes(face, 0, fontSize)

    //disable byte alignement
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

    for c in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()_+-=,./;'[]<>?:\"{}/\\`~ "{

        // fmt.println("rune:", c)

        if FT.load_char(face, u32(c), FT.Load_Flags{.Render}) != .Ok{
            fmt.eprintfln("could not load glyph for rune:", c)
            continue
        }
      
        //TEXTURE 
        char_tex : u32
        gl.GenTextures(1, &char_tex)
        gl.BindTexture(gl.TEXTURE_2D, char_tex)
 
        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RED,
            i32(face.glyph.bitmap.width),
            i32(face.glyph.bitmap.rows),
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            face.glyph.bitmap.buffer
        )

        //set texture options
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);


        character := Character{
            char_tex,
            glm.ivec2{cast(i32)face.glyph.bitmap.width, cast(i32)face.glyph.bitmap.rows},
            glm.ivec2{cast(i32)face.glyph.bitmap_left, cast(i32)face.glyph.bitmap_top},
            u32(cast(i32)face.glyph.advance.x)
        }

        characters[c] = character

    }

    gl.BindTexture(gl.TEXTURE_2D, 0)
    
    FT.done_face(face)
    FT.done_free_type(ft)
    
}




getStringTextRendererWidth :: proc(text : string, scale: f32) -> f32{

    //this is mainly for centering text horizontally. Don't know if there's a builtin function
    //in freetype for this, or if there's a more efficient way to do this (you will loop over your
    //string x2 if you call this, then renderText()), but it seems like this is what everyone recommends you do)

    w : f32 = 0

    for c in text{
        if !(c in characters){
            fmt.eprintln("in getStringLen, could not find character", c, "in loaded characters")
        }else{
            ch := characters[c]
            w += f32(ch.advance >> 6)  * scale
        }
    }    

    return w
}

renderText :: proc(text : string, x, y, scale : f32, color : glm.vec3, sin_wave := false){
    //sin_wave is temp, can make this whole proc more robust later if needed.

    x := x
    //going to be updating x in the loop as you draw each character

    

    useShader("text")

    setUVec3("textColor", color)
    setUMat4fv("projection", glm.mat4Ortho3d(0.0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, -1.0, 1.0))
    setUInt("text", 0)
    
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindVertexArray(tr_vao)

    //!!!remember to enable blend mode so alpha works
    //->had a bug where, if you didn't call anything from gui.odin, the text would
    //render as solid quad, realized that I was setting the blend mode in all the gui procs,
    //but not here->The only reason this isn't set globally is because the project I used as a 
    //base for this one has particles, which get rendered with a different blend func. Either way,
    //should set this in every proc that renders, similar to how I'm calling useShader in every render proc.
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    for c in text{

        if !(c in characters){
            // fmt.eprintln("could not find character", c, "in loaded characters")
        }else{
        
            ch := characters[c]
        
            xpos := x + f32(ch.bearing.x) * scale
            ypos := y + f32(characters['H'].bearing.y - ch.bearing.y) * scale 
            
            if sin_wave {
                ypos += (glm.sin_f32(f32(SDL.GetTicks())*2/1000.0 + xpos*14/WINDOW_WIDTH) * 10)
            }
            
            //The H char y bearing should be the max hight of a glyph. Because we're rendering top to bottom, 
            //you push the glyphs down by subtracting their y bearing (the distance from the midline to their top)
            //from the H char's
            //!!! Make sure capital 'H' actually has a character struct created. 

            w := f32(ch.size.x) * scale
            h := f32(ch.size.y) * scale


            // fmt.println("\'", c, "\' xpos, ypos, w, h:", xpos, ypos, w, h)

            //update vbo for each character
            verts := [6][4]f32{
                { xpos,     ypos + h,   0.0, 1.0 },
                { xpos + w, ypos,       1.0, 0.0 },
                { xpos,     ypos,       0.0, 0.0 },

                { xpos,     ypos + h,   0.0, 1.0 },
                { xpos + w, ypos + h,   1.0, 1.0 },
                { xpos + w, ypos,       1.0, 0.0 }
            }

            // fmt.println("verts:", verts)
            // fmt.println("textid:", ch.texID)

            //render glyph texture over quad
            gl.BindTexture(gl.TEXTURE_2D, ch.texID)
            // gl.BindTexture(gl.TEXTURE_2D, texture_map["face"])


            //update vbo content
            gl.BindBuffer(gl.ARRAY_BUFFER, tr_vbo)
            gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(verts), &verts)
            gl.BindBuffer(gl.ARRAY_BUFFER, 0)

            //render quad
            gl.DrawArrays(gl.TRIANGLES, 0, 6)
            x += f32(ch.advance >> 6) * scale
            //bitshift by 6 == *1/64 -> this gives you the advance in pixels
            //so the current behaviour is that if a char is missing, it won't skip a space or anything 
        }
        
    }    

    gl.BindVertexArray(0)
    gl.BindTexture(gl.TEXTURE_2D, 0)

}
