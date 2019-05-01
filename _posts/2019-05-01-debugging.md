---
layout: post
title:  "Fight the bug, not the tools"
date: 2019-05-01T16:27:33.622298
categories: debugging 
tags: debugging
permalink: /fight-the-bug-not-the-tools
---

> This is the way the world ends, not with a bang, but a whimper.

The anticlimactic end T.S. Eliot describes with this line from The Hollow Men can ring just as true in the world of
debugging as the world of man and war.  Have you ever had a bug that haunted you and wreaked havoc for months, only to
be discovered as a simple and (retrospectively) obvious mistake?  If the bug was so simple, to what do you owe those
feelings of dread and the attrition of willpower towards the problem?  Why was the solution so anticlimactic compared to
the effort?

[Linus's Law](https://en.wikipedia.org/wiki/Linus%27s_Law) states that "given enough eyeballs, all bugs are shallow."
Usually this is taken to mean that when software is made open and available, like in the open source community, the
sheer number of developers and users probing for problems can expose the causes of deep problems quickly.  I propose an
alternative interpretation: debugging tools give us "eyeballs" into software that drastically simplify cognitive load
required to think about the bug.

It is from this interpretation that I aim to convince you that the anguish caused by your toughest bugs is not caused
by the bug itself, but by the frustration of not having the appropriate debugging tools.

Remember when you were a new developer and all you had in your debugging toolbox were print statements?  Easy bugs were
hard, and hard bugs were impossible.  When you learned to use a simple debugger, easy bugs became easy, and hard bugs
became more manageable.  When you learned to write tests, you learned the value of building a virtual "scaffolding"
around the requirements of your code, and should your amorphous code break through this scaffolding, you were likely to
detect it, and at the very least reproduce the conditions causing the breach.  This too is a form of a debugging tool.

Time-travelling debuggers like [rr](<https://en.wikipedia.org/wiki/Rr_(debugging>) further expand on this tooling by
creating deterministic execution traces of your software, allowing you to set breakpoints both forwards and backwards(!)
in time.  This lets you interactively walk forwards and backwards down any and all execution paths your program took,
without restarting.  Now you can think more creatively about bugs and test hypotheses in real time, without the
cognitive load of needing to remember the states of your program at different points in time.

Tools like [TLA+](https://learntla.com/introduction/) can help you formally model complex algorithms, including ones
involving concurrent systems, so that hopefully you discover the bugs before they become written into your production
code.

Many bugs are hard because you lack the number of eyeballs (or views) into the states of the system to adequately see
the evolution of those states.  The right debugging tools give you those views and reduce your cognitive load.  The next
time you begin to feel the anguish of a debugging session, stop and ask yourself: "Am I fighting the bug or am I
fighting my tools?"
