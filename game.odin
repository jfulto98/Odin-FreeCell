package freecell

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math/rand"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import stbi "vendor:stb/image"
import SDL "vendor:sdl2"

//TODO:
//->Add in blender dragging (to prevent unwanted moving when double clicking, make it so you have to drag out of a certain radius before actually
//moving anything
//->add in closest collision detection logic
//if you have a 2+ card sequence in a tableau (eg red8 on black9), if you quickly click and release the 8,then click again before it's back in it's column,
//no collision is done on it and you pick up the 9 and 8 -> prevent this by cancelling visual moving early if you click

spriteVAO: u32

GameState :: enum{GAME_NEW, GAME_DEAL, GAME_PLAYING, GAME_WIN}

gameState : GameState

proj : glm.mat4
//the projection matrix is here since it's meant to be used as a uniform for both
//the default and particle shader, and to be consistent with the other uniforms,
//I'm going to use it each time in the respective draw/render functions
//I'm currently setting it once in the init game func

//cards setup
NUM_CARDS_IN_DECK :: 52


card_size := glm.ivec2{90, 131}
//actual card pngs are 500 x 726 (250/363 ratio)

Card :: struct{
    id : int,
    rank : int,
    suit : int,

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

//added in card array types after adding quick moves, since you need to know what type of
//array is getting drawn. (mentioned this in some other comments but this feels like a shortcomming
//of doing everything in this IMGUI way)
CARD_ARRAY_TYPE :: enum{DEFAULT, TABLEAU, FOUNDATION, FREECELL}
//after adding array type, figured it would be good to just map the pickup procs and empty card texture/etc,
//so you only need to pass in the type to drawCardArray
cardArrayTypeToPutdownProc := map[CARD_ARRAY_TYPE](proc(^[dynamic]^Card)->bool){
    .DEFAULT = proc(card_array : ^[dynamic]^Card)->bool{return true},
    .TABLEAU = putDownProcTableaus,
    .FOUNDATION = putDownProcFoundations,
    .FREECELL = putDownProcFreeCells,
}

cardArrayTypeToEmptyTexture := map[CARD_ARRAY_TYPE]string{
    .DEFAULT = "empty",
    .TABLEAU = "empty",
    .FOUNDATION = "foundation",
    .FREECELL = "freecell",
}


handCardArray : ^[dynamic]^Card
handCardArrayIndex : int 
handCardOffsetX, handCardOffsetY : int

doingManualPutdown := false
currentClosestDistanceManualPutdownCardArray : ^[dynamic]^Card
currentClostestDistanceManualPutdownDistance : f32


visualCardArray : [dynamic]^Card
visualMoveTimeSeconds : f32 = 0.2

fakeCard : Card
//a fake card used to do the winning animations

defaultCardSpacingY := int((card_size.y * 95) / 363)
//for the current card textures, this will give you the correct
//y spacing such that the number and suit symbol of each card will be
//visible in a column/tableau

tableauSpacingX := 35
tableauOffsetX := (WINDOW_WIDTH/2) - ((len(columns)*(cast(int)card_size.x + tableauSpacingX) - tableauSpacingX)/2)
tableauOffsetY := 180

foundationdsAndCellsSpacingX := 35
foundationdsAndCellsOffestY := 20

foundationsOffsetX := (WINDOW_WIDTH/4)*3 -  ((len(foundations)*(cast(int)card_size.x + foundationdsAndCellsSpacingX) - foundationdsAndCellsSpacingX)/2)
freecellsOffsetX := (WINDOW_WIDTH/4) -  ((len(foundations)*(cast(int)card_size.x + foundationdsAndCellsSpacingX) - foundationdsAndCellsSpacingX)/2)

//QUICK MOVES
/*
    I put in a ton of comments in the code detailing quick moves.
    the main problem with doing something like this with IMGUI principles is that it's
    not really designed for the simple thing, which would be to, upon double clicking,
    just loop through all the card arrays, check to see which card array can accept the double clicked card(s), if any,
    and then do/don't do the move immediately. 

    ->instead, the best thing I could come up with was to do the following:

    1) if you double click on a card/subset of cards in an array, change state from .NOT_DOING to LOOKING, and store the card array that contains the cards that are to be moved (this is done by just using the hand, 
    but not releasing it until all the quickmove stuff is done, even if you mouseup/etc)
    
    2) as you loop thought drawing the card arrays, if an array can accept the cards, then check it with the quick move compare function. If it's a better candidate for moving
    than the last card, set it as the currentBestQuickMoveCardArray (don't know the name for this idiom, but it's just a more complex 'if a > b { biggest = a }')
    
    3)in the next frame, when you call drawCardArrays for the array with the cards you double clicked, you will know you have checked all the card arrays. Then set the state to .DOING
    
    4)right after the renderGame() call in updateGame(), there's a check for .DOING. If  currentBestQuickMoveCardArray != nil, then you found an array to quick move to, so now actually 
    do the move. Either way, you then set the state back to .NOT_DOING to finish the quick moving process.
    
    ->so the whole thing takes place over 2 frames. The reason you want to wait until after drawing all the other card arrays on the second frame, instead of immediately moving, is because 
    the currentBestQuickMoveCardArray may be an array that was already drawn this frame. Since you would be releasing the hand (which doesn't get drawn until after all the card arrays are drawn,
    this results in the card disappearing for a frame. 
    ->Had a similar issue with moving cards normally, except with that, you move the cards while drawing the card array you putdown onto. Because
    the cards are drawn on top, you can just draw them immediately after. 

    ->Doing the actual move after all the drawing ensures the cards get drawn
    -> to ensure there are no other issues, I also prevent normal pickups/putdowns from happening while !.NOT_DOING

    ->again, this probably isn't ideal, but it's similar to how might do things like tabbing through an imgui menu (things that involve the different imgui elements needing to know about each other in some capacity.
    ->It's at least an improvement from my old C++ solitaire, where I didn't think to do the  'if a > b { biggest = a }' way of checking, and instead
    I think I did multiple loops to get the best candidate array.

    ->I've made way too many comments, so I won't go into exact detail about how the actual quickMoveCompare works, but the basic idea is that if it's the first time you're moving a card/stack of cards with quick move,
    move it to the best available spot in this order: foundation (collectively) -> tableau cols (individually) -> free cells (collectively) 
    ->then, as long as you keep trying to quick move the same set of cards, just move to the next best available spot, looping back to the foundation after the last tableau col.
    -> with this method, you are guarenteed to have the cards cycle through all the valid card arrays they can move to (an issue in some of the free cell games I tested for this was that a card would just cycle between
    the same two spots, and ignore other potential moves.

*/

quickMoveState := enum{NOT_DOING, LOOKING, DOING}.NOT_DOING

doubleClickTimerResetTimeSeconds : f32 = .5
doubleClickTimerSeconds : f32 = 0
doubleClickHandCardArray : ^[dynamic]^Card
doubleClickHandCardArrayIndex : int

quickMoveStartingCardArray : ^[dynamic]^Card
quickMoveStartingCardArrayType : CARD_ARRAY_TYPE

currentBestQuickMoveCardArray : ^[dynamic]^Card
currentBestQuickMoveCardArrayType : CARD_ARRAY_TYPE

//storing the last card isn't part of quickMoveCompare, it's just
//for determining if at the beginning of a cycle or not
//(if you double click a card, and it's NOT the same as the last card array quick moved to,
//it's a new cycle. Otherwise, it's not 
lastCardArrayQuickMovedTo : ^[dynamic]^Card
lastCardArrayQuickMovedToIndex : int

// lastCardArrayQuickMovedToType : CARD_ARRAY_TYPE

firstQuickMoveInCycle := false

// debug_NoPutdownProcs := true
debug_NoPutdownProcs := false

quickMoveCompare :: proc(card_array : ^[dynamic]^Card, type : CARD_ARRAY_TYPE)->bool{
    //test-> no compare, just replace
    // return true

    if firstQuickMoveInCycle{
        
        //foundation gets priority, but disregard if you either just moved to one last turn, or if we already found
        //a foundation to move to this turn 
        if  type == .FOUNDATION && 
            
            quickMoveStartingCardArrayType != .FOUNDATION &&
            currentBestQuickMoveCardArrayType != .FOUNDATION
        {
                return true
        } 

        //tableau
        if  type == .TABLEAU &&

            currentBestQuickMoveCardArrayType != .FOUNDATION && 

            currentBestQuickMoveCardArrayType != .TABLEAU
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
        
        //Not first move in cycle -> now we just want a simple move through the card arrays in draw order
        //EXCEPT we start where ever the quickmove starts. SO all you have to do is just grab the
        //next valid array, since quickMoveCompare will be called in that draw order (and only for valid arrays)
        //-> STILL want to treat foundatiosn/ free cells collectively though
        if currentBestQuickMoveCardArray == nil {
            return (type == .FOUNDATION && quickMoveStartingCardArrayType != .FOUNDATION) || (type == .FREECELL && quickMoveStartingCardArrayType != .FREECELL) || type == .TABLEAU 
        }
    }

    return false
}

initGame :: proc(){
    gameState = .GAME_NEW
    initDeck()
}

updateGame :: proc(dt: f32){

    //input
    //

    keyboardState := SDL.GetKeyboardState(nil)

    if keyboardState[SDL.SCANCODE_R] == 1 && !keysProcessed[SDL.SCANCODE_R]{
        // fmt.println("r pressed")
        gameState = .GAME_NEW
        keysProcessed[SDL.SCANCODE_R] = true
    }

    if keyboardState[SDL.SCANCODE_W] == 1 && !keysProcessed[SDL.SCANCODE_W]{
        // fmt.println("r pressed")
        debugAutoWin()
        keysProcessed[SDL.SCANCODE_W] = true
    }




    
    if  (keyboardState[SDL.SCANCODE_LCTRL] == 1 || keyboardState[SDL.SCANCODE_RCTRL] == 1) && keyboardState[SDL.SCANCODE_Z] == 1 && !keysProcessed[SDL.SCANCODE_Z]{
        
        if keyboardState[SDL.SCANCODE_LSHIFT] == 1 || keyboardState[SDL.SCANCODE_RSHIFT] == 1{
            fmt.println("ctrl + shift + z pressed, redoing!")
            // redo()

        }else{
            fmt.println("ctrl + z pressed, undoing!")
            // undo()
        }


        keysProcessed[SDL.SCANCODE_Z] = true
    }

    


    //GAME STATE based updates
    //

    if gameState == .GAME_NEW{

        pp_clearFramebuffer = true
        clearCards()
        // shuffleDeck()
        quickMoveState = .NOT_DOING

        gameState = .GAME_DEAL
        
        //dumb, but you have to reset the statics in the deal proc for 
        //each new game, otherwise they retain their values. So 2nd arg is
        //whether or not to reset. In theory, if dt >= 52 * cardDealInterval,
        //you might deal all the cards in one deal() call, so do the check to 
        //see if you need to switch to GAME_PLAYING

        if deal(dt, true, mouseDownEventThisFrameL) do gameState = .GAME_PLAYING
    
    }else if gameState == .GAME_DEAL{


        if deal(dt, false, mouseDownEventThisFrameL) do gameState = .GAME_PLAYING
        
        /*
        debugDealWin()
        gameState = .GAME_PLAYING
        */
    }

    if gameState == .GAME_PLAYING{
        if checkForWin(){
            //all cards are now in foundations, but you have to wait for them to all be there visually.
            //-> when you enter win mode, all drawCardArray in renderGame are skipped so nothing but the fake
            //card/winning text/whatever is beind drawn for the win animation.

            //so everything has to be in place before you actually enter 'win mode'

            enterWinMode := true
            //assume you already have all 52 cards in the foundations, 13 each 
            for card in deck{
                fmt.println("card:", card)
                if getCardIsVisual(card){
                    enterWinMode = false
                    break
                }
            }
            
            if enterWinMode{
                gameState = .GAME_WIN
                doWinningAnimation(dt, true)
            }

            //same thing as deal proc, I like the statics but calling these twice
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


    //similarly to the visual card updating, this should happen regardless of whether or not
    //you want to draw the hand on a particular frame. I guess you could put these back in the
    //render function, but either way they should be in a separate loop
    if handCardArray != nil{
        for i in handCardArrayIndex..<len(handCardArray^){
            //update the visual start positions here, because when you drop the hand, 
            //you want the cards to go from hand position to new target.
            handCardArray[i].visStartPosX, handCardArray[i].visStartPosY = getHandCardPosition(i-handCardArrayIndex)
        }
    }

    //update visual card timer
    //!!!moved this from the visCard loop in render game, because I was playing
    //around with turning on/off rendering certain arrays, if you turn off the visual card 
    //drawing, and the dt update is in there, then cards can get frozen. Not as nice as just
    //having it update in render game, but it should be here so that no matter what's being drawn, 
    //visual cards are getting updated.
    for &visCard in visualCardArray{
        // fmt.println("visCard:",visCard)
        visCard.visTimeSeconds += dt
    }
    clear(&visualCardArray)
    //!!!WATCH -> now that there's two spots where you loop over vis card, need to make sure you clear at the appropriate time.
    //right now this is here, since visCards get added in render game. 





    //RENDERING game
    //

    //todo: gl.Viewport is leftover from the SDL2 demo, apparently isn't super
    //necessary for an app with only 1 viewport (vs. ex. blender, which has multiple views on screen at
    //the same time), but not having it causes issues on some devices. Leaving for now, but should
    //determine exactly what it does and if it's necessary.

    gl.Viewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
    renderGame()
    
    //actually do the quick move, now that all the card arrays have been checked 
    if quickMoveState == .DOING{
        if currentBestQuickMoveCardArray != nil{
            fmt.println("QUICK MOVING CARDS!!! to card array:", currentBestQuickMoveCardArray)

            lastCardArrayQuickMovedToIndex = len(currentBestQuickMoveCardArray)
            //have to get this before actually moving

            moveCards(handCardArray, currentBestQuickMoveCardArray, handCardArrayIndex)

            lastCardArrayQuickMovedTo = currentBestQuickMoveCardArray
            // lastCardArrayQuickMovedToType = currentBestQuickMoveCardArrayType
            
            firstQuickMoveInCycle = false
        }
        //either way, we're done the quick move (if cards weren't quickmoved because there was no available spot, 
        //now that quick move is set to .NOT_DOING, the hand card array drop will happen.
        quickMoveState = .NOT_DOING 
    }

    if doingManualPutdown{
        //!!! could do a nil check for currentClosestDistanceManualPutdownCardArray, but it should 
        //always be set if doingManPutdown = true -> the whole point of having an extra doing flag
        //is to avoid doing distance = 1000000 as a way of setting it to nil (You compare against existing
        //distance to determine the closest array, so you have to set it to a giant number, OR do this, and
        //have a flag to tell you this is the first one, just set the best distance to it to start.
        moveCards(handCardArray, currentClosestDistanceManualPutdownCardArray, handCardArrayIndex)
    }

    doingManualPutdown = false
    currentClosestDistanceManualPutdownCardArray = nil


    //after rendering game (doing collision checks for all putdowns), IF the hand hasn't been
    //putdown into an array, and the mouse has been release/etc, then drop it. 
    //(UNLESS you are doing a quick move, in which case you don't want to drop it yet, 
    //as you may still need to check some arrays next frame
    //-> originally just had this in render game, and it fits in either place, but the code flow is
    //easier to see if it's here in updateGame()
    if handCardArray != nil && quickMoveState == .NOT_DOING && (mouseIsDownR || mouseUpEventThisFrameL){
        
        dropHand()
    }

    

}


renderGame :: proc(){
    //goes through everything that needs to be drawn and draws it.

    beginRenderPostProcessor()
    
    if gameState != .GAME_WIN{
        // drawRect(getTexture("uv_map"), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0.0, glm.vec3(0.5))
        drawBg(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        

        //foundations
        for i in 0..<len(foundations){
            
            posX := foundationsOffsetX + (cast(int)card_size.x + foundationdsAndCellsSpacingX) * i
            posY := foundationdsAndCellsOffestY
            
            drawCardArray(&foundations[i], posX, posY, 0, .FOUNDATION)
        }
        
        //tableau (columns)
        for i in 0..<len(columns){

            posX := tableauOffsetX + ((cast(int)card_size.x + tableauSpacingX) * i)
            posY := tableauOffsetY
            
            drawCardArray(&columns[i], posX, posY, defaultCardSpacingY, .TABLEAU)
        }

        //free cells
        for i in 0..<len(freecells){
            // fmt.println("len(handCardArray) - handCardArrayIndex ", len(handCardArray) - handCardArrayIndex )
            drawCardArray(&freecells[i], freecellsOffsetX + (cast(int)card_size.x + foundationdsAndCellsSpacingX) * i,  foundationdsAndCellsOffestY, 0, .FREECELL)
        }
        

        //draw hand after everything

        if handCardArray != nil{
            for i in handCardArrayIndex..<len(handCardArray^){

                hcx, hcy := getHandCardPosition(i-handCardArrayIndex)
                
                //update the visual start positions here, because when you drop the hand, 
                //you want the cards to go from hand position to new target.
                handCardArray[i].visStartPosX = hcx
                handCardArray[i].visStartPosY = hcy
                
                //turn the hand blue for testing
                // drawRect(cardTextures[handCardArray[i].suit][handCardArray[i].rank], hcx, hcy, cast(int)card_size.x, cast(int)card_size.y, 0, glm.vec3{0.0,1.0,1.0})
                drawRect(cardTextures[handCardArray[i].suit][handCardArray[i].rank], hcx, hcy, cast(int)card_size.x, cast(int)card_size.y, 0)

            }
        }        
            
        //visual cards
        //draw visual cards over top of other cards -> need to queue them in the drawCardArray calls, then draw them all after here, since if you draw them at the same time as normal cols,
        //they will be drawn behind normal cols that get drawn after. eg if card is visually moving from tableau 6 to 1 (meaning it's internally in col 1),
        //and you draw it in normal order (at the same time as the rest of col 1), then it will appear behind cols 2 to 6, since they get drawn after col 1
        for &visCard in visualCardArray{
                
            // fmt.println("drawing vis card:", visCard)
            //!!! was accidently printing out the whole vis card array here instead of vis card, which caused slowdown on deal where you wouldn't
            //see the cards move properly (good to know, although probably won't intentionally ever want to print 52x52=2704 card structs on the same frame...)

            t := 1 - glm.pow(1 - (visCard.visTimeSeconds/visualMoveTimeSeconds), 3)

            visPosX := glm.lerp(cast(f32)visCard.visStartPosX, cast(f32)visCard.visTargetPosX, t)
            visPosY := glm.lerp(cast(f32)visCard.visStartPosY, cast(f32)visCard.visTargetPosY, t)


            drawRect(cardTextures[visCard.suit][visCard.rank], cast(int)visPosX, cast(int)visPosY, cast(int)card_size.x, cast(int)card_size.y, 0)

        }

    }else{
        //this needs to be here (btw start/end pp) in order to get the non-cleared pp effect

        // drawRect(cardTextures[fakeCard.suit][fakeCard.rank], cast(int)fakeCard.visTargetPosX, cast(int)fakeCard.visTargetPosY, cast(int)card_size.x, cast(int)card_size.y, 0)
        drawRect(cardTextures[fakeCard.suit][fakeCard.rank], fakeCard.visTargetPosX, fakeCard.visTargetPosY, cast(int)card_size.x, cast(int)card_size.y, 0)
        
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

        
    
    if gameState == .GAME_WIN{
        renderText("YOU WIN!!!", WINDOW_WIDTH/2 - 150, WINDOW_HEIGHT/2 - 50, 1, glm.vec3((glm.cos(f32(SDL.GetTicks())*3 / 1000.0) + 1)/2))
    }
    

}//renderGame





drawCardArray :: proc(card_array : ^[dynamic]^Card, pos_x, pos_y, cardSpacingY: int, card_array_type: CARD_ARRAY_TYPE){

    cardArrayIsHand := handCardArray == card_array

    endingIndexInclusive := cardArrayIsHand ? handCardArrayIndex -1 : len(card_array)-1

    if cardArrayIsHand && quickMoveState == .LOOKING{
        //done looping though all the draw card arrays (back at the one where the quick move started), now set the state so that 
        //you can actually move the cards in updateGame after all the rendering is done. 
        fmt.println("finished quick move looking")
        quickMoveState = .DOING
    }


    selectedCardIndex := -1
    selectedCardPosY := -1

    // if !(-1 <= endingIndexInclusive){
    //     panic(fmt.tprint("somethings wrong with drawCardArray: endingIndexInclusive, selectedCardIndex", endingIndexInclusive, selectedCardIndex))
    // }

    // fmt.println("card array:", card_array)
    //start at -1 to account for the empty cell. A little sloppy, but before I had an extra check up here for empty putdown that was copy pasted from
    //the below check putdown check for top  card in col. It worked okay, but I'm currently adding in more checks for doing quick moves, and I want everything
    //to go through one path.
    for i := -1; i <= endingIndexInclusive; i+=1{
        ///!!!don't do a range here since, when dropping cards, want to then draw the cards that have just
        //been dropped on the same frame (on drop, the endingIndexInclusive gets set to the new len of card_array
        //and if the cards is a hand, you don't drop the cards here anyways)

        card := i < 0 ? nil : card_array[i]

        if card != nil && mouseDownEventThisFrameL{
            /*
                cancel visual move if mouse is down. Do this up here, so below you can click on a card that just got un-visualed this frame.
                this facilitates doing quick moves, since on the first click in the double click, the card turns visual, even if the start/target positions
                are super close or the same. I was having an issue where you couldn't quick move because you'd click the card, it'd turn visual, then you'd click
                again and you wouldn't be able to click it because it was technically moving)
                ->this also fixes the issue where you could click on cards behind ones that were moving eg black ace on red 2, you'd click on the ace, it would turn visual, then
                you'd click on the black ace again, but you'd pick up the 2 and the ace because the ace was moving, so it wasn't doing collision checks. Now if you tried to do this,
                the ace snaps back in it's target pos and is picked up again.
                ->note: In my old c++ solitaire I'm basing this on, I had a bunch of global flags for stuff like this, but I'm finding as I do this again that there are much simpler
                solutions that feel cleaner and don't require you to jump around in the code as much.
            */
            
            card.visJustStartedMoveSetVisuals = false
            card.visTimeSeconds = visualMoveTimeSeconds
        }

        //draw card
        cardPosY := pos_y + cardSpacingY * max(0,i)

        if card == nil || !getCardIsVisual(card^){
            //only draw/do collision checks/etc if card is non visual

            // fmt.println("drawing card")
            if card == nil{
                drawRect(getTexture(cardArrayTypeToEmptyTexture[card_array_type]), pos_x, pos_y, cast(int)card_size.x, cast(int)card_size.y, 0)
            }else{
                drawRect(cardTextures[card.suit][card.rank], pos_x, cardPosY,  cast(int)card_size.x, cast(int)card_size.y, 0)
            }

            //check for PICKUP
            //added gamestate check currently to prevent picking up while dealing.
            if gameState == .GAME_PLAYING && quickMoveState == .NOT_DOING && card != nil && mouseDownEventThisFrameL && checkCollisionPoint(pos_x, cardPosY, cast(int)card_size.x, cast(int)card_size.y, int(mousePosX), int(mousePosY)){
                //!!! added  quickMoveState == .NOT_DOING as a precaution: even if it's unlikely, want to make sure you can't pickup anything during a quick move
                //(since a quickmove takes place over 2 frames)
                
                selectedCardIndex = i
                selectedCardPosY = cardPosY
                //by replacing selectedCardIndex every time, you end up with the topmost card
                //same idea for cardPosY
      
            }

            //check for PUTDOWN
            //note: here I only check against the topmost card in the array, but some solitaire programs do collisions against all cards in the array
            //(you can put your hand into a tableu by dropping it on any card in the tableau, not just the top one)
            if (i == endingIndexInclusive) && handCardArray != nil && handCardArray != card_array && (mouseUpEventThisFrameL || quickMoveState == .LOOKING){
            // if (i == endingIndexInclusive) && handCardArray != nil && handCardArray != card_array && (mouseUpEventThisFrameL){
                
            
            hcx, hcy := getHandCardPosition(0)
            overlapping := quickMoveState == .NOT_DOING && checkCollisionRect(pos_x, cardPosY, cast(int)card_size.x, cast(int)card_size.y, hcx, hcy, cast(int)card_size.x, cast(int)card_size.y)
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
          
            //card is moving visually

            if card.visJustStartedMoveSetVisuals{
                
                // fmt.println("starting visuals for card:", card_array[i])

                //start visual move for cards in hand
                //!!!the start position is set every frame when drawing the hand, so it doesn't 
                //have to be recalculated here.
                //!!!COULD do a loop in the spot above where moveCards() is actually called, and just do this for every card in the hand,
                //but since you're going to iterate over every added card anyways, figured I put this down here and add a flag (since you 
                //only want to start the visuals on the same frame as you move the cards.

                card.visTimeSeconds = 0

                card.visTargetPosX = pos_x
                card.visTargetPosY = cardPosY 

                //unset the flag
                card.visJustStartedMoveSetVisuals = false
            }
            // fmt.println("!!!")

            //card's vis time is above 0
            append(&visualCardArray, card)
        }
            
    }//for each card

    // fmt.println("max cards, alt & desc :", getMaxMovableCards(), getIsAltAndDesc(card_array, selectedCardIndex))
    //!!!have to use card_array here for checks, NOT handCardArray, since you don't actually have cards in the hand yet

    if selectedCardIndex != -1 && len(card_array) - selectedCardIndex <= getMaxMovableCards() && getIsAltAndDesc(card_array, selectedCardIndex){

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

                doubleClickTimerSeconds = doubleClickTimerResetTimeSeconds;
                //I don't have a "stop checking for double click timer" bool/flag, so to make sure you cancel doing any other potential quick moving stuff,
                //set the timer to the max (which means your done with the double clicking, now do the quick move)

                if !(lastCardArrayQuickMovedTo == card_array && lastCardArrayQuickMovedToIndex == handCardArrayIndex){
                // if !(lastCardArrayQuickMovedTo == card_array){

                    firstQuickMoveInCycle = true
                }

            }else{
                //save card_array. If you click the same card array with the same card index before the quick move timer is up,
                //do a quick move.
                // fmt.println("doubleClickTimerSeconds , doubleClickTimerResetTimeSeconds", doubleClickTimerSeconds, doubleClickTimerResetTimeSeconds)
                fmt.println("quick move primed - timer set to 0")
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
        suitsAreAlternating := false
        
        if handCardArray[handCardArrayIndex].suit == cast(int)SUITS.CLUBS || handCardArray[handCardArrayIndex].suit == cast(int)SUITS.SPADES{
            fmt.printfln("hand is black")
            suitsAreAlternating = card_array[len(card_array)-1].suit == cast(int)SUITS.DIAMONDS || card_array[len(card_array)-1].suit == cast(int)SUITS.HEARTS 
        }else{
            fmt.printfln("hand is red")
            
            suitsAreAlternating = card_array[len(card_array)-1].suit == cast(int)SUITS.CLUBS || card_array[len(card_array)-1].suit == cast(int)SUITS.SPADES
        }
        
        return suitsAreAlternating && handCardArray[handCardArrayIndex].rank == currentRank - 1 
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



getHandCardPosition :: proc(i:int) -> (x, y: int){
    //helper, since currently you need this to 1) draw out hand cards, and 2, to get the position of the bottom
    //card to do collision detection (currently I do collision checks for each card array as they're drawn, against 
    //the hand card.

    //!!! i is the index relative to the handCardArrayIndex. -> eg if handCardArrayIndex == 6, then i == 0
    //gets you the position of the 6 + i == 6 + 0 == 6th card


    return cast(int)mousePosX + handCardOffsetX, (cast(int)mousePosY + defaultCardSpacingY * (i)) + handCardOffsetY
}




moveCards :: proc(from, to : ^[dynamic]^Card, fromStartingIndex:int){
    
    for &card in  handCardArray[handCardArrayIndex:]{
        card.visJustStartedMoveSetVisuals = true
    }

    append(to, ..from[fromStartingIndex:])
    remove_range(from, fromStartingIndex, len(from))

    handCardArray = nil
    handCardArrayIndex = -1

}

dropHand :: proc(){
    fmt.println("in dropping hand")


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
        suitsAreAlternating := false
                    
        if card_array[i].suit == cast(int)SUITS.CLUBS || card_array[i].suit == cast(int)SUITS.SPADES{
            suitsAreAlternating = card_array[i+1].suit == cast(int)SUITS.DIAMONDS || card_array[i+1].suit == cast(int)SUITS.HEARTS 
        }else{
            suitsAreAlternating = card_array[i+1].suit == cast(int)SUITS.CLUBS || card_array[i+1].suit == cast(int)SUITS.SPADES 
        }

        if !suitsAreAlternating do return false
    }

    return true
}

initDeck :: proc(){
    
    for i in 0..<len(deck){
        deck[i].id = i 
        deck[i].suit = i%4
        deck[i].rank = (len(deck)-i -1)/4
    }

}

shuffleDeck :: proc(){
    rand.shuffle(deck[:])
    // shuffle takes in a slice, [:] gives you a slice (see overview)

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

    for dt >= dealIntervalSeconds || dealEverythingImmediately {
        
        
        append(&columns[col], &deck[cardsDealt])
        
        // fmt.println("dealing card:", &deck[cardsDealt])

        columns[col][len(columns[col])-1].visStartPosX = int(-card_size.x)
        columns[col][len(columns[col])-1].visStartPosY = int(-card_size.y)
        columns[col][len(columns[col])-1].visTimeSeconds = visualMoveTimeSeconds

        columns[col][len(columns[col])-1].visJustStartedMoveSetVisuals = true

        cardsDealt +=1
        if cardsDealt == len(deck) do return true
        //!!!I thought of resetting the statics here, when you're done dealing, the issue though
        //is if you hit r in the middle of a deal, there's no way for the function to know,
        //so eg you start dealing on col 5 because you didn't actually finish the previous deal.
        //could prevent redealing in the middle of a deal, but I like doing that and I'm sure there 
        //are other scenarios where this would be an issue.
        
        // col = col + 1 >= len(columns) -1 ? 0 : col + 1//leave one col blank for testing
        col = col + 1 >= len(columns) ? 0 : col + 1
        dt -= dealIntervalSeconds

    }

    leftoverDt = dt

    return false
}

debugDealWin :: proc(){
    //deals all the cards in the foundations to test 'winning'
    
    initDeck()

    for i in 0..<len(deck){
        
        f := i%4
        append(&foundations[f], &deck[i])

        foundations[f][len(foundations[f])-1].visJustStartedMoveSetVisuals = true
        foundations[f][len(foundations[f])-1].visStartPosX = int(-card_size.x)
        foundations[f][len(foundations[f])-1].visStartPosY = int(-card_size.y)
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
    delete(visualCardArray)
}

drawCardsTest :: proc(){

         // //test drawing cards
        /*
        //actual card png size = 500x726

        // for suit in 0..<len(cardTextures){
        //     for rank in 0..<len(cardTextures[suit]){
        //         // fmt.println("suit, rank:", suit, rank)
        //         drawSprite(cardTextures[suit][rank], glm.vec2{f32(rank), f32(suit)} * card_size,card_size, 0, glm.vec3(1.0))
        //     }
        // }

        // cardCount := 0
        // for card in deck{
        //     drawSprite(cardTextures[card.suit][card.rank], glm.vec2{f32(cardCount % 13), f32(cardCount % 4)} * card_size,card_size, 0, glm.vec3(1.0))
        //     cardCount += 1
        // }
        */
}



doWinningAnimation :: proc(dt : f32, newWin : bool ){
    // fmt.println("in do Winning Animation!!!")

    @(static) testPosX := 0

    drawRect(getTexture("uv_map"), testPosX, 100, 100, 100, 0, glm.vec3{1.0, 0.0, 0.0})
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
        }


        fakeCardPositionInBounds := checkCollisionRect(fakeCard.visTargetPosX, fakeCard.visTargetPosY, cast(int)card_size.x, cast(int)card_size.y, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        
        if fakeCardPositionInBounds{
            // fmt.println("fake card in bounds, moving")
            
            fakeCard.visTargetPosX += int(fakeVelocityX * dt)
            ///!!! since this is cast to int, need to make sure velocity is high enough so that v *dt >1, otherwise it will round to 0 when
            //casting and there's no movement

            fakeVelocityY += fakeAccY * dt

            fakeCard.visTargetPosY += int(fakeVelocityY * dt) 

            if fakeCard.visTargetPosY > WINDOW_HEIGHT - cast(int)card_size.y {
                fakeCard.visTargetPosY = WINDOW_HEIGHT - cast(int)card_size.y
                fakeVelocityY *= rand.float32_range(-.8,-.7)
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
    clearCards()
    gameState = .GAME_PLAYING
    debugDealWin()
}