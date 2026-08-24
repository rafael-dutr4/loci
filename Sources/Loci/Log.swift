import Foundation

/// A line per thing that happens, on stderr.
///
/// Loci talks to a part of macOS that has no API and no documentation, so when
/// something is wrong the question is always what the system said, not what the
/// code looks like. Printing what came back from the preference domain answers
/// that in one run.
enum Log {
  private static let start = Date()

  static func say(_ message: String) {
    let elapsed = String(format: "%7.2fs", Date().timeIntervalSince(start))
    FileHandle.standardError.write(Data("[\(elapsed)] \(message)\n".utf8))
  }
}
