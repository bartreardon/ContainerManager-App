//
//  ShellWords.swift
//  ContainerManager
//

import Foundation

/// Splits and joins command lines the way a shell would, so a quoted argument such as
/// `sh -c "a && b"` survives as one argument instead of being torn apart on spaces.
enum ShellWords {
    /// Splits `text` into arguments, honouring single and double quotes.
    nonisolated static func split(_ text: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character?
        // Tracks a quoted-but-empty argument (`""`), which is still an argument.
        var isQuoted = false

        for character in text {
            if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                isQuoted = true
            } else if character.isWhitespace {
                if isQuoted || !current.isEmpty {
                    args.append(current)
                    current = ""
                    isQuoted = false
                }
            } else {
                current.append(character)
            }
        }
        if isQuoted || !current.isEmpty {
            args.append(current)
        }
        return args
    }

    /// Joins arguments into a command line, quoting any that need it so the result
    /// splits back into the same arguments.
    nonisolated static func join(_ args: [String]) -> String {
        args.map { arg in
            if arg.isEmpty { return "\"\"" }
            guard arg.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" }) else { return arg }
            // Wrap in whichever quote the value doesn't already contain.
            return arg.contains("\"") ? "'\(arg)'" : "\"\(arg)\""
        }
        .joined(separator: " ")
    }
}
