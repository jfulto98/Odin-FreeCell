//CARD pngs taken from https://code.google.com/archive/p/vector-playing-cards/downloads

package freecell

import "core:fmt"
import "core:time"
import "core:os"
import "core:strings"

import SDL "vendor:sdl2"
import mix "vendor:sdl2/mixer"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"

import "core:log"
import "core:mem"


WINDOW_WIDTH  :: 1200
WINDOW_HEIGHT :: 675

window : ^SDL.Window

oldTime : f32

quitMainLoop : bool

main :: proc() {

	///!!!make sure not to put anything that depends on SDL/opengl/etc being initialized 
	//up here, or there will be bugs/crashes

	//setup tracking allocator

	//https://www.youtube.com/watch?v=dg6qogN8kIE&ab_channel=KarlZylinski
	//https://odin-lang.org/docs/overview/#file-suffixes
	//(code block under the when statement table)
	context.logger = log.create_console_logger()

	tracking_allocator : mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	defer{
		if len(tracking_allocator.allocation_map) > 0{
			fmt.eprintf("=== %v allocations not freed: ===\n", len(tracking_allocator.allocation_map))
			for _, entry in tracking_allocator.allocation_map{
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}

		if len(tracking_allocator.bad_free_array) > 0{
			fmt.eprintf("=== %v incorrect frees: ===\n", len(tracking_allocator.bad_free_array))
			for entry in tracking_allocator.bad_free_array{
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}

		}

		mem.tracking_allocator_destroy(&tracking_allocator)

	}

    //SDL setup

	window := SDL.CreateWindow("Free Cell", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, {.OPENGL})
	if window == nil {
		fmt.eprintln("Failed to create window")
		return
	}

	//AUDIO setup: based on https://lazyfoo.net/SDL_tutorials/lesson11/index.php
	if SDL.Init(SDL.INIT_AUDIO) < 0{
		fmt.eprintln("Failed to init all SDL subsystems")
	}

	//!!!FOR MP3s, you need to have the libmpg123-0.dll in your directory, otherwise
	//you get an mp3 not supported error and you can't load/play mp3s
	result := mix.Init(mix.INIT_MP3) 
	if result != i32(mix.INIT_MP3){
		fmt.eprintln("could not init mp3 with mixer, result:", result)
		fmt.eprintln("mix.GetError:", mix.GetError())
		
	}

	//init the audio functions
	//params are: sound freq, format, number of channels, sample size
	//DEFAULT_FORMAT is AUDIO_S16SYS
	if mix.OpenAudio(22050, mix.DEFAULT_FORMAT, 2, 640) < 0{
		fmt.eprintfln("sdl2/mixer OpenAudio proc failed")
		return
	}


	defer SDL.DestroyWindow(window)
	defer SDL.Quit()

	
    //OpenGL setup

	gl_context := SDL.GL_CreateContext(window)
	SDL.GL_MakeCurrent(window, gl_context)
	// load the OpenGL procedures once an OpenGL context has been established
	gl.load_up_to(3, 3, SDL.gl_set_proc_address)


	//Setup everything else

	loadResources()

	initGui()
	
    initGame()
    initPostProcessor()

	initTextRenderer()
	loadTextRenderer("fonts/ConcertOne-Regular.ttf", 64)


	// high precision timer
	start_tick := time.tick_now()
	
    //main loop


	for !quitMainLoop {
		
		
		duration := time.tick_since(start_tick)
		t := f32(time.duration_seconds(duration))
        deltaTimeSeconds := min(0.05, t - oldTime)
		//!!!until I find out how to stop SDL from freezing when moving a window on windows, or how to know when those events take
		//place so I can actually do a proper pause, need to clamp dt so you don't get giant timesteps. 
		//was learning about multithreading to try to get this to stop the freezing, but it's apparently a huge hassle, and a) that's
		//not really the point of this project, and b) it's not a huge issue for solitaire (the only reason I remembered it was an issue
		//was because I was doing the win animations) 
		//-> 0.05 clamp is what I did in my old c++ free cell. I noted there that it should be a value > 1/60, or 0.016, since that's how long it
		//takes to do a frame.(you have to account for the fact that you may actually have a low fps while playing, apart from moving the window
		// 0.05 = 1/20 or 20 fps, below this you probably won't have a good time playing the game anyways. 
		//should look into how to do a fixed update (probably also involves multithreading), as it might address issues like these as well.

        oldTime = t
        // fmt.println("deltaTimeSeconds:", deltaTimeSeconds)
		
		handleInput()
		
        
		updateGame(deltaTimeSeconds)
		

		SDL.GL_SwapWindow(window)	


		if len(tracking_allocator.bad_free_array)>0{
			for b in tracking_allocator.bad_free_array{
				log.errorf("bad free at %v", b.location) 
			}

			panic("bad free detected")

		}
		
		free_all(context.temp_allocator)
		
    }//main loop


	//cleanup
    clearResources()
	deinitGame()

}


quit :: proc(){
	quitMainLoop = true
}