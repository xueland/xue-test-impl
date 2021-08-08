from tables import Table, `[]`, `[]=`, contains, del
import "./scanner"
from "../common/config.nim" import DEBUG_DISASSEMBLE_COMPILER
from "../common/helper.nim" import fprintf, until
from "../interpreter/opcode.nim" import XueOpCode, XueInstruction, writeOpCode, writeConstant
from "../compiler/token.nim" import XueToken, XueTokenKind
from "../interpreter/value.nim" import newXueValue, XueValueKind, XueValue
from "../interpreter/vmach.nim" import GlobalVariable, VariableKind, vm
when DEBUG_DISASSEMBLE_COMPILER:
    from "../common/debug.nim" import disassembleInstruction

type
    Parser = object
        current: XueToken
        previous: XueToken

    ParserError = object of CatchableError

    AstNodeKind = enum
        NODE_LITERAL,
        NODE_BINARY,
        NODE_UNARY,
        NODE_POWER,
        NODE_GROUPING,
        NODE_STRINTER,
        NODE_VARIABLE,
        NODE_ASSIGN,

    AstNode = ref AstNodeObject

    AstNodeObject = object
        case kind: AstNodeKind
        of NODE_VARIABLE:
            variable: string
        else:
            discard
        dataKind: XueValueKind

    Precedence = enum
        PREC_NONE,
        PREC_ASSIGNMENT,
        PREC_TERN,
        PREC_LOGIC_OR,
        PREC_LOGIC_AND,
        PREC_BITWISE_OR,
        PREC_BITWISE_XOR,
        PREC_BITWISE_AND,
        PREC_LOGIC_EQUAL,
        PREC_LOGIC_COMP,
        PREC_BITWISE_SHIFT,
        PREC_TERM,
        PREC_FACTOR,
        PREC_POWER,
        PREC_MONO,
        PREC_CALL,
        PREC_ATOM

    ParserPrefixFn = proc(assignable: bool): AstNode
    ParserInfixFn = proc(lvalue: AstNode): AstNode

    ParseRule = object
        prefix: ParserPrefixFn
        infix: ParserInfixFn
        precedence: Precedence

    LocalVariable = object
        name: XueToken
        scope: int
        kind: VariableKind
        dataKind: XueValueKind

    Compiler = object
        locals: seq[LocalVariable]
        scope: int

var parser: Parser
var compilingChunk: ptr XueInstruction
var current: ptr Compiler

proc currentChunk(): ptr XueInstruction {.inline.} =
    return compilingChunk

template reportCompilerError(token: XueToken, format: string, args) =
    fprintf(stderr, "\n")
    fprintf(stderr, "[ at line: %u, column: %u ] ", token.line, token.column)
    fprintf(stderr, format, args)
    fprintf(stderr, "\n\n")
    
    raise newException(ParserError, "")

template reportCompilerError(token: XueToken, format: string) =
    fprintf(stderr, "\n")
    fprintf(stderr, "[ at line: %u, column: %u ] ", token.line, token.column)
    fprintf(stderr, format)
    fprintf(stderr, "\n\n")

    raise newException(ParserError, "")

proc advance() =
    parser.previous = parser.current

    try:
        while true:
            parser.current = scanToken()
            break
    except ScannerError:
        raise newException(ParserError, "")

proc check(kind: XueTokenKind): bool {.inline.} =
    return parser.current.kind == kind

proc match(kinds: varargs[XueTokenKind]): bool {.inline.} =
    for kind in kinds:
        if check(kind):
            advance()
            return true
    return false

proc expect(kind: XueTokenKind, message: string) =
    if parser.current.kind == kind:
        advance()
        return
    reportCompilerError(parser.current, message)

proc emit(instructions: varargs[uint8]) =
    for b in instructions:
        writeOpCode(currentChunk(), b, parser.previous.line)

proc emit(opcodes: varargs[XueOpCode]) =
    for opcode in opcodes:
        writeOpCode(currentChunk(), (uint8)opcode, parser.previous.line)

proc emitLoop(loopStart: uint32) =
    emit(XUE_OP_LOOP)

    var offset: uint32 = ((uint32)currentChunk().code.len()) - loopStart + 2
    if offset > high(uint16):
        reportCompilerError(parser.previous,
            "Oops, too much code to loop!")

    emit((uint8)((offset shr 8) and (uint32)uint32(0xFF)))
    emit((uint8)(offset and (uint32)uint32(0xFF)))

proc emitJump(opcode: XueOpCode): int =
    emit(opcode)
    emit(0xFFu8, 0xFFu8)
    return currentChunk().code.len() - 2

proc patchJump(offset: int) =
    let jump = uint32(currentChunk().code.len() - offset - 2)
    if jump > high(uint16):
        reportCompilerError(parser.previous, "Oops, too much code to jump!")
    currentChunk().code[offset] = uint8((jump shr 8) and uint32(0xFF))
    currentChunk().code[offset + 1] = (uint8)(jump and uint32(0xFF))

proc emitReturn() =
    emit(XUE_OP_RETURN)

proc initCompiler(compiler: ptr Compiler) =
    current = compiler

proc endCompiler() =
    emitReturn()
    when DEBUG_DISASSEMBLE_COMPILER:
        disassembleInstruction(currentChunk(), "code")

proc beginScope() =
    current.scope.inc()

proc endScope() =
    current.scope.dec()
    while current.locals.len() > 0 and
        current.locals[current.locals.len() - 1].scope > current.scope:
        emit(XUE_OP_POP)
        discard current.locals.pop()

proc expression(): AstNode
proc statement()
proc declaration()
proc getRule(kind: XueTokenKind): ParseRule
proc parsePrecedence(precedence: Precedence): AstNode 

proc parseStringInterpolation(assignable: bool): AstNode  =
    until match(XUE_TOKEN_INTERPOLATION):
        writeConstant(currentChunk(), 
            newXueValue(parser.previous.stringValue), parser.previous.line)
        discard expression()
        emit(XUE_OP_CONCAT)

    expect(XUE_TOKEN_STRING_LITERAL,
        "Oops, I was expecting the end of string interpolation!")
    writeConstant(currentChunk(), 
        newXueValue(parser.previous.stringValue), parser.previous.line)
    emit(XUE_OP_CONCAT)
    return AstNode(kind: NODE_STRINTER, dataKind: XUE_VALUE_STRING)

proc parseDuo(lvalue: AstNode): AstNode  =
    let operator = parser.previous
    let rule: ParseRule = getRule(operator.kind)
    let rvalue = parsePrecedence((Precedence)(((uint)rule.precedence) + 1))

    case operator.kind
    of XUE_TOKEN_PLUS:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't add non-numbers!")
        emit(XUE_OP_ADD)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_MINUS:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't subtract non-numbers!")
        emit(XUE_OP_SUBTRACT)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_MULTIPLY:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, operands must be numbers in multiplication!")
        emit(XUE_OP_MULTIPLY)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_DIVIDE:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't divide non-numbers!")
        emit(XUE_OP_DIVIDE)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_MODULO:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't calculate modulo of non-numbers!")
        emit(XUE_OP_MODULO)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_LESS:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't compare non-numbers!")
        emit(XUE_OP_LESS)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_LESS_EQUAL:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't compare non-numbers!")
        emit(XUE_OP_GREATER, XUE_OP_NOT)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_GREATER:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't compare non-numbers!")
        emit(XUE_OP_GREATER)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_GREATER_EQUAL:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't compare non-numbers!")
        emit(XUE_OP_LESS, XUE_OP_NOT)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_BIT_AND:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't calcluate bitwise and of non-numbers!")
        emit(XUE_OP_BIT_AND)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_OR:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't calculate bitwise or of non-numbers!")
        emit(XUE_OP_BIT_OR)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_XOR:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't calculate bitwise xor non-numbers!")
        emit(XUE_OP_BIT_XOR)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_LSH:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't left shift non-numbers!")
        emit(XUE_OP_BIT_LSH)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_RSH:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't right shift non-numbers!")
        emit(XUE_OP_BIT_RSH)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_EQUAL:
        emit(XUE_OP_EQUAL)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_NOT_EQUAL:
        emit(XUE_OP_EQUAL, XUE_OP_NOT)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_CONCAT:
        emit(XUE_OP_CONCAT)
        return AstNode(kind: NODE_BINARY, dataKind: XUE_VALUE_STRING)
    else:
        assert(false)

proc parseGrouing(assignable: bool): AstNode  =
    let enclosing = expression()
    expect(XUE_TOKEN_RIGHT_PAREN, "Oops, missing ')' in grouping!")
    return AstNode(kind: NODE_GROUPING, dataKind: enclosing.dataKind)

proc parseLiteral(assignable: bool): AstNode  =
    case parser.previous.kind
    of XUE_TOKEN_NUMBER_LITERAL:
        writeConstant(currentChunk(), 
            newXueValue(parser.previous.numberValue), parser.previous.line)
        return AstNode(kind: NODE_LITERAL, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_STRING_LITERAL:
        writeConstant(currentChunk(), 
            newXueValue(parser.previous.stringValue), parser.previous.line)
        return AstNode(kind: NODE_LITERAL, dataKind: XUE_VALUE_STRING)
    of XUE_TOKEN_BOOLEAN_LITERAL:
        writeConstant(currentChunk(), 
            newXueValue(parser.previous.booleanValue), parser.previous.line)
        return AstNode(kind: NODE_LITERAL, dataKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_NULL_LITERAL:
        writeConstant(currentChunk(), 
            newXueValue(), parser.previous.line)
        return AstNode(kind: NODE_LITERAL, dataKind: XUE_VALUE_NULL)
    else:
        assert(false)

proc resolveLocal(compiler: ptr Compiler, name: XueToken): int =
    for i in countdown(compiler.locals.len() - 1, 0):
        let local = compiler.locals[i]
        if local.name.lexeme == name.lexeme:
            if local.scope == -1:
                reportCompilerError(name, "Oops! I know this case, but, I won't allow it!")
            return i
    return -1

proc namedIdentifier(name: XueToken, assignable: bool): AstNode =
    let isLocal = resolveLocal(current, name)

    if isLocal == -1:
        if not vm.globals.contains(name.lexeme):
            reportCompilerError(parser.previous,
                "Oops, global variable '%s' does not exist!", name.lexeme)
        let global = vm.globals[name.lexeme]

        if assignable and match(XUE_TOKEN_ASSIGN):
            let op = parser.previous

            if vm.globalsProfile[global].kind == VARIABLE_CONST:
                reportCompilerError(op,
                    "Oops, cannot reassign value to constant!")

            let rvalue = expression()
            if vm.globalsProfile[global].dataKind != rvalue.dataKind:
                reportCompilerError(op,
                    "Oops, cannot assign identifier to different data kind!")

            if global <= high(uint8):
                emit((uint8)XUE_OP_SET_GLOBAL_1, (uint8)global)
            elif global <= high(uint16):
                emit(XUE_OP_SET_GLOBAL_2)
                emit((uint8)(global and uint32(0xFF)), (uint8)((global shr 8) and uint32(0xFF)))
            elif global <= high(uint32):
                emit(XUE_OP_SET_GLOBAL_4)
                emit((uint8)(global and uint32(0xFF)), (uint8)((global shr 8) and uint32(0xFF)))
                emit((uint8)((global shr 16) and uint32(0xFF)), (uint8)((global shr 24) and uint32(0xFF)))
            else:
                reportCompilerError(parser.previous, "Oops, 32-bit integer overflow!")
            
            return AstNode(kind: NODE_ASSIGN, dataKind: rvalue.dataKind)
        else:
            if global <= high(uint8):
                emit((uint8)XUE_OP_GET_GLOBAL_1, (uint8)global)
            elif global <= high(uint16):
                emit(XUE_OP_GET_GLOBAL_2)
                emit((uint8)(global and uint32(0xFF)), (uint8)((global shr 8) and uint32(0xFF)))
            elif global <= high(uint32):
                emit(XUE_OP_GET_GLOBAL_4)
                emit((uint8)(global and uint32(0xFF)), (uint8)((global shr 8) and uint32(0xFF)))
                emit((uint8)((global shr 16) and uint32(0xFF)), (uint8)((global shr 24) and uint32(0xFF)))
            else:
                reportCompilerError(parser.previous, "Oops, 32-bit integer overflow!")

            return AstNode(kind: NODE_VARIABLE, 
                variable: name.lexeme, dataKind: vm.globalsProfile[global].dataKind)
    else:
        let local = (uint32)isLocal
        if assignable and match(XUE_TOKEN_ASSIGN):
            let op = parser.previous

            if current.locals[local].kind == VARIABLE_CONST:
                reportCompilerError(op,
                    "Oops, cannot reassign value to constant!")

            let rvalue = expression()
            if current.locals[local].dataKind != rvalue.dataKind:
                reportCompilerError(op,
                    "Oops, cannot assign identifier to different data kind!")
            
            if local <= high(uint8):
                emit((uint8)XUE_OP_SET_LOCAL_1, (uint8)local)
            elif local <= high(uint16):
                emit(XUE_OP_SET_LOCAL_2)
                emit((uint8)(local and uint32(0xFF)), (uint8)((local shr 8) and uint32(0xFF)))
            elif local <= high(uint32):
                emit(XUE_OP_SET_LOCAL_4)
                emit((uint8)(local and uint32(0xFF)), (uint8)((local shr 8) and uint32(0xFF)))
                emit((uint8)((local shr 16) and uint32(0xFF)), (uint8)((local shr 24) and uint32(0xFF)))
            else:
                reportCompilerError(parser.previous, "Oops, 32-bit integer overflow!")
            
            return AstNode(kind: NODE_ASSIGN, dataKind: rvalue.dataKind)
        else:
            if local <= high(uint8):
                emit((uint8)XUE_OP_GET_LOCAL_1, (uint8)local)
            elif local <= high(uint16):
                emit(XUE_OP_GET_LOCAL_2)
                emit((uint8)(local and uint32(0xFF)), (uint8)((local shr 8) and uint32(0xFF)))
            elif local <= high(uint32):
                emit(XUE_OP_GET_LOCAL_4)
                emit((uint8)(local and uint32(0xFF)), (uint8)((local shr 8) and uint32(0xFF)))
                emit((uint8)((local shr 16) and uint32(0xFF)), (uint8)((local shr 24) and uint32(0xFF)))
            else:
                reportCompilerError(parser.previous, "Oops, 32-bit integer overflow!")

            return AstNode(kind: NODE_VARIABLE, 
                variable: name.lexeme, dataKind: current.locals[local].dataKind)

proc parseIdentifier(assignable: bool): AstNode =
    return namedIdentifier(parser.previous, assignable)

proc parseMono(assignable: bool): AstNode  =
    let operator = parser.previous

    let rvalue = parsePrecedence(PREC_MONO)

    case operator.kind
    of XUE_TOKEN_MINUS:
        if rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't negate a non-number!")
        emit(XUE_OP_NEGATE)
        return AstNode(kind: NODE_UNARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_NOT:
        if rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator,
                "Oops, we can't calculate the complement of a non-number!")
        emit(XUE_OP_BIT_NOT)
        return AstNode(kind: NODE_UNARY, dataKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_NOT:
        emit(XUE_OP_NOT)
        return AstNode(kind: NODE_UNARY, dataKind: XUE_VALUE_BOOLEAN)
    else:
        assert(false)

proc parseExponent(lvalue: AstNode): AstNode  =
    let operator = parser.previous

    let rvalue = parsePrecedence(PREC_POWER)
    if lvalue.dataKind != XUE_VALUE_NUMBER or
            rvalue.dataKind != XUE_VALUE_NUMBER:
        reportCompilerError(operator,
            "Oops, we can't calculate exponent of non-numbers!")
    emit(XUE_OP_POWER)
    return AstNode(kind: NODE_POWER, dataKind: XUE_VALUE_NUMBER)

template createRule(prefixFn: ParserPrefixFn, 
        infixFn: ParserInfixFn, prec: Precedence): ParseRule =
    ParseRule(prefix: prefixFn, infix: infixFn, precedence: prec)

proc parsePrecedence(precedence: Precedence): AstNode =
    var returnNode: AstNode

    advance()
    let prefixRule: ParserPrefixFn = getRule(parser.previous.kind).prefix
    if prefixRule == nil:
        reportCompilerError(parser.previous,
            "Oops, expecting an expression!")
    
    let assignable = precedence <= PREC_ASSIGNMENT
    returnNode = prefixRule(assignable)

    while precedence <= getRule(parser.current.kind).precedence:
        advance()
        let infixRule: ParserInfixFn = getRule(parser.previous.kind).infix;
        returnNode = infixRule(returnNode)

    if assignable and match(XUE_TOKEN_ASSIGN):
        reportCompilerError(parser.previous, "Oops, we can't assign to non-variables!")
    return returnNode

proc parseVariable(message: string, kind: VariableKind, isDeclaration: bool = false): (string, int) =
    expect(XUE_TOKEN_IDENTIFIER, message)
    let identifier = parser.previous
    
    expect(XUE_TOKEN_COLON, "Oops, missing ':' after identifier name!")

    if not match(XUE_TOKEN_STRING_TYPE, XUE_TOKEN_NUMBER_TYPE, XUE_TOKEN_BOOLEAN_TYPE):
        reportCompilerError(parser.current, "Oops, expecting data kind after identifier!")
    let dataKind = parser.previous
    var valueKind: XueValueKind
    case dataKind.kind
    of XUE_TOKEN_STRING_TYPE:
        valueKind = XUE_VALUE_STRING
    of XUE_TOKEN_NUMBER_TYPE:
        valueKind = XUE_VALUE_NUMBER
    of XUE_TOKEN_BOOLEAN_TYPE:
        valueKind = XUE_VALUE_BOOLEAN
    else:
        assert(false)

    if current.scope > 0:
        for i in countdown(current.locals.len() - 1, 0):
            let local = current.locals[i]
            if local.scope != -1 and local.scope < current.scope:
                break

            if local.name == identifier:
                reportCompilerError(identifier, 
                    "Oops, cannot re-declare local variable '%s'!", identifier.lexeme)

        current.locals.add(
            LocalVariable(name: identifier, scope: -1, kind: kind, dataKind: valueKind))
        return (identifier.lexeme, current.locals.len() - 1)

    # global stuffs
    if vm.globals.contains(identifier.lexeme):
        if isDeclaration:
            reportCompilerError(identifier, "Oops, cannot re-declare identifier '%s'!", identifier.lexeme)
        else:
            return (identifier.lexeme, -1)

    if isDeclaration:
        vm.globalsProfile.add(GlobaLVariable(identifier: identifier.lexeme, kind: kind, dataKind: valueKind))
        vm.globals[identifier.lexeme] = (uint32)vm.globalsProfile.len() - 1

        return (identifier.lexeme, -1)
    else:
        reportCompilerError(identifier,
            "Oops, global variable '%s' does not exist!", identifier.lexeme)

proc getRule(kind: XueTokenKind): ParseRule =
    const rules = [
        XUE_TOKEN_PLUS: createRule(nil, parseDuo, PREC_TERM),
        XUE_TOKEN_MINUS: createRule(parseMono, parseDuo, PREC_TERM),
        XUE_TOKEN_MULTIPLY: createRule(nil, parseDuo, PREC_FACTOR),
        XUE_TOKEN_DIVIDE: createRule(nil, parseDuo, PREC_FACTOR),
        XUE_TOKEN_MODULO: createRule(nil, parseDuo, PREC_FACTOR),
        XUE_TOKEN_POWER: createRule(nil, parseExponent, PREC_POWER),
        XUE_TOKEN_LESS: createRule(nil, parseDuo, PREC_LOGIC_COMP),
        XUE_TOKEN_LESS_EQUAL: createRule(nil, parseDuo, PREC_LOGIC_COMP),
        XUE_TOKEN_GREATER: createRule(nil, parseDuo, PREC_LOGIC_COMP),
        XUE_TOKEN_GREATER_EQUAL: createRule(nil, parseDuo, PREC_LOGIC_COMP),
        XUE_TOKEN_EQUAL: createRule(nil, parseDuo, PREC_LOGIC_EQUAL),
        XUE_TOKEN_NOT_EQUAL: createRule(nil, parseDuo, PREC_LOGIC_EQUAL),
        XUE_TOKEN_NOT: createRule(parseMono, nil, PREC_NONE),
        XUE_TOKEN_AND: createRule(nil, nil, PREC_LOGIC_AND),
        XUE_TOKEN_OR: createRule(nil, nil, PREC_LOGIC_OR),
        XUE_TOKEN_BIT_NOT: createRule(parseMono, nil, PREC_MONO),
        XUE_TOKEN_BIT_AND: createRule(nil, parseDuo, PREC_BITWISE_AND),
        XUE_TOKEN_BIT_OR: createRule(nil, parseDuo, PREC_BITWISE_OR),
        XUE_TOKEN_BIT_XOR: createRule(nil, parseDuo, PREC_BITWISE_XOR),
        XUE_TOKEN_BIT_LSH: createRule(nil, parseDuo, PREC_BITWISE_SHIFT),
        XUE_TOKEN_BIT_RSH: createRule(nil, parseDuo, PREC_BITWISE_SHIFT),
        XUE_TOKEN_ASSIGN: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_CONCAT: createRule(nil, parseDuo, PREC_TERM),
        XUE_TOKEN_QUESTION: createRule(nil, nil, PREC_TERN),
        XUE_TOKEN_DOT: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_INTERPOLATION: createRule(parseStringInterpolation, nil, PREC_NONE),
        XUE_TOKEN_DART: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ARROW: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_LEFT_PAREN: createRule(parseGrouing, nil, PREC_NONE),
        XUE_TOKEN_RIGHT_PAREN: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_LEFT_SQUARE: createRule(parseGrouing, nil, PREC_NONE),
        XUE_TOKEN_RIGHT_SQURE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_COMMA: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_COLON: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_SEMICOLON: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_NUMBER_TYPE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_BOOLEAN_TYPE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_STRING_TYPE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_NULL_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_NUMBER_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_BOOLEAN_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_STRING_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_IDENTIFIER: createRule(parseIdentifier, nil, PREC_NONE),
        XUE_TOKEN_BEGIN: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_END: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_CLASS: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_EXTENDS: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_SUPER: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_THIS: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ENDCLASS: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_PROC: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ENDPROC: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_RETURN: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_LET: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_CONST: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ECHO: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_WHILE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_FOR: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_UNTIL: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_DO: createRule(nil, nil, PREC_NONE),
        #XUE_TOKEN_DONE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ENDWHILE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ENDFOR: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_BREAK: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_CONTINUE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_IF: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ELSEIF: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ELSE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_THEN: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ENDIF: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_EOF: createRule(nil, nil, PREC_NONE),
    ]
    return rules[kind]

proc expression(): AstNode =
    return parsePrecedence(PREC_ASSIGNMENT)

proc blockStatement() =
    while not check(XUE_TOKEN_END) and not check(XUE_TOKEN_EOF):
        declaration()
    expect(XUE_TOKEN_END, "Oops, expecting 'end' in block statement!")

proc markInitialized(local: int) =
    current.locals[local].scope = current.scope

proc variableDeclaration(kind: VariableKind) =
    let identifier = parseVariable("Oops, expected identifier name!", kind, true)

    if identifier[1] == -1:
        let global = vm.globals[identifier[0]]

        if match(XUE_TOKEN_ASSIGN):
            let op = parser.previous
            let rvalue = expression()
            if vm.globalsProfile[global].dataKind != rvalue.dataKind:
                reportCompilerError(op,
                    "Oops, cannot assign identifier to different data kind!")
        else:
            case vm.globalsProfile[global].dataKind
            of XUE_VALUE_NUMBER:
                writeConstant(currentChunk(), 
                    newXueValue(0), parser.previous.line)
            of XUE_VALUE_STRING:
                writeConstant(currentChunk(), 
                    newXueValue(@[]), parser.previous.line)
            of XUE_VALUE_BOOLEAN:
                writeConstant(currentChunk(), 
                    newXueValue(false), parser.previous.line)
            else:
                assert(false)

        if parser.current.kind == XUE_TOKEN_SEMICOLON:
            advance()
        else:
            vm.globals.del(identifier[0])
            vm.globalsProfile.del(global)
            reportCompilerError(parser.current, "Oops, expecting semicolon in statement!")
        
        # set value to global variable
        if global <= high(uint8):
            emit((uint8)XUE_OP_SET_GLOBAL_1, (uint8)global)
        elif global <= high(uint16):
            emit(XUE_OP_SET_GLOBAL_2)
            emit((uint8)(global and uint32(0xFF)), (uint8)((global shr 8) and uint32(0xFF)))
        elif global <= high(uint32):
            emit(XUE_OP_SET_GLOBAL_4)
            emit((uint8)(global and uint32(0xFF)), (uint8)((global shr 8) and uint32(0xFF)))
            emit((uint8)((global shr 16) and uint32(0xFF)), (uint8)((global shr 24) and uint32(0xFF)))
        else:
            reportCompilerError(parser.previous, "Oops, 32-bit integer overflow!")
        emit(XUE_OP_POP)
    else:
        let local: uint32 = (uint32)identifier[1]

        if match(XUE_TOKEN_ASSIGN):
            let op = parser.previous
            let rvalue = expression()
            if current.locals[local].dataKind != rvalue.dataKind:
                reportCompilerError(op,
                    "Oops, cannot assign identifier to different data kind!")
        else:
            case current.locals[local].dataKind
            of XUE_VALUE_NUMBER:
                writeConstant(currentChunk(), 
                    newXueValue(0), parser.previous.line)
            of XUE_VALUE_STRING:
                writeConstant(currentChunk(), 
                    newXueValue(@[]), parser.previous.line)
            of XUE_VALUE_BOOLEAN:
                writeConstant(currentChunk(), 
                    newXueValue(false), parser.previous.line)
            else:
                assert(false)

        if parser.current.kind == XUE_TOKEN_SEMICOLON:
            advance()
        else:
            current.locals.del(identifier[1])
            reportCompilerError(parser.current, "Oops, expecting semicolon in statement!")
        
        # set value to global variable
        if local <= high(uint8):
            emit((uint8)XUE_OP_SET_LOCAL_1, (uint8)local)
        elif local <= high(uint16):
            emit(XUE_OP_SET_LOCAL_2)
            emit((uint8)(local and uint32(0xFF)), (uint8)((local shr 8) and uint32(0xFF)))
        elif local <= high(uint32):
            emit(XUE_OP_SET_LOCAL_4)
            emit((uint8)(local and uint32(0xFF)), (uint8)((local shr 8) and uint32(0xFF)))
            emit((uint8)((local shr 16) and uint32(0xFF)), (uint8)((local shr 24) and uint32(0xFF)))
        else:
            reportCompilerError(parser.previous, "Oops, 32-bit integer overflow!")
        markInitialized(identifier[1])

proc expressionStatement() =
    let value = expression()

    expect(XUE_TOKEN_SEMICOLON, "Oops, missing semicolon in statement!")
    if value.kind == NODE_LITERAL:
        let constantIndex: uint32 = (uint32)currentChunk().constant.len() - 1
        discard currentChunk().constant.pop()
        if constantIndex <= high(uint8):
            discard currentChunk().code.pop()
            discard currentChunk().code.pop()
        elif constantIndex <= high(uint16):
            discard currentChunk().code.pop()
            discard currentChunk().code.pop()
            discard currentChunk().code.pop()
        elif constantIndex <= high(uint32):
            discard currentChunk().code.pop()
            discard currentChunk().code.pop()
            discard currentChunk().code.pop()
            discard currentChunk().code.pop()
            discard currentChunk().code.pop()
        else:
            assert(false)
    else:
        emit(XUE_OP_POP)

proc ifStatement() =
    var trueJumps: seq[int]

    #expect(XUE_TOKEN_LEFT_PAREN, "Oops, missing '(' before condition!")
    discard expression()
    #expect(XUE_TOKEN_RIGHT_PAREN, "Oops, missing ')' after condition!")

    var thenJump = emitJump(XUE_OP_JUMP_IF_FALSE)
    emit(XUE_OP_POP)

    if match(XUE_TOKEN_THEN):
        statement()
        let exitJump = emitJump(XUE_OP_JUMP)
        patchJump(thenJump)
        emit(XUE_OP_POP)
        patchJump(exitJump)
    else:
        expect(XUE_TOKEN_COLON, "Oops, expecting ':' next to the condition!")
        # then branch
        while not (check(XUE_TOKEN_ENDIF) or check(XUE_TOKEN_ELSEIF) or 
                check(XUE_TOKEN_ELSE)) and not check(XUE_TOKEN_EOF):
            declaration()
        
        # elseif branches
        while match(XUE_TOKEN_ELSEIF):
            trueJumps.add(emitJump(XUE_OP_JUMP))
            patchJump(thenJump)
            emit(XUE_OP_POP)

            #expect(XUE_TOKEN_LEFT_PAREN, "Oops, missing '(' before condition!")
            discard expression()
            #expect(XUE_TOKEN_RIGHT_PAREN, "Oops, missing ')' after condition!")
            expect(XUE_TOKEN_COLON, "Oops, expecting ':' next to the condition!")

            #expect(XUE_TOKEN_THEN, "Oops, expecting 'then' after elseif!")
            thenJump = emitJump(XUE_OP_JUMP_IF_FALSE)
            emit(XUE_OP_POP)

            while not (check(XUE_TOKEN_ENDIF) or check(XUE_TOKEN_ELSE) or check(XUE_TOKEN_ELSEIF)) and not check(XUE_TOKEN_EOF):
                declaration()
        trueJumps.add(emitJump(XUE_OP_JUMP))
        patchJump(thenJump)
        emit(XUE_OP_POP)

        # else branch
        if match(XUE_TOKEN_ELSE):
            expect(XUE_TOKEN_COLON, "Oops, expecting ':' next to the 'else' word!")
            while not check(XUE_TOKEN_ENDIF) and not check(XUE_TOKEN_EOF):
                declaration()
        expect(XUE_TOKEN_ENDIF, "Oops, missing 'endif' in if statement!")

        # for jmp in countup(0, trueJumps.len() - 2):
        #     patchJump(trueJumps[jmp])
        #     #emit(XUE_OP_POP)
        # patchJump(trueJumps[trueJumps.len() - 1])
        for jmp in trueJumps:
            patchJump(jmp)

proc printStatement() =
    discard expression()
    expect(XUE_TOKEN_SEMICOLON, "Oops, missing semicolon in echo statement!")
    emit(XUE_OP_ECHO)

var innermostLoopStart = -1;
var innermostBreakJump = -1;
var innermostLoopScope = 0;

proc whileStatement() =
    let surroundingLoopStart = innermostLoopStart
    let surroundingLoopScope = innermostLoopScope
    let surroundingBreakJump = innermostBreakJump

    innermostLoopStart = currentChunk().code.len()
    discard expression()

    var exitJump = emitJump(XUE_OP_JUMP_IF_FALSE)
    emit(XUE_OP_POP)

    if match(XUE_TOKEN_DO):
        statement()
    else:
        expect(XUE_TOKEN_COLON, "Oops, expecting ':' next to the condition!")
        while not check(XUE_TOKEN_ENDWHILE) and not check(XUE_TOKEN_EOF):
            declaration()
        expect(XUE_TOKEN_ENDWHILE, "Oops, expecting 'endwhile' in while statement!")

    emitLoop((uint32)innermostLoopStart)
    patchJump(exitJump)
    emit(XUE_OP_POP)

    if innermostBreakJump != -1:
        patchJump(innermostBreakJump)

    innermostLoopStart = surroundingLoopStart
    innermostLoopScope = surroundingLoopScope
    innermostBreakJump = surroundingBreakJump

proc forStatement() =
    beginScope()

    if match(XUE_TOKEN_SEMICOLON):
        discard
    elif match(XUE_TOKEN_LET):
        variableDeclaration(VARIABLE_MUTABLE)
    else:
        expressionStatement()

    let surroundingLoopStart = innermostLoopStart
    let surroundingLoopScope = innermostLoopScope
    let surroundingBreakJump = innermostBreakJump

    innermostLoopScope = current.scope
    innermostLoopStart = currentChunk().code.len()

    var exitJump = -1
    if not match(XUE_TOKEN_SEMICOLON):
        discard expression()
        expect(XUE_TOKEN_SEMICOLON,
            "Oops, missing semicolon next to the condition!")

        exitJump = emitJump(XUE_OP_JUMP_IF_FALSE)
        emit(XUE_OP_POP)

    var delimiter: XueToken
    if (not match(XUE_TOKEN_DO)) and not match(XUE_TOKEN_COLON):
        let loopInst = emitJump(XUE_OP_JUMP)
        let incrementStart = currentChunk().code.len()

        discard expression()
        emit(XUE_OP_POP)
        if (not match(XUE_TOKEN_DO)) and not match(XUE_TOKEN_COLON):
            reportCompilerError(parser.current, "Oops, missing ':' or 'do' in loop!")
        delimiter = parser.previous

        emitLoop((uint32)innermostLoopStart)
        innermostLoopStart = incrementStart
        patchJump(loopInst)

    if delimiter.kind == XUE_TOKEN_DO:
        statement()
    else:
        while not check(XUE_TOKEN_ENDFOR) and not check(XUE_TOKEN_EOF):
            declaration()
        expect(XUE_TOKEN_ENDFOR, "Oops, expecting 'endfor' after loop!")
    emitLoop((uint32)innermostLoopStart)

    if exitJump != -1:
        patchJump(exitJump)
        emit(XUE_OP_POP)
    
    if innermostBreakJump != -1:
        patchJump(innermostBreakJump)

    innermostLoopStart = surroundingLoopStart
    innermostLoopScope = surroundingLoopScope
    innermostBreakJump = surroundingBreakJump

    endScope()

proc breakStatement() =
    if innermostLoopStart == -1:
        reportCompilerError(parser.previous,
            "Oops, cannot use 'break' outside of a loop!")
    expect(XUE_TOKEN_SEMICOLON, "Oops, expecting a semicolon!")

    if current.locals.len() > 0:
        var i = current.locals.len() - 1
        while i >= 0 and current.locals[i].scope > innermostLoopScope:
            emit(XUE_OP_POP)
            i.inc()
    innermostBreakJump = emitJump(XUE_OP_JUMP)

proc continueStatement() =
    if innermostLoopStart == -1:
        reportCompilerError(parser.previous,
            "Oops, cannot use 'break' outside of a loop!")
    expect(XUE_TOKEN_SEMICOLON, "Oops, expecting a semicolon!")

    if current.locals.len() > 0:
        var i = current.locals.len() - 1
        while i >= 0 and current.locals[i].scope > innermostLoopScope:
            emit(XUE_OP_POP)
            i.inc()
    
    emitLoop((uint32)innermostLoopStart)

proc statement() =
    if match(XUE_TOKEN_ECHO):
        printStatement()
    elif match(XUE_TOKEN_IF):
        ifStatement()
    elif match(XUE_TOKEN_WHILE):
        whileStatement()
    elif match(XUE_TOKEN_FOR):
        forStatement()
    elif match(XUE_TOKEN_BREAK):
        breakStatement()
    elif match(XUE_TOKEN_CONTINUE):
        continueStatement()
    elif match(XUE_TOKEN_BEGIN):
        beginScope()
        blockStatement()
        endScope()
    else:
        expressionStatement()

proc declaration() =
    if match(XUE_TOKEN_LET):
        variableDeclaration(VARIABLE_MUTABLE)
    elif match(XUE_TOKEN_CONST):
        variableDeclaration(VARIABLE_CONST)
    else: 
        statement()

#from unicode import `$`

proc XueCompile*(source: string, instruction: ptr XueInstruction): bool =
    initScanner(source)
    compilingChunk = instruction

    var compiler: Compiler
    initCompiler(addr(compiler))

    # while true:
    #     let token = scanToken()
    #     if token.kind == XUE_TOKEN_STRING_LITERAL or
    #             token.kind == XUE_TOKEN_INTERPOLATION:
    #         fprintf(stderr, "[ %s '%s' ]\n", $token.kind, $token.stringValue)
    #     else:
    #         fprintf(stderr, "[ %s '%s' ]\n", $token.kind, token.lexeme)
    #     if token.kind == XUE_TOKEN_EOF:
    #         break
    # return false
    try:
        advance()
        while not match(XUE_TOKEN_EOF):
            declaration()

        endCompiler()
        return true
    except ParserError:
        return false
