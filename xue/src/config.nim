from strformat import fmt

const
    XUE_VERSION_MAJOR* {.intdefine.} = 1
    XUE_VERSION_MINOR* {.intdefine.} = 0
    XUE_VERSION_PATCH* {.intdefine.} = 0
    XUE_VERSION_STRING* = fmt"{XUE_VERSION_MAJOR}.{XUE_VERSION_MINOR}.{XUE_VERSION_PATCH}"

    MAX_INTERPOLATION_NESTING* {.intdefine.} = 8

when defined(release):
    const XUE_DEBUG_DISASSEM* {.booldefine.} = false
    const XUE_DEBUG_TRACE_VM* {.booldefine.} = false
else:
    const XUE_DEBUG_DISASSEM* {.booldefine.} = true
    const XUE_DEBUG_TRACE_VM* {.booldefine.} = true
