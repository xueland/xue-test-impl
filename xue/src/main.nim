from strformat import fmt
from strutils import multiReplace, join, strip
from parseopt import getopt, cmdLongOption, cmdShortOption, cmdArgument, cmdEnd
from termios import Termios, tcGetAttr
from rdstdin import readLineFromStdin
from os import execShellCmd, fileExists, dirExists
import "./config"
import "./utils"
import "./parser"
import "./engine"
when defined(profiler):
    import nimprof

proc introduceXue(shouldExit: bool = true) =
    const timestamp = fmt"{CompileDate}{CompileTime}".multiReplace(("-", ""), (":", ""))
    when defined(release):
        printf("\nXueLand %s+%s ( %s / %s )\n",
            XUE_VERSION_STRING, timestamp, hostOS, hostCPU)
    else:
        printf("\nXueLand %s+%s ( %s / %s ) ( debug )\n",
            XUE_VERSION_STRING, timestamp, hostOS, hostCPU)
    stdout.writeLine("(c) 2021 Hein Thant Maung Maung. Licensed under MIT License.\n")

proc describeXue() =
    introduceXue(false)
    const helpString = [
        "SYNOPSIS:\n",
        "   xue [options]... [script]...\n",
        "OPTIONS:\n",
        "    -r, --run          evaluate the code passed from -r argument.",
        "    -o, --output       output name for compiled IR executable.",
        "    -c, --compile      compile .xue script into IR executable.",
        "    -l, --load         load instructions from compiled IR executable.\n",
        "    -v, --version      print Xue version and others.",
        "    -h, --help         print this help message like usage, options, etc.\n",
        "REPORTING:\n",
        "    https://github.com/xueland/xue/issues. Contributions are also welcome!\n\n"
    ]
    stdout.write(helpString.join("\n"))
    quit(EXIT_SUCCESS)

proc runFromStdin() =
    var rawInput = stdin.readAll()
    shallow(rawInput)

    if rawInput.strip() != "":
        quit(XueInterpret(rawInput, "stdin"))

proc readSource(path: string): string =
    if path == "-":
        return stdin.readAll()

    if not fileExists(path):
        if dirExists(path):
            reportFatalError(EXIT_INVALID, 
                "Oops, '%s' is a DIRECTORY. Give me a FILE!", path)
        reportFatalError(EXIT_INVALID, 
                "Oops, I think '%s' doesn't exist!", path)

    try:
        return readFile(path)
    except IOError:
        reportFatalError(EXIT_INVALID, 
            "Oops, I can't read '%s'. Make sure we have sufficient permission!", path)

proc runFromFile(path: string) =
    var input = readSource(path)
    shallow(input)

    if input.strip() != "":
        quit(XueInterpret(input, path))

proc compileToFile(path: string, output: string) =
    var input = readSource(path)
    shallow(input)

    if input.strip() != "":
        quit(XueCompileToFile(input, path, output))

proc loadFromFile(path: string) =
    var input = readSource(path)

    if input.len() != 0:
        quit(XueInterpretFromCompiled(input))

proc runREPLcmd(cmd: string): bool =
    case cmd
    of "clear":
        discard execShellCmd( when defined(windows): "cls" else: "clear" )
        return true
    of "exit":
        quit(EXIT_SUCCESS)
    else:
        return false

proc spawnREPL() =
    introduceXue(false)
    try:
        while true:
            let rawInput = readLineFromStdin("xue > ")
            let trimmedInput = strip(rawInput)

            if trimmedInput == "":
                continue
            elif runREPLcmd(trimmedInput):
                continue
            else:
                discard XueInterpret(rawInput, "REPL")
    except IOError:
        quit(EXIT_INTERUP)

proc isTTY(f: File): bool {.inline.} =
    var term: Termios
    return tcGetAttr(getOsFileHandle(f), term.addr) != -1

when isMainModule:
    setControlCHook(proc() {.noconv.} =
        stderr.writeLine("")
        quit(EXIT_INTERUP))

    var
        input: string # xue script to interpret
        output: string # intermediate instruction output
        shouldCompile, shouldLoad, shouldRunFromCmd: bool
        runnableCodeCmd: string

    for kind, needle, value in getopt(
            shortNoVal = {'h', 'v', 'c', 'l'},
            longNoVal = @["help", "version", "compile", "load"] ):
        case kind
        of cmdEnd:
            reportFatalError(EXIT_INVALID, 
                "Oops, something went wrong while parseing command line arguments!")
        of cmdLongOption:
            case needle
            of "help": describeXue()
            of "version": introduceXue()
            of "load": shouldLoad = true
            of "compile": shouldCompile = true
            of "output": output = value
            of "run":
                shouldRunFromCmd = true
                runnableCodeCmd = value
            of "": discard
            else:
                reportFatalError(EXIT_INVALID,
                    "Oops, --%s is not a valid option. See 'xue --help'.", needle)
        of cmdShortOption:
            case needle
            of "h": describeXue()
            of "v": introduceXue()
            of "l": shouldLoad = true
            of "c": shouldCompile = true
            of "o": output = value
            of "r":
                shouldRunFromCmd = true
                runnableCodeCmd = value
            of "": input = "-"
            else:
                reportFatalError(EXIT_INVALID,
                    "Oops, -%s is not a valid option. See 'xue --help'.", needle)
        of cmdArgument:
            input = needle

    if shouldCompile and (shouldLoad or shouldRunFromCmd):
        reportFatalError(EXIT_INVALID, "You can't use both 'load' and 'compile'!")

    if shouldCompile:
        if input != "":
            compileToFile(input, output)
        elif isTTY(stdin):
            reportFatalError(EXIT_INVALID, "Oops, we can't compile REPL to IR executable!")
        else:
            discard # compile from stdin
    elif shouldLoad:
        if input != "":
            loadFromFile(input)
        elif isTTY(stdin):
            reportFatalError(EXIT_INVALID, "Oops, we can't load instruction from REPL!")
        else:
            loadFromFile("-")
    elif shouldRunFromCmd:
        quit(XueInterpret(runnableCodeCmd, "stdin"))
    else:
        if input != "":
            runFromFile(input)
        elif isTTY(stdin):
            spawnREPL()
        else: runFromStdin()
