from unicode import Rune

type
    XueTokenKind* = enum
        # arithmetic operators
        XUE_TOKEN_PLUS,
        XUE_TOKEN_MINUS,
        XUE_TOKEN_MULTIPLY,
        XUE_TOKEN_DIVIDE,
        XUE_TOKEN_MODULO,
        XUE_TOKEN_POWER,
        # logical operators
        XUE_TOKEN_LESS,
        XUE_TOKEN_LESS_EQUAL,
        XUE_TOKEN_GREATER,
        XUE_TOKEN_GREATER_EQUAL,
        XUE_TOKEN_EQUAL,
        XUE_TOKEN_NOT_EQUAL,
        XUE_TOKEN_NOT,
        XUE_TOKEN_AND,
        XUE_TOKEN_OR,
        # bitwise operators
        XUE_TOKEN_BIT_NOT,
        XUE_TOKEN_BIT_AND,
        XUE_TOKEN_BIT_OR,
        XUE_TOKEN_BIT_XOR,
        XUE_TOKEN_BIT_LSH,
        XUE_TOKEN_BIT_RSH,
        # other operators
        XUE_TOKEN_ASSIGN,
        # XUE_TOKEN_INCREMENT,
        # XUE_TOKEN_DECREMENT,
        XUE_TOKEN_CONCAT,
        XUE_TOKEN_QUESTION,
        XUE_TOKEN_DOT,
        XUE_TOKEN_INTERPOLATION,
        XUE_TOKEN_DART,
        XUE_TOKEN_ARROW,
        # grouping
        XUE_TOKEN_LEFT_PAREN,
        XUE_TOKEN_RIGHT_PAREN,
        XUE_TOKEN_LEFT_SQUARE,
        XUE_TOKEN_RIGHT_SQURE,
        # others
        XUE_TOKEN_COMMA,
        XUE_TOKEN_COLON,
        XUE_TOKEN_SEMICOLON,
        # literals and identifier
        XUE_TOKEN_NUMBER_TYPE,
        XUE_TOKEN_BOOLEAN_TYPE,
        XUE_TOKEN_STRING_TYPE,
        XUE_TOKEN_NULL_LITERAL,
        XUE_TOKEN_NUMBER_LITERAL,
        XUE_TOKEN_BOOLEAN_LITERAL,
        XUE_TOKEN_STRING_LITERAL,
        XUE_TOKEN_IDENTIFIER,
        # reserved words
        XUE_TOKEN_BEGIN,
        XUE_TOKEN_END,
        XUE_TOKEN_CLASS,
        XUE_TOKEN_EXTENDS,
        XUE_TOKEN_SUPER,
        XUE_TOKEN_THIS,
        XUE_TOKEN_ENDCLASS,
        XUE_TOKEN_PROC,
        XUE_TOKEN_ENDPROC,
        XUE_TOKEN_RETURN,
        XUE_TOKEN_LET,
        XUE_TOKEN_CONST,
        XUE_TOKEN_ECHO,
        XUE_TOKEN_WHILE,
        XUE_TOKEN_FOR,
        XUE_TOKEN_UNTIL,
        XUE_TOKEN_DO,
        XUE_TOKEN_ENDWHILE,
        XUE_TOKEN_ENDFOR,
        XUE_TOKEN_BREAK,
        XUE_TOKEN_CONTINUE,
        XUE_TOKEN_IF,
        XUE_TOKEN_ELSEIF,
        XUE_TOKEN_ELSE,
        XUE_TOKEN_THEN,
        XUE_TOKEN_ENDIF
        # nothing
        XUE_TOKEN_EOF,

    XueToken* = ref XueTokenObject

    XueTokenObject = object
        line*: uint32
        column*: uint32
        case kind*: XueTokenKind
        of XUE_TOKEN_STRING_LITERAL, XUE_TOKEN_INTERPOLATION:
            stringValue*: seq[Rune]
        of XUE_TOKEN_NUMBER_LITERAL:
            numberValue*: cdouble
        of XUE_TOKEN_BOOLEAN_LITERAL:
            booleanValue*: bool
        else:
            discard
        lexeme*: string

proc newXueToken*(value: seq[Rune], lexeme: string,
    line: uint32, column: uint32, isStringLiteral: bool = true): owned(XueToken) =
    if isStringLiteral:
        return XueToken(kind: XUE_TOKEN_STRING_LITERAL,
            lexeme: lexeme, line: line, column: column, stringValue: value)
    return XueToken(kind: XUE_TOKEN_INTERPOLATION,
            lexeme: lexeme, line: line, column: column, stringValue: value)

proc newXueToken*(value: cdouble, lexeme: string,
    line: uint32, column: uint32): owned(XueToken) =
    return XueToken(kind: XUE_TOKEN_NUMBER_LITERAL, 
        lexeme: lexeme, line: line, column: column, numberValue: value)

proc newXueToken*(value: bool, lexeme: string,
    line: uint32, column: uint32): owned(XueToken) =
    return XueToken(kind: XUE_TOKEN_BOOLEAN_LITERAL, 
        lexeme: lexeme, line: line, column: column, booleanValue: value)

proc newXueToken*(kind: XueTokenKind, lexeme: string,
    line: uint32, column: uint32): owned(XueToken) =
    return XueToken(kind: kind, lexeme: lexeme, line: line, column: column)