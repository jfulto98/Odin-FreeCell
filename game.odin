package freecell

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math"
import "core:math/rand"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import stbi "vendor:stb/image"
import SDL "vendor:sdl2"


spriteVAO: u32

GameState :: enum{GAME_NEW, GAME_DEAL, GAME_PLAYING, GAME_AUTOCOMPLETING, GAME_WIN}
canAutocomplete := false
displayMenu := false

gameState : GameState

proj : glm.mat4
//the projection matrix is here since it's meant to be used as a uniform for both
//the default and particle shader, and to be consistent with the other uniforms,
//I'm going to use it each time in the respective draw/render functions
//I'm currently setting it once in the init game func

//cards setup
//
NUM_CARDS_IN_DECK :: 52


SUIT :: enum {DIAMONDS, CLUBS, HEARTS, SPADES}
Suit_Set :: bit_set[SUIT]

Card :: struct{
    id : int,
    rank : int,
    suit : SUIT,

    //visuals
    visStartPosX : int,
    visStartPosY : int,

    visTargetPosX : int, 
    visTargetPosY : int,
    
    visTimeSeconds : f32,

    visJustStartedMoveSetVisuals : bool,
}

//!!!Originally deck was [dynamic]Card, had some issues with all the cards being gone on reset,
//because I was popping off the deck. But I changed all the arrays and I think this works better,
//you just create all the cards in the deck, shuffle them, then every other array just points to them.
deck : [NUM_CARDS_IN_DECK]Card
// deck := make([dynamic]Card, NUM_CARDS_IN_DECK)

columns : [8][dynamic]^Card
foundations : [4][dynamic]^Card
freecells : [4][dynamic]^Card


//added in card array types after adding quick moves, because you need to know what type of
//array is getting drawn. (mentioned this in some other comments but this feels like a shortcomming
//of doing everything in this IMGUI way)
CARD_ARRAY_TYPE :: enum{DEFAULT, TABLEAU, FOUNDATION, FREECELL}

//after adding array type, figured it would be good to just map the pickup procs and empty card texture/etc,
//so you only need to pass in the type to drawCardArray()
cardArrayTypeToPutdownProc := map[CARD_ARRAY_TYPE](proc(^[dynamic]^Card)->bool){
    .DEFAULT = proc(card_array : ^[dynamic]^Card)->bool{return true},
    .TABLEAU = putDownProcTableaus,
    .FOUNDATION = putDownProcFoundations,
    .FREECELL = putDownProcFreeCells,
}

cardArrayTypeToEmptyTexture := map[CARD_ARRAY_TYPE]string{
    .DEFAULT = "empty",
    .TABLEAU = "empty",
    .FOUNDATION = "foundation_2",
    .FREECELL = "freecell",
}


handCardArray : ^[dynamic]^Card
handCardArrayIndex : int 
handCardOffsetX, handCardOffsetY : int
// handCardSpacingY : int

doingManualPutdown := false
currentClosestDistanceManualPutdownCardArray : ^[dynamic]^Card
currentClostestDistanceManualPutdownDistance : f32


visualCardArray : [dynamic]^Card
visualMoveTimeSeconds : f32 = 0.2

//a fake card used to do the winning animations
fakeCard : Card


//SPACING/SIZES
//

//card size is based on margins/window height, in order to enure that 20 cards can fit in 1
//tableau col, (which should be the max number of cards in a single tableau col in freecell)

topMarginY := 20
middleMarginY := 20
bottomMarginY := 10


actualCardRatio : f32 = 500.0 / 726.0
cardTopRatio : f32 =  120.0 / 726.0
//cardTopRatio = how much of the card should stick out on top if buried in a tableau col.
//need the ratio because it will help determine the actual card size / spacing.
//originally had more of the top showing, so you could see the entire rank/suit corner symbols of each card,
//(currently you can see just enough to distinguish the cards, but not the whole suit symbol)
//but for the card textures I'm using, this means you have to make the cards much smaller (to fit 20 
//in a tableau col without going offscreen, with the margins that I want)
//->In a real game, I'd design the cards so that the rank/suit in the corner were a better size
//(it also doesn't help that the face cards in the card texture pack I found have different corner symbol sizes than the
//others) 

cardSizeY := f32(WINDOW_HEIGHT - topMarginY - middleMarginY - bottomMarginY) / (2 + (cardTopRatio * 19))
cardSizeX := cardSizeY * actualCardRatio

cardSize := glm.ivec2{ i32(cardSizeX), i32(cardSizeY)}

defaultCardSpacingY := int(f32(cardSize.y) * cardTopRatio)

foundationdsAndCellsSpacingX := 35

foundationsOffsetX := (WINDOW_WIDTH/4)*3 -  ((len(foundations)*(cast(int)cardSize.x + foundationdsAndCellsSpacingX) - foundationdsAndCellsSpacingX)/2)
freecellsOffsetX := (WINDOW_WIDTH/4) -  ((len(foundations)*(cast(int)cardSize.x + foundationdsAndCellsSpacingX) - foundationdsAndCellsSpacingX)/2)

tableauSpacingX := 35
tableauOffsetX := (WINDOW_WIDTH/2) - ((len(columns)*(cast(int)cardSize.x + tableauSpacingX) - tableauSpacingX)/2)
tableauOffsetY := topMarginY + cast(int)cardSize.y + middleMarginY

tableauMaxSizeY := WINDOW_HEIGHT - tableauOffsetY - bottomMarginY
//this is the maximum vertical size the cards in a tableau col can take up. This is used in order to know when to
//shrink the tableau card spacing (don't want to draw cards beyond the bottom of the screen)


//QUICK MOVES
/*
    I put in a ton of comments in the code detailing quick moves.
    The main problem with doing something like this with (my interpretation of) IMGUI principles is that don't seem to 
    facilitate the simple way of doing quick moves, which would be to, upon double clicking,
    just loop through all the card arrays, check to see which card array can accept the double clicked card(s), if any,
    determine the best card array out of those arrays, and then do/don't do the move immediately. 

    ->instead, the best thing I could come up with was to do the following:

    1) if you double click on a card/subset of cards in an array, change state from .NOT_DOING to .LOOKING, and store the card array that contains the cards that are to be moved (this is done by just using the hand, 
    but not releasing it until all the quickmove stuff is done, even if you mouseup/etc)
    
    2) as you loop through drawing the card arrays, if an array can accept the cards, then check it with the quick move compare function. If it's a better candidate for moving
    than the last card, set it as the currentBestQuickMoveCardArray (don't know the name for this idiom, but it's just a more complex 'if a > b { biggest = a }')
    
    3)in the next frame, when you call drawCardArrays for the array with the cards you double clicked last frame, you will know you have checked all the card arrays. Then set the state to .DOING
    
    4)right after the renderGame() call in updateGame(), there's a check for .DOING. If  currentBestQuickMoveCardArray != nil, then you found an array to quick move to, so now actually 
    do the move. Either way, you then set the state back to .NOT_DOING to finish the quick moving process.
    
    ->so the whole thing takes place over 2 frames. 
    
    ->to ensure there are no other issues, I also prevent normal pickups/putdowns from happening while !.NOT_DOING

    ->again, this probably isn't ideal, but it's similar to how you might do things like tabbing through an IMGUI menu (things that involve the different IMGUI elements needing to know about each other in some capacity.
    ->It's at least an improvement from my old C++ solitaire, where I didn't think to do the  'if a > b { biggest = a }' way of checking, and instead
    I think I did multiple loops to get the best candidate array.

    ->see the quickMoveCompare() proc for more details
*/

quickMoveState := enum{NOT_DOING, LOOKING, DOING}.NOT_DOING

doubleClickTimerResetTimeSeconds : f32 = .5
doubleClickTimerSeconds : f32 = 0
doubleClickHandCardArray : ^[dynamic]^Card
doubleClickHandCardArrayIndex : int

quickMoveStartingCardArray : ^[dynamic]^Card
quickMoveStartingCardArrayType : CARD_ARRAY_TYPE
quickMoveStartingCardArrayIndexIs0 : bool

currentBestQuickMoveCardArray : ^[dynamic]^Card
currentBestQuickMoveCardArrayType : CARD_ARRAY_TYPE

//storing the last card is for determining if at the beginning of a cycle or not
//(if you double click a card, and it's NOT the same as the last card array quick moved to,
//it's a new cycle. Otherwise, if it is the same card, it's the same cycle)
//->see quickMoveCompare for how this affects quick moving

lastCardArrayQuickMovedTo : ^[dynamic]^Card
lastCardArrayQuickMovedToIndex : int

// lastCardArrayQuickMovedToType : CARD_ARRAY_TYPE

firstQuickMoveInCycle := false

quickMoveCompare :: proc(card_array : ^[dynamic]^Card, type : CARD_ARRAY_TYPE)->bool{
    //the parameters represent a card array to test against. If the input card array is a better candidate,
    //returns true, false otherwise.

    if firstQuickMoveInCycle{
        
        //foundation gets priority, but disregard if we are starting from one,  if we already found
        //a foundation to move to this turn .
        if  type == .FOUNDATION && 
            
            quickMoveStartingCardArrayType != .FOUNDATION &&
            currentBestQuickMoveCardArrayType != .FOUNDATION
        {
                return true
        } 

        //tableau
        //->added checks to block moving to an empty tableau col if you're quick moving all the cards in another tableau col.
        //(moving a col to another col has no real gameplay effect. The idea behind quickmoving is to move to another spot
        //that is functionally different. If you just want to reorganize, you can still do it manually if you have enough freecells)
        //(note that this will only skip over empty cols that are next to each other. As soon as you move back to a col that isn't empty in the same cycle,
        //you will then move to another empty col if there is one later in the draw order. I think this is fine, just wanted to avoid
        //having to double click a bunch to move over empty cells, even though you probably won't run into this in a real game)
        if  type == .TABLEAU &&
            currentBestQuickMoveCardArrayType != .FOUNDATION && 
            currentBestQuickMoveCardArrayType != .TABLEAU &&
            !(quickMoveStartingCardArrayType == .TABLEAU && len(card_array) == 0 && quickMoveStartingCardArrayIndexIs0)
        {
                return true
        }
        
        //free cells
        if  type == .FREECELL &&
        
            currentBestQuickMoveCardArrayType != .FOUNDATION &&
            currentBestQuickMoveCardArrayType != .TABLEAU &&
            
            quickMoveStartingCardArrayType != .FREECELL &&
            currentBestQuickMoveCardArrayType != .FREECELL
        {
            return true
        } 

    }else{
        
        //NOT first move in cycle -> now we just want a simple move through the card arrays in draw order
        //EXCEPT we start where ever the quickmove starts. SO all you have to do is just grab the
        //next valid array, since quickMoveCompare will be called in that draw order (and only for valid arrays)
        //!!!THE DRAW ORDER IS KEY TO THIS -> if you move around the draw order, the order of comparisons changes, 
        //and may result in undesired behaviour.

        //->This still treats foundations/free cells collectively
        if currentBestQuickMoveCardArray == nil {
            return (type == .FOUNDATION && quickMoveStartingCardArrayType != .FOUNDATION) || (type == .FREECELL && quickMoveStartingCardArrayType != .FREECELL) || (type == .TABLEAU && !(quickMoveStartingCardArrayType == .TABLEAU && len(card_array) == 0 && quickMoveStartingCardArrayIndexIs0))
        }
    }

    return false
}


//DEBUG stuff
//I just turned these on/off by commenting/uncommenting them.

// debug_NoPutdownProcs := true
debug_NoPutdownProcs := false

// debug_NoPickupConditions : = true
debug_NoPickupConditions : = false




//PROCS
//


initGame :: proc(){

    fmt.print("cardSize:", cardSize)

    initHistory()

    gameState = .GAME_NEW

    //The real max you should be able to have in freecell is 20 (8 cards in a tableau, topmost is king, build from king to ace = 8 + 12 = 20)
    //->Just doing 52 to be thorough, incase there's some weird freecell rule I didn't consider.    
    for &cardArray in columns{
        cardArray = make([dynamic]^Card, 52)
    }

    for &cardArray in foundations{
        cardArray = make([dynamic]^Card, 52)
    }

    for &cardArray in freecells{
        cardArray = make([dynamic]^Card, 52)
    }

    initDeck()
}

canUndo := true
undoRepeating := false

undoRepeatTimeStart : f32 = 0.4
undoRepeatTimeInterval : f32 = 0.1 

undoRepeatTimeStartCount : f32 = 0
undoRepeatTimeIntervalCount : f32 = 0


onUndoRedo :: proc(){
    canUndo = false
    
    if undoRepeating{
        undoRepeatTimeIntervalCount = 0
    }

    //re-evaluate canAutoComplete after undoing 
    canAutocomplete = checkForAutoComplete()
}

//(maybe)hacky way of preventing switching from undo to redo when repeating
//(originally had it where, eg, if you were repeat undoing, pressing
//shift while still repeating causes you to go into redo repeating immediately.
//DON'T want this, because if you are redo repeating, and you lift the shift
//up before the ctrl or z keys, you'll do an unintentional undo. And visa versa)
UndoRepeatType :: enum{NONE, UNDO, REDO}
undoRepeatType : UndoRepeatType

updateGame :: proc(dt: f32){

    //input
    //some of there key checks might be better in the input.odin file procs, like mute, 
    //but I'm mostly working out of game.odin and it's nice to have everything here.

    keyboardState := SDL.GetKeyboardState(nil)

    if keyboardState[SDL.SCANCODE_N] == 1 && !keysProcessed[SDL.SCANCODE_N]{
        // fmt.println("n pressed")
        gameState = .GAME_NEW
        keysProcessed[SDL.SCANCODE_N] = true
    }
    
    if keyboardState[SDL.SCANCODE_ESCAPE] == 1 && !keysProcessed[SDL.SCANCODE_ESCAPE]{
        
        displayMenu = !displayMenu
        if displayMenu{
            playChunk("cancel_reverse")
        }else{
            playChunk("cancel")
        }
        keysProcessed[SDL.SCANCODE_ESCAPE] = true
    }

    
    if keyboardState[SDL.SCANCODE_W] == 1 && !keysProcessed[SDL.SCANCODE_W]{
        // fmt.println("w pressed")
        debugAutoWin()
        keysProcessed[SDL.SCANCODE_W] = true
    }
    
    if keyboardState[SDL.SCANCODE_M] == 1 && !keysProcessed[SDL.SCANCODE_M]{
        fmt.println("m pressed")
        toggleMute()
        keysProcessed[SDL.SCANCODE_M] = true
    }
    
  


    //GAME STATE based updates
    //

    if gameState == .GAME_NEW{

        pp_clearFramebuffer = true
        clearCards()
        resetHistory()

        shuffleDeck()
        quickMoveState = .NOT_DOING

        gameState = .GAME_DEAL
        canAutocomplete = false
        
        //dumb, but you have to reset the statics in the deal proc for 
        //each new game, otherwise they retain their values. So 2nd arg is
        //whether or not to reset. In theory, if dt >= 52 * cardDealInterval,
        //you might deal all the cards in one deal() call, so do the check to 
        //see if you need to switch to GAME_PLAYING

        if deal(dt, true, mouseDownEventThisFrameL) do gameState = .GAME_PLAYING
    
    }else if gameState == .GAME_DEAL{


        if deal(dt, false, mouseDownEventThisFrameL){ 
            gameState = .GAME_PLAYING

            //in the odd chance you have an autocompletable deal, enable autocompleting
            //!! note: deal() returning true doesn't mean all the cards are done moving visually,
            //so if you hit autocomplete button before they're done, the remaining cards will just move from (-cardsize.x, -cardsize.y)
            //to the foundation. (tested this, getting an autocompletable off the bat will almost never happen anyways, but even so it looks fine, and more importantly it works functionally.)
            //you'd otherwise have to make a checker for making sure all cards are not visual after dealing, wouldn't be too hard but I'm trying to
            //wrap this project up.
            canAutocomplete = checkForAutoComplete()
        }

        /*
        debugDealWin()
        gameState = .GAME_PLAYING
        */
    }

    if gameState == .GAME_PLAYING{
        //ONLY WANT TO PROCESS UNDOs while playing the game.
        //could put this in a proc to organize, but it's only really needed here.

        undoBeingHeld := (keyboardState[SDL.SCANCODE_LCTRL] == 1 || keyboardState[SDL.SCANCODE_RCTRL] == 1) && keyboardState[SDL.SCANCODE_Z] == 1

        if !undoBeingHeld{
            //z key up
            canUndo = true
            undoRepeating = false
    
            undoRepeatTimeStartCount = 0
            undoRepeatTimeIntervalCount = 0
        
        }else{
            //undo being held
    
            if !undoRepeating {
                
                if undoRepeatTimeStartCount < undoRepeatTimeStart{
                    undoRepeatTimeStartCount += dt
                }
                
                if  undoRepeatTimeStartCount >= undoRepeatTimeStart{
                    undoRepeating = true
                    undoRepeatType = .NONE
                }
            
            }
            
            if undoRepeating{
                //repeating
                
                if undoRepeatTimeIntervalCount < undoRepeatTimeInterval{
                    undoRepeatTimeIntervalCount += dt
                }
                
                if undoRepeatTimeIntervalCount >= undoRepeatTimeInterval{
                    canUndo = true
                    undoRepeatTimeIntervalCount = 0
                }
            }    
    
    
    
            if canUndo && handCardArray == nil{
                //added in check to make sure handCardArray == nil so you can't
                //undo while you have cards in the hand (other option is to just auto-drop the hand if
                //you undo, which might be nicer. Or have an audio/visual indicator that undo is being
                //blocked because you have a card in the hand)

                undoBlock:{
                    if keyboardState[SDL.SCANCODE_LSHIFT] == 1 || keyboardState[SDL.SCANCODE_RSHIFT] == 1{
                        fmt.println("ctrl + shift + z pressed, redoing!")
                        
                        if undoRepeating{
                            if undoRepeatType == .NONE{
                                undoRepeatType = .REDO
                            }
                            
                            if undoRepeatType != .REDO{
                                break undoBlock
                            }
                        }
    
                        if redo(){
    
    
                            pp_saturation_factor = 0.5
                            pp_desaturate = 1
                            
                            playChunk("redo")
    
                            onUndoRedo()
                        }
    
                    }else{
                        
                        fmt.println("ctrl + z pressed, undoing!")
                        if undoRepeating{
                            if undoRepeatType == .NONE{
                                undoRepeatType = .UNDO
                            }
                            
                            if undoRepeatType != .UNDO{
                                break undoBlock
                            }
                        }
    
                        if undo(){
    
    
                            pp_saturation_factor = 0.5
                            pp_desaturate = -1
                            
                            playChunk("undo")
    
                            onUndoRedo()
    
                        }
                    }
                }
            }
    
            //do this to be thorough, even though for undo I'm operating on raw input
            keysProcessed[SDL.SCANCODE_Z] = true
        }
    
        


        //AUTOCOMPLETING -> also only done while playing
        //similar to dealing, the proc has statics, so on the first call (here),
        //you need to reset them.

        if keyboardState[SDL.SCANCODE_A] == 1 && !keysProcessed[SDL.SCANCODE_A]{
            if canAutocomplete{
                gameState = .GAME_AUTOCOMPLETING
                autoComplete(dt, true)
            }
    
            keysProcessed[SDL.SCANCODE_A] = true
        }
        
    }


    if gameState == .GAME_AUTOCOMPLETING{
        fmt.println("GAME AUTOCOMPLETING!!!")

        autoComplete(dt, false)
        //This will 'turn off' when state changes to win, which is checked the same way as the regular game. 
    }

    if gameState == .GAME_PLAYING || gameState == .GAME_AUTOCOMPLETING{

        if checkForWin(){
            //all cards are now in foundations, but you have to wait for them to all be there visually.
            //-> when you enter win mode, you stop clearing the framebuffer and all drawCardArray in renderGame are skipped so nothing but the fake
            //card/winning text/whatever is beind drawn for the win animation.

            //so everything has to be in place before you actually enter 'win mode'

            enterWinMode := true

            //assume you already have all 52 cards in the foundations, 13 each 
            for card in deck{
                // fmt.println("card:", card)
                if getCardIsVisual(card){
                    enterWinMode = false
                    break
                }
            }
            
            if enterWinMode{
                gameState = .GAME_WIN
                doWinningAnimation(dt, true)

                playChunk("win")
            }

            //same thing as deal proc, I like the statics in the functions for organization,  but calling these twice
            //might indicate a structural problem
        }

    }


    if gameState == .GAME_WIN{
        doWinningAnimation(dt, false)
    }


    //default updates that happen independent of gamestate
    //(timers/visuals)

    if doubleClickTimerSeconds < doubleClickTimerResetTimeSeconds{
        // fmt.println("quick move time:", doubleClickTimerSeconds)
        doubleClickTimerSeconds += dt
        // fmt.println("updated quick move time:", doubleClickTimerSeconds)
    }

    
    //!!! Reduce the undo saturation factor even if not .PLAYING to prevent having wrong staturation if you undo and then switch modes
    //before saturation goes back to normal.
    if pp_saturation_factor > 0 do pp_saturation_factor = max(0,  pp_saturation_factor - 0.4 * dt)




    //update visual card timers. 
    for &visCard in visualCardArray{
        // fmt.println("visCard:",visCard)
        visCard.visTimeSeconds += dt
    }

    clear(&visualCardArray)
    //!!!WATCH -> now that there's two spots where you loop over vis card (one in renderGame() for drawing, 
    //and one here for updating time, independent of drawing), need to make sure you clear at the appropriate time.
    //right now this is here, since visCards get added in render game. 



    //RENDERING game
    //

    //!!! NOTE: gl.Viewport is leftover from the SDL2 demo, apparently isn't super
    //necessary for an app with only 1 viewport (vs. ex. blender, which has multiple views on screen at
    //the same time), but apparently not having can causes issue on some devices. Leaving for now, but
    //should determine exactly what this does if using a different device.

    gl.Viewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
    renderGame()
    

    //QUICK MOVES
    //

    if quickMoveState == .DOING{

        //actually do the quick move, now that all the card arrays have been checked
        //(all other quickmove stuff, like the actual checking/etc) is done in the drawCardArray() calls in renderGame())

        if currentBestQuickMoveCardArray != nil{
            // fmt.println("QUICK MOVING CARDS!!! to card array:", currentBestQuickMoveCardArray)

            lastCardArrayQuickMovedToIndex = len(currentBestQuickMoveCardArray)
            //have to set the lastCardArrayQuickMovedToIndex before moving,
            //since the len changes when you move the cards to the new array.


            moveCards(handCardArray, currentBestQuickMoveCardArray, handCardArrayIndex)
            playChunk("woosh")

            lastCardArrayQuickMovedTo = currentBestQuickMoveCardArray
            // lastCardArrayQuickMovedToType = currentBestQuickMoveCardArrayType
            
            firstQuickMoveInCycle = false
        }

        //Even if we didn't find a valid array to move to, we're done with the quick move 
        //(if we didn't find a valid array, now that quick move is set to .NOT_DOING, the hand card array drop will happen)
        quickMoveState = .NOT_DOING 
    }

    if doingManualPutdown{
        moveCards(handCardArray, currentClosestDistanceManualPutdownCardArray, handCardArrayIndex)
        playRandomCardPlaceSound()

        //!!! could do a nil check for currentClosestDistanceManualPutdownCardArray,
        //(instead of having/checking doingManualPutdown flag)
        //but it should always be set to some value if doingManPutdown = true 
        
        //-> the whole point of having the doingManualPutdown flag
        //is to avoid doing distance = 1000000 as a way of 'setting' it to nil 
        //(You compare against existing distance to determine the closest array,
        //so unless you have a flag, you would have to make up some impossible distance
        //in order to mark it as 'nil'
        //->The reason I didn't use -1 was because you are trying to find the smallest distance (if newdistance < currentDistance),
        //so you'd first have to check if the currentDistance == -1 or < 0, at which point you might as well have an explicit flag

    }

    doingManualPutdown = false
    currentClosestDistanceManualPutdownCardArray = nil


    if handCardArray != nil && quickMoveState == .NOT_DOING && (mouseIsDownR || mouseUpEventThisFrameL){
        dropHand()
    
        //After rendering game (doing collision checks for all putdowns), IF the hand hasn't been
        //putdown into an array, and the mouse has been release/etc, then drop it. 
        
        //UNLESS you are doing a quick move, in which case you don't want to drop it yet, 
        //as you may still need to check some arrays next frame
        
        //->originally just had this in render game, and it fits in either place, but the code flow is
        //easier to see if it's here in updateGame()
    }

    

}


renderGame :: proc(){
    //goes through everything that needs to be drawn and draws it. 
    //!!! IMPORTANT to note that this isn't exclusively rendering, 
    //as the drawCardArray() calls have IMGUI stuff in them.
    //(Maybe it should have a different name instead of renderGame) 
    
    //->the whole idea is that, because you are drawing the quads, and are figuring out
    //where they are being rendered on screen, you can, at the same time, check against mouse input
    //to determine if something is being clicked on/etc, and then react 'immediately'.)
    //This is my way of doing/interpretation IMGUI, don't know if adheres to a more strict definition of
    //IMGUI, but it works, at least for this (relatively small) project. 

    beginRenderPostProcessor()
    
    if gameState != .GAME_WIN{
        // drawRect(getTexture("uv_map"), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, glm.vec3(0.5))
        drawBg(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        

        //foundations
        for i in 0..<len(foundations){
            
            posX := foundationsOffsetX + (cast(int)cardSize.x + foundationdsAndCellsSpacingX) * i
            posY := topMarginY
            
            drawCardArray(&foundations[i], posX, posY, 0, .FOUNDATION)
        }
        
        //tableau (columns)
        for i in 0..<len(columns){

            posX := tableauOffsetX + ((cast(int)cardSize.x + tableauSpacingX) * i)
            posY := tableauOffsetY
            

            squishedCardSpacing := int(f32(tableauMaxSizeY - cast(int)cardSize.y) / f32(max(len(&columns[i]) -1, 1)))
            //!!!+1 to the len so you don't /0 when len is 0
            //I added this squished spacing stuff before realizing I should just make the cards smaller so that
            //they can all be seen on screen. (This is reflected in the spacing calculations at the top of this file (game.odin))
            //->not only does this mean less programming/edge cases, but I realized it's also better for the user to just be
            //able to see the entire game state at all times, without having things either changing constantly, or having to click
            //to see things)
            //As I've mentioned in other comments, I'm keeping this in just in case/so this can be adapted to future projects,
            //but everything is currently spaced/size such that cards should never need to be squished. 
            //->I'm not completely satisfied with the current behaviour though (card spacing changes immediately, you'd probably want to interpolate it,
            //which would probably mean you'd need a struct to wrap each card array with visual data, similar to cards, and it
            //just adds a bunch of complexity that makes for a worse user experience, as I mentioned. In certain cases it might be required though,
            //eg freecell on a small mobile screen needs something like this, as you can't make the cards small enough to not be squished, and still be visible,
             //so for those cases this is at least a start.)

            thisCardSpacingY := min(defaultCardSpacingY, squishedCardSpacing)
            
            drawCardArray(&columns[i], posX, posY, thisCardSpacingY, .TABLEAU)
            // drawCardArray(&columns[i], posX, posY, defaultCardSpacingY, .TABLEAU)
        }

        //free cells
        for i in 0..<len(freecells){
            // fmt.println("len(handCardArray) - handCardArrayIndex ", len(handCardArray) - handCardArrayIndex )
            drawCardArray(&freecells[i], freecellsOffsetX + (cast(int)cardSize.x + foundationdsAndCellsSpacingX) * i,  topMarginY, 0, .FREECELL)
        }
        

        //draw hand after everything (so it draws on top of card arrays)

        if handCardArray != nil{
            for i in handCardArrayIndex..<len(handCardArray^){

                hcx, hcy := getHandCardPosition(i-handCardArrayIndex)
                
                //update the visual start positions here, because when you drop the hand, 
                //you want the cards to go from hand position to new target.
                handCardArray[i].visStartPosX = hcx
                handCardArray[i].visStartPosY = hcy
                
                //turn the hand blue for testing
                // drawRect(cardTextures[handCardArray[i].suit][handCardArray[i].rank], hcx, hcy, cast(int)cardSize.x, cast(int)cardSize.y, 0, glm.vec3{0.0,1.0,1.0})
                drawRect(cardTextures[handCardArray[i].suit][handCardArray[i].rank], hcx, hcy, cast(int)cardSize.x, cast(int)cardSize.y, 0)

            }
        }        
            
        //visual cards
        //draw visual cards over top of other cards -> need to queue them in the drawCardArray calls, then draw them all after here, since if you draw them at the same time as normal cols,
        //they will be drawn behind normal cols that get drawn after. eg if card is visually moving from tableau 6 to 1 (meaning it's internally in col 1),
        //and you draw it at the same time as the rest of col 1, then it will appear behind cols 2 to 6, since they get drawn after col 1. (you can play Freecell in the Microsoft Solitaire Collection on Win10
        //for an example of this, at least on version 4.10.7290.0)
        for &visCard in visualCardArray{
                
            t := 1 - glm.pow(1 - (visCard.visTimeSeconds/visualMoveTimeSeconds), 3)

            visPosX := glm.lerp(cast(f32)visCard.visStartPosX, cast(f32)visCard.visTargetPosX, t)
            visPosY := glm.lerp(cast(f32)visCard.visStartPosY, cast(f32)visCard.visTargetPosY, t)


            drawRect(cardTextures[visCard.suit][visCard.rank], cast(int)visPosX, cast(int)visPosY, cast(int)cardSize.x, cast(int)cardSize.y, 0)

        }

    }else{
        //gameState == .GAME_WIN

        //this needs to be here (btw start/end pp) in order to get the non-cleared pp effect
        // drawRect(cardTextures[fakeCard.suit][fakeCard.rank], cast(int)fakeCard.visTargetPosX, cast(int)fakeCard.visTargetPosY, cast(int)cardSize.x, cast(int)cardSize.y, 0)
        drawRect(cardTextures[fakeCard.suit][fakeCard.rank], fakeCard.visTargetPosX, fakeCard.visTargetPosY, cast(int)cardSize.x, cast(int)cardSize.y, 0)
    }
    
    endRenderPostProcessor()
    renderPostProcessor(f32(SDL.GetTicks()) / 1000.0)
    //want total time here, not dt -> shaders have sin functions 
    
    // if doingQuickMove{
    //     renderText("doing quick move!!!", WINDOW_WIDTH/2 - 150, WINDOW_HEIGHT/2 - 50, 1, glm.vec3{1.0, 0.0, 1.0})
    // }
    
    // renderText(fmt.tprintf("Quick move timer:%f", doubleClickTimerSeconds), 0,0, 1, glm.vec3{0.0, 0.0, 1.0})
    // renderText(fmt.tprintf("Hand card array index:%f", handCardArrayIndex), 0,0, 0.5, glm.vec3{0.0, 0.0, 0.0})
    // renderText(fmt.tprintf("last quick move card array index:%f", lastCardArrayQuickMovedToIndex), 0, 40, 0.5, glm.vec3{0.0, 0.0, 0.0})
    // renderText(fmt.tprint("undoRepeating:", undoRepeating), 10, 10, 0.5, glm.vec3{1.0, 0.0, 0.0})
    // renderText(fmt.tprint("undoRepeatTimeStartCount:", undoRepeatTimeStartCount), 10, 50, 0.5, glm.vec3{1.0, 0.0, 0.0})

    // renderText(fmt.tprint("canAutoComplete:", canAutocomplete), 10, 10, 0.5, glm.vec3{0.0, 0.0, 1.0})
    
    if gameState == .GAME_PLAYING && canAutocomplete{
        acText := "(A)utocomplete"
        acTextScale : f32 = 0.5
        cosFac := (glm.cos(f32(SDL.GetTicks())*3 / 1000.0) + 1) / 2
        acTextColor := glm.vec3{1-cosFac, 1-cosFac, cosFac}
        renderText(acText, (WINDOW_WIDTH - getStringTextRendererWidth(acText, acTextScale))/2, WINDOW_HEIGHT - 50, acTextScale, acTextColor)
    }

        
    
    if gameState == .GAME_WIN{

        //!!!remember, hue range is 0-360, while sat and value are 0-1 like you'd expect.
        winTextColor := hsv_to_rgb(glm.vec3{ 360.0*f32(SDL.GetTicks() % 1000.0)/1000.0,1,0.7})

        winText := "YOU WIN!!!"
        winTextScale : f32 = 1
        renderText(winText, (WINDOW_WIDTH - getStringTextRendererWidth(winText, winTextScale))/2 , WINDOW_HEIGHT/2 - 50, winTextScale, winTextColor, true)
    
        winSubText := "(N)ew Game, (Q)uit"
        winSubTextScale : f32 = 0.5
        renderText(winSubText, (WINDOW_WIDTH - getStringTextRendererWidth(winSubText, winSubTextScale))/2 , WINDOW_HEIGHT/2 , winSubTextScale, winTextColor, true)
    }
    

    if displayMenu{
        menuPanelWidth := 725
        menuPanelHeight := 522

        mpX := (WINDOW_WIDTH - menuPanelWidth)/2
        mpY := (WINDOW_HEIGHT - menuPanelHeight)/2

        drawRect(getTexture("menu_panel"), mpX, mpY, menuPanelWidth, menuPanelHeight, 0, glm.vec4{0.0, 0.0, 0.3, 0.7})

        tY : f32 = cast(f32)mpY + 30


        t1 := "Esc - Back"
        t1s : f32 = 0.3
        renderText(t1, (WINDOW_WIDTH - getStringTextRendererWidth(t1, t1s))/2 , tY , t1s, glm.vec3(1.0))
        
        tY += 50 

        t3 := "FREECELL"
        t3s : f32 = 1
        renderText(t3, (WINDOW_WIDTH - getStringTextRendererWidth(t3, t3s))/2 , tY , t3s, glm.vec3(1.0), true)
        
        tY += 90


        controlLines := [?]string{
            "Controls:",
            "N - New Game, Q - Quit",
            "LMB - Click and drag cards (Double click a card to quick move)",
            "CTRL+Z - Undo, CTRL+SHIFT+Z - Redo",
            "A - Autocomplete (when applicable)",
            "M - Mute/Unmute",
            "W - Win (to demo win animation)",
            "",
            "See README for more info/credits/sources",
            "THANKS FOR PLAYING"

        }
        
        cls : f32 = .35

        for l in controlLines{
            renderText(l, (WINDOW_WIDTH - getStringTextRendererWidth(l, cls))/2 , tY , cls, glm.vec3(1.0))
            tY += 30
        }


    }


}//renderGame


drawCardArray :: proc(card_array : ^[dynamic]^Card, pos_x, pos_y, cardSpacingY: int, card_array_type: CARD_ARRAY_TYPE){

    cardArrayIsHand := handCardArray == card_array

    endingIndexInclusive := cardArrayIsHand ? handCardArrayIndex -1 : len(card_array)-1

    if cardArrayIsHand && quickMoveState == .LOOKING{
        //done looping though all the draw card arrays (back at the one where the quick move started), now set the state so that 
        //you can actually move the cards in updateGame() after all the rendering is done. 
        fmt.println("finished quick move looking")
        quickMoveState = .DOING
    }


    selectedCardIndex := -1
    selectedCardPosY := -1

    extraPixels := card_array_type == .TABLEAU && cardSpacingY != defaultCardSpacingY? (tableauMaxSizeY - cast(int)cardSize.y) - (cardSpacingY * (len(card_array) -1)) : 0;  
    currentCardPos := pos_y

    // if !(-1 <= endingIndexInclusive){
    //     panic(fmt.tprint("somethings wrong with drawCardArray: endingIndexInclusive, selectedCardIndex", endingIndexInclusive, selectedCardIndex))
    // }

    // fmt.println("card array:", card_array)
    //start at -1 to account for the empty cell. A little sloppy, but before I had an extra check up here for empty putdown that was copy pasted from
    //the below check putdown check for top  card in col. It worked okay, but I'm currently adding in more checks for doing quick moves, and I want everything
    //to go through one path/check.
    for i := -1; i <= endingIndexInclusive; i+=1{
        /*
            !!! Originally, I did not have a range here so that, if you move cards to an array as it was being drawn
            you could then update the ending index, and then draw the cards on the same frame. I changed this so 
            that you move the cards after drawing all the card arrays BECAUSE I added in the distance checking
            (can't move cards right away, since you might be overlapping a closer card in the next array -> only after you've checked against all the cards should you actually move)
            ->Everything works, but it does mean that there are a few things in this proc are structured around having the cards being moved immediately, that could be refactored.
            not going to bother doing that now, as I'm writing this at the end of the project, but should take a thorough look at this proc, as it's the most complex one in the whole
            game, and I reworked/added to it several times over development.
        */

        card := i < 0 ? nil : card_array[i]

        if card != nil && mouseDownEventThisFrameL{
            card.visJustStartedMoveSetVisuals = false
            card.visTimeSeconds = visualMoveTimeSeconds

            /*
                Cancel visual move if mouse is down. Do this up here, so below you can click on a card that just got un-visualed this frame.

                This facilitates doing quick moves, since on the first click in the double click, the card turns visual, even if the start/target positions
                are super close or the same. I was having an issue where you couldn't quick move because you'd click the card, it'd turn visual, then you'd click
                again and you wouldn't be able to click it because it was technically moving -> (!!!you can't click a card that is visually moving)

                This also fixes the issue where you could click on cards behind ones that were moving, eg. black ace on red 2: you'd click on the ace, it would turn visual, then
                you'd click on the black ace again, but you'd pick up the 2 and the ace because the ace was moving, so it wasn't doing collision checks. Now if you tried to do this,
                the ace snaps back in it's target pos and is picked up again immediately.

                ->note: In my old c++ solitaire I'm basing this on, I had a bunch of global flags for stuff like this, but this feels a lot cleaner/functionally better/less jumping around in code.
            */
            
        }


        //Determine card's Y position
        /*
            it's commented out below, but originally this was just a simple mult of i * cardSpacing
            All this other stuff is because of squishing: when there are too many cards, you
            want to determine cardSpacingY by dividing the available space such that the col of cards
            will be an exact size (tableauMaxSizeY).
            
            The problem is integer division: if you just divide the space
            up by the number of cards, you will get a rounded down y spacing for each card. Even a difference of 1 pixel
            is noticeable when you draw enough cards (eg 20 cards that are spaced 1 pixel too short results a col that is 20 pixels shorter)
            
            Ideal solution is to just rework the rendering to use floating point screen coords instead of pixel positioning, but I didn't want
            to rewrite everything to do this.
            
            So the solution I came up with is to just get the difference between tableauMaxSizeY and numCards * spacingY (->extraPixels),
            and just add 1 extra pixel to the first few cards. This is barely noticable, but the last card is always drawn in the same spot, which
            is desired

            The issue with this currently though is if you have more extra pixels than you do cards, I haven't thought too much about if/how that
            could happen, but you'd then have to go in and add 2+ pixels for each card instead.
            
            Anyways, this is what I was working on when I realized, as I mentioned in other comments, that it would be better to not have any squishing
            and just size the cards so that will never happen. All the squishing stuff is being left in for the future, (it will have to be
            improved upon, but I tested it and it's at least functional -> prevents cards from going off the bottom of the screen)
        
        */
        
        if(i >0){
            //currentCardPos is set to pos_y initially, so skip empty (-1) and first card (0) 
            currentCardPos += cardSpacingY

            if extraPixels > 0{
                currentCardPos += 1
                extraPixels -= 1
            }
        }
        
        cardPosY := currentCardPos
        // cardPosY := pos_y + cardSpacingY * max(0,i)

        if card == nil || !getCardIsVisual(card^){
            //only draw/do collision checks/etc if card is non visual

            // fmt.println("drawing card")
            if card == nil{
                drawRect(getTexture(cardArrayTypeToEmptyTexture[card_array_type]), pos_x, pos_y, cast(int)cardSize.x, cast(int)cardSize.y, 0)
            }else{
                drawRect(cardTextures[card.suit][card.rank], pos_x, cardPosY,  cast(int)cardSize.x, cast(int)cardSize.y, 0)
                
                card.visStartPosX = pos_x
                card.visStartPosY = pos_y
                
                //!!added setting visStartPos for cards every frame where they're not visual. Currently implementing automoving,
                //and realized the only way the visStartPos for a card will get set is when it's in the hand, and you're moving the hand around.
                
                //This wasn't an issue until this point, since before now you always have the cards in the hand before they move (even quickmoving uses the hand initially)
                //but autocompleting does NOT move cards to the hand, so (when testing, since I just have canAutocomplete set to true, no conditions), all the cards' vispositions
                //were at the dealing origin, not where the cards were in their cols. 
                
                //So to make this work, and to prevent any issues in the future, just set the card's start position
                //any frame, that way it's ready to go and will behave as expected. (remember, because of the imgui stuff, you can't just get a card's actual position, unless you save it here,
                //where it's being determined)
            }


            //PICKUP check
            //
            if gameState == .GAME_PLAYING && quickMoveState == .NOT_DOING && card != nil && mouseDownEventThisFrameL && checkCollisionPoint(pos_x, cardPosY, cast(int)cardSize.x, cast(int)cardSize.y, int(mousePosX), int(mousePosY)){
                //added gamestate check currently to prevent picking up while dealing.
                //!!! added  quickMoveState == .NOT_DOING as a precaution: even if it's unlikely, want to make sure you can't pickup anything during a quick move
                //(since a quickmove takes place over 2 frames)
                
                selectedCardIndex = i
                selectedCardPosY = cardPosY
                //by replacing selectedCardIndex every iteration, you end up with the topmost card at the end of the loop
                //same idea for cardPosY
            }

            //check for PUTDOWN
            //note: here I only check against the topmost card in the array, but some solitaire programs do collisions against all cards in the array
            //(you can put your hand into a tableu by dropping it on any card in the tableau, not just the top one)
            if (i == endingIndexInclusive) && handCardArray != nil && handCardArray != card_array && (mouseUpEventThisFrameL || quickMoveState == .LOOKING){
            // if (i == endingIndexInclusive) && handCardArray != nil && handCardArray != card_array && (mouseUpEventThisFrameL){
                    
                
                hcx, hcy := getHandCardPosition(0)
                overlapping := quickMoveState == .NOT_DOING && checkCollisionRect(pos_x, cardPosY, cast(int)cardSize.x, cast(int)cardSize.y, hcx, hcy, cast(int)cardSize.x, cast(int)cardSize.y)
                //!!!similar to the pickup check, want to ensure no putdowns during quickmoves, since they currently take place over
                //2 frames.
                
                if  (overlapping || quickMoveState == .LOOKING) && (debug_NoPutdownProcs && card_array_type == .TABLEAU || cardArrayTypeToPutdownProc[card_array_type](card_array)){
                    

                    if overlapping{
                            distance := glm.distance(glm.vec2{cast(f32)pos_x, cast(f32)cardPosY}, glm.vec2{cast(f32)hcx, cast(f32)hcy})

                            fmt.print("Putdown Collision!!!! Distance:", distance)
                            if !doingManualPutdown || distance < currentClostestDistanceManualPutdownDistance{
                                currentClosestDistanceManualPutdownCardArray = card_array
                                currentClostestDistanceManualPutdownDistance = distance
                            }


                        doingManualPutdown = true


                        }else if quickMoveState == .LOOKING{
                            if quickMoveCompare(card_array, card_array_type){

                                //GOT A GOOD COMPARE, set new candidate array
                                currentBestQuickMoveCardArray = card_array
                                currentBestQuickMoveCardArrayType = card_array_type

                            }
                        }
                        
                }
            }
            

        }else{
          
            //Card is moving visually -> getCardIsVisual(card) == true (basically just if the visual timer hasn't run out yet)

            //these cards are internally in the card array being draw, but they are visually moving
            //(eg. they were just dropped by the hand)
            
            if card.visJustStartedMoveSetVisuals{
                
                //Start visually moving the card
                //as the cards are interpolated, you set time / target position here once,
                //(as opposed to eg. moving a fraction of the distance each frame, which
                //is an issue if you want to explicitly set the time it should take for each move)

                card.visTimeSeconds = 0
                //(commenting this at the end of the project, I don't know why I made this a count up instead of a countdown)
                
                card.visTargetPosX = pos_x
                card.visTargetPosY = cardPosY 

                //unset the flag
                card.visJustStartedMoveSetVisuals = false
            }
            // fmt.println("!!!")

            //For all visual cards (just starting or currently visual), appeand to the visual card array.
            //Like the hand, want to draw these after everything, so you track them here and then update them
            //in updateGame(). Their timers/etc will also be updated there.
            append(&visualCardArray, card)
        }
            
    }//for each card

    // fmt.println("max cards, alt & desc :", getMaxMovableCards(), getIsAltAndDesc(card_array, selectedCardIndex))
    //!!!have to use card_array here for checks, NOT handCardArray, since you don't actually have cards in the hand yet

    //SELECTING/PICKING UP CARDS
    //now that all the cards have been looped over, we should have the topmost card / set of cards that were collided with the cursor.

    if selectedCardIndex != -1 && ( debug_NoPickupConditions || (len(card_array) - selectedCardIndex <= getMaxMovableCards() && getIsAltAndDesc(card_array, selectedCardIndex)) ) {

       // playRandomCardPlaceSound()
       playChunk("card_place_1")

        //pick up cards
        handCardArray = card_array
        handCardArrayIndex = selectedCardIndex 
        handCardOffsetX = pos_x - cast(int)mousePosX
        handCardOffsetY = selectedCardPosY - cast(int)mousePosY

 
        //QUICK MOVE DOUBLE CLICKING
        //put the quickmove stuff down here, as opposed to in the click check above, since you only want to be able to quick move valid cards.
        //!!!If adding other ways of selecting, eg tab/enter, pressing enter twice might trigger a quick move, depending on how you set it up. 
        if quickMoveState == .NOT_DOING{
            if(doubleClickTimerSeconds < doubleClickTimerResetTimeSeconds){
                
                fmt.println("starting quick move!!!")
                quickMoveState = .LOOKING

      
                // currentBestQuickMoveCardArray = card_array
                // currentBestQuickMoveCardArrayType = card_array_type

                currentBestQuickMoveCardArray = nil
                currentBestQuickMoveCardArrayType = .DEFAULT

                quickMoveStartingCardArray = card_array
                quickMoveStartingCardArrayType = card_array_type
                quickMoveStartingCardArrayIndexIs0 = selectedCardIndex == 0

                doubleClickTimerSeconds = doubleClickTimerResetTimeSeconds;
                //I don't have a "stop checking for double click timer" bool/flag, so to make sure you cancel doing any other potential quick moving stuff,
                //set the timer to the max (which means your done with the double clicking, now do the quick move)

                if !(lastCardArrayQuickMovedTo == card_array && lastCardArrayQuickMovedToIndex == handCardArrayIndex){
                // if !(lastCardArrayQuickMovedTo == card_array){

                    firstQuickMoveInCycle = true
                }

            }else{
                //Same card array selected with the same card index before the quick move timer is up:
                //start doing a quick move (set arrays and set timer)

                // fmt.println("doubleClickTimerSeconds , doubleClickTimerResetTimeSeconds", doubleClickTimerSeconds, doubleClickTimerResetTimeSeconds)
                // fmt.println("quick move primed - timer set to 0")
                doubleClickHandCardArray = card_array
                doubleClickHandCardArrayIndex = selectedCardIndex
                doubleClickTimerSeconds = 0;
            }
        }

    }
}



checkCollisionRect :: proc(x1, y1, w1, h1, x2, y2, w2, h2 : int) -> bool{

    //x1, y1 is the top left hand coord)
    //x1------x1B
    //y1
    // |
    // |
    // |
    //y1B

    x1B := x1 + w1;
    x2B := x2 + w2;
    y1B := y1 + h1;
    y2B := y2 + h2;

    return !(x1B < x2 || x1 > x2B|| y1B < y2 || y1 > y2B) 
}

checkCollisionPoint :: proc(x, y, w, h, point_x, point_y : int) -> bool{
    //check collision between a rect (x, y, w, h) and a point (point_x, point_y)

    return !(point_x < x || point_y < y || point_x > x + w || point_y > y + h)
    
}


//PUT DOWN PROCS
//originally just had these inline in renderGame, moved them out for readability
putDownProcFreeCells :: proc(card_array: ^[dynamic]^Card)->bool{
    // fmt.println("len(handCardArray) - handCardArrayIndex ", len(handCardArray) - handCardArrayIndex)
    // fmt.println("len(handCardArray), handCardArrayIndex ", len(handCardArray), handCardArrayIndex)
    
    cards_in_hand := len(handCardArray) - handCardArrayIndex 
    return cards_in_hand == 1 && len(card_array) == 0
}

                
putDownProcFoundations :: proc(card_array: ^[dynamic]^Card)->bool{

    //only 1 card in hand
    if len(handCardArray) - handCardArrayIndex != 1 do return false 
    
    //matching suits -> skip if foundation is empty
    if len(card_array) != 0 && handCardArray[handCardArrayIndex].suit != card_array[len(card_array)-1].suit do return false 

    //ascending rank
    //-1 for empty, since ace is 0, so the check works for empty
    currentRank := len(card_array) == 0 ? -1 : card_array[len(card_array)-1].rank
    if handCardArray[handCardArrayIndex].rank != currentRank + 1 do return false   
    
    return true

} 

putDownProcTableaus :: proc(card_array : ^[dynamic]^Card)->bool{
                    
    if len(card_array) != 0{
        currentRank := card_array[len(card_array)-1].rank
        return getCardSuitsAreAlternating(handCardArray[handCardArrayIndex], card_array[len(card_array)-1]) && handCardArray[handCardArrayIndex].rank == currentRank - 1 
    }else{
        //if moving to an empty tableau col, you halve the max number of cards you're allowed ot move (see comments in getMaxMovableCards proc) 
        if len(handCardArray) - handCardArrayIndex > getMaxMovableCards()/2 do return false
    }

    //if empty, just put the hand in
    return true
}



checkForWin ::proc()->bool{
    
    for i in 0..<len(foundations){
        if len(foundations[i]) != 13 do return false
    }
    fmt.println("win detected!!!")
    return true
}


checkForAutoComplete :: proc()->bool{
    //I have this set so you can autocomplete as long
    //as all tableau cols have cards sorted by rank descending.
    //(I don't think suits should matter)
    
    for i in 0..<len(columns){
        for j in 0..< len(columns[i]) -1{
            if columns[i][j].rank < columns[i][j+1].rank{
                return false
            }
        }
    }

    fmt.println("game is autocompletable!!!")
    return true
}


getHandCardPosition :: proc(i:int) -> (x, y: int){
    //helper, since currently you need this to 1: draw out hand cards, and 2: to get the position of the bottom
    //card to do collision detection (currently I do collision checks for each card array as they're drawn, against 
    //the hand card)

    //!!! i is the index relative to the handCardArrayIndex. -> eg if handCardArrayIndex == 6, then i == 0
    //gets you the position of the 6 + i == 6 + 0 == 6th card

    return cast(int)mousePosX + handCardOffsetX, (cast(int)mousePosY + defaultCardSpacingY * (i)) + handCardOffsetY
    // return cast(int)mousePosX + handCardOffsetX, (cast(int)mousePosY + handCardSpacingY * (i)) + handCardOffsetY
}


moveCards :: proc(from, to : ^[dynamic]^Card, fromStartingIndex:int){
    
    //FIRST, backup the existing card arrays. (for undo history)
    savePoint(from)
    savePoint(to)

    //then do the actual move stuff
    for &card in  handCardArray[handCardArrayIndex:]{
        card.visJustStartedMoveSetVisuals = true
    }

    append(to, ..from[fromStartingIndex:])
    remove_range(from, fromStartingIndex, len(from))

    handCardArray = nil
    handCardArrayIndex = -1

    //check for autocomplete after every move
    canAutocomplete = checkForAutoComplete()

}


dropHand :: proc(){
    fmt.println("in dropping hand")

    // playRandomCardPlaceSound()
    playChunk("card_place_1")

    for &card in handCardArray[handCardArrayIndex:]{
        card.visJustStartedMoveSetVisuals = true
    }

    handCardArray = nil
    handCardArrayIndex = -1

}

getMaxMovableCards :: proc()->int{
    /*
        https://www.solitairecity.com/Help/FreeCell.shtml
        this is explained in more detail here, but in free cell, you are only allowed to move 1 card at a time, but
        by using empty tableaus/free cells, you can effectively move stacks of cards that are of descending rank, with
        alternating colors. The base number of cards you can move is equal to the number of free cells plus one, doubled 
        by each free tableau (site looks older, so in the future if the link is broken I'm sure you can find details online,
        or just work it out yourself) 

        !!!
        THIS RETURNS THE BASE MAX
        max cards gets halved if you're moving to an empty col, since you can't use that col as a doubler if that's where
        you're transfering cards to (see https://en.wikipedia.org/wiki/FreeCell#cite_note-stackex-5, https://boardgames.stackexchange.com/questions/45155/freecell-how-many-cards-can-be-moved-at-once/45157#45157)
        although it's more comprehensive to represent this as subtracting from the empty tableau count, as
        opposed to dividing the result by 2, even though you're doing the latter 
        ->so you also need to do a check when putting down -> you should still be allowed to pick up max
        cards, but if you try to put them into an empty tableau, then you do the /2 check.
    */

    emptyfreeCellCount := 0
    for cell in freecells{
        if len(cell) == 0{
            emptyfreeCellCount += 1
        }    
    }    

    emptyTableauCount := 0
    for col in columns{
        if len(col) == 0{
            emptyTableauCount += 1
        }    
    }    

    return (emptyfreeCellCount + 1) * int(glm.pow(2.0, f32(emptyTableauCount))) 
}

getIsAltAndDesc :: proc(card_array : ^[dynamic]^Card, starting_index : int)->bool{
    //currently this is just to check to see if a prospective hand is good to be picked up,
    //so the args assume you're concerned with the cards from startingIndex to the end.

    for i := starting_index; i < len(card_array) -1; i += 1{
        //for every pair, first check if the rank is descending by 1
        if card_array[i].rank != card_array[i+1].rank +1{
            return false
        }

        //then check for alternating suits
        suitsAreAlternating := getCardSuitsAreAlternating(card_array[i], card_array[i+1])

        if !suitsAreAlternating do return false
    }

    return true
}

getCardSuitsAreAlternating :: proc(card1, card2 : ^Card) -> bool{
   
    if card1.suit == SUIT.CLUBS || card1.suit == SUIT.SPADES{
        // fmt.printfln("card 1 is black")
        return card2.suit == SUIT.DIAMONDS || card2.suit == SUIT.HEARTS 
    }else{
        // fmt.printfln("card 1 is red")
        return card2.suit == SUIT.CLUBS || card2.suit == SUIT.SPADES
    }
}

initDeck :: proc(){
    
    for i in 0..<len(deck){
        deck[i].id = i 
        deck[i].suit = SUIT(i%4)
        deck[i].rank = (len(deck)-i -1)/4
    }

}

shuffleDeck :: proc(){
    rand.shuffle(deck[:])
    // shuffle takes in a slice, [:] gives you a slice (see odin overview docs)

    /*
        old manual shuffle 
        fmt.printfln("shuffling deck")
        fmt.printfln("deck before shuffle:", deck)

        for i : i32 = 0; i <12; i+=1{
            for j : i32 = 0; j < i32(len(deck)); j+=1{
                swapIndex := i + rand.int31_max(i32(len(deck))-i)
                temp := deck[swapIndex]
                deck[swapIndex] = deck[i]
                deck[i] = temp
            }

        }

        fmt.printfln("deck after shuffle:", deck)
    */
}


deal :: proc(dt : f32, resetStatics : bool, dealEverythingImmediately : bool) -> bool{
    //returns true when deal is done (all cards dealt)
    
    dt:=dt

    @(static) timerSeconds : f32 = 0.0
    @(static) leftoverDt : f32 = 0.0
    @(static) cardsDealt := 0
    @(static) col := 0
    
    if resetStatics{
        timerSeconds = 0.0
        leftoverDt = 0.0
        cardsDealt = 0
        col = 0
    }

    dealIntervalSeconds : f32 = .05


    dt += leftoverDt

    if dealEverythingImmediately{
        //play one sound effect when dealing everything, as opposed to all of them (sounds bad when 30 card place sfx play at once)
        playChunk("undo")
    }


    for dt >= dealIntervalSeconds || dealEverythingImmediately {
        
        
        append(&columns[col], &deck[cardsDealt])
        if !dealEverythingImmediately{
            // playRandomCardPlaceSound()
            playChunk("card_place_1")
            //sounds better while dealing when it's the same sound effect, as opposed to random.
        }

        // fmt.println("dealing card:", &deck[cardsDealt])

        columns[col][len(columns[col])-1].visStartPosX = int(-cardSize.x)
        columns[col][len(columns[col])-1].visStartPosY = int(-cardSize.y)
        columns[col][len(columns[col])-1].visTimeSeconds = visualMoveTimeSeconds

        columns[col][len(columns[col])-1].visJustStartedMoveSetVisuals = true

        cardsDealt +=1

        // if cardsDealt == 25 do return true
        //test card squishing by putting a bunch of cards in one col.

        if cardsDealt == len(deck) do return true
        //!!!I thought of resetting the statics here, when you're done dealing, the issue though
        //is if you start a new game in the middle of a deal, there's no way for the function to know,
        //so eg, you start dealing on col 5 because you didn't actually finish the previous deal.
        //could prevent redealing in the middle of a deal, but I like doing that and I'm sure there 
        //are other scenarios where this would be an issue.
        
        // col = col + 1 >= len(columns) -1 ? 0 : col + 1//leave one col blank for testing
        col = col + 1 >= len(columns) ? 0 : col + 1
        dt -= dealIntervalSeconds

    }

    leftoverDt = dt

    return false
}

autoComplete :: proc(dt : f32, resetStatics : bool){
    
    dt:=dt

    @(static) timerSeconds : f32 = 0.0
    @(static) leftoverDt : f32 = 0.0
    @(static) foundationIndex : int = 0

    if resetStatics{
        timerSeconds = 0.0
        leftoverDt = 0.0
        foundationIndex = 0
    }

    intervalSeconds : f32 = .05

    dt += leftoverDt


    for dt >= intervalSeconds  {

        flen : = len(foundations[foundationIndex])

        currentTopFoundationCard := flen == 0 ? nil : foundations[foundationIndex][flen-1]

        rankToFind := currentTopFoundationCard == nil ? 0 : currentTopFoundationCard.rank + 1 
        suitToFind : SUIT
        
        if currentTopFoundationCard == nil{
            //if there's no card in a foundation, need to find an suit that doesn't already have a 
            //foundation (since foundations don't have an assigned suit)
            //Using bitset to avoid having to loop through all foundations and compare against each suit in SUIT.
            
            existingSuits : Suit_Set = {}
            
            for f in foundations{
                if len(f) > 0{
                    //this is how you set a bit in a bitset (using += {enum value} for an enum bitset -> {enum value I guess gets treated like it's own set, as + op is the union of two sets})
                    existingSuits += {f[len(f)-1].suit}
                }
            }

            for suit in SUIT{
                if suit not_in existingSuits{
                    suitToFind = suit
                    break
                }
            }
        
        }else{
            suitToFind = currentTopFoundationCard.suit
        }


        acBlock : {
            for &fc in freecells{
                for cardIndex in 0..<len(fc){
                    if fc[cardIndex].suit == suitToFind && fc[cardIndex].rank == rankToFind{
                        append(&foundations[foundationIndex], fc[cardIndex])
                        //this has to be an ordered remove
                        //ordered remove : shifts all elements over to fill in the removed item.
                        //unordered: removes the item, then replaces the enpty spot with the last element (so you only touch 2 elements, it's O(1) (see docs))
                        fc[cardIndex].visJustStartedMoveSetVisuals = true
                        ordered_remove(&fc, cardIndex)
                        playChunk("card_place_1")
                    
                        break acBlock
                    }
                }
            }

            for &col in columns{
                for cardIndex in 0..<len(col){
                    if col[cardIndex].suit == suitToFind && col[cardIndex].rank == rankToFind{
                        append(&foundations[foundationIndex], col[cardIndex])
                        col[cardIndex].visJustStartedMoveSetVisuals = true
                        ordered_remove(&col, cardIndex)
                        playChunk("card_place_1")
                    
                        break acBlock
                    }
                }
            }

        }

        foundationIndex = foundationIndex + 1 >= len(foundations) ? 0 : foundationIndex + 1
        dt -= intervalSeconds

    }

    leftoverDt = dt
    
}

debugDealWin :: proc(){
    //deals all the cards in the foundations to test 'winning'
    //note: this was originally to test the winning animation, 
    //but now I've implemented autocomplete, so I just call that instead
    
    initDeck()

    for i in 0..<len(deck){
        
        f := i%4
        append(&foundations[f], &deck[i])

        foundations[f][len(foundations[f])-1].visJustStartedMoveSetVisuals = true
        foundations[f][len(foundations[f])-1].visStartPosX = int(-cardSize.x)
        foundations[f][len(foundations[f])-1].visStartPosY = int(-cardSize.y)
        foundations[f][len(foundations[f])-1].visTimeSeconds = visualMoveTimeSeconds
    }

}

clearCards :: proc(){
    
    for i in 0..<len(columns) do clear(&columns[i])
    for i in 0..<len(foundations) do clear(&foundations[i])
    for i in 0..<len(freecells) do clear(&freecells[i])

    handCardArray = nil
    handCardArrayIndex = -1

}

deinitGame :: proc(){
    // delete(deck)


    for col in columns do delete(col)
    for foundation in foundations do delete(foundation)
    for freecell in freecells do delete(freecell)

    delete(visualCardArray)
    deinitHistory()
}


doWinningAnimation :: proc(dt : f32, newWin : bool ){
    // fmt.println("in do Winning Animation!!!")

    @(static) testPosX := 0

    drawRect(getTexture("uv_map"), testPosX, 100, 100, 100, 0, glm.vec4{1.0, 0.0, 0.0, 1.0})
    // testPosX = int((glm.cos(dt)+1)/2) * WINDOW_WIDTH
    testPosX += 1

    @(static) fakeVelocityX : f32 = 0.0
    @(static) fakeVelocityY : f32 = 0.0
    
    @static fakeAccY : f32 = 3400.0

    @(static) readyToStartNextCardAnimation := true

    @static cardCount := 0

    
    if newWin{
        cardCount = len(deck)
        readyToStartNextCardAnimation = true
        //!!!reset ready, otherwise fake card continues from where it left off 

        pp_clearFramebuffer = false

    }

    //idea is to pop the card pointers, then just assign them to a fake card that does the animation.
    //this works in this case since you animate one card at a time, and it means you don't have to mess 
    //with the actual card arrays or anything.

    if cardCount > 0{

        if readyToStartNextCardAnimation{
            // fmt.println("starting next card")
            readyToStartNextCardAnimation = false

            invertCardCount := len(deck) - cardCount
            nextCard := foundations[invertCardCount % 4][(cardCount-1)/4]
            
            fakeCard.visTargetPosX, fakeCard.visTargetPosY = nextCard.visTargetPosX, nextCard.visTargetPosY
            
            fakeCard.suit = nextCard.suit
            fakeCard.rank = nextCard.rank

            sign : [3]f32 = {1, -1, -1}
            fakeVelocityX = rand.choice(sign[:]) * rand.float32_range(150.0, 1000.0)
            fakeVelocityY = 0

            playRandomCardPlaceSound()
        }


        fakeCardPositionInBounds := checkCollisionRect(fakeCard.visTargetPosX, fakeCard.visTargetPosY, cast(int)cardSize.x, cast(int)cardSize.y, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        if fakeCardPositionInBounds{
            // fmt.println("fake card in bounds, moving")
            
            fakeCard.visTargetPosX += int(fakeVelocityX * dt)
            ///!!! since this is cast to int, need to make sure velocity is high enough so that v *dt >1, otherwise it will round to 0 when
            //casting and there's no movement

            fakeVelocityY += fakeAccY * dt

            fakeCard.visTargetPosY += int(fakeVelocityY * dt) 

            if fakeCard.visTargetPosY > WINDOW_HEIGHT - cast(int)cardSize.y {
                fakeCard.visTargetPosY = WINDOW_HEIGHT - cast(int)cardSize.y
                fakeVelocityY *= rand.float32_range(-.8,-.7)

                playChunk("pingpong_1")
                
                fmt.println("fakevelocityY:", fakeVelocityY)

                //!! < 75 is for whatever the current values are
                if abs(fakeVelocityY) < 70{
                    fakeVelocityY = -5000
                    playChunk("siren_whistle")


                }
            
            }

        }else{
            readyToStartNextCardAnimation = true
            cardCount -= 1
        }

    }

}

getCardIsVisual :: proc(card : Card)-> bool{
    return card.visJustStartedMoveSetVisuals || card.visTimeSeconds < visualMoveTimeSeconds
}

debugAutoWin ::proc (){
    // clearCards()
    // debugDealWin()
    
    //keeping this for the actual game, now that autocompleting is implemented,
    //it's a better way of doing this. NOTE !!! -> the old way (calling clearCards()/debugDealWin()) should still
    //set gamestate to autocomplete, otherwise the autocomplete popup will show up as the cards are
    //all moving to the foundations (because there are no cards in the tableaus, and debugDealWin 
    //sets the state to .PLAYING, so autocomplete checks are done)
    if gameState == .GAME_PLAYING{
        //added gamestate check because you can't autocomplete if you're dealing, so 
        //if you call this while dealing, everything stops and you have to start a new game)
        gameState = .GAME_AUTOCOMPLETING
    }
}

playRandomCardPlaceSound :: proc(){

    cardChunkSlice := []string{"card_place_1", "card_place_2", "card_place_3"}
    playChunk(rand.choice(cardChunkSlice))
    // playChunk("card_place_1")
}


hsv_to_rgb :: proc (hsv : glm.vec3)->glm.vec3{

    //just copied this over from the post processing frag shader,
    //This is one of the last things I'm adding, I just need to make the win text more
    //visible (against the animating cards), and I don't want to bother setting up SDF outlines,
    //so I'm just adding a hue shift effect.

    h := hsv.x
    s := hsv.y
    v := hsv.z

    if s == 0 {
        //if saturation is 0, just return value for everything
        //in the book, they do an additional check for h == undefined, if it is, they do the return, else they throw an error
        //this seems unecessary, but either way I'm not doing it.
        return glm.vec3(v)
    
    }else{
        // // /60 and sextant -> The HSV model is represented by an inverted hexagonal pyramid ('hexicone')
        // //the 6 points on the hexigon are red, yellow, green, cyan, blue, and magenta. so each sextant is the 6th of the cone
        // //between two of these colors (360/6 = 60 degrees). Look at figure 8.7 in the book (pg 320 pdf / 302 actual)

        h = glm.mod(h, 360.0)/60.0

        sextant := glm.floor(h)

        fract := h - sextant

        p := v * (1 - s) 
        q := v * (1 - (s*fract)) 
        t := v * (1 - (s*(1-fract))) 
       
       
        rgb := glm.vec3(0)            

        if(sextant == 0){
            rgb = glm.vec3{v, t, p}

        }else if(sextant == 1){
            rgb = glm.vec3{q, v, p}

        }else if(sextant == 2){
            rgb = glm.vec3{p, v, t}

        }else if(sextant == 3){
            rgb = glm.vec3{p, q, v}

        }else if(sextant == 4){
            rgb = glm.vec3{t, p, v}

        }else if(sextant == 5){
            rgb = glm.vec3{v, p, q}
        
        }

        return rgb;
    }
}