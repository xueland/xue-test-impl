from strformat import fmt
const
    MAX_INTERPOLATION_NESTING* {.intdefine.} = 8

    XUE_VERSION_MAJOR* {.intdefine.} = 1
    XUE_VERSION_MINOR* {.intdefine.} = 0
    XUE_VERSION_PATCH* {.intdefine.} = 0
    XUE_VERSION_STRING* = 
        fmt"{XUE_VERSION_MAJOR}.{XUE_VERSION_MINOR}.{XUE_VERSION_PATCH}"

    XUE_BASE_DIRECTORY* {.strdefine.} = "."
    VM_RUNTIME_CHECK* {.booldefine.} = false
    OPTIMIZE_WHEN_COMPILE* {.booldefine.} = true

when not defined(release):
    const
        DEBUG_TRACE_EXECUTION* {.booldefine.} = true
        DEBUG_DISASSEMBLE_COMPILER* {.booldefine.} = true
else:
    const
        DEBUG_TRACE_EXECUTION* {.booldefine.} = false
        DEBUG_DISASSEMBLE_COMPILER* {.booldefine.} = false
