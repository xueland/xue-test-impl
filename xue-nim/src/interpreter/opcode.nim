from "./value.nim" import XueValue, XueValueKind
from "../common/helper.nim" import reportFatalError, EXIT_FAILURE

type
    LineStart = tuple[offset: uint32, line: uint32]

    XueOpCode* = enum
        XUE_OP_PUSH_1,
        XUE_OP_PUSH_2,
        XUE_OP_PUSH_4,
        XUE_OP_POP,
        XUE_OP_NEGATE,
        XUE_OP_ADD,
        XUE_OP_SUBTRACT,
        XUE_OP_MULTIPLY,
        XUE_OP_DIVIDE,
        XUE_OP_MODULO,
        XUE_OP_POWER,
        XUE_OP_LESS,
        XUE_OP_GREATER,
        XUE_OP_BIT_AND,
        XUE_OP_BIT_OR,
        XUE_OP_BIT_XOR,
        XUE_OP_BIT_NOT,
        XUE_OP_BIT_LSH,
        XUE_OP_BIT_RSH,
        XUE_OP_NOT,
        XUE_OP_EQUAL,
        XUE_OP_CONCAT,
        XUE_OP_ECHO,
        XUE_OP_SET_GLOBAL_1,
        XUE_OP_SET_GLOBAL_2,
        XUE_OP_SET_GLOBAL_4,
        XUE_OP_GET_GLOBAL_1,
        XUE_OP_GET_GLOBAL_2,
        XUE_OP_GET_GLOBAL_4,
        XUE_OP_SET_LOCAL_1,
        XUE_OP_SET_LOCAL_2,
        XUE_OP_SET_LOCAL_4,
        XUE_OP_GET_LOCAL_1,
        XUE_OP_GET_LOCAL_2,
        XUE_OP_GET_LOCAL_4,
        XUE_OP_JUMP_IF_FALSE,
        XUE_OP_JUMP,
        XUE_OP_LOOP,
        XUE_OP_RETURN,

    XueInstruction* = object
        code*: seq[uint8]
        line*: seq[LineStart]
        constant*: seq[XueValue]

proc getInstructionsLine*(instruction: ptr XueInstruction, offset: uint32): uint32 =
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

proc writeOpCode*(instruction: ptr XueInstruction, data: uint8 | XueOpCode, line: uint32) =
    instruction.code.add((uint8)data)
    
    if instruction.line.len() > 0 and
            instruction.line[instruction.line.len() - 1].line == line:
        return
    instruction.line.add((offset: (uint32)instruction.code.len() - 1,line: line))

proc addConstant*(instruction: ptr XueInstruction, value: XueValue): uint32 =
    instruction.constant.add(value)
    return (uint32)instruction.constant.len() - 1

proc writeConstant*(instruction: ptr XueInstruction, value: XueValue, line: uint32) =
    let index: uint32 = addConstant(instruction, value)

    if index <= high(uint8):
        writeOpCode(instruction, XUE_OP_PUSH_1, line)
        writeOpCode(instruction, (uint8)index, line)
    elif index <= high(uint16):
        writeOpCode(instruction, XUE_OP_PUSH_2, line)
        writeOpCode(instruction, (uint8)(index and uint32(0xFF)), line)
        writeOpCode(instruction, (uint8)((index shr 8) and uint32(0xFF)), line)
    elif index <= high(uint32):
        writeOpCode(instruction, XUE_OP_PUSH_4, line)
        writeOpCode(instruction, (uint8)(index and uint32(0xFF)), line)
        writeOpCode(instruction, (uint8)((index shr 8) and uint32(0xFF)), line)
        writeOpCode(instruction, (uint8)((index shr 16) and uint32(0xFF)), line)
        writeOpCode(instruction, (uint8)((index shr 24) and uint32(0xFF)), line)
    else:
        reportFatalError(EXIT_FAILURE, 
            "Oops, too much number of constants in single instruction chunk.")
