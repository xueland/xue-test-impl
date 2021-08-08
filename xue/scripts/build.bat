@ECHO OFF

SET task=debug

REM there's no $# ( argc ) like bash. So, we need to count
SET argc=0
FOR %%n IN (%*) DO SET /A argc+=1

IF %argc% GTR 1 (
    ECHO.
    ECHO [*] usage: build.bat [task]
    EXIT /B 2
)
IF %argc% EQU 1 SET task=%1

REM there's no case statement. So, let's do with conditions.
IF %task% == debug GOTO :debug
IF %task% == release GOTO :release
IF %task% == profiler GOTO :profiler
IF %task% == clean GOTO :clean

ECHO.
ECHO [*] unknown task: %task%
EXIT /B 2

:clean
    rd /s /q "bin"
    GOTO :EOF

:release
    nimble --cc:clang build --define:danger --define:noSignalHandler --gc:arc --passC:-flto --passL:-flto
    GOTO :EOF

:debug
    nimble --cc:clang build --define:debug --gc:arc
    GOTO :EOF

:profiler
    nimble --cc:clang build --define:danger --define:noSignalHandler --gc:arc --passC:-flto --passL:-flto --opt:speed --lineDir:on --debuginfo --debugger:native
    GOTO EOF
