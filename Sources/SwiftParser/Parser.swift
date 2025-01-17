//===-------------------------- Parser.swift ------------------------------===//
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

extension Parser {
  public static func parse(
    source: String,
    parseTransition: IncrementalParseTransition? = nil,
    filenameForDiagnostics: String = "",
    languageVersion: String? = nil,
    enableBareSlashRegexLiteral: Bool? = nil
  ) throws -> SourceFileSyntax {
    var source = source
    source.makeContiguousUTF8()
    return try source.withUTF8 { buffer in
      return try parse(source: buffer,
                       parseTransition: parseTransition,
                       filenameForDiagnostics: filenameForDiagnostics,
                       languageVersion: languageVersion,
                       enableBareSlashRegexLiteral: enableBareSlashRegexLiteral)
    }
  }

  public static func parse(
    source: UnsafeBufferPointer<UInt8>,
    parseTransition: IncrementalParseTransition? = nil,
    filenameForDiagnostics: String = "",
    languageVersion: String? = nil,
    enableBareSlashRegexLiteral: Bool? = nil
  ) throws -> SourceFileSyntax {
    var parser = Parser(source)
    // Extended lifetime is required because `SyntaxArena` in the parser must
    // be alive until `Syntax(raw:)` retains the arena.
    return withExtendedLifetime(parser) {
      let rawSourceFile =  parser.parseSourceFile()
      return Syntax(raw: rawSourceFile.raw).as(SourceFileSyntax.self)!
    }
  }
}

/// A parser for the Swift programming language.
///
/// `Parser` implements a recursive descent parser that produces a SwiftSyntax
/// tree. Its implementation is divided among a set of files named for the
/// class of syntax nodes they parse. For example, declaration parsing happens
/// in `Declaration.swift`, and expression parsing happens in `Expression.swift`.
///
/// Parsing Swift
/// =============
///
/// Broadly, the parser has a one-to-one correspondence between syntax nodes
/// and parsing functions. If a function consumes input from the token stream,
/// it must be marked `mutating` to do so. Thus, parsing functions that only
/// serve e.g. to read the current token and disambiguate the parse, or recover
/// from a bad parse should be left `nonmutating` to indicate that they do not
/// consume tokens.
///
/// Token consumption is generally conditional via ``TokenConsumer/consume(if:)``
/// or unconditional via `consumeAnyToken()`. During parsing, it is
/// also useful to assert that the current token matches some expected structure
/// via ``TokenConsumer/eat(_:)``, which acts like ``TokenConsumer/consume(if:)``,
/// but asserts if the parsed token did not match the expected kind.
///
/// It can also be useful to expect the presence of certain structural elements.
/// For example, a function that parses the content of code items might expect
/// an opening brace, its items, and also expect a closing brace:
///
///     let lbrace = self.eat(.leftBrace)
///     /*  */
///     let rbrace = self.expect(.rightBrace)
///
/// Unlike ``TokenConsumer/eat(_:)``, `expect(_:)` returns
/// a `missing` token of the given kind. This allows the tree to remain
/// well-formed even when the input text is not, all without affecting
/// source fidelity.
///
/// For compound syntactic structures, parsing loops are often required. The general
/// structure of a source-preserving loop is
///
///     var keepGoing: RawTokenSyntax? = nil
///     repeat {
///       // Parse an element
///       let element = self.parseElement()
///
///       // Consume the delimeter
///       keepGoing = self.consume(if: .delimiter)
///       elements.append(RawElementSyntax(element, ..., keepGoing))
///     } while keepGoing != nil
///
/// Such parsing loops are kept enclosed in `do` blocks to avoid having their
/// state leak into surrounding scopes.
///
/// Lookahead
/// =========
///
/// This parser provides at most one token worth of lookahead via
/// `peek()`. If more tokens are required to disambiguate a parse, a
/// ``Parser/Lookahead`` instance should be constructed instead with
/// ``Parser/lookahead()``.
///
/// Source Fidelity
/// ===============
///
/// The syntax trees produced by this parser are required to faithfully
/// represent the input source text. As such, there are no utilities that allow
/// for skipping tokens in the parser. In addition, consumed tokens must become
/// part of at  least one syntax node.
///
/// The exception to this is parser lookahead, which is allowed to skip as many
/// tokens as needed to disambiguate a parse. However, because lookahead
/// operates on a copy of the lexical stream, no input tokens are lost..
public struct Parser: TokenConsumer {
  let arena: SyntaxArena
  /// A view of the sequence of lexemes in the input.
  var lexemes: Lexer.LexemeSequence
  /// The current token. If there was no input, this token will have a kind of `.eof`.
  @_spi(RawSyntax)
  public var currentToken: Lexer.Lexeme

  /// Initializes a Parser from the given input buffer.
  ///
  /// The lexer will copy any string data it needs from the resulting buffer
  /// so it is the caller's responsibility to free it.
  ///
  /// - Parameters
  ///   - input: An input buffer containing Swift source text.
  ///   - arena: Arena the parsing syntax are made into. If it's `nil`, a new
  ///            arena is created automatically, and `input` copied into the
  ///            arena. If non-`nil`, `input` must be the registered source
  ///            buffer of `arena` or a slice of the source buffer.
  @_spi(Testing)
  public init(_ input: UnsafeBufferPointer<UInt8>, arena: SyntaxArena? = nil) {
    var sourceBuffer: UnsafeBufferPointer<UInt8>
    if let arena = arena {
      self.arena = arena
      sourceBuffer = input
      assert(arena.contains(text: SyntaxText(baseAddress: input.baseAddress, count: input.count)))
   } else {
     self.arena = SyntaxArena(
      parseTriviaFunction: TriviaParser.parseTrivia(_:position:))
     sourceBuffer = self.arena.internSourceBuffer(input)
    }
    self.lexemes = Lexer.tokenize(sourceBuffer)
    self.currentToken = self.lexemes.advance()
  }
}

// MARK: Inspecting Tokens

extension Parser {
  /// Retrieves the token following the current token without consuming it.
  @_spi(RawSyntax)
  public func peek() -> Lexer.Lexeme {
    return self.lexemes.peek()
  }
}

// MARK: Consuming Tokens

extension Parser {
  @_spi(RawSyntax)
  public mutating func missingToken(_ kind: RawTokenKind) -> RawTokenSyntax {
    return RawTokenSyntax(missing: kind, arena: arena)
  }
  /// Consumes the current token and advances the lexer to the next token.
  ///
  /// - Returns: The token that was consumed.
  @_spi(RawSyntax)
  public mutating func consumeAnyToken() -> RawTokenSyntax {
    let tok = self.currentToken
    self.currentToken = self.lexemes.advance()
    return RawTokenSyntax(
      kind: tok.tokenKind,
      wholeText: tok.wholeText,
      textRange: tok.textRange,
      presence: .present,
      arena: arena
    )
  }

  /// Consumes the current token and sets its kind to the given `TokenKind`,
  /// then advances the lexer to the next token.
  ///
  /// - Parameter kind: The kind to reset the consumed token to.
  /// - Returns: The token that was consumed with its kind re-mapped to the
  ///            given `TokenKind`.
  @_spi(RawSyntax)
  public mutating func consume(remapping kind: RawTokenKind) -> RawTokenSyntax {
    self.currentToken.tokenKind = kind
    return self.consumeAnyToken()
  }

  /// Attempts to consume a token of the given kind.
  /// If it cannot be found, the parser tries
  ///  1. To each unexpected tokens that have lower ``TokenPrecedence`` than the
  ///     expected token and see if the token occurs after that unexpected.
  ///  2. If the token couldn't be found after skipping unexpected, it synthesizes
  ///     a missing token of the requested kind.
  @_spi(RawSyntax)
  public mutating func expect(_ kind: RawTokenKind) -> (unexpected: RawUnexpectedNodesSyntax?, token: RawTokenSyntax) {
    if let tok = self.consume(if: kind) {
      return (nil, tok)
    }
    var lookahead = self.lookahead()
    if lookahead.canRecoverTo(kind) {
      var unexpectedNodes = [RawSyntax]()
      for _ in 0..<lookahead.tokensConsumed {
        unexpectedNodes.append(RawSyntax(self.consumeAnyToken()))
      }
      let token = eat(kind)
      return (RawUnexpectedNodesSyntax(elements: unexpectedNodes, arena: self.arena), token)
    }
    return (nil, RawTokenSyntax(missing: kind, arena: self.arena))
  }

  /// Attempts to consume a token whose kind is in `kinds`.
  /// If it cannot be found, the parser tries
  ///  1. To each unexpected tokens that have lower ``TokenPrecedence`` than the
  ///     lowest precedence of the expected token kinds and see if a token of
  ///     the requested kinds occurs after the unexpected.
  ///  2. If the token couldn't be found after skipping unexpected, it synthesizes
  ///     a missing token of `defaultKind`.
  @_spi(RawSyntax)
  public mutating func expectAny(
    _ kinds: [RawTokenKind],
    default defaultKind: RawTokenKind
  ) -> (unexpected: RawUnexpectedNodesSyntax?, token: RawTokenSyntax) {
    for kind in kinds {
      if let tok = self.consume(if: kind) {
        return (nil, tok)
      }
    }
    var lookahead = self.lookahead()
    if lookahead.canRecoverTo(kinds) {
      var unexpectedNodes = [RawSyntax]()
      for _ in 0..<lookahead.tokensConsumed {
        unexpectedNodes.append(RawSyntax(self.consumeAnyToken()))
      }
      let token = consumeAnyToken()
      assert(kinds.contains(token.tokenKind))
      return (RawUnexpectedNodesSyntax(elements: unexpectedNodes, arena: self.arena), token)
    }
    return (nil, RawTokenSyntax(missing: defaultKind, arena: self.arena))
  }

  /// Attempts to consume a token of the given kind, synthesizing a missing
  /// token if the current token's kind does not match.
  ///
  /// This method does not try to eat unexpected until it finds the token of the specified `kind`.
  /// In general, `expect` or `expectAny` should be preferred.
  ///
  /// - Parameter kind: The kind of token to consume.
  /// - Returns: A token of the given kind.
  @_spi(RawSyntax)
  public mutating func expectWithoutLookahead(_ kind: RawTokenKind, _ text: SyntaxText? = nil) -> RawTokenSyntax {
    if self.currentToken.tokenKind == kind {
      if let text = text {
        if self.currentToken.tokenText == text {
          return self.consumeAnyToken()
        }
      } else {
        return self.consumeAnyToken()
      }
    }
    return RawTokenSyntax(missing: kind, arena: self.arena)
  }
}

// MARK: Spliting Tokens

extension Parser {
  /// Consumes a given token, or splits the current token into a leading token
  /// matching the given `prefix` and a trailing token and consumes the leading
  /// token.
  ///
  ///     <TOKEN> ... -> consume(<TOK>, as: kind) -> [ <TOK> ] <EN> ...
  mutating func consumePrefix(
    _ prefix: SyntaxText,
    as tokenKind: RawTokenKind
  ) -> RawTokenSyntax {
    let current = self.currentToken
    // Current token can be either one-character token we want to consume...
    let tokenText = current.tokenText

    if tokenText == prefix {
      return self.consume(remapping: tokenKind)
    }
    assert(tokenText.hasPrefix(prefix))

    let endIndex = current.textRange.lowerBound.advanced(by: prefix.count)
    let tok = RawTokenSyntax(
      kind: tokenKind,
      wholeText: SyntaxText(rebasing: current.wholeText[..<endIndex]),
      textRange: current.textRange.lowerBound ..< endIndex,
      presence: .present,
      arena: self.arena
    )

    // ... or a multi-character token with the first N characters being the one
    // that we want to consume as a separate token.
    // Careful: We need to reset the lexer to a point just before it saw the
    // current token, plus the split point. That means we need to take trailing
    // trivia into account for the current token, but we only need to take the
    // number of UTF-8 bytes of the text of the split - no trivia necessary.
    //
    // <TOKEN<trailing trivia>> <NEXT TOKEN> ... -> <T> <OKEN<trailing trivia>> <NEXT TOKEN>
    //
    // The current calculation is:
    //
    //        <<leading trivia>TOKEN<trailing trivia>>
    //                                        CURSOR ^
    // + trailing trivia length
    //
    //        <<leading trivia>TOKEN<trailing trivia>>
    //                       CURSOR ^
    // + content length
    //
    //        <<leading trivia>TOKEN<trailing trivia>>
    //                  CURSOR ^
    // - split point length
    //
    //        <<leading trivia>TOKEN<trailing trivia>>
    //                   CURSOR ^
    let offset = (self.currentToken.trailingTriviaByteLength
                  + tokenText.count
                  - prefix.count)
    self.currentToken = self.lexemes.resetForSplit(of: offset)
    return tok
  }
}

extension SyntaxText {
  func withBuffer<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
    try body(UnsafeBufferPointer<UInt8>(start: self.baseAddress, count: self.count))
  }
}
