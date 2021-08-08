from tables import Table, `[]`, `[]=`, contains, len, keys
from os import dirExists, fileExists, splitFile, joinPath
import "./config"
import "./token"
import "./scanner"
import "./core"
import "./utils"
import "./engine"
import "./xue2bin"

type
    XueParser = object
        previous: XueToken
        current: XueToken

    XueFunctionKind = enum
        FUNCTION_SCRIPT,
        FUNCTION_USER_DEFINED,

    XueLocal = object
        identifier: string
        mutable: bool
        scope: int
        case returnKind: XueValueKind
        of XUE_VALUE_OBJECT:
            returnObjectKind: XueObjectKind
        else:
            discard

    XueGlobal = object
        identifier: string
        mutable: bool
        case returnKind: XueValueKind
        of XUE_VALUE_OBJECT:
            returnObjectKind: XueObjectKind
        else:
            discard
        valueIndex: int

    XueCompiler {.acyclic.} = object
        enclosing: ptr XueCompiler
        function: XueValueFunction
        kind: XueFunctionKind
        locals: seq[XueLocal]
        currentScope: int

    XueParserError = object of CatchableError

    XueNodeStat = object
        case returnKind: XueValueKind
        of XUE_VALUE_OBJECT:
            returnObjectKind: XueObjectKind
        else:
            discard

    XuePrecedence = enum
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

    XueParserPrefixFn = proc(assignable: bool): XueNodeStat
    XueParserInfixFn = proc(lvalue: XueNodeStat): XueNodeStat

    XueParseRule = object
        prefix: XueParserPrefixFn
        infix: XueParserInfixFn
        precedence: XuePrecedence

var globals: Table[string, XueGlobal]
var parser: XueParser
var current: ptr XueCompiler = nil

proc currentChunk(): ptr XueChunk =
    return addr(current.function.functionChunk)

# #########################################################

template reportCompilerError(token: XueToken, hint: string, message: string) =
    reportFrontendError(XueParserError, token.line, token.column, hint, message)

proc advance() =
    parser.previous = parser.current
    parser.current = scanXueToken()

proc check(kind: XueTokenKind): bool {.inline.} =
    return parser.current.kind == kind

proc match(kinds: varargs[XueTokenKind]): bool {.inline.} =
    for kind in kinds:
        if check(kind):
            advance()
            return true
    return false

proc expect(kind: XueTokenKind, hint: string, message: string) =
    if parser.current.kind == kind:
        advance()
        return
    reportFrontendError(XueParserError, parser.current.line, parser.current.column, hint, message)

########################################################################

proc expression(): XueNodeStat
proc statement()
proc declaration()
proc getRule(kind: XueTokenKind): XueParseRule
proc parsePrecedence(precedence: XuePrecedence): XueNodeStat

proc emit(line: int, u8: uint8 | XueOpCode) =
    currentChunk().writeOpCodeXueChunk((uint8)u8, line)

proc emitReturn() =
    writeConstantXueChunk(currentChunk(), newXueValueNull(), parser.previous.line)
    emit(parser.previous.line, XUE_OP_RETURN)

proc initXueCompiler(compiler: ptr XueCompiler, kind: XueFunctionKind, scriptName: string) =
    compiler.enclosing = current
    compiler.kind = kind
    compiler.function = newXueValueFunction("", scriptName)
    current = compiler

proc endXueCompiler(): XueValueFunction =
    emitReturn()
    let function = current.function

    when XUE_DEBUG_DISASSEM:
        disassembleXueChunk(currentChunk(), if function.functionName == "":
            "main" else: function.functionName)
    current = current.enclosing
    return function

proc beginScope() =
    current.currentScope.inc()

proc endScope() =
    current.currentScope.dec()

    while current.locals.len() > 0 and
            current.locals[^1].scope > current.currentScope:
        emit(parser.previous.line, XUE_OP_POP);
        discard current.locals.pop()

################################################################

proc declareVariable(mutable: bool): (XueToken, int) =
    let identifier = parser.previous
    if current.currentScope > 0:
        for i in countdown(current.locals.len() - 1, 0):
            let local = current.locals[i]
            if local.scope != -1 and local.scope < current.currentScope:
                break
            if identifier.lexeme == local.identifier:
                reportCompilerError(identifier,
                    "rename it to something", "Oops, identifier exists in the scope!")
        current.locals.add(
            XueLocal(identifier: identifier.lexeme, 
                mutable: mutable, scope: -1, returnKind: XUE_VALUE_NULL))
        return (identifier, current.locals.len() - 1)
    else:
        if globals.contains(identifier.lexeme):
            reportCompilerError(identifier,
                    "rename it to something", "Oops, identifier exists in the scope!")
        vm.globals.add(newXueValueNull())
        globals[identifier.lexeme] = XueGlobal(identifier: identifier.lexeme, 
            mutable: mutable, returnKind: XUE_VALUE_NULL, valueIndex: vm.globals.len() - 1)
        return (identifier, -1)

proc parseVariable(errorMessage: string, mutable: bool): (XueToken, int) =
    expect(XUE_TOKEN_IDENTIFIER, "variable must have an identifier", errorMessage)
    return declareVariable(mutable)

################################################################

proc resolveLocal(compiler: ptr XueCompiler, name: XueToken): int =
    if current.currentScope == 0:
        return -1
    for i in countdown(compiler.locals.len() - 1, 0):
        let local = compiler.locals[i]
        if local.identifier == name.lexeme:
            if local.scope == -1:
                reportCompilerError(name, "assign other value", "Oops, cannot read local variable in its own initializer!")
            return i
    return -1

proc namedVariable(name: XueToken, assignable: bool): XueNodeStat =
    let index = resolveLocal(current, name)

    if assignable and match(XUE_TOKEN_ASSIGN): # we got identifier = value;
        let operator = parser.previous
        let rvalue = expression()

        if index == -1:
            if not globals.contains(name.lexeme):
                reportCompilerError(name, "check identifier", "Oops, identifier does not exists!")
            let global = globals[name.lexeme]

            if not global.mutable:
                reportCompilerError(name, "change 'const' to 'let'", "Oops, can't re-assign value to a constant!")

            emit(operator.line, XUE_OP_SET_GLOBAL)
            let u8s = cast[array[4, uint8]](global.valueIndex)
            for u8 in u8s:
                writeOpCodeXueChunk(currentChunk(), u8, operator.line)
            var nodeStat: XueNodeStat
            nodeStat.returnKind = rvalue.returnKind
            globals[name.lexeme].returnKind = rvalue.returnKind
            if nodeStat.returnKind == XUE_VALUE_OBJECT:
                nodeStat.returnObjectKind = rvalue.returnObjectKind
                globals[name.lexeme].returnObjectKind = rvalue.returnObjectKind
            return nodeStat
        else:
            if not current.locals[index].mutable:
                reportCompilerError(name, "change 'const' to 'let'", "Oops, can't re-assign value to a constant!")

            emit(operator.line, XUE_OP_SET_LOCAL)
            let u8s = cast[array[4, uint8]](index)
            for u8 in u8s:
                writeOpCodeXueChunk(currentChunk(), u8, operator.line)
            var nodeStat: XueNodeStat
            nodeStat.returnKind = rvalue.returnKind
            current.locals[index].returnKind = rvalue.returnKind
            if nodeStat.returnKind == XUE_VALUE_OBJECT:
                nodeStat.returnObjectKind = rvalue.returnObjectKind
                current.locals[index].returnObjectKind = rvalue.returnObjectKind
            return nodeStat
    else:
        if index == -1:
            if not globals.contains(name.lexeme):
                reportCompilerError(name, "check identifier", "Oops, identifier does not exists!")
            
            let global = globals[name.lexeme]
            emit(name.line, XUE_OP_GET_GLOBAL)
            let u8s = cast[array[4, uint8]](global.valueIndex)
            for u8 in u8s:
                writeOpCodeXueChunk(currentChunk(), u8, parser.previous.line)
            var nodeStat: XueNodeStat
            nodeStat.returnKind = global.returnKind
            if nodeStat.returnKind == XUE_VALUE_OBJECT:
                nodeStat.returnObjectKind = global.returnObjectKind
            return nodeStat

        emit(name.line, XUE_OP_GET_LOCAL)
        let u8s = cast[array[4, uint8]](index)
        for u8 in u8s:
            writeOpCodeXueChunk(currentChunk(), u8, parser.previous.line)

        var nodeStat: XueNodeStat
        nodeStat.returnKind = current.locals[index].returnKind
        if nodeStat.returnKind == XUE_VALUE_OBJECT:
            nodeStat.returnObjectKind = current.locals[index].returnObjectKind
        return nodeStat

proc getVariable(assignable: bool): XueNodeStat =
    let identifier = parser.previous
    return namedVariable(identifier, assignable)

proc parseGrouing(assignable: bool): XueNodeStat  =
    let enclosing = expression()
    expect(XUE_TOKEN_RIGHT_PAREN, "add ')' at the end of group", "Oops, missing ')' in grouping!")

    if enclosing.returnKind == XUE_VALUE_OBJECT:
        return XueNodeStat(returnKind: XUE_VALUE_OBJECT, returnObjectKind: enclosing.returnObjectKind)
    return XueNodeStat(returnKind: enclosing.returnKind)

proc parseLiteral(assignable: bool): XueNodeStat =
    case parser.previous.kind
    of XUE_TOKEN_NUMBER_LITERAL:
        writeConstantXueChunk(currentChunk(), parser.previous.value, parser.previous.line)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_STRING_LITERAL:
        writeConstantXueChunk(currentChunk(), parser.previous.value, parser.previous.line)
        return XueNodeStat(returnKind: XUE_VALUE_OBJECT, returnObjectKind: XUE_OBJECT_STRING)
    of XUE_TOKEN_BOOLEAN_LITERAL:
        writeConstantXueChunk(currentChunk(), parser.previous.value, parser.previous.line)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_NULL_LITERAL:
        writeConstantXueChunk(currentChunk(), parser.previous.value, parser.previous.line)
        return XueNodeStat(returnKind: XUE_VALUE_NULL)
    else:
        discard
    assert(false)

proc parseStringInterpolation(assignable: bool): XueNodeStat =
    until match(XUE_TOKEN_INTERPOLATION):
        writeConstantXueChunk(currentChunk(), parser.previous.value, parser.previous.line)
        discard expression()
        emit(parser.previous.line, XUE_OP_CONCAT)

    expect(XUE_TOKEN_STRING_LITERAL, "",
        "Oops, I was expecting the end of string interpolation!")
    writeConstantXueChunk(currentChunk(), parser.previous.value, parser.previous.line)
    emit(parser.previous.line, XUE_OP_CONCAT)
    return XueNodeStat(returnKind: XUE_VALUE_OBJECT, returnObjectKind: XUE_OBJECT_STRING)

proc parseDuo(lvalue: XueNodeStat): XueNodeStat  =
    let operator = parser.previous
    let rule: XueParseRule = getRule(operator.kind)
    let rvalue = parsePrecedence((XuePrecedence)(((uint)rule.precedence) + 1))

    {.computedGoto.}
    case operator.kind
    of XUE_TOKEN_PLUS:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't add non-numbers!")
        emit(operator.line, XUE_OP_ADD)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_MINUS:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't subtract non-numbers!")
        emit(operator.line, XUE_OP_SUBTRACT)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_MULTIPLY:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, operands must be numbers in multiplication!")
        emit(operator.line, XUE_OP_MULTIPLY)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_DIVIDE:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't divide non-numbers!")
        emit(operator.line, XUE_OP_DIVIDE)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_MODULO:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate modulo of non-numbers!")
        emit(operator.line, XUE_OP_MODULO)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_LESS:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        emit(operator.line, XUE_OP_LESS)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_LESS_EQUAL:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        emit(operator.line, XUE_OP_LESS_EQUAL)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_GREATER:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        emit(operator.line, XUE_OP_GREATER)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_GREATER_EQUAL:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        emit(operator.line, XUE_OP_GREATER_EQ)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_BIT_AND:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calcluate bitwise and of non-numbers!")
        emit(operator.line, XUE_OP_BIT_AND)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_OR:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate bitwise or of non-numbers!")
        emit(operator.line, XUE_OP_BIT_OR)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_XOR:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate bitwise xor non-numbers!")
        emit(operator.line, XUE_OP_BIT_XOR)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_LSH:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't left shift non-numbers!")
        emit(operator.line, XUE_OP_BIT_LSH)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_RSH:
        if lvalue.returnKind != XUE_VALUE_NUMBER or
                rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't right shift non-numbers!")
        emit(operator.line, XUE_OP_BIT_RSH)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_EQUAL:
        emit(operator.line, XUE_OP_EQUAL)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_NOT_EQUAL:
        emit(operator.line, XUE_OP_NOT_EQUAL)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_CONCAT:
        emit(operator.line, XUE_OP_CONCAT)
        return XueNodeStat(returnKind: XUE_VALUE_OBJECT, returnObjectKind: XUE_OBJECT_STRING)
    else:
        discard
    assert(false)

proc parseMono(assignable: bool): XueNodeStat =
    let operator = parser.previous
    let rvalue = parsePrecedence(PREC_MONO)

    case operator.kind
    of XUE_TOKEN_MINUS:
        if rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't negate a non-number!")
        emit(operator.line, XUE_OP_NEGATE)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_NOT:
        if rvalue.returnKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate the complement of a non-number!")
        emit(operator.line, XUE_OP_BIT_NOT)
        return XueNodeStat(returnKind: XUE_VALUE_NUMBER)
    of XUE_TOKEN_NOT:
        emit(operator.line, XUE_OP_NOT)
        return XueNodeStat(returnKind: XUE_VALUE_BOOLEAN)
    else:
        discard
    assert(false)

proc parseExponent(lvalue: XueNodeStat): XueNodeStat =
    let operator = parser.previous
    let rvalue = parsePrecedence(PREC_POWER)

    if lvalue.returnKind != XUE_VALUE_NUMBER or
            rvalue.returnKind != XUE_VALUE_NUMBER:
        reportCompilerError(operator, "", "Oops, we can't calculate exponent of non-numbers!")
    emit(operator.line, XUE_OP_POWER)
    return XueNodeStat(returnKind: XUE_VALUE_NUMBER)

################################################################

template createRule(prefixFn: XueParserPrefixFn, 
        infixFn: XueParserInfixFn, prec: XuePrecedence): XueParseRule =
    XueParseRule(prefix: prefixFn, infix: infixFn, precedence: prec)

proc parsePrecedence(precedence: XuePrecedence): XueNodeStat =
    var returnNode: XueNodeStat

    advance()
    let prefixRule: XueParserPrefixFn = getRule(parser.previous.kind).prefix
    if prefixRule == nil:
        reportCompilerError(parser.previous, "", "Oops, expecting an expression!")
    
    let assignable = precedence <= PREC_ASSIGNMENT
    returnNode = prefixRule(assignable)

    while precedence <= getRule(parser.current.kind).precedence:
        advance()
        let infixRule: XueParserInfixFn = getRule(parser.previous.kind).infix;
        returnNode = infixRule(returnNode)

    if assignable and match(XUE_TOKEN_ASSIGN):
        reportCompilerError(parser.previous, "", "Oops, cannot assign to non-variables/constants!")

    return returnNode

proc getRule(kind: XueTokenKind): XueParseRule =
    const rules = [
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
        XUE_TOKEN_ENDWHILE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ENDFOR: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_BREAK: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_CONTINUE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_IF: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ELSEIF: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ELSE: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_THEN: createRule(nil, nil, PREC_NONE),
        XUE_TOKEN_ENDIF: createRule(nil, nil, PREC_NONE),
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
        XUE_TOKEN_NULL_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_NUMBER_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_BOOLEAN_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_STRING_LITERAL: createRule(parseLiteral, nil, PREC_NONE),
        XUE_TOKEN_IDENTIFIER: createRule(getVariable, nil, PREC_NONE),
        XUE_TOKEN_EOF: createRule(nil, nil, PREC_NONE),
    ]
    return rules[kind]

proc expression(): XueNodeStat =
    return parsePrecedence(PREC_ASSIGNMENT)

proc variableDeclaration(mutable: bool = true) =
    let variable = parseVariable("Oops, expecting an identifier", mutable)
    if match(XUE_TOKEN_ASSIGN):
        let rvalue = expression()
        if variable[1] != -1:
            current.locals[variable[1]].returnKind = rvalue.returnKind
            if rvalue.returnKind == XUE_VALUE_OBJECT:
                current.locals[variable[1]].returnObjectKind = rvalue.returnObjectKind
        else:
            globals[variable[0].lexeme].returnKind = rvalue.returnKind
            if rvalue.returnKind == XUE_VALUE_OBJECT:
                globals[variable[0].lexeme].returnObjectKind = rvalue.returnObjectKind
    else:
        writeConstantXueChunk(currentChunk(), newXueValueNull(), parser.previous.line)
    expect(XUE_TOKEN_SEMICOLON, "add semicolon at the end", "Oops, expecting ';' at the end of statement!")

    if variable[1] == -1:
        let global = globals[variable[0].lexeme]
        emit(parser.previous.line, XUE_OP_SET_GLOBAL)
        let u8s = cast[array[4, uint8]](global.valueIndex)
        for u8 in u8s:
            writeOpCodeXueChunk(currentChunk(), u8, parser.previous.line)
        emit(parser.previous.line, XUE_OP_POP) # need to POP since statement
    else:
        emit(parser.previous.line, XUE_OP_SET_LOCAL)
        let u8s = cast[array[4, uint8]](variable[1])
        for u8 in u8s:
            writeOpCodeXueChunk(currentChunk(), u8, parser.previous.line)
        # no need to pop -> since local use stack
        current.locals[variable[1]].scope = current.currentScope

proc declaration() =
    if match(XUE_TOKEN_LET):
        variableDeclaration()
    elif match(XUE_TOKEN_CONST):
        variableDeclaration(false)
    else:
        statement()

proc expressionStatement() =
    discard expression()
    expect(XUE_TOKEN_SEMICOLON, "add ';' at the end", 
        "Oops, missing semicolon at the end of statement!")
    emit(parser.previous.line, XUE_OP_POP)

proc echoStatement() =
    let token = parser.previous
    discard expression()

    expect(XUE_TOKEN_SEMICOLON, "add ';' at the end", 
        "Oops, missing semicolon at the end of statement!")
    emit(token.line, XUE_OP_ECHO)

proc normalBlock() =
    while (not check(XUE_TOKEN_END) and not check(XUE_TOKEN_EOF)):
        declaration()

    expect(XUE_TOKEN_END, "add end", "Oops, expecting 'end' in block statement!")

proc statement() =
    if match(XUE_TOKEN_ECHO):
        echoStatement()
    elif match(XUE_TOKEN_BEGIN):
        beginScope()
        normalBlock()
        endScope()
    else:
        expressionStatement()

proc skipErrorTokens() =
    advance()

    while not match(XUE_TOKEN_EOF):
        if parser.previous.kind == XUE_TOKEN_SEMICOLON:
            return
        case parser.current.kind
        of XUE_TOKEN_CLASS,
            XUE_TOKEN_BEGIN,
            XUE_TOKEN_PROC,
            XUE_TOKEN_LET,
            XUE_TOKEN_CONST,
            XUE_TOKEN_ECHO,
            XUE_TOKEN_WHILE,
            XUE_TOKEN_FOR,
            XUE_TOKEN_UNTIL,
            XUE_TOKEN_DO,
            XUE_TOKEN_IF,
            XUE_TOKEN_BREAK,
            XUE_TOKEN_CONTINUE,
            XUE_TOKEN_RETURN:
            return
        else:
            advance()

proc XueCompile*(source: string, scriptName: string): XueValueFunction =
    initXueScanner(source, scriptName)

    var compiler: XueCompiler
    initXueCompiler(addr(compiler), FUNCTION_SCRIPT, scriptName)

    try:
        advance()
        while not match(XUE_TOKEN_EOF):
            declaration()
        return endXueCompiler()
    except XueScannerError, XueParserError:
        skipErrorTokens(); return nil

proc XueInterpret*(source: string, scriptName: string): int =
    let mainScript = XueCompile(source, scriptName)
    return interpret(mainScript)

proc XueCompileToFile*(source: string, scriptName: string, output: string): int =
    let mainScript = XueCompile(source, scriptName)
    var binString: string
    binString = binString & binStringFromXueObject(mainScript)
    binString = binString & binStringFromGlobals(vm.globals)

    if output == "":
        writeFile("a.xcode", binString)
    elif fileExists(output):
        writeFile(output, binString)
    elif dirExists(output):
        let inputName = splitFile(scriptName).name
        writeFile(joinPath(output, inputName & ".xcode"), binString)
    else:
        writeFile(output, binString)
