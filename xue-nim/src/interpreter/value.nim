from unicode import Rune, `$`, `==`

type
    XueValueKind* = enum
        XUE_VALUE_VOID,
        XUE_VALUE_NULL,
        XUE_VALUE_NUMBER,
        XUE_VALUE_BOOLEAN,
        XUE_VALUE_STRING,

    XueValue* = ref XueValueObject

    XueValueObject = object
        case kind*: XueValueKind
        of XUE_VALUE_NUMBER: number*: cdouble
        of XUE_VALUE_BOOLEAN: boolean*: bool
        of XUE_VALUE_STRING: str*: seq[Rune]
        else:
            discard

proc newXueValue*(): XueValue =
    return XueValue(kind: XUE_VALUE_NULL)

proc newXueValue*(value: cdouble): XueValue =
    return XueValue(kind: XUE_VALUE_NUMBER, number: value)

proc newXueValue*(value: bool): XueValue =
    return XueValue(kind: XUE_VALUE_BOOLEAN, boolean: value)

proc newXueValue*(value: seq[Rune]): XueValue =
    return XueValue(kind: XUE_VALUE_STRING, str: value)

proc asCdouble*(value: XueValue): cdouble {.inline.} =
    return if value.kind == XUE_VALUE_NUMBER: value.number else: 0

proc `$`*(value: XueValue): string =
    case value.kind
    of XUE_VALUE_NULL:
        return "null"
    of XUE_VALUE_NUMBER:
        if (cdouble)((cint)value.number) == value.number:
            return $((cint)value.number)
        return $value.number
    of XUE_VALUE_BOOLEAN:
        return if value.boolean: "true" else: "false"
    of XUE_VALUE_STRING:
        return $value.str
    else:
        assert(false)

proc `==`*(a: XueValue, b: XueValue): bool =
    if a.kind != b.kind:
        return false
    case a.kind
    of XUE_VALUE_NULL:
        return true
    of XUE_VALUE_NUMBER:
        return a.number == b.number
    of XUE_VALUE_BOOLEAN:
        return a.boolean == b.boolean
    of XUE_VALUE_STRING:
        return a.str == b.str
    else:
        assert(false)