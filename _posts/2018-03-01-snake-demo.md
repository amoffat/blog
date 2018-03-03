---
layout: post
title:  "Advanced Python development in Vim+TMUX"
date: 2018-03-01T09:50:04.567394 
categories: debugging editing
tags: snake vim python tmux
permalink: /advanced-python-tmux-vim.html
---

TMUX and Vim are powerful tools in a commandline environment, but their
integration with eachother in the context of software development leaves much to
be desired.

Wouldn't it be cool if Vim was aware of the context of other TMUX panes and
could provide tools according to that content?  I'm going to show how to do that
by building an example Vim plugin that can open the file where a Python traceback
occurred.

<asciinema-player src="{{site.baseurl}}/assets/screencasts/tmux.cast?{{site.time | date: '%s%N'}}" autoplay="1" loop="1"></asciinema-player>

In the above screencast, you can see we run a contrived Python script that
raises an exception.  When we press a key sequence in Vim, our plugin analyzes
our TMUX panes for an exception, parses it, and opens a new buffer with the file
closest to the exception.

To build this plugin, we'll use [Snake.](https://github.com/amoffat/snake)
Snake is a Vim wrapper around Python that lets you write plugins in pure Python.
It lets you do things like the following:

```python
import snake
import datetime

snake.abbrev("rightnow", lambda: datetime.datetime.utcnow().strftime("%c"))
```

Now any time you type "rightnow", the Python lambda will be called which
evaluates the current datetime and expands "rightnow" to that time:

<asciinema-player src="{{site.baseurl}}/assets/screencasts/rightnow.cast?{{site.time | date: '%s%N'}}" loop="1" autoplay="1"></asciinema-player>

You can also bind keypresses to Python functions, for example, to take the word
under the cursor, look it up on thesaurus.com, and replace it with the nearest
match.  The possibilities for scripting Vim with Snake are endless.

But back to the tool we're building.  These are the steps we'll take to
accomplish our goal:

1. Interface with TMUX to read contents of panes
2. Parse the contents of a pane for an exception
3. For a given exception, determine the most recent stack frame (file and line)
4. Set up Snake a keybinding to call our exception-parsing function
5. For the most recent stack frame metadata, use Snake to load the file and go
   to the line

Let's get started!

# Interfacing with TMUX

We'll be using the excellent library [libtmux](https://github.com/tony/libtmux/)
to work programmatically with TMUX.  This will allow us to discover the TMUX
session / window / pane that contains a traceback.

First things first, lets learn how to get our current TMUX session.  We need
this session because we want to read the contents of the pane in the window of
our session.  If you're new to TMUX, think of a session as a collection of
windows managed by TMUX.  Each window itself is a collection of panes.  Each
pane is running a process (like bash, or Vim).

```python
# connects to an existing tmux server
server = tmux.Server()
```

We have a server, and on that server object, according to the docs, we can call
`server.list_sessions()`, but that is going to be flaky to find our existing
session.  Fortunately, libtmux provides an escape hatch to run raw TMUX commands
with `server.cmd`.  Some googling tells us that, in order to get the current
session name, we can run the TMUX command `display-message -p "#S"` to write our
current session name to stdout.  We can then look up the session by that
captured name:

```python
# connects to an existing tmux server
server = tmux.Server()

# evaluate the session name of our current session where we're executing
sess_name = server.cmd("display-message", "-p", "#S").stdout[0]
```

Now we can look up our session:
```python
# connects to an existing tmux server
server = tmux.Server()

# evaluate the session name of our current session where we're executing
sess_name = server.cmd("display-message", "-p", "#S").stdout[0]

# actually fetch our session
sess = server.find_where({"session_name": sess_name})
```

Now that we have our session, we want the window that we're in, since a session
can have many windows.  Fortunately, this is pretty easy:

```python
# connects to an existing tmux server
server = tmux.Server()

# evaluate the session name of our current session where we're executing
sess_name = server.cmd("display-message", "-p", "#S").stdout[0]

# actually fetch our session
sess = server.find_where({"session_name": sess_name})

# get our current window
window = sess.attached_window
```

Bingo.  So we have our current window, which contains a collection of panes.
Each pane has text content that can be read with libtmux.  So let's veer down a
different path and think about a related problem: given some string content, how
will we determine if there's an exception, and what to do about it?

# Parsing contents for an exception

Let's start by looking at a typical Python exception in the terminal.  Save this
code to `/tmp/exception.py` and run it:

```python
def b():
    raise Exception

def a():
    b()

def main():
    a()

main()
```

Running the above yields the following output:

```
Traceback (most recent call last):
  File "/tmp/exception.py", line 10, in <module>
    main()
  File "/tmp/exception.py", line 8, in main
    a()
  File "/tmp/exception.py", line 5, in a
    b()
  File "/tmp/exception.py", line 2, in b
    raise Exception
Exception
```

The format looks pretty simple here.  A traceback block begins with a
predictable string `Traceback (most recent call last):` followed by some lines.
Lines indented with two spaces are lines containing location metadata, and a
line containing no indent is the end of the traceback block.  Lines indented
with four spaces are lines we don't care about, so we'll skip those.  Sounds
simple enough, so let's write a function that can parse out the data we care
about.

We'll start by assuming our input is a list of lines from the TMUX pane.  We'll
also assume that these lines are in order with the earliest line history coming
first in the list.  With this in mind, we need to consider that there might be
many tracebacks in our lines, and we only care about the *last* traceback (since
it's the one we just ran).  So we'll iterate over the list in reversed order and
look for our traceback marker string:

```python
def find_tb(lines):
    """ given a list of lines, find the location of the last traceback
    block """
    m = "Traceback (most recent call last):"
    tb_found = None
    for idx, line in enumerate(reversed(lines)):
        if line == m:
            # we're computing our index from the non-reversed list
            tb_found = len(lines) - idx - 1
    return tb_found
```

Pretty simple.  We're looking for the last occurence of the beginning of a
traceback block and returning the line index from the line list.  Now let's
think about how we're going to parse out the stack metadata from our traceback
block.  The simplest function we can make in this area is one that takes a
traceback line and parses out the file and line number.  A trivial regular
expression can cover this:

```python
def parse_file(line):
    """ parse out filename and line metadata from a traceback line """
    m = re.search(r"File \"(.+?)\", line (\d+), in", line)
    filename = m.group(1)
    line = int(m.group(2))
    return filename, line
```

So given a line like `File "/tmp/exception.py", line 10, in <module>`, this
returns a tuple `("/tmp/exception.py", 10)`.  I believe
strongly in unit tests, but I will leave the unit test exercise to the reader!

So now we know how to parse out what we want, and we know the location of what
we want.  The next step is to stitch these two components together.  Think back
and remember that we only care about lines with two space indents.  With that in
mind, we can expand our `find_tb` function to apply `parse_file` to only those
lines:

```python
def find_tb(lines):
    """ given a list of lines, return a list of (filename, line) tuples of the
    last traceback stack """

    # find our last traceback index
    m = "Traceback (most recent call last):"
    tb_found = False
    for idx, line in enumerate(reversed(lines)):
        if line == m:
            # we're computing our index from the non-reversed list
            tb_found = len(lines) - idx - 1

    stack = None

    # if we found a traceback, iterate over the lines, starting at that block
    # index, and parse out the stack metadata from only lines starting with 2
    # spaces
    if tb_found is not False:
        stack = []
        for line in lines[tb_found+1:]:
            # we've hit the end of our traceback block
            if not line.startswith(" "):
                break

            # if this line starts with two spaces, we care about it
            m = re.match(r"\s{2}\b", line)
            if m:
                filename, line = parse_file(line)
                stack.append((filename, line))

    return stack
```

Great.  Now let's go back to our TMUX code.  The input to our `find_tb` function
is a list of lines, so let us get the pane contents to the function as a list of
lines.  Let's write a function that, given a pane, returns the contents of the
pane in the format that we want.  Reading the TMUX manpage again, it seems we
can do this with the `capture-pane` command.  We'll add the option `-p` which
prints to stdout (so we can capture it) and `-J` to join wrapped lines, so our
output is less confusing:

```python
def get_contents(pane):
    """ return the contents of a pane as a list of lines """
    lines = pane.cmd("capture-pane", "-p", "-J").stdout
    return lines
```

So far, we've implemented the ability to do the following things:

* Get our current window
* Get the contents of a pane in the window
* Parse the pane's contents for a traceback and return useful info about the
  traceback

The next step is to connect these things into a top-level function we'll call
`find_traceback()`:

```python
def find_traceback():
    # connects to an existing tmux server
    server = tmux.Server()

    # evaluate the session name of our current session where we're executing
    sess_name = server.cmd("display-message", "-p", "#S").stdout[0]

    # actually fetch our session
    sess = server.find_where({"session_name": sess_name})

    # get our current window
    window = sess.attached_window

    # for each pane in our window.panes, try to find a traceback.  stop at the
    # first traceback we find
    stack = None
    found_pane = None
    for pane in window.panes:
        lines = get_contents(pane)
        stack = find_tb(lines)
        if stack:
            found_pane = pane
            break

    return found_pane, stack
```

Excellent.  We can test it out by adding the following to the bottom of the
file:

```python
if __name__ == "__main__":
    print(find_traceback())
```

And running it:

<asciinema-player src="{{site.baseurl}}/assets/screencasts/find_traceback.cast?{{site.time | date: '%s%N'}}" loop="1" autoplay="1"></asciinema-player>

Now we have a useful function that we can connect to Snake and use
directly from Vim.

# Setting up the Vim keybinding with Snake

First, [install Snake](https://github.com/amoffat/snake#installation)

Now we'll need to take a brief detour into Snake to learn how to access the code
we just wrote from within Vim.  Basically, Vim has a plugin directory at
`~/.vim/bundle`.  We need to make our code into a module and symlink the
module's directory into the Vim plugin.

So if our code is at `~/workspace/python_debug`, and the code we just wrote
lives in `debugger.py`, we'll run this to turn it into a Python package:

```bash
$ echo "from .debugger import find_traceback" > ~/workspace/python_debug/__init__.py
```

And this to make our package available to Vim:

```bash
$ ln -sf ~/workspace/python_debug ~/.vim/bundle/python_debug
```

We'll also need to make sure our script has all of the dependencies it needs.
We know we're using libtmux, and although we have it installed in our local
virtualenv (I hope you're using virtualenvs!), Vim's Python doesn't know about
our requirements.  I'm going to wave my hands a little here and just say you
need to create a `requirements.txt` in your `python_debug` folder:

```bash
$ echo "libtmux" >> ~/workspace/python_debug/requirements.txt
```

Basically, when Snake loads your plugin, it will set up a virtualenv for you
automatically and install the contents of `requirements.txt` for you.  It's a
[little magical.](https://github.com/amoffat/snake#can-i-use-a-virtualenv-for-my-plugin)

Now we're ready to connect our code to Vim.  We'll edit our `~/.vimrc.py` file
(which is just like `~/.vimrc`, except for Python code) and add the following:

```python
import snake
import python_debug

def goto_traceback():
    pane, stack = python_debug.find_traceback()
    print(pane, stack)

@snake.when_buffer_is("python")
def python_setup(ctx):
    ctx.key_map("<leader>t", goto_traceback)
```

`snake.when_buffer_is(buftype)` is a Snake decorator that evaluates the
decorated function whenever a buffer of type `buftype` is loaded.  The decorated
function accepts a `ctx` parameter which represents the buffer, so anything we
do on that context object applies *only* to the buffer, and not to Vim globally.
This is ideal for setting up key mappings that should only exist in Python
files, but not on other files.

The line for `ctx.key_map` then binds a key sequence to our function.
`<leader>` represents the [leader key](http://learnvimscriptthehardway.stevelosh.com/chapters/06.html#leader),
which, long story short, is a user-defined prefix key to begin your own key
sequences.  Using a leader key helps keep you from stomping on Vim's builtin
sequences.  My leader key is `,`.

So now, in theory, when a Python file is loaded, we can press `<leader>t` and
`goto_traceback` will run.  Can we try it?  Yes!  Let's set up a helper first
though, to make our development and test iteration time faster.

We'll add a keybinding for re-sourcing our vim plugins and reloading the current
file.  Put this in your `~/.vimrc.py`:

```python
snake.key_map("<leader>sv", ":source $MYVIMRC<CR>:e!<CR>")
```

And exit and re-open Vim.  Now when you press `<leader>sv` any changes you've
made to your plugin will be hot-reloaded for you.  

If you press your traceback keybinding, `<leader>t`, what happens?  If there was
no exception in another pane, you should see `(None, None)` printed in your Vim
message area.   This is because we found no pane and no traceback stack.  So far
so good!

Let's create an exception.  In another TMUX pane, run the `/tmp/exception.py`
code from above.  Go back to Vim and press `<leader>t` again.  You should see
something like

`(Pane(%14 Window(@8 5:zsh, Session($0 0))), [(u'/tmp/exception.py', 8), (u'/tmp/exception.py', 5), (u'/tmp/exception.py', 2)])`

Ah-ha!  Our code found a TMUX pane with an exception, and parsed out the
exception stack.  Now we want to do something useful with that stack, like open
the last file in a Vim buffer.  This is trivial.  Let's expand our
`goto_traceback` function:

```python
def goto_traceback():
    pane, stack = python_debug.find_traceback()
    if pane:
        last_file, line_num = stack[-1]
        snake.command("e " + last_file)
        snake.keys(str(line_num) + "gg")
```

Here we're looking at the last (innermost) frame in the stack trace, if we found
a pane with an exception.  Then we tell Snake to run the Vim edit command `e` (as
if you typed `:e` in Vim) with the file name as an argument.  Once the file is
opened, we tell Snake to press the keys corresponding to moving to a line number
in Vim, as if a user had pressed them.  In our case, those keys are `2gg`, which
moves the cursor to the second line from the top.

We're done!

# Bonus debugging tool

Here's another useful tool for Python debugging in Vim that goes hand-in-hand
with the traceback opener.  Put the following lines in your `debugger.py`
module:

```python
def try_except(sel):
    """ wraps some text in a try-except + pdb """
    first_line = sel.split("\n")[0]
    count = 0
    for char in first_line:
        if char == " ":
            count += 1
        else:
            break

    one_indent_num = 4
    space = " "
    one_indent = space * one_indent_num
    existing_spaces = space * count

    repl = existing_spaces + "try:\n"
    sel = indent(sel.rstrip("\n"), one_indent_num) + "\n"
    repl += sel
    repl += existing_spaces + "except Exception as e:\n"
    repl += existing_spaces + one_indent + "import pdb; pdb.set_trace()\n"
    repl += existing_spaces + one_indent + "pass\n"
    return repl

def indent(block, amount=4):
    return "\n".join([(" " * amount) + line for line in block.split("\n")])
```

And add the following code to your `~/.vimrc.py`:

```python
@snake.when_buffer_is("python")
def python_setup(ctx):
    ctx.visual_key_map("<leader>e", python_debug.try_except)
```

Now, after re-sourcing your Vim plugin with `<leader>sv`, you should be able to
visually-select a block of code and press `<leader>e`.  The result is that your
code will be wrapped with a `try` block and a debugger in the `except` block.
So now in that place that raised previously raised an exception, you can have a
debugger to figure out exactly what happened.

<asciinema-player src="{{site.baseurl}}/assets/screencasts/try_except.cast?{{site.time | date: '%s%N'}}" loop="1" autoplay="1"></asciinema-player>

{% include asciinema.html %}
