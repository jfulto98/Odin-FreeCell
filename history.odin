package freecell

import "core:fmt"
import "core:container/queue"



HistoryItem :: struct{
    // cardArrayData : [dynamic]^Card,
    cardArrayData : [NUM_CARDS_IN_DECK]^Card,
    cardArrayPointer : ^[dynamic]^Card
}

History :: struct{
    undoQueue : queue.Queue(HistoryItem),
    redoQueue : queue.Queue(HistoryItem)
}

history : History

HISTORY_QUEUE_LEN :: 10

initHistory :: proc(){

    queue.reserve(&history.undoQueue, HISTORY_QUEUE_LEN) 
    queue.reserve(&history.redoQueue, HISTORY_QUEUE_LEN) 

}

deinitHistory :: proc(){

    queue.destroy(&history.undoQueue) 
    queue.destroy(&history.redoQueue) 
}

resetHistory :: proc(){
    fmt.println("resetting history!!")
    queue.clear(&history.undoQueue) 
    queue.clear(&history.redoQueue) 

}


savePoint :: proc(cardArrayPointer : ^[dynamic]^Card){
    //push, and then clear the redo queue

    fmt.println("in savePoint proc")

    pushState(cardArrayPointer, &history.undoQueue)

    queue.clear(&history.redoQueue)

}

pushState :: proc(cardArrayPointer : ^[dynamic]^Card, q : ^queue.Queue(HistoryItem)){

    i := 0
    item := HistoryItem{}
    item.cardArrayPointer = cardArrayPointer

    for cardPointer in cardArrayPointer{
        if cardPointer == nil || i > len(item.cardArrayData){
            break;
        }
        fmt.println("card pointer in save:", cardPointer)
        item.cardArrayData[i] = cardPointer
        i += 1
    }   

    queue.push_back(q, item)    

}

undo :: proc(){
    
    // fmt.println("in undo proc")

    //hack-> right now do it twice, since there are 2 saves for each card move,
    //and the only thing being saved is card moves. In a more complex game, you'd
    //need to have some way of combining an arbitrary amount of save points together.
    for i in 0..<2{
        if queue.len(history.undoQueue) <= 0{
            fmt.println("undoQueue is empty!!")
            break
        }else{

            undoItem := queue.pop_back(&history.undoQueue)
            

            fmt.println("undo item:", undoItem)

            //first, push current state onto redo queue
            pushState(undoItem.cardArrayPointer, &history.redoQueue)

            //then undo
            clear(undoItem.cardArrayPointer)

            for i in 0..<len(undoItem.cardArrayData){
                fmt.println("appending from undo item:", undoItem.cardArrayData[i])
                
                //dom't want to append nil values (currently assuming any nil values are just empty spaces at the end of the len-52 array)
                //could include the number of actual cards in HistoryItem to be thorough, but this is enough
                //currently need this since nil is interpretted as the empty card cell in the drawCardArray proc in game.odin
                //!!!was getting an error where I guess I was drawing a bunch of empty cells ontop of the card arrays that were undone.
                if undoItem.cardArrayData[i] == nil do break

                append(undoItem.cardArrayPointer, undoItem.cardArrayData[i])
            }

            // undoItem.cardArrayPointer = undoItem.cardArrayData
        }
    }
}

redo :: proc(){
    
    fmt.println("in redo proc")

    for i in 0..<2{
        if queue.len(history.redoQueue) <= 0{
            fmt.println("redoQueue is empty!!")
            break
        }else{

            redoItem := queue.pop_back(&history.redoQueue)
            
            //first, push current state onto undo queue
            pushState(redoItem.cardArrayPointer, &history.undoQueue)

            //then redo
            clear(redoItem.cardArrayPointer)

            for i in 0..<len(redoItem.cardArrayData){
                
                if redoItem.cardArrayData[i] == nil do break

                append(redoItem.cardArrayPointer, redoItem.cardArrayData[i])
            }

        }
    }
}








//Attempt at doing the command pattern without OOP
//I think this could be done (didn't get it working), but it would be annoying and I wanted to try doing the stateful method.
//-> the one benefit command pattern provides for solitaire is that you can actually see the cards moving back.
//with the above approach cards instantly move when you undo/redo.
//In most other games/places where you'd want an undo system, this isn't desirable/doesn't make sense (eg in a sokoban, 
//you don't really want to walk in the opposite direction is you undo a move), but in solitaire you might want that.

// Undo_Item :: 

// CommandType :: enum{
//     Move_Cards,
//     Test_Print
// }

// CommandPointer :: struct{
//     rpointer : rawptr,
//     commandType : CommandType
// }

// CommandMoveCards :: struct{
    
//     oldArray, newArray : ^[dynamic]Card, 
//     oldArrayStartingIndex:int

// }

// CommandTestPrint :: struct{
//     doText, undoText : string
// }

// undoStack : queue.Queue(^CommandPointer)
// redoStack : queue.Queue(^CommandPointer)


// initHistory :: proc(){

//     queue.init(&undoStack)
//     queue.init(&redoStack)


// }

// undo :: proc(){
//     fmt.println("in undo!!!")

//     if queue.len(undoStack) > 0{
//         cmd_ptr := queue.pop_back(&undoStack)
//         //todo: there's also pop_back_safe with elem, ok
//         fmt.println("cmd_ptr:", cmd_ptr)


//         switch cmd_ptr.commandType{
//             case .Move_Cards:
//                 fmt.println("undoing a move cards command!!!")

//             case .Test_Print:
//                 fmt.println("command pointer type is .TestPrint, calling testPrintUndo!!!")
                
//                 testPrintUndo(cast(^CommandTestPrint)cmd_ptr.rpointer)
//         }

//         queue.push_back(&redoStack, cmd_ptr)
//     }else{
//         fmt.println("undo queue is empty!!!")

//     }
// }

// execute :: proc(cmd : ^CommandPointer){
//     switch cmd.commandType{
//         case .Move_Cards:
//             fmt.println("executing a move cards command!!!")

//         case .Test_Print:
//             testPrintExecute(cast(^CommandTestPrint)cmd.rpointer)

//     }
    
//     queue.push_back(&undoStack, cmd)
// }


// redo :: proc(){
//     fmt.println("in redo!!!")

//     command := queue.pop_back(&redoStack)
    
//     execute(command)

//     queue.push_back(&redoStack, command)
// }


// clearHistory :: proc(){

    
// }


// //PROCS FOR EACH COMMAND

// //move cards

// moveCardsExecute :: proc(cmd : ^CommandMoveCards){
//     append(cmd.newArray, ..cmd.oldArray[cmd.oldArrayStartingIndex:])
//     remove_range(cmd.oldArray, cmd.oldArrayStartingIndex, len(cmd.oldArray))
// }

// moveCardsUndo :: proc(cmd : ^CommandMoveCards){
//     append(cmd.oldArray, ..cmd.newArray[cmd.oldArrayStartingIndex:])
//     remove_range(cmd.newArray, cmd.oldArrayStartingIndex, len(cmd.oldArray))
// }

// //test print

// createAndExecuteTestPrintCommand :: proc(doStr, undoStr : string){
//     cmd := CommandTestPrint{doStr, undoStr}

//     cmd_ptr := CommandPointer{rawptr(&cmd), CommandType.Test_Print}
//     fmt.println("cmd_ptr:", cmd_ptr)

//     execute(&cmd_ptr)

// }

// testPrintExecute :: proc(cmd : ^ CommandTestPrint){
//     fmt.println("in test print execute!!!, cmd.doText: ", cmd.doText)
// }

// testPrintUndo :: proc(cmd : ^ CommandTestPrint){
//     fmt.println("in test print undo!!! cmd.undoText:", cmd.undoText)
// }