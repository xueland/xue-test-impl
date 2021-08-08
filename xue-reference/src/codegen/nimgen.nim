from strformat import fmt
from md5 import toMD5, `$`
from times import now, utc, `$`
from unicode import `$`
from os import createDir, joinPath, extractFilename, 
    copyFileToDir, splitFile, removeDir, absolutePath
import osproc
import "../common/config"
import "../parser/asttree"
import "../common/sintaks"
import "../interpreter/core"
import "../parser/token"

type
    NimGenerator* = ref object of XueCodeGenerator
        nimcode: seq[string]
        imports: seq[string]
        xuemods: seq[string]

method writeCode(generator: NimGenerator, code: string) {.base.} =
    when DEBUG_DISASSEMBLE_COMPILER:
        stdout.write(code)
    generator.nimcode.add(code)

method addNimModule(generator: NimGenerator, modules: varargs[string]) {.base.} =
    for module in modules:
        if not (module in generator.imports):
            generator.imports.add(module)
    endfor
endmethod

method addXueModule(generator: NimGenerator, modules: varargs[string]) {.base.} =
    for module in modules:
        if not (module in generator.xuemods):
            generator.xuemods.add(module)
    endfor
endmethod

method generateNode(generator: NimGenerator, node: XueAstNode) =
    node.accept(generator)
endmethod

method visitLiteralNode(generator: NimGenerator, node: XueLiteralNode) =
    case node.dataKind
    of XUE_VALUE_NULL:
        generator.writeCode("nil")
    of XUE_VALUE_NUMBER:
        generator.writeCode($node.value.numberValue)
    of XUE_VALUE_BOOLEAN:
        generator.writeCode(if node.value.booleanValue: "true" else: "false")
    of XUE_VALUE_STRING:
        generator.writeCode(fmt "\"{$node.value.stringValue}\"")
    else:
        assert(false)
endmethod

method visitGroupingNode(generator: NimGenerator, node: XueGroupingNode) =
    generator.writeCode("( ")
    generator.generateNode(node.expression)
    generator.writeCode(" )")
endmethod

method visitMonoOpNode(generator: NimGenerator, node: XueMonoOpNode) =
    case node.operator.kind
    of XUE_TOKEN_MINUS:
        generator.writeCode("- ")
    of XUE_TOKEN_NOT, XUE_TOKEN_BIT_NOT:
        generator.writeCode("not ")
    else:
        assert(false)
    if node.right.kind == XUE_NODE_LITERAL and 
            XueLiteralNode(node.right).value.kind == XUE_TOKEN_NULL_LITERAL:
        generator.addXueModule("xcore")
    generator.generateNode(node.right)
endmethod

method visitDuoOpNode(generator: NimGenerator, node: XueDuoOpNode) =
    if node.operator.kind == XUE_TOKEN_CONCAT:
        generator.writeCode("$(")
        generator.generateNode(node.left)
        generator.writeCode(")")
    else:
        generator.generateNode(node.left)

    {.computedGoto.}
    case node.operator.kind
    of XUE_TOKEN_PLUS:
        generator.writeCode(" + ")
    of XUE_TOKEN_MINUS:
        generator.writeCode(" - ")
    of XUE_TOKEN_MULTIPLY:
        generator.writeCode(" * ")
    of XUE_TOKEN_DIVIDE:
        generator.writeCode(" / ")
    of XUE_TOKEN_MODULO:
        generator.writeCode(" mod ")
    of XUE_TOKEN_POWER:
        generator.writeCode(" pow ")
    of XUE_TOKEN_LESS:
        generator.writeCode(" < ")
    of XUE_TOKEN_LESS_EQUAL:
        generator.writeCode(" <= ")
    of XUE_TOKEN_GREATER:
        generator.writeCode(" > ")
    of XUE_TOKEN_GREATER_EQUAL:
        generator.writeCode(" >= ")
    of XUE_TOKEN_BIT_AND:
        generator.writeCode(" and ")
    of XUE_TOKEN_BIT_OR:
        generator.writeCode(" or ")
    of XUE_TOKEN_BIT_XOR:
        generator.writeCode(" xor ")
    of XUE_TOKEN_BIT_LSH:
        generator.writeCode(" lsh ")
    of XUE_TOKEN_BIT_RSH:
        generator.writeCode(" rsh ")
    of XUE_TOKEN_EQUAL:
        generator.writeCode(" == ")
    of XUE_TOKEN_NOT_EQUAL:
        generator.writeCode(" != ")
    of XUE_TOKEN_CONCAT:
        generator.writeCode(" & ")
    else:
        assert(false)
    
    if node.operator.kind == XUE_TOKEN_CONCAT:
        generator.writeCode("$(")
        generator.generateNode(node.right)
        generator.writeCode(")")
    else:
        generator.generateNode(node.right)
endmethod

method visitEchoStatement(generator: NimGenerator,
                            node: XueEchoStatement) =
    generator.writeCode("echo ")
    generator.generateNode(node.value)
    generator.writeCode("\n")
endmethod

method visitExpressionStatement(generator: NimGenerator,
                            node: XueExpressionStatement) =
    generator.generateNode(node.expression)
    generator.writeCode("\n")
endmethod

proc generate*(generator: NimGenerator, nodes: seq[XueAstNode], scriptName: string, output: string) =
    when DEBUG_DISASSEMBLE_COMPILER:
        echo "[nimcg] generating nim code:"

    for node in nodes:
        if node != nil:
            stdout.write "        "
            generator.generateNode(node)
    endfor

    let tempworkspace = fmt"{splitFile(scriptName).name}_{($toMD5($now().utc())).substr(0, 7)}"
    createDir(tempworkspace)

    let tempNimFileName = splitFile(scriptName).name & ".nim"
    let tempNimFilePath = joinPath(tempworkspace, tempNimFileName)
    var tempNimFile = open(tempNimFilePath, fmWrite)

    for module in generator.imports:
        tempNimFile.writeLine(fmt "import \"{module}\"")

    # cp xue-std libs
    for module in generator.xuemods:
        copyFileToDir(joinPath(XUE_BASE_DIRECTORY, "nim-codegen", module & ".nim"), tempworkspace)
        tempNimFile.writeLine(fmt "import \"{module}\"")

    tempNimFile.writeLine("\n")
    tempNimFile.writeLine(generator.nimcode)

    var executableName = output
    if output == "":
        executableName = splitFile(scriptName).name
    else:
        executableName = output

    executableName = absolutePath(executableName)
    # compile generated nim
    echo execCmd(fmt"nim c -o:{executableName} {tempNimFilePath}")

    # remove temp workspace
    # removeDir(tempworkspace)
endmethod
