from parseopt import getopt, cmdLongOption, cmdShortOption, cmdArgument, cmdEnd
from strformat import fmt
from strutils import multiReplace, strip
from termios import Termios, tcGetAttr
from rdstdin import readLineFromStdin
from os import execShellCmd, fileExists, dirExists
from "../common/config.nim" import XUE_VERSION_STRING
from "../common/helper.nim" 
    import reportFatalError, EXIT_SUCCESS, EXIT_INVALID, printf, 
        XueInterpretResult, EXIT_ESYNTAX, EXIT_RUNTIME
from "../compiler/compiler.nim" import XueCompile
from "../interpreter/opcode.nim" import XueInstruction
from "../interpreter/vmach.nim" import initXueVM, XueInterpret
when compileOption("profiler"):
    import nimprof

proc introduceXue() =
    const timestamp = fmt"{CompileDate}{CompileTime}".multiReplace(("-", ""), (":", ""))
    when defined(release):
        printf("\nXueLand %s+%s ( %s / %s )\n",
            XUE_VERSION_STRING, timestamp, hostOS, hostCPU)
    else:
        printf("\nXueLand %s+%s ( %s / %s ) ( debug )\n",
            XUE_VERSION_STRING, timestamp, hostOS, hostCPU)
    printf("(c) 2021-present Hein Thant Maung Maung, https://heinthanth.com\n\n")

proc describeXue() =
    introduceXue()

    stdout.write("""
SYNOPSIS:

    xue [options]... [script]...

OPTIONS:

    -v, --version            print Xue version and others.
    -h, --help               print this help message showing usage, options, etc.

    -c, --compile=vm|native  compile .xue to target XueVM or native executable.
    -o, --output=out         set output path for compiled instruction or executable.

REPORTING:

    https://github.com/xueland/xue/issues

""")

proc isTTY(f: File): bool {.inline.}  =
    var term: Termios
    return tcGetAttr(getOsFileHandle(f), term.addr) != -1

proc interpret(source: string): XueInterpretResult =
    var instruction: XueInstruction

    if not XueCompile(source, addr(instruction)):
        return XUE_INTERPRET_COMPILE_ERROR

    return if XueInterpret(addr(instruction)):
        XUE_INTERPRET_OK else: XUE_INTERPRET_RUNTIME_ERROR

proc runFromStdin() =
    let rawInput = stdin.readAll()

    if rawInput.strip() != "":
        case interpret(rawInput)
        of XUE_INTERPRET_COMPILE_ERROR:
            quit(EXIT_ESYNTAX)
        of XUE_INTERPRET_RUNTIME_ERROR:
            quit(EXIT_RUNTIME)
        else:
            quit(EXIT_SUCCESS)

proc runFromFile(path: string) =
    if path == "-":
        runFromStdin()
        return

    if not fileExists(path):
        if dirExists(path):
            reportFatalError(EXIT_INVALID, 
                "Oops, '%s' is a DIRECTORY. Give me a FILE!", path)
        reportFatalError(EXIT_INVALID, 
                "Oops, I think '%s' doesn't exist!", path)

    try:
        let input = readFile(path)
        if input.strip() != "":
            case interpret(input)
            of XUE_INTERPRET_COMPILE_ERROR:
                quit(EXIT_ESYNTAX)
            of XUE_INTERPRET_RUNTIME_ERROR:
                quit(EXIT_RUNTIME)
            else:
                quit(EXIT_SUCCESS)
    except IOError:
        reportFatalError(EXIT_INVALID, 
            "Oops, I can't read '%s'. Make sure we have sufficient permission!", path)

proc runREPLcmd(cmd: string): bool =
    case cmd
    of "clear":
        discard execShellCmd( when defined(windows): "cls" else: "clear" )
        return true
    of "exit":
        quit(EXIT_SUCCESS)
    else:
        return false

proc runFromREPL() =
    try:
        while true:
            let rawInput = readLineFromStdin("xue > ")
            let trimmedInput = strip(rawInput)

            if trimmedInput == "":
                continue
            elif runREPLcmd(trimmedInput):
                continue
            else:
                discard interpret(rawInput)
    except IOError:
        quit(130)

when isMainModule:
    initXueVM()

    var 
        introduceRequest, describeRequest: bool
        scripts: seq[string]

    for kind, needle, value in getopt(
            shortNoVal = {'h', 'v'}, longNoVal = @["help", "version"] ):
        case kind
        of cmdEnd:
            reportFatalError(EXIT_INVALID, 
                "Oops, something went wrong while parseing command line arguments!")
        of cmdLongOption:
            case needle
            of "help":
                describeRequest = true
            of "version":
                introduceRequest = true
            of "":
                discard
            else:
                reportFatalError(EXIT_INVALID,
                    "Oops, --%s is not a valid option. See 'xuec --help'.", needle)
        of cmdShortOption:
            case needle
            of "h":
                describeRequest = true
            of "v":
                introduceRequest = true
            of "":
                scripts.add("-")
            else:
                reportFatalError(EXIT_INVALID,
                    "Oops, -%s is not a valid option. See 'xuec --help'.", needle)
        of cmdArgument:
            scripts.add(needle)

    if describeRequest: describeXue()
    elif introduceRequest: introduceXue()

    if scripts.len() > 0:
        runFromFile(scripts[0])
    else:
        if isTTY(stdin): runFromREPL() else: runFromStdin()
