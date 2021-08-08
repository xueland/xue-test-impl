from unicode import Rune

import "./core"

type
    XueTokenKind* = enum
        # reserved words
        XUE_TOKEN_BEGIN,            # begin
        XUE_TOKEN_END,              # end
        XUE_TOKEN_CLASS,            # class
        XUE_TOKEN_EXTENDS,          # extends, <
        XUE_TOKEN_SUPER,            # super
        XUE_TOKEN_THIS,             # this
        XUE_TOKEN_ENDCLASS,         # endclass
        XUE_TOKEN_PROC,             # proc
        XUE_TOKEN_ENDPROC,          # endproc
        XUE_TOKEN_RETURN,           # return
        XUE_TOKEN_LET,              # let
        XUE_TOKEN_CONST,            # const
        XUE_TOKEN_ECHO,             # echo
        XUE_TOKEN_WHILE,            # while
        XUE_TOKEN_FOR,              # for
        XUE_TOKEN_UNTIL,            # until
        XUE_TOKEN_DO,               # do
        XUE_TOKEN_ENDWHILE,         # endwhile
        XUE_TOKEN_ENDFOR,           # endfor
        XUE_TOKEN_BREAK,            # break
        XUE_TOKEN_CONTINUE,         # continue
        XUE_TOKEN_IF,               # if
        XUE_TOKEN_ELSEIF,           # elseif
        XUE_TOKEN_ELSE,             # else
        XUE_TOKEN_THEN,             # then
        XUE_TOKEN_ENDIF             # endif
        # arithmetic operators
        XUE_TOKEN_PLUS,             # +
        XUE_TOKEN_MINUS,            # -
        XUE_TOKEN_MULTIPLY,         # *
        XUE_TOKEN_DIVIDE,           # /
        XUE_TOKEN_MODULO,           # mod, %
        XUE_TOKEN_POWER,            # pow, **
        # logical operators
        XUE_TOKEN_LESS,             # <
        XUE_TOKEN_LESS_EQUAL,       # <=
        XUE_TOKEN_GREATER,          # >
        XUE_TOKEN_GREATER_EQUAL,    # >=
        XUE_TOKEN_EQUAL,            # is, ==
        XUE_TOKEN_NOT_EQUAL,        # isnot, <>, !=
        XUE_TOKEN_NOT,              # not, !
        XUE_TOKEN_AND,              # and, &&
        XUE_TOKEN_OR,               # or, ||
        # bitwise operators
        XUE_TOKEN_BIT_NOT,          # ~
        XUE_TOKEN_BIT_AND,          # &
        XUE_TOKEN_BIT_OR,           # |
        XUE_TOKEN_BIT_XOR,          # ^
        XUE_TOKEN_BIT_LSH,          # <<
        XUE_TOKEN_BIT_RSH,          # >>
        # other operators
        XUE_TOKEN_ASSIGN,           # be, =
        XUE_TOKEN_CONCAT,           # ..
        XUE_TOKEN_QUESTION,         # ? ( used in expr ? expr : expr )
        XUE_TOKEN_DOT,              # .
        XUE_TOKEN_INTERPOLATION,    # "%(something)"
        XUE_TOKEN_DART,             # -> ( used to access objects' props)
        XUE_TOKEN_ARROW,            # => ( used in map ["a" => 12] )
        # grouping
        XUE_TOKEN_LEFT_PAREN,       # (
        XUE_TOKEN_RIGHT_PAREN,      # )
        XUE_TOKEN_LEFT_SQUARE,      # [
        XUE_TOKEN_RIGHT_SQURE,      # ]
        # others
        XUE_TOKEN_COMMA,            # ,
        XUE_TOKEN_COLON,            # :
        XUE_TOKEN_SEMICOLON,        # ;
        # literals and identifier
        XUE_TOKEN_NULL_LITERAL,     # null
        XUE_TOKEN_NUMBER_LITERAL,   # 1.23, 12, NaN, INF
        XUE_TOKEN_BOOLEAN_LITERAL,  # true, false
        XUE_TOKEN_STRING_LITERAL,   # "string literal", 'string literal too'
        XUE_TOKEN_IDENTIFIER,       # a, _a, _a_, $a, price$amount, xue123
        # nothing
        XUE_TOKEN_EOF,              # \0

    XueToken* {.shallow.} = object
        case kind*: XueTokenKind
        of XUE_TOKEN_NULL_LITERAL, XUE_TOKEN_NUMBER_LITERAL,
                XUE_TOKEN_BOOLEAN_LITERAL, XUE_TOKEN_STRING_LITERAL,
                XUE_TOKEN_INTERPOLATION:
            value*: XueValue
        else:
            discard
        lexeme*: string
        line*, column*: int

proc newXueStringToken*(value: seq[Rune], lexeme: string,
        line, column: int, isLiteral: bool): XueToken =
    let valueString = XueValue(kind: XUE_VALUE_OBJECT, heapedObject: newXueValueString(value))
    if isLiteral:
        return XueToken(kind: XUE_TOKEN_STRING_LITERAL, 
            value: valueString, lexeme: lexeme, line: line, column: column)
    return XueToken(kind: XUE_TOKEN_INTERPOLATION, value: valueString,
        lexeme: lexeme, line: line, column: column)

proc newXueNumberToken*(value: SomeNumber, lexeme: string, line, column: int): XueToken =
    return XueToken(kind: XUE_TOKEN_NUMBER_LITERAL, value: newXueValueNumber(value),
        lexeme: lexeme, line: line, column: column)

proc newXueBooleanToken*(value: bool, lexeme: string, line, column: int): XueToken =
    return XueToken(kind: XUE_TOKEN_BOOLEAN_LITERAL, value: newXueValueBoolean(value),
        lexeme: lexeme, line: line, column: column)

proc newXueNullToken*(lexeme: string, line, column: int): XueToken =
    return XueToken(kind: XUE_TOKEN_NULL_LITERAL, value: newXueValueNull(), 
        lexeme: lexeme, line: line, column: column)

proc newXueToken*(kind: XueTokenKind, lexeme: string, line, column: int): XueToken =
    return XueToken(kind: kind, lexeme: lexeme, line: line, column: column)
