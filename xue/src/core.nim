from unicode import Rune, toRunes, `$`, `==`
from math import classify, fcNaN, fcInf
import "./utils"

type
    XueOpCode* = enum
        XUE_OP_PUSH,
        XUE_OP_POP,
        XUE_OP_ADD,
        XUE_OP_SUBTRACT,
        XUE_OP_NEGATE,
        XUE_OP_MULTIPLY,
        XUE_OP_DIVIDE,
        XUE_OP_MODULO,
        XUE_OP_POWER,
        XUE_OP_BIT_NOT,
        XUE_OP_BIT_AND,
        XUE_OP_BIT_OR,
        XUE_OP_BIT_XOR,
        XUE_OP_BIT_LSH,
        XUE_OP_BIT_RSH,
        XUE_OP_LESS,
        XUE_OP_LESS_EQUAL,
        XUE_OP_GREATER,
        XUE_OP_GREATER_EQ,
        XUE_OP_NOT,
        XUE_OP_EQUAL,
        XUE_OP_NOT_EQUAL,
        XUE_OP_CONCAT,
        XUE_OP_ECHO,
        XUE_OP_SET_GLOBAL,
        XUE_OP_GET_GLOBAL,
        XUE_OP_SET_LOCAL,
        XUE_OP_GET_LOCAL,
        XUE_OP_RETURN,

    XueLineStart* = tuple
        offset: int
        line: int

    XueChunk* = object
        code*: seq[uint8]
        data*: seq[XueValue]
        line*: seq[XueLineStart]

    XueValueKind* = enum
        XUE_VALUE_NOTHING,
        XUE_VALUE_NULL,
        XUE_VALUE_BOOLEAN,
        XUE_VALUE_NUMBER,
        XUE_VALUE_OBJECT,

    XueValue* {.acyclic, shallow.} = object
        case kind*: XueValueKind
        of XUE_VALUE_NOTHING, XUE_VALUE_NULL:
            discard
        of XUE_VALUE_BOOLEAN:
            boolean*: bool
        of XUE_VALUE_NUMBER:
            number*: cdouble
        of XUE_VALUE_OBJECT:
            heapedObject*: XueObject

    XueObjectKind* = enum
        XUE_OBJECT_STRING,
        XUE_OBJECT_FUNCTION

    XueObject* = ref object of RootObj
        kind*: XueObjectKind

    XueValueFunction* = ref object of XueObject
        functionParamCount*: int
        functionName*: string
        scriptName*: string
        functionChunk*: XueChunk
    
    XueValueString* = ref object of XueObject
        unirunes*: seq[Rune]

proc newXueValueNothing*(): XueValue =
    return XueValue(kind: XUE_VALUE_NOTHING)

proc newXueValueNull*(): XueValue =
    return XueValue(kind: XUE_VALUE_NULL)

proc newXueValueBoolean*(value: bool): XueValue =
    return XueValue(kind: XUE_VALUE_BOOLEAN, boolean: value)

proc newXueValueNumber*(value: SomeNumber): XueValue =
    return XueValue(kind: XUE_VALUE_NUMBER, number: (cdouble)value)

proc newXueValueString*(value: seq[Rune]): XueValueString =
    new(result)
    result.kind = XUE_OBJECT_STRING
    result.unirunes = value

proc newXueValueString*(value: string): XueValueString =
    return newXueValueString(value.toRunes())

proc newXueValueFunction*(name: string = "", scriptName: string = "", argsCount: int = 0, 
        chunk: XueChunk = XueChunk()): XueValueFunction =
    new(result)
    result.kind = XUE_OBJECT_FUNCTION
    result.functionParamCount = argsCount
    result.functionName = name
    result.functionChunk = chunk

# ---------------------------------------------------------

proc `==`*(a: XueValue, b: XueValue): bool =
    if a.kind != b.kind:
        return false
    case a.kind
    of XUE_VALUE_BOOLEAN:
        return a.boolean == b.boolean
    of XUE_VALUE_NUMBER:
        return a.number == b.number
    of XUE_VALUE_NULL, XUE_VALUE_NOTHING:
        return true
    of XUE_VALUE_OBJECT:
        case a.heapedObject.kind
        of XUE_OBJECT_STRING:
            let a: XueValueString = XueValueString(a.heapedObject)
            let b: XueValueString = XueValueString(b.heapedObject)
            return a.unirunes == b.unirunes
        else:
            return false

template XueValueAsNumber*(value: XueValue): cdouble =
    value.number

template XueValueAsBoolean*(value: XueValue): bool =
    value.boolean

template XueValueAsObject*(value: XueValue): XueObject =
    value.heapedObject

proc `$`*(heapedObject: XueObject): string =
    case heapedObject.kind
    of XUE_OBJECT_STRING:
        return $XueValueString(heapedObject).unirunes
    of XUE_OBJECT_FUNCTION:
        let function = XueValueFunction(heapedObject)
        return "[ func: " & (if function.functionName == "": "script" 
            else: function.functionName) & " ]"

proc `$`*(value: XueValue): string =
    case value.kind
    of XUE_VALUE_NOTHING:
        return "__nothing__"
    of XUE_VALUE_NULL:
        return "null"
    of XUE_VALUE_BOOLEAN:
        return if value.boolean: "true" else: "false"
    of XUE_VALUE_NUMBER:
        case value.number.classify
        of fcNan: return "NaN"
        of fcInf: return "INF"
        else:
            let integer = (cint)value.number
            return if cdouble(integer) == value.number:
                $integer else: $value.number
    of XUE_VALUE_OBJECT:
        return $value.heapedObject

template XueValueAsUniString*(value: XueValue): seq[Rune] =
    XueValueString(XueValueAsObject(value)).unirunes

template XueValueAsString*(value: XueValue): string =
    $XueValueAsUniString(value)

###########################################################

proc getLineXueChunk*(chunk: ptr XueChunk, offset: int): int =
    var start: int = 0
    var stop: int = chunk.line.len() - 1

    while true:
        let mid: int = (start + stop) div 2
        var line: ptr XueLineStart = addr(chunk.line[mid])

        if offset < line.offset:
            stop = mid - 1
        elif mid == chunk.line.len() - 1 or
                offset < chunk.line[mid + 1].offset:
            return line.line
        else:
            start = mid + 1
    # there is no control where loop end -> can lead to infinite loop

proc writeOpCodeXueChunk*(chunk: ptr XueChunk, u8: uint8 | XueOpCode, line: int) =
    chunk.code.add(uint8(u8))

    if chunk.line.len() > 0 and
        chunk.line[^1].line == line:
            return
    chunk.line.add((offset: chunk.code.len() - 1, line: line))

proc addConstantXueChunk*(chunk: ptr XueChunk, constant: XueValue): int =
    chunk.data.add(constant)
    return chunk.data.len() - 1

proc writeConstantXueChunk*(chunk: ptr, constant: XueValue, line: int) =
    writeOpCodeXueChunk(chunk, XUE_OP_PUSH, line)
    let constantIndex = addConstantXueChunk(chunk, constant)
    let u8s = cast[array[4, uint8]](constantIndex)

    # cast int( 32 bit ) -> 4 * u8 ( 8 bit )
    for u8 in u8s:
        writeOpCodeXueChunk(chunk, u8, line)

###########################################################

proc constantInstruction(name: string, chunk: ptr XueChunk, 
                                            offset: int): int =
    if offset >= chunk.code.len() - 1:
        reportFatalError(EXIT_FAILURE,
            "Oops, corrupted instruction chunk!")

    let u8s = [
        chunk.code[offset + 1],
        chunk.code[offset + 2],
        chunk.code[offset + 3],
        chunk.code[offset + 4],
    ]

    let index: int = cast[int](u8s)
    if index >= chunk.data.len():
        reportFatalError(EXIT_FAILURE,
            "Oops, invalid PUSH instruction!")

    fprintf(stderr, "%s %s\n", name, $chunk.data[index])
    return offset + 5

proc indexInstruction(name: string, chunk: ptr XueChunk, 
                                            offset: int): int =
    if offset >= chunk.code.len() - 1:
        reportFatalError(EXIT_FAILURE,
            "Oops, corrupted instruction chunk!")

    let u8s = [
        chunk.code[offset + 1],
        chunk.code[offset + 2],
        chunk.code[offset + 3],
        chunk.code[offset + 4],
    ]

    let index: int = cast[int](u8s)
    fprintf(stderr, "%s %d\n", name, index)
    return offset + 5

proc simpleInstruction(name: string, offset: int): int =
    fprintf(stderr, "%s\n", name)
    return offset + 1

proc disassembleXueInstruction*(chunk: ptr XueChunk, offset: int): int =
    fprintf(stderr, "%3u | %04u ", getLineXueChunk(chunk, offset), offset)

    {.computedGoto.}
    let opcode = (XueOpCode)chunk.code[offset]

    case opcode
    of XUE_OP_PUSH:
        return constantInstruction("PSH", chunk, offset)
    of XUE_OP_POP:
        return simpleInstruction("POP", offset)
    of XUE_OP_ADD:
        return simpleInstruction("ADD", offset)
    of XUE_OP_SUBTRACT:
        return simpleInstruction("SUB", offset)
    of XUE_OP_NEGATE:
        return simpleInstruction("NEG", offset)
    of XUE_OP_MULTIPLY:
        return simpleInstruction("MUL", offset)
    of XUE_OP_DIVIDE:
        return simpleInstruction("DIV", offset)
    of XUE_OP_MODULO:
        return simpleInstruction("MOD", offset)
    of XUE_OP_POWER:
        return simpleInstruction("POW", offset)
    of XUE_OP_LESS:
        return simpleInstruction("LES", offset)
    of XUE_OP_LESS_EQUAL:
        return simpleInstruction("LEQ", offset)
    of XUE_OP_GREATER:
        return simpleInstruction("GRT", offset)
    of XUE_OP_GREATER_EQ:
        return simpleInstruction("GEQ", offset)
    of XUE_OP_BIT_AND:
        return simpleInstruction("BAN", offset)
    of XUE_OP_BIT_OR:
        return simpleInstruction("BOR", offset)
    of XUE_OP_BIT_XOR:
        return simpleInstruction("BXO", offset)
    of XUE_OP_BIT_NOT:
        return simpleInstruction("BNO", offset)
    of XUE_OP_BIT_LSH:
        return simpleInstruction("LSH", offset)
    of XUE_OP_BIT_RSH:
        return simpleInstruction("RSH", offset)
    of XUE_OP_NOT:
        return simpleInstruction("NOT", offset)
    of XUE_OP_EQUAL:
        return simpleInstruction("EQL", offset)
    of XUE_OP_NOT_EQUAL:
        return simpleInstruction("NEQ", offset)
    of XUE_OP_CONCAT:
        return simpleInstruction("CAT", offset)
    of XUE_OP_ECHO:
        return simpleInstruction("ECO", offset)
    of XUE_OP_SET_GLOBAL:
        return indexInstruction("SGL", chunk, offset)
    of XUE_OP_GET_GLOBAL:
        return indexInstruction("GGL", chunk, offset)
    of XUE_OP_SET_LOCAL:
        return indexInstruction("SLO", chunk, offset)
    of XUE_OP_GET_LOCAL:
        return indexInstruction("GLO", chunk, offset)
    of XUE_OP_RETURN:
        return simpleInstruction("RET", offset)

proc disassembleXueChunk*(chunk: ptr XueChunk, name: string) =
    fprintf(stderr, "[debug] disassemble '%s':\n", name)

    var offset: int = 0
    while offset < chunk.code.len():
        fprintf(stderr, "        ")
        offset = disassembleXueInstruction(chunk, offset)
