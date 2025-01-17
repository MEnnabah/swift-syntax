//===------------------------- Recovery.swift -----------------------------===//
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

@_spi(RawSyntax) import SwiftSyntax

// MARK: Lookahead

extension Parser.Lookahead {
  /// Tries eating tokens until it finds a token of `kind` without skipping any
  /// higher precedence tokens. If it found a token of `kind` in this way,
  /// returns `true`, otherwise `false`.
  /// If this method returns `true`, the parser probably wants to consume the
  /// tokens this lookahead skipped over to find `kind` by consuming
  /// `lookahead.tokensConsumed` as unexpected.
  mutating func canRecoverTo(_ kind: RawTokenKind) -> Bool {
    // If the `Set` implementation has noticable performance overheads, we could
    // provide a matching implementaiton for a single `TokenKind` here.
    return canRecoverTo([kind])
  }

  /// Tries eating tokens until it finds a token whose kind is in `kinds`
  /// without skipping tokens that have a precedence that's higher than the
  /// lowest precedence in `kinds`. If it found a token of `kind` in this way,
  /// returns `true`, otherwise `false`.
  /// If this method returns `true`, the parser probably wants to consume the
  /// tokens this lookahead skipped over to find `kind` by consuming
  /// `lookahead.tokensConsumed` as unexpected.
  mutating func canRecoverTo(_ kinds: [RawTokenKind]) -> Bool {
    assert(!kinds.isEmpty)
    let recoveryPrecedence = kinds.map(TokenPrecedence.init).min()!
    while !self.at(.eof) {
      if !recoveryPrecedence.shouldSkipOverNewlines,
          self.currentToken.isAtStartOfLine {
        break
      }
      if self.atAny(kinds) {
        return true
      }
      let currentTokenPrecedence = TokenPrecedence(self.currentToken.tokenKind)
      if currentTokenPrecedence >= recoveryPrecedence {
        break
      }
      self.consumeAnyToken()
      if let closingDelimiter = currentTokenPrecedence.closingTokenKind {
        guard self.canRecoverTo(closingDelimiter) else {
          break
        }
        self.eat(closingDelimiter)
      }
    }

    return false
  }
}

