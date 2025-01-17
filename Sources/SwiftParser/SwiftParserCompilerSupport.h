/*===----------------------- SwiftParserCompilerSupport.h -------------------===

   This source file is part of the Swift.org open source project

   Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
   Licensed under Apache License v2.0 with Runtime Library Exception

   See https://swift.org/LICENSE.txt for license information
   See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

  ===----------------------------------------------------------------------===*/
#ifndef SWIFT_PARSER_COMPILER_SUPPORT_H
#define SWIFT_PARSER_COMPILER_SUPPORT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

enum SwiftParserConsistencyCheckFlags {
  /// Ensure that the syntax tree produced by the parser fully reproduces the
  /// input source.
  SPCC_RoundTrip = 0x01
};

/// Entry point for the Swift compiler to use for consistency checking.
///
/// - Parameters:
///   - bufferPtr: Pointer to the input buffer.
///   - bufferLength: Length of the input buffer.
///   - filename: The name of the source file, which is used only for diagnostics
///   - flags: Flags that indicate what checks should be performed.
///       0x01: Perform round-trip checking.
/// - Returns: 0 if all requested consistency checks passed, nonzero otherwise.
int swift_parser_consistencyCheck(
  const char *buffer, ptrdiff_t bufferLength, const char *filename,
  unsigned int flags);

#ifdef __cplusplus
}
#endif

#endif /* SWIFT_PARSER_COMPILER_SUPPORT_H */
