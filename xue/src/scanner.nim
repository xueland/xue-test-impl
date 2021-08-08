from unicode import Rune
from tables import toTable, contains, `[]`
from strutils import splitLines, spaces, strip, parseFloat, parseBool, parseInt
import "./config"
import "./token"
import "./utils"

type
    XueScanner* = object
        source: string
        scriptName: string
        sourceLength: int

        start, current: int
        line, column: int
        parens: array[MAX_INTERPOLATION_NESTING, int]
        numParens: int

    XueScannerError* = object of CatchableError

var scanner: XueScanner

proc initXueScanner*(source: string, scriptName: string) =
    scanner.source = source
    scanner.scriptName = scriptName
    scanner.sourceLength = source.len() # just pre-computing.
    scanner.start = 0
    scanner.current = 0
    scanner.line = 1
    scanner.column = 0

export splitLines, spaces, strip

proc showSource*(lineImpl: int, columnImpl: int, hint: string) =
    var
        line = lineImpl
        column = columnImpl

    let lines = splitLines(scanner.source)
    var strippedLineLength = lines[line - 1].strip(false).len() + 1

    if line == lines.len():
        # error at EOF, so go back
        while lines[line - 1].strip(false) == "":
            line.dec()
            column = lines[line - 1].strip(false).len() + 1
            strippedLineLength = column
    # trailing spaces
    if column > strippedLineLength: column = strippedLineLength

    fprintf(stderr, "\n")
    fprintf(stderr, "\e[31mcan't compile - \e[33m%s:%u:%u: \e[0m\n\n", scanner.scriptName,
            line, column)

    if line > 1:
        fprintf(stderr, "\e[90m%4d |\e[0m %s\n", line - 1, lines[line - 2])

    fprintf(stderr, "\e[90m%4d |\e[0m %s\n", line, lines[line - 1])
    if hint == "":
        fprintf(stderr, "     \e[90m|\e[0m %s\e[33m^ check around here!\e[0m\n", spaces(column - 1))
    else:
        fprintf(stderr, "     \e[90m|\e[0m %s\e[33m^ %s!\e[0m\n", 
            spaces(column - 1), hint)

    if line < lines.len():
        fprintf(stderr, "\e[90m%4d |\e[0m %s\n", line + 1, lines[line])

template reportFrontendError*(exception: typedesc, line: int, column: int,
        hint: string, format: string, args) =
    showSource(line, column, hint)

    fprintf(stderr, "\n\e[31mreported message:\e[0m ")
    fprintf(stderr, format, args)
    fprintf(stderr, "\n\n")
    raise newException(exception, "")

template reportFrontendError*(exception: typedesc, line: int, column: int, 
        hint: string, format: string) =
    showSource(line, column, hint)

    fprintf(stderr, "\n\e[31mreported message:\e[0m ")
    fprintf(stderr, format)
    fprintf(stderr, "\n\n")
    raise newException(exception, "")

proc token(kind: XueTokenKind): XueToken =
    return newXueToken(kind, scanner.source.substr(scanner.start, scanner.current - 1),
        scanner.line, scanner.column)

proc isEOF(): bool {.inline.} =
    return scanner.current >= scanner.sourceLength

proc advance(): char {.inline.} =
    inc(scanner.current)
    inc(scanner.column)
    return scanner.source[scanner.current - 1]

proc match(expected: char): bool {.inline.} =
    if isEOF(): return false
    if scanner.source[scanner.current] != expected:
        return false
    scanner.current.inc()
    scanner.column.inc()
    return true

proc peek(): char {.inline.} =
    if isEOF():
        return '\0'
    return scanner.source[scanner.current]

proc peekNext(): char {.inline.} =
    if scanner.current + 1 >= scanner.source.len(): return '\0'
    return scanner.source[scanner.current + 1]

proc peekNextNext(): char {.inline.} =
    if scanner.current + 2 >= scanner.source.len(): return '\0'
    return scanner.source[scanner.current + 2]

proc skipNonCodes() =
    while true:
        let c = peek()
        case c
        of ' ', '\r', '\t':
            discard advance()
        of '\n':
            scanner.column = 0
            scanner.line.inc()
            discard advance()
        of '-':
            if peekNext() == '-':
                if peekNextNext() == '-':
                    discard advance() # -
                    discard advance() # -
                    discard advance() # -
                    while not isEOF() and
                        not (peek() == '-' and peekNext() == '-' and 
                            peekNextNext() == '-'):
                        if peek() == '\n':
                            scanner.line.inc()
                            scanner.column = 0
                        discard advance()
                    if isEOF():
                        reportFrontendError(XueScannerError, scanner.line, scanner.column,
                            "add '---' at the end",
                            "Oops, unterminated block comment!")
                    discard advance() # -
                    discard advance() # -
                    discard advance() # -
                else:
                    while peek() != '\n' and not isEOF():
                        discard advance()
            else: return
        of '#':
            while peek() != '\n' and not isEOF():
                discard advance()
        of '<':
            if peekNext() == '-':
                while peek() != '\n' and not isEOF():
                    discard advance()
            else: return
        of '/':
            if peekNext() == '/':
                while peek() != '\n' and not isEOF():
                    discard advance()
            elif peekNext() == '*':
                discard advance()
                discard advance()
                var nesting: int = 1

                while nesting > 0:
                    if isEOF():
                        reportFrontendError(XueScannerError, scanner.line, scanner.column,
                            "add '*/' at the end",
                            "Oops, unterminated block comment")
                    if peek() == '/' and peekNext() == '*':
                        discard advance()
                        discard advance()
                        nesting.inc()
                        continue
                    if peek() == '*' and peekNext() == '/':
                        discard advance()
                        discard advance()
                        nesting.dec()
                        continue
                    if peek() == '\n':
                        scanner.line.inc()
                        scanner.column = 0
                    discard advance()
            else: return
        else: return

proc makeRawString(): XueToken =
    var 
        userString: seq[Rune]
        shouldEscape: bool = false
    const escapeMap = {'\'': '\'', '\\': '\\'}.toTable()

    while (peek() != '\'' or shouldEscape) and not isEOF():
        let c = peek()
        if c == '\n':
            reportFrontendError(XueScannerError, scanner.line, scanner.column, 
                "add ' before the new-line", "Oops, unterminated string!")

        if shouldEscape:
            if escapeMap.contains(c):
                userString.add((Rune)escapeMap[c])
            else:
                userString.add((Rune)'\\')
                userString.add((Rune)c)
            shouldEscape = false
        elif c == '\\':
            shouldEscape = true
        else:
            userString.add((Rune)c)
        discard advance()

    if isEOF():
        reportFrontendError(XueScannerError, scanner.line, scanner.column, 
            "add ' at the end of string", "Oops, unterminated string!")
    discard advance() # closing quote '

    shallow(userString)
    return newXueStringToken(userString, 
        scanner.source.substr(scanner.start, scanner.current - 1), 
            scanner.line, scanner.column, true)

proc makeString(): XueToken =
    var userString: seq[Rune]
    var shouldEscape: bool = false
    var kind: XueTokenKind = XUE_TOKEN_STRING_LITERAL

    const escapeMap = {
        '"': '"',
        '%': '%',
        '0': '\0',
        'a': '\a',
        'b': '\b',
        'e': '\e',
        'f': '\f',
        'n': '\n',
        'r': '\r',
        't': '\t',
        'v': '\v',
        '\\': '\\'
    }.toTable()

    while (peek() != '"' or shouldEscape) and not isEOF():
        let c = peek()
        if c == '\n':
            reportFrontendError(XueScannerError, scanner.line, scanner.column, 
                "add \" before the new-line", "Oops, unterminated string!")

        if shouldEscape:
            if escapeMap.contains(c):
                userString.add((Rune)escapeMap[c])
            else:
                userString.add((Rune)'\\')
                userString.add((Rune)c)
            shouldEscape = false
        elif c == '%':
            discard advance()
            if scanner.numParens < MAX_INTERPOLATION_NESTING:
                if peek() != '(':
                    reportFrontendError(XueScannerError, scanner.line, scanner.column,
                        "add '(' if u want to interpolate string",
                            "Oops, I was expecting '%(expression)'!")
                scanner.parens[scanner.numParens] = 1
                scanner.numParens.inc()
                kind = XUE_TOKEN_INTERPOLATION
                break
            reportFrontendError(XueScannerError, scanner.line, scanner.column, "",
                "Oops, XueLand, now, supports interpolation for just '%d' nesting level!",
                    MAX_INTERPOLATION_NESTING)
        elif c == '\\':
            shouldEscape = true
        else:
            userString.add((Rune)c)
        discard advance()

    if isEOF():
        reportFrontendError(XueScannerError, scanner.line, scanner.column, 
            "add \" at the end of string", "Oops, unterminated string!")
    discard advance() # closing quote '

    shallow(userString)
    return newXueStringToken(userString, 
        scanner.source.substr(scanner.start, scanner.current - 1), 
            scanner.line, scanner.column, kind == XUE_TOKEN_STRING_LITERAL)

proc isdigit(c: char): bool {.inline.} =
    return c >= '0' and c <= '9'

proc isalpha(c: char): bool {.inline.} =
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        ['$', '_'].contains(c)

proc detectReserved(): XueToken =
    let lexeme = scanner.source.substr(scanner.start, scanner.current - 1)

    const reservedWord = {
        "mod": XUE_TOKEN_MODULO,
        "pow": XUE_TOKEN_POWER,
        "is": XUE_TOKEN_EQUAL,
        "isnot": XUE_TOKEN_NOT_EQUAL,
        "not": XUE_TOKEN_NOT,
        "and": XUE_TOKEN_AND,
        "or": XUE_TOKEN_OR,
        "be": XUE_TOKEN_ASSIGN,
        "begin": XUE_TOKEN_BEGIN,
        "end": XUE_TOKEN_END,
        "class": XUE_TOKEN_CLASS,
        "extends": XUE_TOKEN_EXTENDS,
        "super": XUE_TOKEN_SUPER,
        "this": XUE_TOKEN_THIS,
        "endclass": XUE_TOKEN_ENDCLASS,
        "proc": XUE_TOKEN_PROC,
        "return": XUE_TOKEN_RETURN,
        "endproc": XUE_TOKEN_ENDPROC,
        "let": XUE_TOKEN_LET,
        "const": XUE_TOKEN_CONST,
        "echo": XUE_TOKEN_ECHO,
        "while": XUE_TOKEN_WHILE,
        "for": XUE_TOKEN_FOR,
        "until": XUE_TOKEN_UNTIL,
        "do": XUE_TOKEN_DO,
        "endwhile": XUE_TOKEN_ENDWHILE,
        "endfor": XUE_TOKEN_ENDFOR,
        "break": XUE_TOKEN_BREAK,
        "continue": XUE_TOKEN_CONTINUE,
        "if": XUE_TOKEN_IF,
        "elseif": XUE_TOKEN_ELSEIF,
        "else": XUE_TOKEN_ELSE,
        "then": XUE_TOKEN_THEN,
        "endif": XUE_TOKEN_ENDIF,
        "null": XUE_TOKEN_NULL_LITERAL,
        "true": XUE_TOKEN_BOOLEAN_LITERAL,
        "false": XUE_TOKEN_BOOLEAN_LITERAL,
        "on": XUE_TOKEN_BOOLEAN_LITERAL,
        "off": XUE_TOKEN_BOOLEAN_LITERAL,
        "NaN": XUE_TOKEN_NUMBER_LITERAL,
        "INF": XUE_TOKEN_NUMBER_LITERAL,
    }.toTable()

    if reservedWord.contains(lexeme):
        let kind = reservedWord[lexeme]
        if kind == XUE_TOKEN_BOOLEAN_LITERAL:
            return newXueBooleanToken(parseBool(lexeme), lexeme, scanner.line, scanner.column)
        elif kind == XUE_TOKEN_NUMBER_LITERAL:
            return newXueNumberToken(parseFloat(lexeme), lexeme, scanner.line, scanner.column)
        elif kind == XUE_TOKEN_NULL_LITERAL:
            return newXueNullToken(lexeme, scanner.line, scanner.column)
        else:
            return token(kind)
    return token(XUE_TOKEN_IDENTIFIER)

proc makeIdentifier(): XueToken =
    while isalpha(peek()) or isdigit(peek()):
        discard advance()
    return detectReserved()

proc makeNumber(): XueToken =
    while isdigit(peek()):
        discard advance()

    if peek() == '.' and isdigit(peekNext()):
        discard advance()
        while isdigit(peek()):
            discard advance()
        let lexeme = scanner.source.substr(scanner.start, scanner.current - 1)
        return newXueNumberToken(parseFloat(lexeme), lexeme, scanner.line, scanner.column)

    var lexeme = scanner.source.substr(scanner.start, scanner.current - 1)
    shallow(lexeme)
    return newXueNumberToken(parseInt(lexeme), lexeme, scanner.line, scanner.column)

proc scanXueToken*(): XueToken =
    skipNonCodes()
    scanner.start = scanner.current

    if isEOF(): return token(XUE_TOKEN_EOF)

    let c: char = advance()

    if isalpha(c): return makeIdentifier()
    if isdigit(c): return makeNumber()

    case c
    of '+':
        return token(XUE_TOKEN_PLUS)
    of '-':
        return token(if match('>'): XUE_TOKEN_DART else: XUE_TOKEN_MINUS)
    of '*':
        return token(if match('*'): XUE_TOKEN_POWER else: XUE_TOKEN_MULTIPLY)
    of '/':
        return token(XUE_TOKEN_DIVIDE)
    of '%':
        return token(XUE_TOKEN_MODULO)
    of '<':
        if match('>'):
            return token(XUE_TOKEN_NOT_EQUAL)
        if match('='):
            return token(XUE_TOKEN_LESS_EQUAL)
        if match('<'):
            return token(XUE_TOKEN_BIT_LSH)
        return token(XUE_TOKEN_LESS)
    of '>':
        if match('='):
            return token(XUE_TOKEN_GREATER_EQUAL)
        if match('>'):
            return token(XUE_TOKEN_BIT_RSH)
        return token(XUE_TOKEN_GREATER)
    of '=':
        if match('='):
            return token(XUE_TOKEN_EQUAL)
        if match('>'):
            return token(XUE_TOKEN_ARROW)
        return token(XUE_TOKEN_ASSIGN)
    of '!':
        return token(if match('='): XUE_TOKEN_NOT_EQUAL else: XUE_TOKEN_NOT)
    of '~':
        return token(XUE_TOKEN_BIT_NOT)
    of '&':
        return token(if match('&'): XUE_TOKEN_AND else: XUE_TOKEN_BIT_AND)
    of '|':
        return token(if match('|'): XUE_TOKEN_OR else: XUE_TOKEN_BIT_OR)
    of '^':
        return token(XUE_TOKEN_BIT_XOR)
    of '?':
        return token(XUE_TOKEN_QUESTION)
    of '.':
        return token(if match('.'): XUE_TOKEN_CONCAT else: XUE_TOKEN_DOT)
    of '(':
        if scanner.numParens > 0:
            scanner.parens[scanner.numParens - 1].inc()
        return token(XUE_TOKEN_LEFT_PAREN)
    of ')':
        if scanner.numParens > 0:
            scanner.parens[scanner.numParens - 1].dec()
            if scanner.parens[scanner.numParens - 1] == 0:
                scanner.numParens.dec()
                return makeString()
        return token(XUE_TOKEN_RIGHT_PAREN)
    of '[':
        return token(XUE_TOKEN_LEFT_PAREN)
    of ']':
        return token(XUE_TOKEN_RIGHT_PAREN)
    of ',':
        return token(XUE_TOKEN_COMMA)
    of ':':
        return token(XUE_TOKEN_COLON)
    of ';':
        return token(XUE_TOKEN_SEMICOLON)
    of '\'':
        return makeRawString()
    of '"': return makeString()
    else:
        reportFrontendError(XueScannerError, scanner.line, scanner.column, "",
                    "Oops, unrecognized character '%c'!", c)
