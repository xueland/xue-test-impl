import "../common/config"
import "../common/sintaks"
import "./scanner"
import "./token"
import "./asttree"
import "../interpreter/core"
# from unicode import `$`
import "../common/helper"

type
    XueParser = object
        current*: XueToken
        previous*: XueToken

    ParserError = object of CatchableError

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

    ParserPrefixFn = proc(assignable: bool): XueAstNode
    ParserInfixFn = proc(lvalue: XueAstNode): XueAstNode

    ParseRule = object
        prefix: ParserPrefixFn
        infix: ParserInfixFn
        precedence: Precedence

var parser: XueParser

template reportCompilerError(token: XueToken, hint: string, message: string) =
    reportFrontendError(ParserError, token.line, 
                                    token.column, hint, message)

proc advance() =
    parser.previous = parser.current

    try:
        parser.current = scanToken()
    except:
        raise newException(ParserError, "")

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
    reportFrontendError(ParserError, parser.current.line, parser.current.column, hint, message)

proc expression(): XueAstNode
proc statement(): XueAstNode
proc declaration(): XueAstNode
proc getRule(kind: XueTokenKind): ParseRule
proc parsePrecedence(precedence: Precedence): XueAstNode

proc parseStringInterpolation(assignable: bool): XueAstNode  =
    var lvalue: XueAstNode
    until match(XUE_TOKEN_INTERPOLATION):
        lvalue = newXueLiteralNode(parser.previous, XUE_VALUE_STRING)
        let rvalue = expression()
        lvalue = newXueDuoOpNode(lvalue,
            newXueToken(XUE_TOKEN_CONCAT, "", 0, 0), rvalue, XUE_VALUE_STRING)

    expect(XUE_TOKEN_STRING_LITERAL, "", "Oops, I was expecting the end of string interpolation!")
    let rest = newXueLiteralNode(parser.previous, XUE_VALUE_STRING)
    return newXueDuoOpNode(lvalue,
            newXueToken(XUE_TOKEN_CONCAT, "", 0, 0), rest, XUE_VALUE_STRING)

proc parseDuo(lvalue: XueAstNode): XueAstNode  =
    let operator = parser.previous
    let rule: ParseRule = getRule(operator.kind)
    let rvalue = parsePrecedence((Precedence)(((uint)rule.precedence) + 1))

    {.computedGoto.}
    case operator.kind
    of XUE_TOKEN_PLUS:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't add non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_MINUS:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't subtract non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_MULTIPLY:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, operands must be numbers in multiplication!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_DIVIDE:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't divide non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_MODULO:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate modulo of non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_LESS:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_LESS_EQUAL:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_GREATER:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_GREATER_EQUAL:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't compare non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_BIT_AND:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calcluate bitwise and of non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_OR:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate bitwise or of non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_XOR:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate bitwise xor non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_LSH:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't left shift non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_RSH:
        if lvalue.dataKind != XUE_VALUE_NUMBER or
                rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't right shift non-numbers!")
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_EQUAL:
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_STRING)
    of XUE_TOKEN_NOT_EQUAL:
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_STRING)
    of XUE_TOKEN_CONCAT:
        return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_STRING)
    else:
        assert(false)

proc parseGrouing(assignable: bool): XueAstNode  =
    let enclosing = expression()
    expect(XUE_TOKEN_RIGHT_PAREN, "add ')' at the end of group", "Oops, missing ')' in grouping!")
    return newXueGroupingNode(enclosing, enclosing.dataKind)

proc parseLiteral(assignable: bool): XueAstNode  =
    case parser.previous.kind
    of XUE_TOKEN_NUMBER_LITERAL:
        return newXueLiteralNode(parser.previous, XUE_VALUE_NUMBER)
    of XUE_TOKEN_STRING_LITERAL:
        return newXueLiteralNode(parser.previous, XUE_VALUE_STRING)
    of XUE_TOKEN_BOOLEAN_LITERAL:
        return newXueLiteralNode(parser.previous, XUE_VALUE_BOOLEAN)
    of XUE_TOKEN_NULL_LITERAL:
        return newXueLiteralNode(parser.previous, XUE_VALUE_NULL)
    else:
        assert(false)

proc parseMono(assignable: bool): XueAstNode  =
    let operator = parser.previous

    let rvalue = parsePrecedence(PREC_MONO)

    case operator.kind
    of XUE_TOKEN_MINUS:
        if rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't negate a non-number!")
        return newXueMonoOpNode(operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_BIT_NOT:
        if rvalue.dataKind != XUE_VALUE_NUMBER:
            reportCompilerError(operator, "",
                "Oops, we can't calculate the complement of a non-number!")
        return newXueMonoOpNode(operator, rvalue, XUE_VALUE_NUMBER)
    of XUE_TOKEN_NOT:
        return newXueMonoOpNode(operator, rvalue, XUE_VALUE_NUMBER)
    else:
        assert(false)

proc parseExponent(lvalue: XueAstNode): XueAstNode  =
    let operator = parser.previous

    let rvalue = parsePrecedence(PREC_POWER)
    if lvalue.dataKind != XUE_VALUE_NUMBER or
            rvalue.dataKind != XUE_VALUE_NUMBER:
        reportCompilerError(operator, "",
            "Oops, we can't calculate exponent of non-numbers!")
    return newXueDuoOpNode(lvalue, operator, rvalue, XUE_VALUE_NUMBER)

template createRule(prefixFn: ParserPrefixFn, 
        infixFn: ParserInfixFn, prec: Precedence): ParseRule =
    ParseRule(prefix: prefixFn, infix: infixFn, precedence: prec)

proc parsePrecedence(precedence: Precedence): XueAstNode =
    var returnNode: XueAstNode

    advance()
    let prefixRule: ParserPrefixFn = getRule(parser.previous.kind).prefix
    if prefixRule == nil:
        reportCompilerError(parser.previous, "", "Oops, expecting an expression!")
    
    let assignable = precedence <= PREC_ASSIGNMENT
    returnNode = prefixRule(assignable)

    while precedence <= getRule(parser.current.kind).precedence:
        advance()
        let infixRule: ParserInfixFn = getRule(parser.previous.kind).infix;
        returnNode = infixRule(returnNode)

    return returnNode

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
        XUE_TOKEN_IDENTIFIER: createRule(nil, nil, PREC_NONE),
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
        XUE_TOKEN_EOF: createRule(nil, nil, PREC_NONE),
    ]
    return rules[kind]
endproc

proc expression(): XueAstNode =
    return parsePrecedence(PREC_ASSIGNMENT)
endproc

proc expressionStatement(): XueAstNode =
    let expression = expression()
    expect(XUE_TOKEN_SEMICOLON, "add ';' at the end", 
        "Oops, missing semicolon at the end of statement!")

    when OPTIMIZE_WHEN_COMPILE:
        if expression.kind == XUE_NODE_LITERAL:
            return nil
    return newXueExpressionStatement(expression, parser.previous)

proc echoStatement(): XueAstNode =
    let token = parser.previous
    let value = expression()
    expect(XUE_TOKEN_SEMICOLON, "add ';' at the end", 
        "Oops, missing semicolon at the end of statement!")
    return newXueEchoStatement(value, token)

proc declaration(): XueAstNode =
    return statement()

proc statement(): XueAstNode =
    if match(XUE_TOKEN_ECHO):
        return echoStatement()
    else:
        return expressionStatement()

proc parse*(source: string, scriptName: string): (bool, seq[XueAstNode]) =
    initScanner(source, scriptName)

    # try:
    #     while true:
    #         let token = scanToken()
    #         if token.kind == XUE_TOKEN_STRING_LITERAL or
    #                 token.kind == XUE_TOKEN_INTERPOLATION:
    #             fprintf(stderr, "[ %s '%s' ]\n", $token.kind, $token.stringValue)
    #         else:
    #             fprintf(stderr, "[ %s '%s' ]\n", $token.kind, token.lexeme)
    #         if token.kind == XUE_TOKEN_EOF:
    #             break
    #         endif
    #     endwhile
    # except ScannerError:
    #     return nil

    var statements: seq[XueAstNode] = @[]

    try:
        advance()
        while not match(XUE_TOKEN_EOF):
            statements.add(declaration())

        return (true, statements)
    except ParserError:
        return (false, @[])
endproc
