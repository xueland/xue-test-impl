###############################################################################
#
# JUST TWEAKING NIM SYNTAX! THANKS TO NIM MACRO SYSTEM.
# NOW, NIM HAS EXPLICIT END KEYWORDS LIKE RUBY, LUA, ETC.
#
# (c) 2021 HEIN THANT MAUNG MAUNG
#
###############################################################################

template endtemplate*() =
    discard

template endtype*() =
    discard

template endif*() =
    discard

template endwhen*() =
    discard

template endcase*() =
    discard

template endproc*() =
    discard

template endmethod*() =
    discard

template endwhile*() =
    discard

template endfor*() =
    discard

template alias*(name: untyped, kind: typedesc): untyped =
    type name = kind

template until*(condition, code) =
    code
    while condition:
        code