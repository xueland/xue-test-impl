from strformat import fmt
from unicode import Rune, toRunes, `$`
from sequtils import concat
import "../common/sintaks"

type
    XueOpCode* = enum
        XUE_OP_PUSH,
        XUE_OP_ADD,
        XUE_OP_POP,
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
        XUE_OP_GREATER,
        XUE_OP_NOT,
        XUE_OP_EQUAL,
        XUE_OP_ECHO,
        XUE_OP_CONCAT,
        XUE_OP_RETURN

    LineStart = tuple[offset: uint32, line: uint32]

    XueInstruction* = object
        code*: seq[uint8]
        constant*: seq[XueValue]
        line*: seq[LineStart]

    XueValueKind* = enum
        XUE_VALUE_NOTHING,
        XUE_VALUE_NULL,
        XUE_VALUE_BOOLEAN,
        XUE_VALUE_NUMBER,
        XUE_VALUE_STRING,
        XUE_VALUE_PROCEDURE,

    XueValue* = ref object of RootObj
        kind*: XueValueKind

    XueNothing* = ref object of XueValue

    XueNull* = ref object of XueValue

    XueBoolean* = ref object of XueValue
        value*: bool

    XueNumber* = ref object of XueValue
        value*: cdouble

    XueString* = ref object of XueValue
        value*: seq[Rune]

    XueProcedure* = ref object of XueValue
        argsCount*: uint8 # 255 arguments
        name*: string
        scriptName*: string
        instruction*: XueInstruction

proc newXueNothing*(): XueNothing =
    new(result)
    result.kind = XUE_VALUE_NOTHING
endproc

proc newXueNull*(): XueNull =
    new(result)
    result.kind = XUE_VALUE_NULL
endproc

proc newXueBoolean*(value: bool): XueBoolean =
    new(result)
    result.kind = XUE_VALUE_BOOLEAN
    result.value = value
endproc

proc newXueNumber*(value: SomeNumber): XueNumber =
    new(result)
    result.kind = XUE_VALUE_NUMBER
    result.value = (cdouble)value
endproc

proc newXueString*(value: string): XueString =
    new(result)
    result.kind = XUE_VALUE_STRING
    result.value = toRunes(value)
endproc

proc newXueString*(value: seq[Rune]): XueString =
    new(result)
    result.kind = XUE_VALUE_STRING
    result.value = value
endproc

proc newXueFunction*(argsCount: uint8, name: string, scriptName: string): XueProcedure =
    new(result)
    result.kind = XUE_VALUE_PROCEDURE
    result.argsCount = 0
    result.name = name
    result.scriptName = scriptName

proc newXueFunction*(argsCount: uint8, name: string, scriptName: string, instruction: XueInstruction): XueProcedure =
    new(result)
    result.kind = XUE_VALUE_PROCEDURE
    result.argsCount = 0
    result.name = name
    result.scriptName = scriptName
    result.instruction = instruction

proc `$`*(value: XueValue): string =
    case value.kind
    of XUE_VALUE_NOTHING:
        assert(false)
    of XUE_VALUE_NULL:
        return "null"
    of XUE_VALUE_BOOLEAN:
        return if XueBoolean(value).value: "true" else: "false"
    of XUE_VALUE_NUMBER:
        let number = XueNumber(value)
        if cdouble(int(number.value)) == number.value:
            return $int(number.value)
        else:
            return $number.value
    of XUE_VALUE_STRING:
        return $XueString(value).value
    of XUE_VALUE_PROCEDURE:
        return fmt"proc {XueProcedure(value).name}()"
endproc

proc `cdouble`*(value: XueValue): cdouble {.inline.} =
    return if value.kind == XUE_VALUE_NUMBER: XueNumber(value).value else: 0
endproc

proc `&`*(a: XueValue, b: XueValue): seq[Rune] =
    if a.kind == XUE_VALUE_STRING:
        if b.kind == XUE_VALUE_STRING:
            return XueString(a).value.concat(XueString(b).value)
        else:
            return XueString(a).value.concat(($b).toRunes())
    else:
        if b.kind == XUE_VALUE_STRING:
            return ($a).toRunes().concat(XueString(b).value)
        else:
            return ($a).toRunes().concat(($b).toRunes())
    endif
endproc

###########################################################

proc writeOpCode*(instruction: ptr XueInstruction, data: uint8 | XueOpCode, line: uint32) =
    instruction.code.add((uint8)data)

    if instruction.line.len() > 0 and
        instruction.line[^1].line == line: return
    instruction.line.add((offset: (uint32)instruction.code.len() - 1, line: line))
endproc

proc addConstant*(instruction: ptr XueInstruction, constant: XueValue): uint32 =
    instruction.constant.add(constant)
    return (uint32)instruction.constant.len() - 1
endproc

proc writeConstant*(instruction: ptr XueInstruction, constant: XueValue, line: uint32) =
    writeOpCode(instruction, XUE_OP_PUSH, line)
    for b in cast[array[4, uint8]](addConstant(instruction, constant)):
        writeOpCode(instruction, b, line)
    endfor
endproc

proc getLine*(instruction: ptr XueInstruction, offset: uint32): uint32 =
    var start: uint32 = 0
    var stop: uint32 = (uint32)instruction.line.len() - 1

    while true:
        let mid: uint32 = (start + stop) div 2
        var line: ptr LineStart = addr(instruction.line[mid])
        
        if offset < line.offset:
            stop = mid - 1
        elif mid == ((uint32)instruction.line.len() - 1) or
                offset < instruction.line[mid + 1].offset:
            return line.line
        else:
            start = mid + 1
    endwhile
endproc

from streams import StringStream, write, read, readStr
from unicode import `$`

proc save*(stream: var StringStream, instruction: XueInstruction)

proc save*(stream: var StringStream, value: XueValue) =
    write(stream, value.kind)
    case value.kind
    of XUE_VALUE_NULL, XUE_VALUE_NOTHING:
        discard
    of XUE_VALUE_BOOLEAN:
        write(stream, XueBoolean(value).value)
    of XUE_VALUE_NUMBER:
        write(stream, XueNumber(value).value)
    of XUE_VALUE_STRING:
        let str = $XueString(value).value
        write(stream, (uint32)str.len())
        write(stream, str)
    of XUE_VALUE_PROCEDURE:
        let function = XueProcedure(value)
        write(stream, function.argsCount)
        write(stream, (uint32)function.name.len())
        write(stream, function.name)
        write(stream, (uint32)function.scriptName.len())
        write(stream, function.scriptName)
        stream.save(function.instruction)
endproc

proc save(stream: var StringStream, instruction: XueInstruction) =
    write(stream, (uint32)instruction.code.len())
    for b in instruction.code:
        write(stream, b)
    write(stream, (uint32)instruction.constant.len())
    for constant in instruction.constant:
        stream.save(constant)
    write(stream, (uint32)instruction.line.len())
    for linestart in instruction.line:
        write(stream, linestart[0])
        write(stream, linestart[1])
    endfor
endproc

proc loadInstruction*(stream: var StringStream): XueInstruction

proc load*(stream: var StringStream): XueValue =
    var kind: XueValueKind
    read(stream, kind)
    case kind
    of XUE_VALUE_NULL:
        return newXueNull()
    of XUE_VALUE_NOTHING:
        return newXueNothing()
    of XUE_VALUE_BOOLEAN:
        var r: XueBoolean = new(XueBoolean)
        r.kind = XUE_VALUE_BOOLEAN
        read(stream, r.value)
        return r
    of XUE_VALUE_NUMBER:
        var r: XueNumber = new(XueNumber)
        r.kind = XUE_VALUE_NUMBER
        read(stream, r.value)
        return r
    of XUE_VALUE_STRING:
        var strLen: uint32
        var str: string

        read(stream, strLen)
        readStr(stream, (int)strLen, str)
        return newXueString(str)
    of XUE_VALUE_PROCEDURE:
        var r: XueProcedure = new(XueProcedure)
        r.kind = XUE_VALUE_PROCEDURE
        read(stream, r.argsCount)

        var strLen: uint32
        read(stream, strLen)
        readStr(stream, (int)strLen, r.name)
        read(stream, strLen)
        readStr(stream, (int)strLen, r.scriptName)

        r.instruction = stream.loadInstruction()
        return r
endproc

proc loadInstruction*(stream: var StringStream): XueInstruction =
    var instruction: XueInstruction

    var seqLen: uint32
    read(stream, seqLen)

    for i in countup(0, (int)seqLen - 1):
        var code: uint8
        read(stream, code)
        instruction.code.add(code)
        
    read(stream, seqLen)
    for i in countup(0, (int)seqLen - 1):
        var constant = stream.load()
        instruction.constant.add(constant)

    read(stream, seqLen)
    var first, second: uint32
    for i in countup(0, (int)seqLen - 1):
        read(stream, first)
        read(stream, second)
        instruction.line.add((first, second))
    endfor

    return instruction
endproc
