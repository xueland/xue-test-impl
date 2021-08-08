from parseopt import getopt, cmdLongOption, cmdShortOption, cmdArgument, cmdEnd
from strformat import fmt
from strutils import multiReplace, strip
from termios import Termios, tcGetAttr
from rdstdin import readLineFromStdin
from os import execShellCmd, fileExists, dirExists, splitFile
from streams import newStringStream, close
import "../common/config"
import "../common/helper"
import "../common/sintaks"
import "../parser/parser"
import "../interpreter/vmach"
import "../codegen/xuegen"
import "../codegen/nimgen"
import "../interpreter/core"
when compileOption("profiler"):
    import nimprof

proc introduceXue(shouldExit: bool = true) =
    const timestamp = fmt"{CompileDate}{CompileTime}".multiReplace(("-", ""), (":", ""))
    when defined(release):
        printf("\nXueLand %s+%s ( %s / %s )\n",
            XUE_VERSION_STRING, timestamp, hostOS, hostCPU)
    else:
        printf("\nXueLand %s+%s ( %s / %s ) ( debug )\n",
            XUE_VERSION_STRING, timestamp, hostOS, hostCPU)
    endwhen
    printf("(c) 2021-present Hein Thant Maung Maung, https://heinthanth.com\n\n")
    if shouldExit: quit(0)
endproc

proc describeXue() =
    introduceXue(false)

    stdout.write("""
SYNOPSIS:
    xue [options]... [script]...

OPTIONS:
    -v, --version            print Xue version and others.
    -h, --help               print this help message showing usage, options, etc.

    -c, --compile=vm|native  compile .xue to target XueVM or native executable.
    -o, --output=out         set output path for compiled instruction or executable.
    -r, --run                run instruction from exported compiled instruction file.

REPORTING:
    https://github.com/xueland/xue/issues

""")
    quit(0)
endproc

proc isTTY(f: File): bool {.inline.}  =
    var term: Termios
    return tcGetAttr(getOsFileHandle(f), term.addr) != -1
endproc

proc interpret(source: string, path: string): int =
    let ast = parse(source, path)
    if ast[1] == []:
        return if ast[0]: EXIT_SUCCESS else: EXIT_COMPILE

    var irGen = new(XueIrGenerator)
    var mainFunction = irGen.generate(ast[1], path)

    return XueInterpret(addr(mainFunction))
endproc

proc generateNim(source: string, path: string, output: string): int =
    let ast = parse(source, path)
    if ast[1] == []:
        return if ast[0]: EXIT_SUCCESS else: EXIT_COMPILE

    var nimGen = new(NimGenerator)
    nimGen.generate(ast[1], path, output)
    return EXIT_SUCCESS
endproc

proc generateXue(source: string, path: string, output: string): int =
    let ast = parse(source, path)
    if ast[1] == []:
        return if ast[0]: EXIT_SUCCESS else: EXIT_COMPILE

    var irGen = new(XueIrGenerator)
    var mainFunction = irGen.generate(ast[1], path)
    if mainFunction == nil:
        return EXIT_COMPILE

    var ir = newStringStream("")
    ir.save(mainFunction)
    
    var executableName = output
    if output == "":
        executableName = splitFile(path).name
    else:
        executableName = output

    try:
        writeFile(executableName, ir.data)
    except IOError:
        reportFatalError(EXIT_INUSAGE, 
            "Oops, I can't read '%s'. Make sure we have sufficient permission!", path)
    return EXIT_SUCCESS
endproc

# ##########################################################

proc readSource(path: string): string =
    if path == "-":
        return stdin.readAll()

    if not fileExists(path):
        if dirExists(path):
            reportFatalError(EXIT_INUSAGE, 
                "Oops, '%s' is a DIRECTORY. Give me a FILE!", path)
        endif
        reportFatalError(EXIT_INUSAGE, 
                "Oops, I think '%s' doesn't exist!", path)
    endif

    try:
        return readFile(path)
    except IOError:
        reportFatalError(EXIT_INUSAGE, 
            "Oops, I can't read '%s'. Make sure we have sufficient permission!", path)
endproc

proc runFromStdin() =
    let rawInput = stdin.readAll()

    if rawInput.strip() != "":
        quit(interpret(rawInput, "stdin"))
endproc

proc runFromFile(path: string) =
    let input = readSource(path)
    if input.strip() != "":
        quit(interpret(input, path))
endproc

# ##########################################################

proc runFromIrFile(path: string) =
    let input = readSource(path)

    if input.len() == 0:
        quit(EXIT_SUCCESS)

    var ir = newStringStream(input)
    try:
        var mainFunction: XueProcedure = XueProcedure(ir.load())
        ir.close()

        quit(XueInterpret(addr(mainFunction)))
    except:
        ir.close()
        reportFatalError(EXIT_FAILURE, "Oops, invalid or corrupted instruction!")
endproc

# ##########################################################

proc generateFromStdin(target: string, output: string) =
    let rawInput = stdin.readAll()

    if rawInput.strip() != "":
        case target
        of "native":
            quit(generateNim(rawInput, "stdin", output))
        of "vm":
            quit(generateXue(rawInput, "stdin", output))
        else:
            reportFatalError(EXIT_INUSAGE, "Oops, I don't know that target!")
    endif
endproc

proc generateFromFile(path: string, target: string, output: string) =
    let input = readSource(path)

    if input.strip() != "":
        case target
        of "native":
            quit(generateNim(input, path, output))
        of "vm":
            quit(generateXue(input, path, output))
        else:
            reportFatalError(EXIT_INUSAGE, "Oops, I don't know that target!")
    endif
endproc

proc runREPLcmd(cmd: string): bool =
    case cmd
    of "clear":
        discard execShellCmd( when defined(windows): "cls" else: "clear" )
        return true
    of "exit":
        quit(EXIT_SUCCESS)
    else:
        return false
    endcase
endproc

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
                discard interpret(rawInput, "REPL")
    except IOError:
        quit(130)
endproc

when isMainModule:
    initXueVM(stdout, stderr)

    var 
        introduceRequest, describeRequest: bool
        scripts: seq[string]
        shouldCompile, shouldRun: bool
        target, output: string

    for kind, needle, value in getopt(
            shortNoVal = {'h', 'v'}, longNoVal = @["help", "version"] ):
        case kind
        of cmdEnd:
            reportFatalError(EXIT_INUSAGE, 
                "Oops, something went wrong while parseing command line arguments!")
        of cmdLongOption:
            case needle
            of "help":
                describeRequest = true
            of "version":
                introduceRequest = true
            of "compile":
                shouldCompile = true
                target = value
            of "run":
                shouldRun = true
            of "output":
                output = value
            of "": discard
            else:
                reportFatalError(EXIT_INUSAGE,
                    "Oops, --%s is not a valid option. See 'xuec --help'.", needle)
        of cmdShortOption:
            case needle
            of "h":
                describeRequest = true
            of "v":
                introduceRequest = true
            of "c":
                shouldCompile = true
                target = value
            of "r":
                shouldRun = true
            of "o":
                output = value
            of "":
                scripts.add("-")
            else:
                reportFatalError(EXIT_INUSAGE,
                    "Oops, -%s is not a valid option. See 'xuec --help'.", needle)
        of cmdArgument:
            scripts.add(needle)
        endcase
    endfor

    if describeRequest: describeXue()
    elif introduceRequest: introduceXue()

    if shouldRun:
        if scripts.len() > 0:
            runFromIrFile(scripts[0])
        else:
            reportFatalError(EXIT_INUSAGE, "Oops, running with compiled instruction is not supported on stdin or REPL.")
    elif shouldCompile:
        if scripts.len() > 0:
            generateFromFile(scripts[0], target, output)
        elif not isTTY(stdin):
            generateFromStdin(target, output)
        else:
            reportFatalError(EXIT_INUSAGE, "Oops, code generation is not supported in REPL mode!")
    else:
        if scripts.len() > 0:
            runFromFile(scripts[0])
        else:
            if isTTY(stdin): runFromREPL() else: runFromStdin()
        endif
    endif
endproc
