package freecell

import "core:fmt"
import "core:container/queue"


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