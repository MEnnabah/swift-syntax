@_spi(RawSyntax) import SwiftSyntax
@_spi(RawSyntax) import SwiftParser
import XCTest

final class AttributeTests: XCTestCase {
  func testMissingArgumentToAttribute() {
    AssertParse(
      """
      @_dynamicReplacement(#^DIAG_1^#
      func #^DIAG_2^#test_dynamic_replacement_for2() {
      }
      """,
      diagnostics: [
        DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected 'for' in attribute argument"),
        DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected ':' in attribute argument"),
        DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected ')' to end attribute"),
      ]
    )
  }
  
  func testMissingGenericTypeToAttribute() {
    AssertParse(
      """
      @differentiable(reverse wrt#^DIAG_1^#,where T#^DIAG_2^#
      func podcastPlaybackSpeed() {
      }
      """,
      diagnostics: [
        DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected ':' in '@differentiable' argument"),
        DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected '=' in same type requirement"),
        DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected ')' to end attribute"),
      ]
    )
  }
  
  func testMissingClosingParenToAttribute() {
    AssertParse(
      """
      @_specialize(e#^DIAG_1^#
      """,
      diagnostics: [
        DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected ':' in attribute argument"),
        DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected ')' to end attribute"),
      ]
    )
  }
  
  func testMultipleInvalidSpecializeParams() {
    AssertParse(
      """
      @_specialize(e#^DIAG_1^#, exported#^DIAG_2^#)
      """,
      diagnostics: [
        DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected ':' in attribute argument"),
        DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected ':' in attribute argument"),
        DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected 'false' in attribute argument"),
      ]
    )
  }
}
