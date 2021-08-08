import "./sintaks"

const
    EXIT_SUCCESS* = 0
    EXIT_FAILURE* = 1
    EXIT_INUSAGE* = 2
    EXIT_COMPILE* = 3
    EXIT_EXECUTE* = 4

proc printf*(format: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}
proc fprintf*(output: File, format: cstring) {.header: "<stdio.h>", 
                                                        importc: "fprintf", varargs.}

# some helper function to print errors
template reportError*(formatstr, args) =
    fprintf(stderr, "\n")
    fprintf(stderr, formatstr, args)
    fprintf(stderr, "\n\n")
endtemplate

template reportError*(formatstr) =
    fprintf(stderr, "\n")
    fprintf(stderr, formatstr)
    fprintf(stderr, "\n\n")
endtemplate

# report fatal error that cause program to exit
template reportFatalError*(exitcode, formatstr, args) =
    reportError(formatstr, args)
    quit(exitcode)
endtemplate

template reportFatalError*(exitcode, formatstr) =
    reportError(formatstr)
    quit(exitcode)
endtemplate
