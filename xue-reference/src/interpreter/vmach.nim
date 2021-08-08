from math import `mod`, pow
import "./core"
import "../common/sintaks"
import "../common/helper"
import "../common/config"
when DEBUG_TRACE_EXECUTION:
    import "./dasm.nim"

type
    CallFrame = object
        procedure: ptr XueProcedure
        eip: uint32
        stack: seq[XueValue]

    XueVirtualMachine* = object
        output: File
        error: File
        frames: seq[ptr CallFrame]

var vm: XueVirtualMachine

proc initXueVM*(output: File, error: File) =
    vm.output = output
    vm.error = error

proc getCurrentFrame(): ptr CallFrame {.inline.} =
    return vm.frames[^1]
endproc

template pushStack(value: XueValue) =
    getCurrentFrame().stack.add(value)
endtemplate

proc popStack(): XueValue =
    let frame = getCurrentFrame()
    if frame.stack.len() == 0:
        reportFatalError(EXIT_FAILURE, "Oops, no more element to pop!")
    return frame.stack.pop()
endproc

proc peekStack(distance: uint32): XueValue =
    let frame = getCurrentFrame()
    if frame.stack.len() == 0:
        reportFatalError(EXIT_FAILURE, "Oops, no more element to peek!")
    return frame.stack[^(1 + (int)distance)]
endproc

proc resetStack() =
    vm.frames = @[]
endproc

proc reportRuntimeError(message: string) =
    fprintf(vm.error, "\n%s\n\n", message)
    fprintf(vm.error, "traceback:\n")
    for frameIndex in countdown(vm.frames.len() - 1, 0):
        let frame = vm.frames[0]
        let errorLine = getLine(addr(frame.procedure.instruction), frame.eip - 1)

        fprintf(vm.error, "    at %s ( %s:%u )\n", frame.procedure.name,
                                                    frame.procedure.scriptName, errorLine)
    endfor
    fprintf(vm.error, "\n")
    resetStack()

proc READ_BYTE(): uint8 =
    let frame = getCurrentFrame()
    inc(frame.eip)
    return frame.procedure.instruction.code[frame.eip - 1]
endproc

proc GET_CONSTANT(): XueValue =
    let frame = getCurrentFrame()
    if frame.eip >= (uint32)frame.procedure.instruction.code.len() - 1:
        reportFatalError(EXIT_FAILURE, "Oops, corrupted instruction chunk!")

    let index = cast[uint32]([
        frame.procedure.instruction.code[frame.eip],
        frame.procedure.instruction.code[frame.eip + 1],
        frame.procedure.instruction.code[frame.eip + 2],
        frame.procedure.instruction.code[frame.eip + 3]
    ])
    frame.eip.inc(4)
    if index >= (uint32)frame.procedure.instruction.constant.len():
        reportFatalError(EXIT_FAILURE, "Oops, invalid PUSH instruction!")

    return frame.procedure.instruction.constant[index]
endproc

template BINARY_OP(nt, op, c) =
    until(false):
        when VM_RUNTIME_CHECK:
            if peekStack(0).kind != XUE_VALUE_NUMBER or
                    peekStack(1).kind != XUE_VALUE_NUMBER:
                reportRuntimeError("Oops, operands must be two numbers!")
                return EXIT_EXECUTE
        let b: c = (c)core.cdouble(popStack())
        let a: c = (c)core.cdouble(popStack())
        pushStack(nt(op(a, b)))
endtemplate

proc isFalse(value: XueValue): bool {.inline.} =
    return value.kind == XUE_VALUE_NULL or
        (value.kind == XUE_VALUE_BOOLEAN and not XueBoolean(value).value)
endproc

proc vmExecute(): int =
    while true:
        when DEBUG_TRACE_EXECUTION:
            let stack = getCurrentFrame().stack

            fprintf(stderr, "[stack] ");
            for value in stack:
                fprintf(stderr, "[%s]", $value)
            fprintf(stderr, "%s\n", 
                if stack.len() == 0: "stack has no value" else: "")
            fprintf(stderr, "        ")
    
            discard disassembleOpCode(
                addr(getCurrentFrame().procedure.instruction), getCurrentFrame().eip)
        endwhen

        {.computedGoto.}
        let instruction = (XueOpCode)READ_BYTE()
        let frame = getCurrentFrame()

        case instruction
        of XUE_OP_PUSH:
            pushStack(GET_CONSTANT())
        of XUE_OP_POP:
            discard popStack()
        of XUE_OP_ADD:
            BINARY_OP(newXueNumber, `+`, cdouble)
        of XUE_OP_SUBTRACT:
            BINARY_OP(newXueNumber, `-`, cdouble)
        of XUE_OP_NEGATE:
            when VM_RUNTIME_CHECK:
                if peekStack(0).kind != XUE_VALUE_NUMBER:
                    reportRuntimeError("Oops, we can't negate a non-number!")
                    return EXIT_EXECUTE
            frame.stack[^1] = newXueNumber(
                - cdouble(frame.stack[^1]))
        of XUE_OP_MULTIPLY:
            BINARY_OP(newXueNumber, `*`, cdouble)
        of XUE_OP_DIVIDE:
            BINARY_OP(newXueNumber, `/`, cdouble)
        of XUE_OP_MODULO:
            BINARY_OP(newXueNumber, `mod`, cdouble)
        of XUE_OP_POWER:
            BINARY_OP(newXueNumber, `pow`, cdouble)
        of XUE_OP_BIT_NOT:
            when VM_RUNTIME_CHECK:
                if peekStack(0).kind != XUE_VALUE_NUMBER:
                    reportRuntimeError("Oops, we can't calculate the complement of a non-number!")
                    return EXIT_EXECUTE
            frame.stack[^1] = newXueNumber(
                (cdouble)(not (cint)cdouble(frame.stack[^1])))
        of XUE_OP_BIT_AND:
            BINARY_OP(newXueNumber, `and`, cint)
        of XUE_OP_BIT_OR:
            BINARY_OP(newXueNumber, `or`, cint)
        of XUE_OP_BIT_XOR:
            BINARY_OP(newXueNumber, `xor`, cint)
        of XUE_OP_BIT_LSH:
            BINARY_OP(newXueNumber, `shl`, cint)
        of XUE_OP_BIT_RSH:
            BINARY_OP(newXueNumber, `shr`, cint)
        of XUE_OP_LESS:
            BINARY_OP(newXueBoolean, `<`, cdouble)
        of XUE_OP_GREATER:
            BINARY_OP(newXueBoolean, `>`, cdouble)
        of XUE_OP_NOT:
            frame.stack[^1] = newXueBoolean(
                    isFalse(frame.stack[^1]))
        of XUE_OP_EQUAL:
            let b = popStack()
            let a = popStack()
            pushStack(newXueBoolean(a == b))
        of XUE_OP_ECHO:
            vm.output.writeLine($popStack())
        of XUE_OP_CONCAT:
            let b = popStack()
            let a = popStack()
            pushStack(newXueString(a & b))
        of XUE_OP_RETURN:
            return EXIT_SUCCESS
    endwhile
endproc

proc XueInterpret*(scriptMain: ptr XueProcedure): int =
    var frame = CallFrame(procedure: scriptMain)
    vm.frames.add(addr(frame))

    return vmExecute()
endproc
