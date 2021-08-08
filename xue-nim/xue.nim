from "src/interpreter/vmach.nim" import XueInterpret
from "src/common/config.nim" 
    import XUE_VERSION_MAJOR, XUE_VERSION_MINOR, XUE_VERSION_PATCH, XUE_VERSION_STRING
from "src/compiler/compiler.nim" import XueCompile

export XueInterpret, XueCompile,
    XUE_VERSION_MAJOR, XUE_VERSION_MINOR, XUE_VERSION_PATCH, XUE_VERSION_STRING
