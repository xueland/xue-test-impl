from strformat import fmt

const
    USE_POINTER_ARITHMETIC* {.booldefine.} = false

    XUE_VERSION_MAJOR* {.intdefine.} = 1
    XUE_VERSION_MINOR* {.intdefine.} = 0
    XUE_VERSION_PATCH* {.intdefine.} = 0
    XUE_VERSION_STRING* = 
        fmt"{XUE_VERSION_MAJOR}.{XUE_VERSION_MINOR}.{XUE_VERSION_PATCH}"

when not defined(release):
    const
        DEBUG_TRACE_EXECUTION* {.booldefine.} = true
        DEBUG_DISASSEMBLE_COMPILER* {.booldefine.} = true
else:
    const
        DEBUG_TRACE_EXECUTION* {.booldefine.} = false
        DEBUG_DISASSEMBLE_COMPILER* {.booldefine.} = false
