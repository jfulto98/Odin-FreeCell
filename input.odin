package freecell

import "core:fmt"
import SDL "vendor:sdl2"

//trying out putting all the input stuff in one file. 
//the idea is to handle events here, and make the corresponding
//calls to procs in other files, and then other files can do their own polling
//if they need it (using some of the variables that are kept track of here,
//like mouse position)


keysProcessed : [1024]bool
mousePosX, mousePosY : i32
mouseDeltaX, mouseDeltaY : i32

mouseIsDownL, mouseIsDownR, mouseIsDownM : bool
//mouseIsDownX tracks whether the mouse button is currently being held down

mouseDownEventThisFrameL, mouseUpEventThisFrameL : bool


handleInput :: proc(){
    
	SDL.PumpEvents();
    //apparently you don't NEED to call pump events if you call SDL.PollEvent, 
    //since SDL.PollEVent implicitly calls PumpEvents

    //INPUT event polling
    event: SDL.Event
    
    mouseDownEventThisFrameL = false
    mouseUpEventThisFrameL = false
    //!!!make sure event handling happens before calls to updates/other procs
    //that need to know what happened this frame -> eg for mouseDownEventThisFrameL/Up,
    //if you put updates before, you'll get the last frame's value.

    for SDL.PollEvent(&event) {
        // #partial switch tells the compiler not to error if every case is not present
        #partial switch event.type {

            case .MOUSEBUTTONDOWN:
                switch event.button.button {
                    case SDL.BUTTON_LEFT:
                        mouseDownEventThisFrameL = true
                        fmt.println("mouse down this frame L")
                }

            case .MOUSEBUTTONUP:
                switch event.button.button {
                    case SDL.BUTTON_LEFT:
                        mouseUpEventThisFrameL = true
                        fmt.println("mouse up this frame L")

                }

            case .KEYDOWN:
                #partial switch event.key.keysym.sym {
                    case .Q:
                        quit()

                }

            case .QUIT:
                quit()
            }


        if event.type == .KEYUP{
            // fmt.println("scancode up:",event.key.keysym.scancode)
            keysProcessed[event.key.keysym.scancode] = false
        }

    }

    //https://wiki.libsdl.org/SDL2/SDL_BUTTON
    //https://www.gamedev.net/forums/topic/302784-sdl_buttonx-macro/
    //explains the bitmask for SDL.GetMousState

    mouseButtonBitmask := SDL.GetMouseState(&mousePosX, &mousePosY)
    mouseIsDownL = mouseButtonBitmask & SDL.BUTTON_LMASK != 0
    mouseIsDownR = mouseButtonBitmask & SDL.BUTTON_RMASK != 0
    mouseIsDownM = mouseButtonBitmask & SDL.BUTTON_MMASK != 0


    SDL.GetRelativeMouseState(&mouseDeltaX, &mouseDeltaY)
    
    // fmt.println("mousePosX, mousePosY:", mousePosX, mousePosY)
    // fmt.println("mouseDeltaX, mouseDeltaY:", mouseDeltaX, mouseDeltaY)

    // fmt.println("mouseIsDownL, mouseIsDownR, mouseIsDownM, mouseDownEventThisFrameL, mouseUpEventThisFrameL:", mouseIsDownL, mouseIsDownR, mouseIsDownM, mouseDownEventThisFrameL, mouseUpEventThisFrameL)

    // fmt.println("mouseDownEventThisFrameL, mouseUpEventThisFrameL:", mouseDownEventThisFrameL, mouseUpEventThisFrameL)

}