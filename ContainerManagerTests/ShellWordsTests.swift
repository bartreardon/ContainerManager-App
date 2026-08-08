//
//  ShellWordsTests.swift
//  ContainerManagerTests
//

import Testing

@testable import ContainerManager

/// `ContainerServiceSpec.commandLine` rebuilds a container's argv by splitting the
/// stored command line, so a split that loses or invents an argument silently changes
/// what a service runs when it's edited or replaced.
@Suite("ShellWords")
struct ShellWordsTests {
    @Test("A quoted argument survives as one argument")
    func quotedArgumentStaysWhole() {
        #expect(ShellWords.split(#"sh -c "a && b""#) == ["sh", "-c", "a && b"])
        #expect(ShellWords.split("sh -c 'a && b'") == ["sh", "-c", "a && b"])
    }

    @Test("Quoting starting mid-argument attaches to it")
    func quoteInsideArgument() {
        #expect(ShellWords.split(#"--flag="a b""#) == ["--flag=a b"])
    }

    @Test("The other quote character is literal inside a quoted run")
    func oppositeQuoteIsLiteral() {
        #expect(ShellWords.split(#"'it"s'"#) == [#"it"s"#])
        #expect(ShellWords.split(#""it's""#) == ["it's"])
    }

    @Test("An empty quoted argument is still an argument")
    func emptyQuotedArgument() {
        #expect(ShellWords.split(#"echo "" done"#) == ["echo", "", "done"])
        #expect(ShellWords.split(#""""#) == [""])
    }

    @Test("Runs of whitespace collapse and don't produce empty arguments")
    func whitespaceCollapses() {
        #expect(ShellWords.split("  a \t b  \n c ") == ["a", "b", "c"])
        #expect(ShellWords.split("") == [])
        #expect(ShellWords.split("   ") == [])
    }

    @Test("An unterminated quote takes the rest of the line")
    func unterminatedQuote() {
        #expect(ShellWords.split(#"sh -c "a && b"#) == ["sh", "-c", "a && b"])
    }

    /// The property `ContainerServiceSpec.commandLine` actually depends on: whatever a
    /// container stores as argv must come back out of a joined command line unchanged.
    @Test(
        "Arguments round-trip through join and split",
        arguments: [
            ["sh", "-c", "a && b"],
            ["nginx", "-g", "daemon off;"],
            ["echo", "hello world"],
            ["echo", ""],
            ["/bin/sh"],
            ["sh", "-c", "echo 'quoted'"],
            ["sh", "-c", #"echo "quoted""#],
            ["a\tb"],
        ])
    func roundTrip(argv: [String]) {
        #expect(ShellWords.split(ShellWords.join(argv)) == argv)
    }

    /// A known limit, recorded so it's a decision rather than a surprise: `join` picks
    /// one quote character to wrap in, so an argument containing *both* has no valid
    /// wrapping and doesn't survive the trip. No image's entrypoint has been seen to
    /// need it, and supporting it means backslash escaping on both sides.
    @Test("An argument containing both quote characters does not round-trip")
    func bothQuoteCharactersIsALimitation() {
        let argv = [#"a"b'c"#]
        #expect(ShellWords.split(ShellWords.join(argv)) != argv)
    }

    @Test("Only arguments that need quoting get it")
    func joinQuotesOnlyWhenNeeded() {
        #expect(ShellWords.join(["nginx", "-g", "daemon off;"]) == #"nginx -g "daemon off;""#)
        #expect(ShellWords.join(["a", "b"]) == "a b")
        #expect(ShellWords.join([""]) == #""""#)
        // Wrapped in the quote it doesn't itself contain.
        #expect(ShellWords.join([#"say "hi""#]) == #"'say "hi"'"#)
    }
}
