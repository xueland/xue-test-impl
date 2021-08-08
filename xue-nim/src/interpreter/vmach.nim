from math import `mod`, `pow`
from sequtils import concat
from unicode import toRunes
from tables import Table
from "./opcode.nim" import XueInstruction, XueOpCode
from "./value.nim" import XueValueKind, XueValue, newXueValue, `$`, `==`, asCdouble
from "../common/config" import USE_POINTER_ARITHMETIC, DEBUG_TRACE_EXECUTION
from "../common/helper.nim" import reportFatalError, EXIT_FAILURE, `+=`, `-=`, `-`, `[]`, fprintf, until
when DEBUG_TRACE_EXECUTION:
    from "../common/debug.nim" import disassembleInstructionOffset

type
    VariableKind* = enum
        VARIABLE_MUTABLE,
        VARIABLE_CONST,

    GlobalVariable* = object
        identifier*: string
        kind*: VariableKind
        dataKind*: XueValueKind
        value*: XueValue

    XueVirtualMachine* = object
        stack: seq[XueValue]
        output: File
        error: File
        instruction: ptr XueInstruction
        when USE_POINTER_ARITHMETIC:
            eip: ptr uint8
        else:
            eip: uint32
        globals*: Table[string, uint32]
        globalsProfile*: seq[GlobalVariable]

var vm*: XueVirtualMachine

proc initXueVM*(output: File = stdout, error: File = stderr) =
    vm.output = output
    vm.error = error

proc pushVmStack(value: XueValue) =
    vm.stack.add(value)

proc popVmStack(): XueValue {.inline.} =
    return vm.stack.pop()

proc peekVmStack(depth: uint32): XueValue {.inline.} =
    return vm.stack[vm.stack.len() - 1 - (int)depth]

proc READ_BYTE(): uint8 {.inline.} =
    when USE_POINTER_ARITHMETIC:
        vm.eip += 1
        return vm.eip[-1]
    else:
        vm.eip.inc()
        return vm.instruction.code[vm.eip - 1]

proc getCurrentEipOffset(): uint32 {.inline.} =
    when USE_POINTER_ARITHMETIC:
        return (uint32)(vm.eip - addr(vm.instruction.code[0]))
    else:
        return vm.eip

proc READ_INDEX(size: uint8): uint32 =
    let instructionEIP = getCurrentEipOffset()

    if instructionEIP >= (uint32)vm.instruction.code.len() - 1:
        reportFatalError(EXIT_FAILURE, 
            "Oops, corrupted instruction chunk!")
    var index: uint32
    case size
    of 1:
        index = READ_BYTE()
    of 2:
        index = uint32(READ_BYTE()) + (uint32(READ_BYTE()) shl 8)
    of 4:
        index = uint32(READ_BYTE()) + (uint32(READ_BYTE()) shl 8) or (uint32(READ_BYTE()) shl 16) or (uint32(READ_BYTE()) shl 24)
    else:
        reportFatalError(EXIT_FAILURE, 
            "Oops, broken instruction at offset: %u", instructionEIP)
    return index

proc GET_CONSTANT(size: uint8): XueValue =
    let instructionEIP = getCurrentEipOffset()

    if instructionEIP >= (uint32)vm.instruction.code.len() - 1:
        reportFatalError(EXIT_FAILURE, 
            "Oops, corrupted instruction chunk!")

    var index: uint32
    case size
    of 1:
        index = READ_BYTE()
    of 2:
        index = uint32(READ_BYTE()) + (uint32(READ_BYTE()) shl 8)
    of 4:
        index = uint32(READ_BYTE()) + (uint32(READ_BYTE()) shl 8) or (uint32(READ_BYTE()) shl 16) or (uint32(READ_BYTE()) shl 24)
    else:
        reportFatalError(EXIT_FAILURE, 
            "Oops, broken PUSH instruction at offset: %u", instructionEIP)

    if index >= (uint32)vm.instruction.constant.len():
        reportFatalError(EXIT_FAILURE, 
            "Oops, corrupted PUSH instruction at offset: %u", instructionEIP)

    return vm.instruction.constant[index]

proc isFalse(value: XueValue): bool {.inline.} =
    return value.kind == XUE_VALUE_NULL or
        (value.kind == XUE_VALUE_BOOLEAN and not value.boolean)

template BINARY_OP(nt, op, c) =
    until(false):
        let b: c = (c)asCdouble(popVmStack())
        let a: c = (c)asCdouble(popVmStack())
        pushVmStack(newXueValue((nt)op(a, b)))

proc execute(): bool =
    while true:
        when DEBUG_TRACE_EXECUTION:
            fprintf(stderr, "[stack] ");
            for value in vm.stack:
                fprintf(stderr, "[%s]", $value)
            fprintf(stderr, "%s\n", 
                if vm.stack.len() == 0: "stack has no value" else: "")
            fprintf(stderr, "        ")
            discard disassembleInstructionOffset(vm.instruction, getCurrentEipOffset())

        {.computedGoto.}
        let opcode: XueOpCode = (XueOpCode)READ_BYTE()
        case opcode
        of XUE_OP_PUSH_1:
            pushVmStack(GET_CONSTANT(1))
        of XUE_OP_PUSH_2:
            pushVmStack(GET_CONSTANT(2))
        of XUE_OP_PUSH_4:
            pushVmStack(GET_CONSTANT(4))
        of XUE_OP_POP:
            discard popVmStack()
        of XUE_OP_ADD:
            BINARY_OP(cdouble, `+`, cdouble)
        of XUE_OP_SUBTRACT:
            BINARY_OP(cdouble, `-`, cdouble)
        of XUE_OP_NEGATE:
            vm.stack[vm.stack.len() - 1] = newXueValue(
                - asCdouble(vm.stack[vm.stack.len() - 1]))
        of XUE_OP_MULTIPLY:
            BINARY_OP(cdouble, `*`, cdouble)
        of XUE_OP_DIVIDE:
            BINARY_OP(cdouble, `/`, cdouble)
        of XUE_OP_MODULO:
            BINARY_OP(cdouble, `mod`, cdouble)
        of XUE_OP_POWER:
            BINARY_OP(cdouble, `pow`, cdouble)
        of XUE_OP_BIT_NOT:
            vm.stack[vm.stack.len() - 1] = newXueValue(
                (cdouble)(not (cint)asCdouble(vm.stack[vm.stack.len() - 1])))
        of XUE_OP_BIT_AND:
            BINARY_OP(cdouble, `and`, cint)
        of XUE_OP_BIT_OR:
            BINARY_OP(cdouble, `or`, cint)
        of XUE_OP_BIT_XOR:
            BINARY_OP(cdouble, `xor`, cint)
        of XUE_OP_BIT_LSH:
            BINARY_OP(cdouble, `shl`, cint)
        of XUE_OP_BIT_RSH:
            BINARY_OP(cdouble, `shr`, cint)
        of XUE_OP_LESS:
            BINARY_OP(bool, `<`, cdouble)
        of XUE_OP_GREATER:
            BINARY_OP(bool, `>`, cdouble)
        of XUE_OP_NOT:
            vm.stack[vm.stack.len() - 1] = newXueValue(isFalse(vm.stack[vm.stack.len() - 1]))
        of XUE_OP_EQUAL:
            let b = popVmStack()
            let a = popVmStack()
            pushVmStack(newXueValue(a == b))
        of XUE_OP_ECHO:
            vm.output.writeLine($popVmStack())
        of XUE_OP_CONCAT:
            let b = popVmStack()
            let a = popVmStack()
            if a.kind == XUE_VALUE_STRING:
                if b.kind == XUE_VALUE_STRING:
                    pushVmStack(newXueValue(a.str.concat(b.str)))
                else:
                    pushVmStack(newXueValue(a.str.concat(($b).toRunes())))
            else:
                if b.kind == XUE_VALUE_STRING:
                    pushVmStack(newXueValue(concat(($a).toRunes(), b.str)))
                else:
                    pushVmStack(newXueValue(concat(($a).toRunes(), ($b).toRunes())))
        of XUE_OP_SET_GLOBAL_1:
            let index = READ_INDEX(1)
            vm.globalsProfile[index].value = peekVmStack(0)
        of XUE_OP_SET_GLOBAL_2:
            let index = READ_INDEX(2)
            vm.globalsProfile[index].value = peekVmStack(0)
        of XUE_OP_SET_GLOBAL_4:
            let index = READ_INDEX(4)
            vm.globalsProfile[index].value = peekVmStack(0)
        of XUE_OP_GET_GLOBAL_1:
            let index = READ_INDEX(1)
            pushVmStack(vm.globalsProfile[index].value)
        of XUE_OP_GET_GLOBAL_2:
            let index = READ_INDEX(2)
            pushVmStack(vm.globalsProfile[index].value)
        of XUE_OP_GET_GLOBAL_4:
            let index = READ_INDEX(4)
            pushVmStack(vm.globalsProfile[index].value)
        of XUE_OP_GET_LOCAL_1:
            let index = READ_INDEX(1)
            pushVmStack(vm.stack[index])
        of XUE_OP_GET_LOCAL_2:
            let index = READ_INDEX(2)
            pushVmStack(vm.stack[index])
        of XUE_OP_GET_LOCAL_4:
            let index = READ_INDEX(4)
            pushVmStack(vm.stack[index])
        of XUE_OP_SET_LOCAL_1:
            let index = READ_INDEX(1)
            vm.stack[index] = peekVmStack(0)
        of XUE_OP_SET_LOCAL_2:
            let index = READ_INDEX(2)
            vm.stack[index] = peekVmStack(0)
        of XUE_OP_SET_LOCAL_4:
            let index = READ_INDEX(4)
            vm.stack[index] = peekVmStack(0)
        of XUE_OP_JUMP_IF_FALSE:
            var jump = (uint16)((uint32(READ_BYTE()) shl 8) + uint32(READ_BYTE()))

            if isFalse(peekVmStack(0)):
                when USE_POINTER_ARITHMETIC:
                    vm.eip += (int)jump
                else:
                    vm.eip = vm.eip + jump
        of XUE_OP_JUMP:
            var jump = (uint16)((uint32(READ_BYTE()) shl 8) + uint32(READ_BYTE()))

            when USE_POINTER_ARITHMETIC:
                vm.eip += (int)jump
            else:
                vm.eip = vm.eip + jump
        of XUE_OP_LOOP:
            var jump = (uint16)((uint32(READ_BYTE()) shl 8) + uint32(READ_BYTE()))

            when USE_POINTER_ARITHMETIC:
                vm.eip -= (int)jump
            else:
                vm.eip = vm.eip - jump
        of XUE_OP_RETURN:
            #vm.output.writeLine($popVmStack())
            return true

proc XueInterpret*(instruction: ptr XueInstruction): bool =
    if instruction.code.len() == 0:
        return true

    vm.instruction = instruction
    when USE_POINTER_ARITHMETIC:
        vm.eip = addr(vm.instruction.code[0])
    else:
        vm.eip = 0
    return execute()
