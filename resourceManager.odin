package freecell

import "core:fmt"
import "core:os"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import "core:strings"

import SDL "vendor:sdl2"
import mix "vendor:sdl2/mixer"
import stbi "vendor:stb/image"


shader_map := make(map[string]u32)
texture_map := make(map[string]u32)
music_map := make(map[string]^mix.Music)
chunk_map := make(map[string]^mix.Chunk)

cardTextures : [4][13]u32


loadResources :: proc(){

    stbi.set_flip_vertically_on_load(i32(1))

    //load shaders
    loadShader("default", "shaders/default_vert.shader", "shaders/default_frag.shader")
    loadShader("pp", "shaders/postProcess_vert.shader", "shaders/postProcess_frag.shader")
    loadShader("text", "shaders/text_vert.shader", "shaders/text_frag.shader")
    
    loadShader("bg", "shaders/bg_vert.shader", "shaders/bg_frag.shader")


    //load textures
    dir, o_err := os.open("textures", os.O_RDONLY)
    if o_err != os.ERROR_NONE{
        fmt.eprintln("error opening texture directory for texture loading")
    }

    file_infos, rd_err := os.read_dir(dir, -1)
    if rd_err != os.ERROR_NONE{
        fmt.eprint("error calling os.read_dir for texture loading")
    }

    for file in file_infos{
        //!!! I'm just wrapping up the project, I added a screenshot folder to the textures folder
        //to put the screenshots for github. That messes this up, causes the program to crash, 
        //will have to rework later if adding subfolders to textures folder (for now
        //I'm just putting the screenshots in with the other textures.)


        loadTexture(strings.clone(file.name[:strings.index(file.name,".")]), file.fullpath)
        /*
        //!!!should look into this, but without cloning, there were issues where the textures weren't 
        //drawing, because the string keys in the texture map were all garbage. I'm guessing this is
        //because passing the file.name string directly just gives you the reference to the file struct's
        //name string, and since the file infos get deleted, this results in the strings being deleted as well.
        //-> the card textures were okay because I just stored their ids in the cardTextures array. (I use get
        //texture to get the id, but I guess the delete is either deferred, or the memory the strings reference 
        //hasn't been modified yet? -> the latter is suppported by the fact that sometime the texture would load,
        //sometimes they would appear for a few frames, the disappear -> todo: figure out  if this is the case
        //->according to docs, strings are just rawptrs and len (according to discord, rawptrs are like void pointer in
        //c, which are just memory pointer with no associated type (can't be dereferenced unless you cast the to a typed pointer)
        //->this supports my theory.
        //->ANYWAYS, cloning, and then MAKING SURE to delete the (cloned string) keys along with the values in the clearResources
        //in the cleanup seems to fix the issue without any apparent memory leaks/problems.
        */

    }

    // fmt.println("texture_map after loading using os.read_dir:\n", texture_map)
	os.file_info_slice_delete(file_infos)
    //!!!was trying delete(file_infos), doesn't work, also tried using temp_alloc in os.read_dir,
    //but I guess a) the temp alloc deletes all or something in read_dir, and b), the actual file.names must
    //be allocated with the temp_alloc as well or something, because using temp_alloc in os.read_dir caused
    //all the keys in the texture map to be blank, so I'm guessing the string pointers got deleted, !!!todo
    //maybe look into this

    //card textures
    cardTextures[SUIT.DIAMONDS][0] = getTexture("ace_of_diamonds")
    cardTextures[SUIT.DIAMONDS][1] = getTexture("2_of_diamonds")
    cardTextures[SUIT.DIAMONDS][2] = getTexture("3_of_diamonds")
    cardTextures[SUIT.DIAMONDS][3] = getTexture("4_of_diamonds")
    cardTextures[SUIT.DIAMONDS][4] = getTexture("5_of_diamonds")
    cardTextures[SUIT.DIAMONDS][5] = getTexture("6_of_diamonds")
    cardTextures[SUIT.DIAMONDS][6] = getTexture("7_of_diamonds")
    cardTextures[SUIT.DIAMONDS][7] = getTexture("8_of_diamonds")
    cardTextures[SUIT.DIAMONDS][8] = getTexture("9_of_diamonds")
    cardTextures[SUIT.DIAMONDS][9] = getTexture("10_of_diamonds")
    cardTextures[SUIT.DIAMONDS][10] = getTexture("jack_of_diamonds2")
    cardTextures[SUIT.DIAMONDS][11] = getTexture("queen_of_diamonds2")
    cardTextures[SUIT.DIAMONDS][12] = getTexture("king_of_diamonds2")

    cardTextures[SUIT.CLUBS][0]  = getTexture("ace_of_clubs")
    cardTextures[SUIT.CLUBS][1]  = getTexture("2_of_clubs")
    cardTextures[SUIT.CLUBS][2]  = getTexture("3_of_clubs")
    cardTextures[SUIT.CLUBS][3]  = getTexture("4_of_clubs")
    cardTextures[SUIT.CLUBS][4]  = getTexture("5_of_clubs")
    cardTextures[SUIT.CLUBS][5]  = getTexture("6_of_clubs")
    cardTextures[SUIT.CLUBS][6]  = getTexture("7_of_clubs")
    cardTextures[SUIT.CLUBS][7]  = getTexture("8_of_clubs")
    cardTextures[SUIT.CLUBS][8]  = getTexture("9_of_clubs")
    cardTextures[SUIT.CLUBS][9]  = getTexture("10_of_clubs")
    cardTextures[SUIT.CLUBS][10] = getTexture("jack_of_clubs2")
    cardTextures[SUIT.CLUBS][11] = getTexture("queen_of_clubs2")
    cardTextures[SUIT.CLUBS][12] = getTexture("king_of_clubs2")

    cardTextures[SUIT.HEARTS][0] = getTexture("ace_of_hearts")
    cardTextures[SUIT.HEARTS][1] = getTexture("2_of_hearts")
    cardTextures[SUIT.HEARTS][2] = getTexture("3_of_hearts")
    cardTextures[SUIT.HEARTS][3] = getTexture("4_of_hearts")
    cardTextures[SUIT.HEARTS][4] = getTexture("5_of_hearts")
    cardTextures[SUIT.HEARTS][5] = getTexture("6_of_hearts")
    cardTextures[SUIT.HEARTS][6] = getTexture("7_of_hearts")
    cardTextures[SUIT.HEARTS][7] = getTexture("8_of_hearts")
    cardTextures[SUIT.HEARTS][8] = getTexture("9_of_hearts")
    cardTextures[SUIT.HEARTS][9] = getTexture("10_of_hearts")
    cardTextures[SUIT.HEARTS][10] = getTexture("jack_of_hearts2")
    cardTextures[SUIT.HEARTS][11] = getTexture("queen_of_hearts2")
    cardTextures[SUIT.HEARTS][12] = getTexture("king_of_hearts2")

    cardTextures[SUIT.SPADES][0] = getTexture("ace_of_spades")
    cardTextures[SUIT.SPADES][1] = getTexture("2_of_spades")
    cardTextures[SUIT.SPADES][2] = getTexture("3_of_spades")
    cardTextures[SUIT.SPADES][3] = getTexture("4_of_spades")
    cardTextures[SUIT.SPADES][4] = getTexture("5_of_spades")
    cardTextures[SUIT.SPADES][5] = getTexture("6_of_spades")
    cardTextures[SUIT.SPADES][6] = getTexture("7_of_spades")
    cardTextures[SUIT.SPADES][7] = getTexture("8_of_spades")
    cardTextures[SUIT.SPADES][8] = getTexture("9_of_spades")
    cardTextures[SUIT.SPADES][9] = getTexture("10_of_spades")
    cardTextures[SUIT.SPADES][10] = getTexture("jack_of_spades2")
    cardTextures[SUIT.SPADES][11] = getTexture("queen_of_spades2")
    cardTextures[SUIT.SPADES][12] = getTexture("king_of_spades2")



    
    //load audio

    loadChunk("card_place_1", "audio/card_place_1.wav")
    loadChunk("card_place_2", "audio/card_place_2.wav")
    loadChunk("card_place_3", "audio/card_place_3.wav")

    loadChunk("pingpong_1", "audio/pingpong_1.mp3")
    
    loadChunk("woosh", "audio/woosh.wav")

    loadChunk("undo", "audio/undo.wav")
    loadChunk("redo", "audio/redo.wav")

    loadChunk("win", "audio/win.mp3")
    loadChunk("cancel", "audio/cancel.wav")
    loadChunk("cancel_reverse", "audio/cancel_reverse.mp3")

    loadChunk("siren_whistle", "audio/siren_whistle.wav")

}

clearResources :: proc(){
    for key, value in shader_map{
        gl.DeleteProgram(value)
    }

    for key, value in texture_map{
        value:=value
        //you have to do the same thing as procs, you can't take the pointer 
        //unless you do the x := x thing to make x mutable
        gl.DeleteTextures(1, &value)
        delete(key)
    }

    for key, value in music_map{
        mix.FreeMusic(value)
    }

    for key, value in chunk_map{
        mix.FreeChunk(value)
    }

}


//SHADERS
//the load_shader_source/load_shader_file procs return a u32 id for the shader program.

loadShader :: proc(name, vs_path, fs_path:string)->(u32, bool){
    shader_program_id, program_ok := gl.load_shaders_file(vs_path, fs_path)
	
    if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
	}
	// defer gl.DeleteProgram(program)
    //doing clear instead -> just clears everything, have to remember to call at end of program.	

    // fmt.println("shader program id: ", shader_program_id)
    shader_map[name] = shader_program_id

    return shader_program_id, program_ok
}

useShader :: proc(name:string){
    gl.UseProgram(shader_map[name])
}

getUniformLocation :: proc(uniform_name:string)->i32{

    current_shader_program_id : i32
    gl.GetIntegerv(gl.CURRENT_PROGRAM, &current_shader_program_id)

    
    uniform_name_cstring := strings.clone_to_cstring(uniform_name)
    defer free(rawptr(uniform_name_cstring))
    

    return gl.GetUniformLocation(cast(u32)current_shader_program_id, uniform_name_cstring)

}

setUMat4fv :: proc(uniform_name:string, mat: glm.mat4){
    
    mat := mat
    //params are immuatable, unless you "do an explicit copy by shadowing the variable declaration"
    //need to do this here because it looks like you can't get the pointer to &mat[0,0] otherwise (gives error)

    uniform_location := getUniformLocation(uniform_name)

    gl.UniformMatrix4fv(uniform_location, 1, false, &mat[0, 0])


    //!!!old -> don't need to load all the uniforms, can just call getUniformLocation

    // current_shader_program_id : i32
    // gl.GetIntegerv(gl.CURRENT_PROGRAM, &current_shader_program_id)

    // uniforms := gl.get_uniforms_from_program(cast(u32)current_shader_program_id)
    // defer delete(uniforms)

    // //!! by default, if an element doesn't exist in a map, the zero value of the element's type will be returned.
    // //so you want to check to see if the uniform exists, because in this case, you get a 0 initialized uniform struct,
    // //with location = 0, which is the actual location you want. Without the check, you'll just always be setting the
    // //first uniform if you give an invalid uniform name.
    // if uniform_name in uniforms{
    //     gl.UniformMatrix4fv(uniforms[uniform_name].location, 1, false, &mat[0, 0])
    // }else{
    //     fmt.println("Uniform does not exist in shader program being used: ", uniform_name)
    // }

}



setUInt :: proc(uniform_name:string, value:i32){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

    gl.Uniform1i(uniform_location, value)
}


setUFloat :: proc(uniform_name:string, value:f32){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

    gl.Uniform1f(uniform_location, value)
}


setUVec2 :: proc(uniform_name:string, value:glm.vec2){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

  
    gl.Uniform2f(uniform_location,value.x, value.y)
}

setUVec3 :: proc(uniform_name:string, value:glm.vec3){
    
    value := value
  
    uniform_location := getUniformLocation(uniform_name)


    gl.Uniform3f(uniform_location,value.x, value.y, value.z)
}

setUVec4 :: proc(uniform_name:string, value:glm.vec4){
    
    value := value

    uniform_location := getUniformLocation(uniform_name)

    gl.Uniform4f(uniform_location,value.x, value.y, value.z, value.w)
}



//TEXTURES


loadTexture := proc(name, path: string){
    //faciliates using stbi.load to load a texture, then calls generateTexture to actually create 
    //the texture and get the id setup etc.

    width, height, nrComponents : i32
    
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))

    data := stbi.load(cstr, &width, &height, &nrComponents, 0)
    defer(stbi.image_free(data))


    if data == nil{
        fmt.eprintln("texture failed to load at path:", path) 
        
    }else{
        // fmt.println("successfully created texture: name, path:", name, path)
        texture_map[name] = generateTexture(width, height, nrComponents, data, gl.CLAMP_TO_BORDER)
    }

}

generateTexture :: proc(width, height, nrComponents : i32, data : [^]u8, wrapmode : i32)-> u32{
    //actually create the texture with the given data
    //sending null data should create an exmpty texture ->
    //currently needed for the post processor

    //added wrapmode param since you want to clamp for regular textures, but you do want to repeat for the framebuffer texture for 
    //some of the post processing shader effects

    textureID : u32 
    gl.GenTextures(1, &textureID)

    format : gl.GL_Enum

    switch nrComponents{
        case 1:
            format = gl.GL_Enum.RED
        case 3:
            format = gl.GL_Enum.RGB
        case:
            //expecting 4 for rgba, but just have this as the default
            format = gl.GL_Enum.RGBA
    }

    gl.BindTexture(gl.TEXTURE_2D, textureID)

    gl.TexImage2D(gl.TEXTURE_2D, 0, cast(i32)format, width, height, 0, cast(u32)format, gl.UNSIGNED_BYTE, data)

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrapmode)//clamp to edge for transparent rgba textures prevent weird effect -> without it, the pixels at the top of the quad are interpolated between the top, and the bottom of the texture. if the top of the texture is transparent, and that's the desired color you want for the quad, you need to clamp_to_edge, otherwise you'll there will be non transparent pixels at the top of the texture.
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrapmode)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    
    //[^] is a multipointer, which is a c like pointer that has indexing, and is meant for working with c code 
    // bcol := [?]f32{0, 0, 0, 1}
    // borderColor : [^]f32 = raw_data(bcol[:]) 
    // gl.TexParameterfv(gl.TEXTURE_2D, gl.TEXTURE_BORDER_COLOR, borderColor)

    ///!!actually have to generate the mip maps if you use gl.LINEAR_MIPMAP_LINEAR or gl.LINEAR_MIPMAP_NEAREST for 
    //the texture parameters, otherwise everything will be black (I guess everything that needs to use a mip map anyways)
    gl.GenerateMipmap(gl.TEXTURE_2D)

    //https://www.opengl-tutorial.org/beginners-tutorials/tutorial-5-a-textured-cube/#mipmaps
    //this is good as refesher. Just remember that without bitmaps, textures that are smaller than their actaul image size would have to sample more 
    //and more pixels from the original image (worst case is that the texture is 1x1 in the game, so you'd have to sample every pixel in the image to
    //get the proper blend. Mipmaps are pre generated smaller versions of the texture, that get used when drawing the smaller textures. This
    //way, you can just do linear filtering (which just takes in the 4 pixels in the 2x2 pixel region closest to the texture coord.) on the essentially (pre-filtered) pixels.
   
    //there's LINEAR_MIPMAP_LINEAR and LINEAR_MIPMAP_NEAREST, you can look up the exact differences but the two linears/ one linear one nearest determine how to
    //sample the mip map, but also whether or not to blend two mipmap levels together (If I recall this is more for 3d, due to perspective, you will want to 
    //use a larger mip map for the closer part of a eg a quad, and a smaller one for the further away part. You can either just take the nearest mipmap level
    //for a given pixel, OR you can blend between the 2 closest mipmap levels, to get a smoother looking blend -> for 2d I don't think this matters, since 
    //the quad you're drawing should just have 1 mipmap level)

    return textureID
}

getTexture :: proc(name :string)->(u32, bool)  #optional_ok{
    //added the #optional_ok procedure parameter for the card texture loading.

    tid : u32
    ok : bool

    if name in texture_map{
        tid = texture_map[name]
        ok = true
    }else{
        fmt.eprintln("could not find texture in map, probably not loaded, name:", name)
        fmt.print("texture map:", texture_map)
        ok = false
    }
        
    return texture_map[name], ok      
}


//AUDIO

loadMusic :: proc(name, path :string){

    // music := mix.LoadMUS(strings.clone_to_cstring(path))
        
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))

    music := mix.LoadMUS(cstr)

    if music == nil{
        fmt.eprintfln("could not load music at path:", path, ", make sure you have the right subfolder")
        return
    }

    music_map[name] = music

}

playMusic :: proc(name : string){
    mix.PlayMusic(music_map[name], -1)
    //last arg is number of repeats
    //-1 loops the audio indefinately
}


loadChunk :: proc(name, path :string){
    
    cstr := strings.clone_to_cstring(path)
    defer free(rawptr(cstr))
    chunk := mix.LoadWAV(cstr)

    if chunk == nil{
        fmt.eprintfln("could not load chunk at path:", path, ", make sure you have the right subfolder")
        return
    }

    chunk_map[name] = chunk

}

playChunk :: proc(name : string){
    mix.PlayChannel(-1, chunk_map[name], 0)
    //first arg is channel index, -1 just picks the nearest available channel
    //last arg is # of repeats, 0 since you want it to play once, no repeats
}

toggleMute :: proc(){

    //-1 is for querying (just sends the current volume without modifying, I guess)
    //note: tried using GetMusicVolume, but it gave me a linker error 

    // breakout.obj : error LNK2019: unresolved external symbol Mix_GetMusicVolume referenced in function fmt.eprintf
    // (path)\breakout.exe : fatal error LNK1120: 1 unresolved externals

    // fmt.printfln("volume", mix.VolumeMusic(-1))
    mix.VolumeMusic(mix.VolumeMusic(-1) > 0 ? 0 : 128)
    mix.Volume(-1, mix.Volume(0, -1) > 0 ? 0 : 128 )
    //!!!! there's no mater volume proc in odin for sdl mixer, but I found just by trying it that
    //passing -1 as the channel SEEMS to control all channels (.Volume is for chunk channels, if you put anything
    //other than -1 it will ONLY set that channel)


}