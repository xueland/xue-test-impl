from math import `mod`, pow
import "./config"
import "./core"
import "./utils"

type
    CallFrame = object
        function: XueValueFunction
        eip: int
        stack: seq[XueValue]

    XueVirtualMachine* = object
        globals*: seq[XueValue]
        frames: seq[CallFrame]

## global virtual machine
var vm*: XueVirtualMachine

template getCurrentCallFrame(): ptr CallFrame =
    addr(vm.frames[^1])

proc pushStack(value: XueValue) {.inline.} =
    getCurrentCallFrame().stack.add(value)

proc popStack(): XueValue {.inline.} =
    return getCurrentCallFrame().stack.pop()

proc peekStack(depth: int): XueValue {.inline.} =
    return getCurrentCallFrame().stack[^(depth + 1)]

template resetStack() =
    vm.frames = @[]

template reportRuntimeError(message: string, args: varargs[untyped]) =
    fprintf(stderr, "\n" & message & "\n\n", args)
    fprintf(stderr, "traceback:\n")
    for frameIndex in countdown(vm.frames.len() - 1, 0):
        let frame = vm.frames[0]
        let errorLine = getLineXueChunk(addr(frame.function.functionChunk), frame.eip - 1)

        fprintf(stderr, "    at %s ( %s:%u )\n", frame.function.functionChunk,
                                                    frame.function.scriptName, errorLine)
    fprintf(stderr, "\n")
    resetStack()

proc callFunction(function: XueValueFunction, argsCount: int): bool =
    if argsCount != function.functionParamCount:
        reportRuntimeError("Oops, expecting %d arguments but got %d.", function.functionParamCount, argsCount);
        return false
    vm.frames.add(CallFrame(function: function))
    return true

proc READ_BYTE(): uint8 {.inline.} =
    let frame = getCurrentCallFrame()
    inc(frame.eip)
    return frame.function.functionChunk.code[frame.eip - 1]

proc GET_CONSTANT(): XueValue =
    let frame = getCurrentCallFrame()
    if frame.eip >= frame.function.functionChunk.code.len() - 1:
        reportFatalError(EXIT_FAILURE, "Oops, corrupted instruction chunk!")

    let u8s = [
        frame.function.functionChunk.code[frame.eip],
        frame.function.functionChunk.code[frame.eip + 1],
        frame.function.functionChunk.code[frame.eip + 2],
        frame.function.functionChunk.code[frame.eip + 3]
    ]
    let index = cast[int](u8s)

    frame.eip.inc(4)
    if index >= frame.function.functionChunk.data.len():
        reportFatalError(EXIT_FAILURE, "Oops, invalid PUSH instruction!")

    return frame.function.functionChunk.data[index]

proc GET_INDEX(): int =
    let frame = getCurrentCallFrame()
    if frame.eip >= frame.function.functionChunk.code.len() - 1:
        reportFatalError(EXIT_FAILURE, "Oops, corrupted instruction chunk!")

    let u8s = [
        frame.function.functionChunk.code[frame.eip],
        frame.function.functionChunk.code[frame.eip + 1],
        frame.function.functionChunk.code[frame.eip + 2],
        frame.function.functionChunk.code[frame.eip + 3]
    ]
    let index = cast[int](u8s)

    frame.eip.inc(4)
    return index

template BINARY_OP(xueValueConstructor, operator, nimKind) =
    until(false):
        let b: nimKind = (nimKind)XueValueAsNumber(popStack())
        let a: nimKind = (nimKind)XueValueAsNumber(popStack())
        pushStack(xueValueConstructor(operator(a, b)))

proc isFalse(value: XueValue): bool {.inline.} =
    return value.kind == XUE_VALUE_NULL or
        (value.kind == XUE_VALUE_BOOLEAN and not value.boolean)

proc execute(): int =
    while true:
        var frame = getCurrentCallFrame()

        when XUE_DEBUG_TRACE_VM:
            let stack = frame.stack

            fprintf(stderr, "[stack] ")
            for value in stack:
                fprintf(stderr, "[%s]", $value)
            fprintf(stderr, "%s\n", 
                if stack.len() == 0: "stack has no value" else: "")
            fprintf(stderr, "        ")

            discard disassembleXueInstruction(
                addr(frame.function.functionChunk), frame.eip)

        {.computedGoto.}
        let instruction = (XueOpCode)READ_BYTE()

        case instruction
        of XUE_OP_PUSH:
            pushStack(GET_CONSTANT())
        of XUE_OP_POP:
            discard popStack()
        of XUE_OP_RETURN:
            {.linearScanEnd.}
            let ret = popStack()
            discard vm.frames.pop()

            if vm.frames.len() == 0:
                return EXIT_SUCCESS
            pushStack(ret)
            frame = getCurrentCallFrame()
        of XUE_OP_ADD:
            BINARY_OP(newXueValueNumber, `+`, cdouble)
        of XUE_OP_SUBTRACT:
            BINARY_OP(newXueValueNumber, `-`, cdouble)
        of XUE_OP_NEGATE:
            frame.stack[^1] = newXueValueNumber(- XueValueAsNumber(frame.stack[^1]))
        of XUE_OP_MULTIPLY:
            BINARY_OP(newXueValueNumber, `*`, cdouble)
        of XUE_OP_DIVIDE:
            BINARY_OP(newXueValueNumber, `/`, cdouble)
        of XUE_OP_MODULO:
            BINARY_OP(newXueValueNumber, `mod`, cdouble)
        of XUE_OP_POWER:
            BINARY_OP(newXueValueNumber, pow, cdouble)
        of XUE_OP_BIT_NOT:
            frame.stack[^1] = newXueValueNumber(
                (cdouble)(not (cint)XueValueAsNumber(frame.stack[^1])))
        of XUE_OP_BIT_AND:
            BINARY_OP(newXueValueNumber, `and`, cint)
        of XUE_OP_BIT_OR:
            BINARY_OP(newXueValueNumber, `or`, cint)
        of XUE_OP_BIT_XOR:
            BINARY_OP(newXueValueNumber, `xor`, cint)
        of XUE_OP_BIT_LSH:
            BINARY_OP(newXueValueNumber, `shl`, cint)
        of XUE_OP_BIT_RSH:
            BINARY_OP(newXueValueNumber, `shr`, cint)
        of XUE_OP_LESS:
            BINARY_OP(newXueValueBoolean, `<`, cdouble)
        of XUE_OP_LESS_EQUAL:
            BINARY_OP(newXueValueBoolean, `<=`, cdouble)
        of XUE_OP_GREATER:
            BINARY_OP(newXueValueBoolean, `>`, cdouble)
        of XUE_OP_GREATER_EQ:
            BINARY_OP(newXueValueBoolean, `>=`, cdouble)
        of XUE_OP_NOT:
            frame.stack[^1] = newXueValueBoolean(
                    isFalse(frame.stack[^1]))
        of XUE_OP_EQUAL:
            let b = popStack()
            let a = popStack()
            pushStack(newXueValueBoolean(a == b))
        of XUE_OP_NOT_EQUAL:
            let b = popStack()
            let a = popStack()
            pushStack(newXueValueBoolean(not (a == b)))
        of XUE_OP_CONCAT:
            let b = $popStack()
            let a = $popStack()
            pushStack(XueValue(kind: XUE_VALUE_OBJECT, heapedObject: newXueValueString(a & b)))
        of XUE_OP_ECHO:
            echo $popStack()
        of XUE_OP_SET_GLOBAL:
            let index = GET_INDEX()
            vm.globals[index] = peekStack(0)
        of XUE_OP_GET_GLOBAL:
            let index = GET_INDEX()
            pushStack(vm.globals[index])
        of XUE_OP_SET_LOCAL:
            let index = GET_INDEX()
            frame.stack[index] = peekStack(0)
        of XUE_OP_GET_LOCAL:
            let index = GET_INDEX()
            pushStack(frame.stack[index])

proc interpret*(mainScript: XueValueFunction): int =
    if mainScript == nil:
        return EXIT_ESYNTAX
    if mainScript.functionChunk.code.len() == 0:
        return EXIT_SUCCESS

    discard callFunction(mainScript, 0)
    return execute()

import "./bin2xue"

proc XueInterpretFromCompiled*(input: string): int =
    let r = loadXueFromFile(input)
    vm.globals = r[1]

    if r[0] == nil:
        return EXIT_ESYNTAX
    if r[0].functionChunk.code.len() == 0:
        return EXIT_SUCCESS

    discard callFunction(r[0], 0)
    return execute()
