//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

let formatFile = SourceFile {
  ImportDecl(
    leadingTrivia: .docLineComment(copyrightHeader),
    path: "SwiftSyntax"
  )

  StructDecl(modifiers: [TokenSyntax.public], identifier: "Format") {
    VariableDecl(
      modifiers: [TokenSyntax.public],
      .let,
      name: "indentWidth",
      type: "Int"
    )

    VariableDecl(
      modifiers: [TokenSyntax.private],
      .var,
      name: "indents",
      type: "Int",
      initializer: IntegerLiteralExpr(0)
    )

    InitializerDecl(
      modifiers: [TokenSyntax.public],
      signature: FunctionSignature(
        input: ParameterClause {
          FunctionParameter(
            firstName: .identifier("indentWidth"),
            colon: .colon,
            type: "Int",
            defaultArgument: IntegerLiteralExpr(4)
          )
        }
      )
    ) {
      SequenceExpr {
        MemberAccessExpr(base: "self", name: "indentWidth")
        AssignmentExpr()
        "indentWidth"
      }
    }
  }

  ExtensionDecl(extendedType: "Format") {
    VariableDecl(
      modifiers: [TokenSyntax.public],
      name: "_indented",
      type: "Self"
    ) {
      VariableDecl(.var, name: "copy", initializer: "self")
      SequenceExpr {
        MemberAccessExpr(base: "copy", name: "indents")
        BinaryOperatorExpr("+=")
        IntegerLiteralExpr(1)
      }
      ReturnStmt(expression: "copy")
    }

    VariableDecl(
      modifiers: [TokenSyntax.public],
      name: "_indentTrivia",
      type: "Trivia"
    ) {
      ReturnStmt(expression: TernaryExpr(
        if: SequenceExpr {
          "indents"
          BinaryOperatorExpr("==")
          IntegerLiteralExpr(0)
        },
        then: MemberAccessExpr(name: "zero"),
        else: FunctionCallExpr(MemberAccessExpr(base: "Trivia", name: "spaces")) {
          TupleExprElement(expression: SequenceExpr {
            "indents"
            BinaryOperatorExpr("*")
            "indentWidth"
          })
        }
      ))
    }

    FunctionDecl(
      modifiers: [TokenSyntax.private],
      identifier: .identifier("requiresLeadingNewline"),
      signature: FunctionSignature(
        input: ParameterClause {
          FunctionParameter(
            firstName: .wildcard,
            secondName: .identifier("syntax"),
            colon: .colon,
            type: "SyntaxProtocol"
          )
        },
        output: "Bool"
      )
    ) {
      SwitchStmt(
        expression: FunctionCallExpr(MemberAccessExpr(
          base: FunctionCallExpr("Syntax") {
            TupleExprElement(expression: "syntax")
          },
          name: "as"
        )) {
          TupleExprElement(expression: MemberAccessExpr(base: "SyntaxEnum", name: "self"))
        }
      ) {
        // TODO: Generate cases based on requiresLeadingNewline
        // (which however is only defined on child not on nodes?)
        SwitchCase(label: SwitchDefaultLabel()) {
          ReturnStmt(expression: BooleanLiteralExpr(false))
        }
      }
    }

    FunctionDecl(
      modifiers: [TokenSyntax.public],
      identifier: .identifier("_leadingTrivia"),
      signature: FunctionSignature(
        input: ParameterClause {
          FunctionParameter(
            firstName: .identifier("for").withTrailingTrivia(.space),
            secondName: .identifier("syntax"),
            colon: .colon,
            type: "SyntaxProtocol"
          )
        },
        output: "Trivia"
      )
    ) {
      VariableDecl(
        .var,
        name: "leadingTrivia",
        type: "Trivia",
        initializer: ArrayExpr()
      )

      IfStmt(
        conditions: ExprList {
          FunctionCallExpr("requiresLeadingNewline") {
            TupleExprElement(expression: "syntax")
          }
        }
      ) {
        SequenceExpr {
          "leadingTrivia"
          BinaryOperatorExpr("+=")
          MemberAccessExpr(name: "newline")
          BinaryOperatorExpr("+")
          "_indentTrivia"
        }
      }

      SequenceExpr {
        "leadingTrivia"
        BinaryOperatorExpr("+=")
        MemberAccessExpr(base: "syntax", name: "leadingTrivia")
        BinaryOperatorExpr("??")
        ArrayExpr()
      }

      ReturnStmt(expression: "leadingTrivia")
    }
  }
}
