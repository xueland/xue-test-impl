const
    EXIT_SUCCESS* = 0
    EXIT_FAILURE* = 1
    EXIT_INVALID* = 2
    EXIT_ESYNTAX* = 3
    EXIT_RUNTIME* = 4

type XueInterpretResult* = enum
    XUE_INTERPRET_OK,
    XUE_INTERPRET_COMPILE_ERROR,
    XUE_INTERPRET_RUNTIME_ERROR,

# C stdio to nim bindings
proc printf*(formatstr: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}
proc fprintf*(output: File, formatstr: cstring) {.header: "<stdio.h>", 
                                                        importc: "fprintf", varargs.}

# some helper function to print errors
template reportError*(formatstr, args) =
    fprintf(stderr, "\n")
    fprintf(stderr, formatstr, args)
    fprintf(stderr, "\n\n")

template reportError*(formatstr) =
    fprintf(stderr, "\n")
    fprintf(stderr, formatstr)
    fprintf(stderr, "\n\n")

# report fatal error that cause program to exit
template reportFatalError*(exitcode, formatstr, args) =
    reportError(formatstr, args)
    quit(exitcode)

template reportFatalError*(exitcode, formatstr) =
    reportError(formatstr)
    quit(exitcode)

# pointer arithmetic
template `+`*[T](p: ptr T, offset: int): ptr T =
    ## the same as *ptr + offset
    cast[ptr type(p[])](cast[ByteAddress](p) +% offset * sizeof(p[]))

template `-`*[T](p: ptr T, offset: int): ptr T =
    ## the same as *ptr - offset
    cast[ptr type(p[])](cast[ByteAddress](p) -% offset * sizeof(p[]))

template `+`*[T](p1: ptr T, p2: ptr T): int =
    ## the same as *ptr + *ptr
    cast[ByteAddress](p1) +% cast[ByteAddress](p2)

template `-`*[T](p1: ptr T, p2: ptr T): int =
    ## the same as *ptr - *ptrs
    cast[ByteAddress](p1) -% cast[ByteAddress](p2)

template `+=`*[T](p: ptr T, offset: int) =
    ## the same as ptr* += offset
    p = p + offset

template `-=`*[T](p: ptr T, offset: int) =
    ## the same as ptr* -= offset
    p = p - offset

template `[]`*[T](p: ptr T, offset: int): T =
    ## the same as ptr*[offset]
    (p + offset)[]

template `[]=`*[T](p: ptr T, offset: int, val: T) =
    ## the same as ptr*[offset] = value
    (p + offset)[] = val

# do - while loop
template until*(condition, code) =
    code
    while condition:
        code
