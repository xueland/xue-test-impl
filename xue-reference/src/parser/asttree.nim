import "../parser/token"
import "../common/sintaks"
import "../interpreter/core"

type
    XueCodeGenerator* = ref object of RootObj

    XueAstNodeKind* = enum
        XUE_NODE_LITERAL,
        XUE_NODE_MONO_OP,
        XUE_NODE_DUO_OP,
        XUE_NODE_GROUPING,
        XUE_ECHO_STMT,
        XUE_EXPR_STMT,

    XueAstNode* = ref object of RootObj
        kind*: XueAstNodeKind
        dataKind*: XueValueKind

    XueLiteralNode* = ref object of XueAstNode
        value*: XueToken

    XueGroupingNode* = ref object of XueAstNode
        expression*: XueAstNode

    XueDuoOpNode* = ref object of XueAstNode
        left*: XueAstNode
        operator*: XueToken
        right*: XueAstNode

    XueMonoOpNode* = ref object of XueAstNode
        operator*: XueToken
        right*: XueAstNode

    XueEchoStatement* = ref object of XueAstNode
        value*: XueAstNode
        token*: XueToken

    XueExpressionStatement* = ref object of XueAstNode
        expression*: XueAstNode
        token*: XueToken
endtype

# generator interface
method visitLiteralNode(generator: XueCodeGenerator, 
                            node: XueLiteralNode) {.base.} =
    raise newException(CatchableError, 
        "Oops, code-generator must implement this method")
endmethod

method visitGroupingNode(generator: XueCodeGenerator, 
                            node: XueGroupingNode) {.base.} =
    raise newException(CatchableError, 
        "Oops, code-generator must implement this method")
endmethod

method visitMonoOpNode(generator: XueCodeGenerator, 
                            node: XueMonoOpNode) {.base.} =
    raise newException(CatchableError, 
        "Oops, code-generator must implement this method")
endmethod

method visitDuoOpNode(generator: XueCodeGenerator, 
                            node: XueDuoOpNode) {.base.} =
    raise newException(CatchableError, 
        "Oops, code-generator must implement this method")
endmethod

method visitEchoStatement(generator: XueCodeGenerator,
                            statement: XueEchoStatement) {.base.} =
    raise newException(CatchableError,
        "Oops, code-generator must implement this method")
endmethod

method visitExpressionStatement(generator: XueCodeGenerator,
                            node: XueExpressionStatement) {.base.} =
    raise newException(CatchableError,
        "Oops, code-generator must implement this method")

method generateNode(generator: XueCodeGenerator, 
                            node: XueAstNode) {.base.} =
    raise newException(CatchableError, 
        "Oops, code-generator must implement this method")
endmethod

# constructors
proc newXueLiteralNode*(value: XueToken, dataKind: XueValueKind): XueLiteralNode =
    new(result)
    result.kind = XUE_NODE_LITERAL
    result.value = value
    result.dataKind = dataKind
endproc

proc newXueGroupingNode*(expression: XueAstNode, 
            dataKind: XueValueKind): XueGroupingNode =
    new(result)
    result.kind = XUE_NODE_GROUPING
    result.expression = expression
    result.dataKind = dataKind
endproc

proc newXueMonoOpNode*(operator: XueToken, right: XueAstNode, 
            dataKind: XueValueKind): XueMonoOpNode =
    new(result)
    result.kind = XUE_NODE_MONO_OP
    result.operator = operator
    result.right = right
    result.dataKind = dataKind
endproc

proc newXueDuoOpNode*(left: XueAstNode, operator: XueToken, 
            right: XueAstNode, dataKind: XueValueKind): XueDuoOpNode =
    new(result)
    result.kind = XUE_NODE_DUO_OP
    result.left = left
    result.operator = operator
    result.right = right
    result.dataKind = dataKind
endproc

proc newXueEchoStatement*(value: XueAstNode, token: XueToken): XueEchoStatement =
    new(result)
    result.kind = XUE_ECHO_STMT
    result.value = value
    result.token = token
    result.dataKind = XUE_VALUE_NOTHING
endproc

proc newXueExpressionStatement*(expression: XueAstNode, token: XueToken): XueExpressionStatement =
    new(result)
    result.kind = XUE_EXPR_STMT
    result.expression = expression
    result.token = token
    result.dataKind = XUE_VALUE_NOTHING
endproc

# ast node interface
method accept*(node: XueAstNode, generator: XueCodeGenerator) {.base.} =
    raise newException(CatchableError, "Oops, node must implement accept method")
endmethod

method accept(node: XueLiteralNode, generator: XueCodeGenerator) =
    generator.visitLiteralNode(node)
endmethod

method accept(node: XueGroupingNode, generator: XueCodeGenerator) =
    generator.visitGroupingNode(node)
endmethod

method accept(node: XueDuoOpNode, generator: XueCodeGenerator) =
    generator.visitDuoOpNode(node)
endmethod

method accept(node: XueMonoOpNode, generator: XueCodeGenerator) =
    generator.visitMonoOpNode(node)
endmethod

method accept(node: XueEchoStatement, generator: XueCodeGenerator) =
    generator.visitEchoStatement(node)
endmethod

method accept(node: XueExpressionStatement, generator: XueCodeGenerator) =
    generator.visitExpressionStatement(node)
endmethod
