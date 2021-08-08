from "../interpreter/opcode.nim" import XueOpCode, XueInstruction, getInstructionsLine
from "./helper.nim" import fprintf, reportFatalError, EXIT_FAILURE
from "../interpreter/value.nim" import `$`

proc indexInstruction(name: string, size: uint8, 
                        instruction: ptr XueInstruction, offset: uint32): uint32 =
    if offset >= (uint32)instruction.code.len() - 1:
        reportFatalError(EXIT_FAILURE, 
            "Oops, corrupted instruction chunk!")

    var index: uint32
    case size
    of 1:
        index = uint32(instruction.code[offset + 1])
    of 2:
        index = uint32(instruction.code[offset + 1]) + (uint32(instruction.code[offset + 2]) shl 8)
    of 4:
        index = uint32(instruction.code[offset + 1]) + (uint32(instruction.code[offset + 2]) shl 8) or (uint32(instruction.code[offset + 3]) shl 16) or (uint32(instruction.code[offset + 4]) shl 24)
    else:
        reportFatalError(EXIT_FAILURE, "Oops, broken PUSH instruction at offset: %u", offset)

    fprintf(stderr, "%s [%u]\n", name, index);
    return offset + 1 + size

proc constantInstruction(name: string, size: uint8, 
                        instruction: ptr XueInstruction, offset: uint32): uint32 =
    if offset >= (uint32)instruction.code.len() - 1:
        reportFatalError(EXIT_FAILURE, 
            "Oops, corrupted instruction chunk!")

    var index: uint32
    case size
    of 1:
        index = uint32(instruction.code[offset + 1])
    of 2:
        index = uint32(instruction.code[offset + 1]) + (uint32(instruction.code[offset + 2]) shl 8)
    of 4:
        index = uint32(instruction.code[offset + 1]) + (uint32(instruction.code[offset + 2]) shl 8) or (uint32(instruction.code[offset + 3]) shl 16) or (uint32(instruction.code[offset + 4]) shl 24)
    else:
        reportFatalError(EXIT_FAILURE, "Oops, broken PUSH instruction at offset: %u", offset)

    if index >= (uint32)instruction.constant.len():
        reportFatalError(EXIT_FAILURE, 
            "Oops, corrupted PUSH instruction at offset: %u", offset)

    fprintf(stderr, "%s %s [%u]\n", name, $instruction.constant[index], index);
    return offset + 1 + size

proc jumpInstruction(name: string, sign: int8, instruction: ptr XueInstruction, offset: uint32): uint32 =
    var jump: uint16 = (uint16)((uint32(instruction.code[offset + 1]) shl 8) + uint32(instruction.code[offset + 2]))

    if sign == -1:
        fprintf(stderr, "%s %04u\n", name, offset + 3 - jump)
    else:
        fprintf(stderr, "%s %04u\n", name, offset + 3 + jump)
    return offset + 3

proc simpleInstruction(name: string, offset: uint32): uint32 =
    fprintf(stderr, "%s\n", name)
    return offset + 1

proc disassembleInstructionOffset*(instruction: ptr XueInstruction, 
                                                    offset: uint32): uint32 =
    fprintf(stderr, "%u | %04u ", getInstructionsLine(instruction, offset), offset)

    let opcode: XueOpCode = (XueOpCode)instruction.code[offset]
    case opcode
    of XUE_OP_PUSH_1:
        return constantInstruction("PSH", 1, instruction, offset)
    of XUE_OP_PUSH_2:
        return constantInstruction("PSH", 2, instruction, offset)
    of XUE_OP_PUSH_4:
        return constantInstruction("PSH", 4, instruction, offset)
    of XUE_OP_POP:
        return simpleInstruction("POP", offset)
    of XUE_OP_RETURN:
        return simpleInstruction("RET", offset)
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
    of XUE_OP_GREATER:
        return simpleInstruction("GRT", offset)
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
    of XUE_OP_CONCAT:
        return simpleInstruction("CAT", offset)
    of XUE_OP_ECHO:
        return simpleInstruction("ECO", offset)
    of XUE_OP_SET_GLOBAL_1:
        return indexInstruction("SGL", 1, instruction, offset)
    of XUE_OP_SET_GLOBAL_2:
        return indexInstruction("SGL", 2, instruction, offset)
    of XUE_OP_SET_GLOBAL_4:
        return indexInstruction("SGL", 4, instruction, offset)
    of XUE_OP_GET_GLOBAL_1:
        return indexInstruction("GGL", 1, instruction, offset)
    of XUE_OP_GET_GLOBAL_2:
        return indexInstruction("GGL", 2, instruction, offset)
    of XUE_OP_GET_GLOBAL_4:
        return indexInstruction("GGL", 4, instruction, offset)
    of XUE_OP_SET_LOCAL_1:
        return indexInstruction("SLO", 1, instruction, offset)
    of XUE_OP_SET_LOCAL_2:
        return indexInstruction("SLO", 2, instruction, offset)
    of XUE_OP_SET_LOCAL_4:
        return indexInstruction("SLO", 4, instruction, offset)
    of XUE_OP_GET_LOCAL_1:
        return indexInstruction("GLO", 1, instruction, offset)
    of XUE_OP_GET_LOCAL_2:
        return indexInstruction("GLO", 2, instruction, offset)
    of XUE_OP_GET_LOCAL_4:
        return indexInstruction("GLO", 4, instruction, offset)
    of XUE_OP_JUMP:
        return jumpInstruction("JMP", 1, instruction, offset)
    of XUE_OP_JUMP_IF_FALSE:
        return jumpInstruction("JIF", 1, instruction, offset)
    of XUE_OP_LOOP:
        return jumpInstruction("LOP", -1, instruction, offset)
    # else:
    #     return offset + 1

proc disassembleInstruction*(instruction: ptr XueInstruction, name: string) =
    fprintf(stderr, "[debug] disassemble '%s':\n", name)

    var offset: uint32 = 0
    while offset < (uint32)instruction.code.len():
        fprintf(stderr, "        ")
        offset = disassembleInstructionOffset(instruction, offset)
