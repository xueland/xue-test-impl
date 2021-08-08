import "../common/config"
import "../parser/asttree"
import "../common/sintaks"
import "../interpreter/core"
import "../parser/token"
when DEBUG_DISASSEMBLE_COMPILER:
    import "../interpreter/dasm"

type
    XueIrGenerator* = ref object of XueCodeGenerator

    FunctionKind = enum
        FUNCTION_SCRIPT,
        FUNCTION_PROCEDURE,

    Compiler = object
        procedure: XueProcedure
        kind: FunctionKind

var current: ptr Compiler

proc currentChunk(): ptr XueInstruction =
    return addr(current.procedure.instruction)

# proc emit(line: uint32, instructions: varargs[uint8]) =
#     for b in instructions:
#         writeOpCode(currentChunk(), b, line)

proc emit(line: uint32, opcodes: varargs[XueOpCode]) =
    for opcode in opcodes:
        writeOpCode(currentChunk(), (uint8)opcode, line)

proc emitReturn() =
    emit(0, XUE_OP_RETURN)

proc initCompiler(compiler: ptr Compiler, kind: FunctionKind, scriptName: string) =
    compiler.kind = kind
    compiler.procedure = newXueFunction(0, "main", scriptName)
    current = compiler

proc endCompiler(): XueProcedure =
    emitReturn()
    let mainFunction = current.procedure
    when DEBUG_DISASSEMBLE_COMPILER:
        disassembleInstruction(currentChunk(), mainFunction.name)
    return mainFunction

method generateNode(generator: XueIrGenerator, node: XueAstNode) =
    node.accept(generator)
endmethod

method visitLiteralNode(generator: XueIrGenerator, node: XueLiteralNode) =
    case node.dataKind
    of XUE_VALUE_NULL:
        writeConstant(currentChunk(), newXueNull(), node.value.line)
    of XUE_VALUE_NUMBER:
        writeConstant(currentChunk(), newXueNumber(node.value.numberValue), node.value.line)
    of XUE_VALUE_BOOLEAN:
        writeConstant(currentChunk(), newXueBoolean(node.value.booleanValue), node.value.line)
    of XUE_VALUE_STRING:
        writeConstant(currentChunk(), newXueString(node.value.stringValue), node.value.line)
    else:
        assert(false)
endmethod

method visitGroupingNode(generator: XueIrGenerator, node: XueGroupingNode) =
    generator.generateNode(node.expression)
endmethod

method visitMonoOpNode(generator: XueIrGenerator, node: XueMonoOpNode) =
    generator.generateNode(node.right)
    case node.operator.kind
    of XUE_TOKEN_MINUS:
        emit(node.operator.line, XUE_OP_NEGATE)
    of XUE_TOKEN_NOT:
        emit(node.operator.line, XUE_OP_NOT)
    of XUE_TOKEN_BIT_NOT:
        emit(node.operator.line, XUE_OP_BIT_NOT)
    else:
        assert(false)
endmethod

method visitDuoOpNode(generator: XueIrGenerator, node: XueDuoOpNode) =
    generator.generateNode(node.left)
    generator.generateNode(node.right)
    case node.operator.kind
    of XUE_TOKEN_PLUS:
        emit(node.operator.line, XUE_OP_ADD)
    of XUE_TOKEN_MINUS:
        emit(node.operator.line, XUE_OP_SUBTRACT)
    of XUE_TOKEN_MULTIPLY:
        emit(node.operator.line, XUE_OP_MULTIPLY)
    of XUE_TOKEN_DIVIDE:
        emit(node.operator.line, XUE_OP_DIVIDE)
    of XUE_TOKEN_MODULO:
        emit(node.operator.line, XUE_OP_MODULO)
    of XUE_TOKEN_POWER:
        emit(node.operator.line, XUE_OP_POWER)
    of XUE_TOKEN_LESS:
        emit(node.operator.line, XUE_OP_LESS)
    of XUE_TOKEN_LESS_EQUAL:
        emit(node.operator.line, XUE_OP_GREATER, XUE_OP_NOT)
    of XUE_TOKEN_GREATER:
        emit(node.operator.line, XUE_OP_GREATER)
    of XUE_TOKEN_GREATER_EQUAL:
        emit(node.operator.line, XUE_OP_LESS, XUE_OP_NOT)
    of XUE_TOKEN_BIT_AND:
        emit(node.operator.line, XUE_OP_BIT_AND)
    of XUE_TOKEN_BIT_OR:
        emit(node.operator.line, XUE_OP_BIT_OR)
    of XUE_TOKEN_BIT_XOR:
        emit(node.operator.line, XUE_OP_BIT_XOR)
    of XUE_TOKEN_BIT_LSH:
        emit(node.operator.line, XUE_OP_BIT_LSH)
    of XUE_TOKEN_BIT_RSH:
        emit(node.operator.line, XUE_OP_BIT_RSH)
    of XUE_TOKEN_EQUAL:
        emit(node.operator.line, XUE_OP_EQUAL)
    of XUE_TOKEN_NOT_EQUAL:
        emit(node.operator.line, XUE_OP_EQUAL, XUE_OP_NOT)
    of XUE_TOKEN_CONCAT:
        emit(node.operator.line, XUE_OP_CONCAT)
    else:
        assert(false)
endmethod

method visitEchoStatement(generator: XueIrGenerator,
                            node: XueEchoStatement) =
    generator.generateNode(node.value)
    emit(node.token.line, XUE_OP_ECHO)
endmethod

method visitExpressionStatement(generator: XueIrGenerator,
                            node: XueExpressionStatement) =
    generator.generateNode(node.expression)
    emit(node.token.line, XUE_OP_POP)
endmethod

proc generate*(generator: XueIrGenerator, nodes: seq[XueAstNode], scriptName: string): XueProcedure =
    var compiler: Compiler
    initCompiler(addr(compiler), FUNCTION_SCRIPT, scriptName)

    for node in nodes:
        if node != nil:
            generator.generateNode(node)
    endfor

    return endCompiler()
endmethod
