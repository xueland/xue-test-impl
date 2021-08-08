from streams import StringStream, newStringStream, read, readStr
from unicode import toRunes
import "./core"

proc XueChunkFromBinStream(stream: StringStream): XueChunk

proc XueObjectFromBinStream*(stream: StringStream): XueObject =
    var kind: XueObjectKind
    stream.read(kind)

    case kind
    of XUE_OBJECT_STRING:
        var strLen: uint32
        stream.read(strLen)
        var str = stream.readStr((int)strLen)
        return newXueValueString((str.toRunes()))
    of XUE_OBJECT_FUNCTION:
        var paramCount: uint32
        stream.read(paramCount)

        var funcNameLen: uint32
        stream.read(funcNameLen)
        var funcName = stream.readStr((int)funcNameLen)

        var scriptNameLen: uint32
        stream.read(scriptNameLen)
        var scriptName = stream.readStr((int)scriptNameLen)
        
        var chunk: XueChunk = XueChunkFromBinStream(stream)
        return newXueValueFunction(funcName, scriptName, (int)paramCount, chunk)

proc XueValueFromBinStream*(stream: StringStream): XueValue =
    var kind: XueValueKind
    stream.read(kind)

    case kind
    of XUE_VALUE_NOTHING:
        return newXueValueNothing()
    of XUE_VALUE_NULL:
        return newXueValueNull()
    of XUE_VALUE_BOOLEAN:
        var boolean: bool
        stream.read(boolean)
        return newXueValueBoolean(boolean)
    of XUE_VALUE_NUMBER:
        var number: cdouble
        stream.read(number)
        return newXueValueNumber(number)
    of XUE_VALUE_OBJECT:
        return XueValue(kind: XUE_VALUE_OBJECT, heapedObject: XueObjectFromBinStream(stream))

proc XueChunkFromBinStream(stream: StringStream): XueChunk =
    var chunk: XueChunk

    var codeLen: uint32
    stream.read(codeLen)
    for i in countup(1, (int)codeLen):
        var u8: uint8
        stream.read(u8)
        chunk.code.add(u8)

    var dataLen: uint32
    stream.read(dataLen)
    for i in countup(1, (int)dataLen):
        chunk.data.add(XueValueFromBinStream(stream))

    var lineLen: uint32
    stream.read(lineLen)
    for i in countup(1, (int)lineLen):
        var line, offset: uint32
        stream.read(offset)
        stream.read(line)
        chunk.line.add(((int)offset, (int)line))

    return chunk

proc globalsFromBinStream(stream: StringStream): seq[XueValue] =
    var globals: seq[XueValue]

    var globalLen: uint32
    stream.read(globalLen)
    for global in countup(1, (int)globalLen):
        globals.add(XueValueFromBinStream(stream))

    return globals

proc loadXueFromFile*(data: string): (XueValueFunction, seq[XueValue]) =
    var stream = newStringStream(data)
    return (XueValueFunction(XueObjectFromBinStream(stream)), globalsFromBinStream(stream))