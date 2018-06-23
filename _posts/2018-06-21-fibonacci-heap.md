---
layout: post
title:  "Why is it called a Fibonacci Heap?"
date: 2018-06-22T06:50:03.481262
categories: programming
tags: datastructures programming
permalink: /fibonacci-heap
---
<video width="100%" loop video autoplay>
    <source src="https://s3.amazonaws.com/amoffat.github.io/fib.mp4" type="video/mp4">
    Your browser does not support the video tag.
</video>

A fibonacci heap is one of those interesting data structures that gives you performance gains that shouldn't seem
possible.  Using a few simple rules, the fibonacci heap maintains the heap property with excellent time complexity for
its operations:

<img src="{{site.baseurl}}/assets/images/heap-complexity.png" />

But why is "fibonacci" in the name?  Where does the fibonacci sequence occur in the implementation?

To explain, I'm going to assume you have a basic familiarity with how a fibonacci heap works.  If you want a refresher,
[this is an excellent resource](https://www.cs.princeton.edu/~wayne/teaching/fibonacci-heap.pdf) to come up to speed
quickly.

# Fibonacci heap constraints

There are two constraints in a fibonacci heap that directly ensure a fibonacci sequence arises:

1. When two sub-heap trees of the same rank exist, they are merged.
2. When more than one node is removed from a sub-heap tree, the parent node is removed as well.

When these two rules are followed during the use of the heap, the result is that each sub-heap tree has a minimum number
of nodes that corresponds to a fibonacci number!

# The merge operation

As part of the extract-min operation in a fibonacci heap, the heap "cleans up" itself by merging sub-heap trees with the
same number of immediate children, called its *rank*, starting at the smallest rank first.  If two rank 0 (no children)
sub-heap trees are found in the heap, they are merged into a single rank 1 (1 child) sub-heap:

<img src="{{site.baseurl}}/assets/images/fib-r0.jpg" />

This process is repeated.  If two rank 1 sub-heaps now exist, they are merged into a single rank 2 sub-heap, etc:

<img src="{{site.baseurl}}/assets/images/fib-r1r2.jpg" />

The process of merging is *always* one of combining two same-rank sub heap trees.  **This is important to understand
where the fibonacci sequence comes from.**

Another important point to note is that when two trees are merged, the resulting tree can have more than the minimum
required number of nodes for its rank.  For example, when two rank 1 trees are merged into a rank 2 tree, there is a
node that could be deleted *without changing the rank of the tree*:

<img src="{{site.baseurl}}/assets/images/fib-prune.jpg" />

In other words, when two trees are merged, there exists a maximum number of nodes that may be removed from the resulting
tree, without removing more than one branch per parent, while preserving the tree's rank.  If we remove the extra nodes
after each merge, we can show the minimum possible node configuration for each rank:

<img src="{{site.baseurl}}/assets/images/full_fib.jpg" />

Notice anything about the final node counts?  1, 2, 3, 5, 8...  the fibonacci sequence.  But why?

# Fibonacci sequence rewritten

If you recall, a number in the fibonacci sequence is defined by the sum of the previous two numbers:


<img src="{{site.baseurl}}/assets/images/fib_equation.jpg" />

There is another way to write this that makes its relationship to the fibonacci heap more explicit:

<img src="{{site.baseurl}}/assets/images/fib_equation2.jpg" />

Now this is starting to look like our merge operation!  One way to read this is: "The number of nodes of our resulting
tree is the sum of two previous rank trees, minus the size of a minimum tree from 3 ranks ago."  This makes it clear
that a merge operation of two same-rank trees with fibonacci node counts can result in a merged tree with a fibonacci
node count, plus some potentially-prunable nodes.

But why is the prunable number of nodes equal to the size of a tree from 3 ranks ago, and why does this correspond to
cutting only the biggest branch from one of the merging trees?

The reason is because the tree being pruned is being reduced from a rank n-1 to a rank n-2 tree by the very act of
pruning it:

<img src="{{site.baseurl}}/assets/images/rank_reduction.jpg" />

And this corresponds to a difference of a rank n-3 tree:

<img src="{{site.baseurl}}/assets/images/rank_math.jpg" />

And now you know where the fibonacci sequence exists in the fibonacci heap: as a minimum valid bound for each of the
sub-heap trees.
