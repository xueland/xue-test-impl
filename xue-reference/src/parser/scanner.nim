from unicode import Rune
from tables import toTable, `[]`, contains
from strutils import parseFloat, splitLines, spaces, strip
import "../common/config"
import "../common/helper"
import "../common/sintaks"
import "./token"

type
    Scanner = object
        source: string
        scriptName: string

        start: int
        current: int
        line: uint32
        column: uint32

        parens: array[MAX_INTERPOLATION_NESTING, int]
        numParens: int

    ScannerError* = object of CatchableError

var scanner: Scanner

proc initScanner*(source: string, scriptName: string) =
    scanner.source = source
    scanner.scriptName = scriptName
    scanner.start = 0
    scanner.current = 0
    scanner.line = 1
    scanner.column = 0
endproc

export splitLines, spaces, strip
template showSource*(line: uint32, column: uint32, hint: string) =
    let lines = splitLines(scanner.source)
    var strippedLineLength = (uint32)lines[line - 1].strip(false).len() + 1

    if line == (uint32)lines.len():
        # error at EOF, so go back
        while lines[line - 1].strip(false) == "":
            line.dec()
            column = (uint32)lines[line - 1].strip(false).len() + 1
            strippedLineLength = column
        endwhile
    endif
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

    if line < (uint32)lines.len():
        fprintf(stderr, "\e[90m%4d |\e[0m %s\n", line + 1, lines[line])
endtemplate

template reportFrontendError*(exception: typedesc, line: uint32, column: uint32,
        hint: string, format: string, args) =
    showSource(line, column, hint)

    fprintf(stderr, "\n\e[31mreported message:\e[0m ")
    fprintf(stderr, format, args)
    fprintf(stderr, "\n\n")
    raise newException(exception, "")
endtemplate

template reportFrontendError*(exception: typedesc, line: uint32, column: uint32, 
        hint: string, format: string) =
    showSource(line, column, hint)

    fprintf(stderr, "\n\e[31mreported message:\e[0m ")
    fprintf(stderr, format)
    fprintf(stderr, "\n\n")
    raise newException(exception, "")
endtemplate

proc makeToken(kind: XueTokenKind): XueToken =
    return newXueToken(kind, scanner.source.substr(scanner.start, scanner.current - 1),
        scanner.line, scanner.column)
endproc

proc isEOF(): bool {.inline.} =
    return scanner.current >= scanner.source.len()
endproc

proc advance(): char {.inline.} =
    scanner.current.inc()
    scanner.column.inc()
    return scanner.source[scanner.current - 1]
endproc

proc match(expected: char): bool {.inline.} =
    if isEOF(): return false
    if scanner.source[scanner.current] != expected:
        return false
    scanner.current.inc()
    scanner.column.inc()
    return true
endproc

proc peek(): char {.inline.} =
    if isEOF():
        return '\0'
    return scanner.source[scanner.current]
endproc

proc peekNext(): char {.inline.} =
    if scanner.current + 1 >= scanner.source.len(): return '\0'
    return scanner.source[scanner.current + 1]
endproc

proc peekNextNext(): char {.inline.} =
    if scanner.current + 2 >= scanner.source.len(): return '\0'
    return scanner.source[scanner.current + 2]
endproc

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
                        reportFrontendError(ScannerError, scanner.line, scanner.column,
                            "add '---' at the end",
                            "Oops, unterminated block comment!")
                    discard advance() # -
                    discard advance() # -
                    discard advance() # -
                else:
                    while peek() != '\n' and not isEOF():
                        discard advance()
                endif
            else:
                return
            endif
        of '#':
            while peek() != '\n' and not isEOF():
                discard advance()
        of '<':
            if peekNext() == '-':
                while peek() != '\n' and not isEOF():
                    discard advance()
            else:
                return
            endif
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
                        reportFrontendError(ScannerError, scanner.line, scanner.column,
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
                endwhile
            else:
                return
            endif
        else:
            return
        endif
endproc

proc makeRawString(): XueToken =
    var userString: seq[Rune]
    var shouldEscape: bool = false

    while (peek() != '\'' or shouldEscape) and not isEOF():
        let c = peek()
        if c == '\n':
            reportFrontendError(ScannerError, scanner.line, scanner.column, 
                "add ' before the new-line", "Oops, unterminated string!")

        if shouldEscape:
            if c == '\'':
                userString.add((Rune)'\'')
            if c == '\\':
                userString.add((Rune)'\\')
            else:
                userString.add((Rune)'\\')
                userString.add((Rune)c)
            shouldEscape = false
        elif c == '\\':
            shouldEscape = true
        else:
            userString.add((Rune)c)
        endif
        discard advance()

    if isEOF():
        reportFrontendError(ScannerError, scanner.line, scanner.column, 
            "add ' at the end of string", "Oops, unterminated string!")
    discard advance() # closing quote '

    shallow(userString)
    return newXueToken(userString, 
        scanner.source.substr(scanner.start, scanner.current - 1), 
            scanner.line, scanner.column)
endproc

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
            reportFrontendError(ScannerError, scanner.line, scanner.column, 
                "add \" before the new-line", "Oops, unterminated string!")

        if shouldEscape:
            if escapeMap.contains(c):
                userString.add((Rune)escapeMap[c])
            else:
                userString.add((Rune)'\\')
                userString.add((Rune)c)
            endif
            shouldEscape = false
        elif c == '%':
            discard advance()
            if scanner.numParens < MAX_INTERPOLATION_NESTING:
                if peek() != '(':
                    reportFrontendError(ScannerError, scanner.line, scanner.column,
                        "add '(' if u want to interpolate string",
                            "Oops, I was expecting '%(expression)'!")
                endif
                scanner.parens[scanner.numParens] = 1
                scanner.numParens.inc()
                kind = XUE_TOKEN_INTERPOLATION
                break
            endif
            reportFrontendError(ScannerError, scanner.line, scanner.column, "",
                "Oops, XueLand, now, supports interpolation for just '%d' nesting level!",
                    MAX_INTERPOLATION_NESTING)
        elif c == '\\':
            shouldEscape = true
        else:
            userString.add((Rune)c)
        discard advance()

    if isEOF():
        reportFrontendError(ScannerError, scanner.line, scanner.column, 
            "add \" at the end of string", "Oops, unterminated string!")
    discard advance() # closing quote '

    shallow(userString)
    return newXueToken(userString, 
        scanner.source.substr(scanner.start, scanner.current - 1), 
            scanner.line, scanner.column, kind == XUE_TOKEN_STRING_LITERAL)
endproc

proc isdigit(c: char): bool {.inline.} =
    return c >= '0' and c <= '9'
endproc

proc isalpha(c: char): bool {.inline.} =
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or c == '_';
endproc

proc makeNumber(): XueToken =
    while isdigit(peek()):
        discard advance()

    if peek() == '.' and isdigit(peekNext()):
        discard advance()
        while isdigit(peek()):
            discard advance()
    endif

    let lexeme = scanner.source.substr(scanner.start, scanner.current - 1)
    return newXueToken(parseFloat(lexeme), lexeme, scanner.line, scanner.column)
endproc

proc detectReserved(): XueToken =
    let lexeme = scanner.source.substr(scanner.start, scanner.current - 1)

    const reservedWord = {
        "mod": XUE_TOKEN_MODULO,
        "pow": XUE_TOKEN_POWER,
        "string": XUE_TOKEN_STRING_TYPE,
        "number": XUE_TOKEN_NUMBER_TYPE,
        "bool": XUE_TOKEN_BOOLEAN_TYPE,
        "is": XUE_TOKEN_EQUAL,
        "isnot": XUE_TOKEN_NOT_EQUAL,
        "not": XUE_TOKEN_NOT,
        "and": XUE_TOKEN_AND,
        "or": XUE_TOKEN_OR,
        "be": XUE_TOKEN_ASSIGN,
        "null": XUE_TOKEN_NULL_LITERAL,
        "true": XUE_TOKEN_BOOLEAN_LITERAL,
        "false": XUE_TOKEN_BOOLEAN_LITERAL,
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
        #"done": XUE_TOKEN_DONE,
        "break": XUE_TOKEN_BREAK,
        "continue": XUE_TOKEN_CONTINUE,
        "if": XUE_TOKEN_IF,
        "elseif": XUE_TOKEN_ELSEIF,
        "else": XUE_TOKEN_ELSE,
        "then": XUE_TOKEN_THEN,
        "endif": XUE_TOKEN_ENDIF,
    }.toTable()

    if reservedWord.contains(lexeme):
        let kind = reservedWord[lexeme]
        if kind == XUE_TOKEN_BOOLEAN_LITERAL:
            return newXueToken(lexeme == "true", lexeme, scanner.line, scanner.column)
        return makeToken(kind)
    endif

    return makeToken(XUE_TOKEN_IDENTIFIER)
endproc

proc makeIdentifier(): XueToken =
    while isalpha(peek()) or isdigit(peek()):
        discard advance()
    return detectReserved()
endproc

proc scanToken*(): XueToken =
    skipNonCodes()

    scanner.start = scanner.current

    if isEOF():
        return makeToken(XUE_TOKEN_EOF)

    let c: char = advance()

    if isalpha(c) or c == '$':
        return makeIdentifier()

    if isdigit(c):
        return makeNumber()

    case c
    of '+':
        return makeToken(XUE_TOKEN_PLUS)
    of '-':
        return makeToken(if match('>'): XUE_TOKEN_DART else: XUE_TOKEN_MINUS)
    of '*':
        return makeToken(if match('*'): XUE_TOKEN_POWER else: XUE_TOKEN_MULTIPLY)
    of '/':
        return makeToken(XUE_TOKEN_DIVIDE)
    of '%':
        return makeToken(XUE_TOKEN_MODULO)
    of '<':
        if match('>'):
            return makeToken(XUE_TOKEN_NOT_EQUAL)
        if match('='):
            return makeToken(XUE_TOKEN_LESS_EQUAL)
        if match('<'):
            return makeToken(XUE_TOKEN_BIT_LSH)
        return makeToken(XUE_TOKEN_LESS)
    of '>':
        if match('='):
            return makeToken(XUE_TOKEN_GREATER_EQUAL)
        if match('>'):
            return makeToken(XUE_TOKEN_BIT_RSH)
        return makeToken(XUE_TOKEN_GREATER)
    of '=':
        if match('='):
            return makeToken(XUE_TOKEN_EQUAL)
        if match('>'):
            return makeToken(XUE_TOKEN_ARROW)
        return makeToken(XUE_TOKEN_ASSIGN)
    of '!':
        return makeToken(if match('='): XUE_TOKEN_NOT_EQUAL else: XUE_TOKEN_NOT)
    of '~':
        return makeToken(XUE_TOKEN_BIT_NOT)
    of '&':
        return makeToken(if match('&'): XUE_TOKEN_AND else: XUE_TOKEN_BIT_AND)
    of '|':
        return makeToken(if match('|'): XUE_TOKEN_OR else: XUE_TOKEN_BIT_OR)
    of '^':
        return makeToken(XUE_TOKEN_BIT_XOR)
    of '?':
        return makeToken(XUE_TOKEN_QUESTION)
    of '.':
        return makeToken(if match('.'): XUE_TOKEN_CONCAT else: XUE_TOKEN_DOT)
    of '(':
        if scanner.numParens > 0:
            scanner.parens[scanner.numParens - 1].inc()
        return makeToken(XUE_TOKEN_LEFT_PAREN)
    of ')':
        if scanner.numParens > 0:
            scanner.parens[scanner.numParens - 1].dec()
            if scanner.parens[scanner.numParens - 1] == 0:
                scanner.numParens.dec()
                return makeString()
        return makeToken(XUE_TOKEN_RIGHT_PAREN)
    of '[':
        return makeToken(XUE_TOKEN_LEFT_PAREN)
    of ']':
        return makeToken(XUE_TOKEN_RIGHT_PAREN)
    of ',':
        return makeToken(XUE_TOKEN_COMMA)
    of ':':
        return makeToken(XUE_TOKEN_COLON)
    of ';':
        return makeToken(XUE_TOKEN_SEMICOLON)
    of '\'':
        return makeRawString()
    of '"': return makeString()
    else:
        reportFrontendError(ScannerError, scanner.line, scanner.column, "",
                    "Oops, unrecognized character '%c'!", c)
endproc