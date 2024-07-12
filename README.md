A FreeCell game written in Odin, based on a C++ version I made last year. 
This project is currently 90% done, the last major thing I want to add is an undo/redo system, and
then do some minor bug fixes. 


___________________________________________________________________________________________________



Dev Notes:
I had an unfinished C++ FreeCell variant that I made last year that I've wanted to finish. Last month I figured I should
go finish it. I hadn't done much C++ since, and I had just read this article about game developement using Odin 
(https://blog.massimogauthier.com/p/game-engine-dev-explained-for-non-c31), and I though I would try Odin out.
As an initial test, I went through and did the breakout tutorial from learnopengl.com in Odin in a week.

I don't feel I have enough experience in C++ where I can really speak to how much better/worse Odin is in comparison, and my
assessment is being influenced by having a fresh start doing something new, but at least on the surface level, using
Odin is much nicer, both for getting stuff working, and in terms of learning. So I went forward with using Odin for the FreeCell 
variant.

Instead of doing the whole variant at first though, I figured I should just get a basic FreeCell game working first, then extend it.
So that's what this is. The game takes an IMGUI approach based on a few tutorials/videos I saw back when I made the C++ version. I don't 
know how well the game actually adheres to IMGUI principles, but for the most part I'm happy with the code structure and everything functions well. 

It started to fall apart a little when I put in double-click quick moving, since that involves storing a lot of state. 
(I had quick moving in the original variant, but due to the different ruleset it was much simpler than what you need for normal FreeCell)
It took me a couple tries to find something that worked, and it does work, but you'd probably want to have more organization
for an actual serious project. (ex. there's a few cases of ^[dynamic]^Card and index:int pairs that could be a struct)

There's a ton of comments in the source code. This was more just a way of note-taking/working through problems, than it is
for actually explaining the code, although admittedly it could also be indicative of the code being too tangled on it's own. I might go through after 
and make a cleaned up version with fewer/revised comments that's easier to navigate for other people. (I should note 
though, I did the same over-commenting for the C++ version, and it saved me from making a few mistakes I had forgotten about.)

The game isn't super high quality, but I made some fixes that I noticed while testing out other FreeCell versions, namely the
Win10 MS FreeCell, which has the visual bug I fixed early on where cards will appear under other tableau stacks while visually interpolating
positions, and most other versions have a not-great quick-move order, where cards will jump back and forth between the same two spots.
(When you quick-move in this version, the card will go to the best spot first, and then cycle through all other valid spots until
you move it manually, or move another card. It also treats free cells and foundations each collectively, so for ex. if you try to quick-move
a card in a free cell, it won't just move to another free cell, since that's effectively like not moving)

This version decidedly does not have auto moving cards (auto moving is ex. if you have an ace showing it auto moves to a foundation), and allows you 
to move cards out of the foundations, because I like having the potential strategy of storing cards in the foundation, and then moving them out, 
even if you almost never have an opportunity to do that.

At the time of writing, the only major thing I have left to do is to implement an undo/redo system. Like I mentioned, after this
I'm planning on finishing the actual variant, which might actually be something you'd want to play. I also have one other non-solitaire
card game I would like to make using this as a base. 

I will update this file if I have any other notes when I'm done.




