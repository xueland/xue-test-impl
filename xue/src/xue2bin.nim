from streams import StringStream, newStringStream, write
from unicode import `$`
import "./core"

proc binStringFromXueChunk*(chunk: ptr XueChunk): string

proc binStringFromXueObject*(obj: XueObject): string =
    var binStream: StringStream = newStringStream("")

    # save kind
    binStream.write(obj.kind)

    case obj.kind
    of XUE_OBJECT_STRING:
        let str = $XueValueString(obj).unirunes
        binStream.write((int32)str.len())
        binStream.write(str)
    of XUE_OBJECT_FUNCTION:
        let function = XueValueFunction(obj)
        binStream.write((int32)function.functionParamCount)
        binStream.write((int32)function.functionName.len())
        binStream.write(function.functionName)
        binStream.write((int32)function.scriptName.len())
        binStream.write(function.scriptName)
        # function chunk
        binStream.write(binStringFromXueChunk(addr(function.functionChunk)))

    return binStream.data

proc binStringFromXueValue*(value: XueValue): string =
    var binStream: StringStream = newStringStream("")

    # save kind
    binStream.write(value.kind)

    case value.kind
    of XUE_VALUE_NOTHING, XUE_VALUE_NULL:
        discard
    of XUE_VALUE_BOOLEAN:
        binStream.write(value.boolean)
    of XUE_VALUE_NUMBER:
        binStream.write(value.number)
    of XUE_VALUE_OBJECT:
        binStream.write(binStringFromXueObject(value.heapedObject))

    return binStream.data

proc binStringFromXueChunk*(chunk: ptr XueChunk): string =
    var binStream: StringStream = newStringStream("")

    # save code
    binStream.write((int32)chunk.code.len())
    for u8 in chunk.code:
        binStream.write(u8)

    # save constant
    binStream.write((int32)chunk.data.len())
    for constant in chunk.data:
        binStream.write(binStringFromXueValue(constant))

    # save line informations
    binStream.write((int32)chunk.line.len())
    for lineStart in chunk.line:
        binStream.write((int32)lineStart.offset)
        binStream.write((int32)lineStart.line)

    return binStream.data

proc binStringFromGlobals*(globals: seq[XueValue]): string =
    var binStream: StringStream = newStringStream("")

    binStream.write((int32)globals.len())
    for global in globals:
        binStream.write(binStringFromXueValue(global))

    return binStream.data
