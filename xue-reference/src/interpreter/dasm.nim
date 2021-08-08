import "../common/helper"
import "../common/sintaks"
import "../interpreter/core"

proc constantInstruction(name: string, instruction: ptr XueInstruction, 
                                            offset: uint32): uint32 =
    if offset >= (uint32)instruction.code.len() - 1:
        reportFatalError(EXIT_FAILURE,
            "Oops, corrupted instruction chunk!")

    let arr = [
        instruction.code[offset + 1],
        instruction.code[offset + 2],
        instruction.code[offset + 3],
        instruction.code[offset + 4],
    ]
    let index = cast[uint32](arr)

    if index >= (uint32)instruction.constant.len():
        reportFatalError(EXIT_FAILURE,
            "Oops, invalid PUSH instruction!")

    fprintf(stderr, "%s %s\n", name, $instruction.constant[index])
    return offset + 5
endproc

proc simpleInstruction(name: string, offset: uint32): uint32 =
    fprintf(stderr, "%s\n", name)
    return offset + 1
endproc

proc disassembleOpCode*(instruction: ptr XueInstruction, offset: uint32): uint32 =
    fprintf(stderr, "%3u | %04u ", getLine(instruction, offset), offset)

    let opcode = (XueOpCode)instruction.code[offset]
    case opcode
    of XUE_OP_PUSH:
        return constantInstruction("PSH", instruction, offset)
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
endproc

proc disassembleInstruction*(instruction: ptr XueInstruction, name: string) =
    fprintf(stderr, "[debug] disassemble '%s':\n", name)

    var offset: uint32 = 0
    while offset < (uint32)instruction.code.len():
        fprintf(stderr, "        ")
        offset = disassembleOpCode(instruction, offset)
    endwhile
endproc
