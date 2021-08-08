const
    EXIT_SUCCESS* = 0
    EXIT_FAILURE* = 1
    EXIT_INVALID* = 2
    EXIT_ESYNTAX* = 3
    EXIT_RUNTIME* = 4
    EXIT_INTERUP* = 130

proc printf*(format: cstring) {.importc: "printf", 
                                varargs, header: "<stdio.h>".}

proc fprintf*(stream: File, formatstr: cstring) {.importc: "fprintf", 
                                varargs, header: "<stdio.h>".}

###########################################################

from times import epochTime
from strutils import formatFloat, FloatFormatMode

export epochTime, formatFloat, FloatFormatMode

template benchmark*(benchmarkName: string, code: untyped) =
    block:
        let t0 = epochTime()
        code
        let elapsed = epochTime() - t0
        let elapsedStr = elapsed.formatFloat(format = ffDecimal, precision = 10)
        echo "cpu time [ ", benchmarkName, " ] ", elapsedStr, "s"

###########################################################

# some helper function to print errors
template reportError*(formatstr, args) =
    fprintf(stderr, "\n" & formatstr & "\n\n", args)

template reportError*(formatstr) =
    fprintf(stderr, "\n" & formatstr & "\n\n")

# report fatal error that cause program to exit
template reportFatalError*(exitcode, formatstr, args) =
    reportError(formatstr, args); quit(exitcode)

template reportFatalError*(exitcode, formatstr) =
    reportError(formatstr); quit(exitcode)

# do - while loop
template until*(condition, code) =
    code
    while condition:
        code
