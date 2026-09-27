//
//  HelperLogicTests.swift
//  ContainerManagerTests
//

import ContainerAPIClient
import DNSServer
import Foundation
import SystemPackage
import Testing

@testable import ContainerManager

/// The privileged helper acts as root on these decisions, so each one is pinned against
/// real tool output and against the inputs an attacker would try.
@Suite("Helper logic")
struct HelperLogicTests {
    // MARK: Domains

    @Test("Ordinary domains are valid", arguments: ["test", "local.dev", "my-domain", "a1.b2.c3", "x"])
    func validDomains(domain: String) {
        #expect(ResolverDomain.isValid(domain))
    }

    @Test(
        "Anything else is refused",
        arguments: [
            "", "Test", "a..b", ".test", "test.", "-test", "test-", "a.-b", "a.b-", "te st",
            "test/../etc", "test/x", "test\n", "tést",
            String(repeating: "a", count: 64),
            (1...64).map { _ in "abc" }.joined(separator: "."),
        ])
    func invalidDomains(domain: String) {
        #expect(!ResolverDomain.isValid(domain))
    }

    @Test("A 63-character label is the longest allowed")
    func labelLength() {
        #expect(ResolverDomain.isValid(String(repeating: "a", count: 63)))
    }

    // MARK: Resolver file

    /// If container changes its resolver format, `container system dns list` stops seeing
    /// the helper's domains — this is where that would show up.
    @Test("container's own resolver reads back the file the helper writes")
    func resolverRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try ResolverDomain.contents(for: "test").write(
            to: directory.appendingPathComponent(ResolverDomain.fileName(for: "test")),
            atomically: true, encoding: .utf8)

        let domains = HostDNSResolver(configPath: FilePath(directory.path)).listDomains()
        #expect(domains.map(\.pqdn) == ["test"])
    }

    @Test("The resolver file points at container's DNS port")
    func resolverContents() {
        #expect(ResolverDomain.fileName(for: "test") == "containerization.test")
        #expect(
            ResolverDomain.contents(for: "test")
                == "domain test\nsearch test\nnameserver 127.0.0.1\nport 2053\n")
    }

    // MARK: Package signature

    static let applePkgutil = """
        Package "container-installer.pkg":
           Status: signed by a developer certificate issued by Apple for distribution
           Notarization: trusted by the Apple notary service
           Signed with a trusted timestamp on: 2026-09-09 01:41:27 +0000
           Certificate Chain:
            1. Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)
               Expires: 2030-06-04 16:44:29 +0000
            2. Developer ID Certification Authority
            3. Apple Root CA
        """

    static let appleSpctl = """
        /Library/Application Support/x/container-installer.pkg: accepted
        source=Notarized Developer ID
        origin=Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)
        """

    @Test("Apple's notarized container installer is accepted")
    func acceptsApple() {
        #expect(PackageSignature.pkgutilAccepts(Self.applePkgutil))
        #expect(PackageSignature.spctlAccepts(Self.appleSpctl))
    }

    @Test("Another team's package is refused, even if notarized")
    func refusesOtherTeam() {
        let other = "Developer ID Installer: Someone Else (ABCDE12345)"
        #expect(!PackageSignature.pkgutilAccepts(
            Self.applePkgutil.replacingOccurrences(of: PackageSignature.installerSigner, with: other)))
        #expect(!PackageSignature.spctlAccepts(
            Self.appleSpctl.replacingOccurrences(of: PackageSignature.installerSigner, with: other)))
    }

    @Test("Apple's name further down the chain doesn't count")
    func refusesAppleAsIntermediate() {
        let output = """
               Status: signed by a developer certificate issued by Apple for distribution
               Notarization: trusted by the Apple notary service
               Certificate Chain:
                1. Developer ID Installer: Someone Else (ABCDE12345)
                2. Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)
            """
        #expect(!PackageSignature.pkgutilAccepts(output))
    }

    @Test("Unsigned or un-notarized packages are refused")
    func refusesUnsignedOrUnnotarized() {
        #expect(!PackageSignature.pkgutilAccepts("Package \"x.pkg\":\n   Status: no signature\n"))
        #expect(!PackageSignature.pkgutilAccepts(
            Self.applePkgutil.replacingOccurrences(
                of: "Notarization: trusted by the Apple notary service\n", with: "")))
        #expect(!PackageSignature.spctlAccepts("x.pkg: rejected\nsource=no usable signature\n"))
        #expect(!PackageSignature.spctlAccepts(
            Self.appleSpctl.replacingOccurrences(
                of: "source=Notarized Developer ID", with: "source=Developer ID")))
    }

    // MARK: Uninstall

    static let packageInfo = """
        package-id: com.apple.container-installer
        version: 1.4.1
        volume: /
        location: usr/local
        install-time: 1790508582
        """

    @Test("The plan removes the receipt's files and its own directories, deepest first")
    func uninstallPlan() throws {
        let plan = try UninstallPlan.make(
            packageInfo: Self.packageInfo,
            files: "bin/container\nlibexec/container/plugins/k8s/bin/k8s\n",
            directories: "bin\nlibexec\nlibexec/container\nlibexec/container/plugins\nlibexec/container/plugins/k8s\nlibexec/container/plugins/k8s/bin\n")
        #expect(plan.files == ["bin/container", "libexec/container/plugins/k8s/bin/k8s"])
        #expect(
            plan.directories == [
                "libexec/container/plugins/k8s/bin", "libexec/container/plugins/k8s",
                "libexec/container/plugins", "libexec/container",
            ])
    }

    @Test("A receipt for anywhere but /usr/local is refused")
    func refusesOtherLocation() {
        #expect(throws: UninstallPlan.PlanError.unexpectedLocation("")) {
            try UninstallPlan.make(
                packageInfo: Self.packageInfo.replacingOccurrences(of: "location: usr/local", with: "location: "),
                files: "bin/container", directories: "")
        }
        #expect(throws: UninstallPlan.PlanError.unexpectedLocation("System/Library")) {
            try UninstallPlan.make(
                packageInfo: Self.packageInfo.replacingOccurrences(of: "usr/local", with: "System/Library"),
                files: "bin/container", directories: "")
        }
    }

    @Test(
        "Paths that could escape /usr/local are refused",
        arguments: ["/etc/passwd", "../etc/passwd", "bin/../../etc/passwd", "bin//container", "./bin/container"])
    func refusesEscapingPaths(path: String) {
        #expect(throws: UninstallPlan.PlanError.unsafePath(path)) {
            try UninstallPlan.make(packageInfo: Self.packageInfo, files: path, directories: "")
        }
    }

    // MARK: Messages

    @Test("Requests and replies survive encoding")
    func codableRoundTrip() throws {
        let request = HelperRequest.createResolver(domain: "test", authorization: Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(HelperRequest.self, from: JSONEncoder().encode(request))
        guard case .createResolver(let domain, let authorization) = decoded else {
            Issue.record("Decoded as \(decoded)")
            return
        }
        #expect(domain == "test")
        #expect(authorization == Data([1, 2, 3]))

        let reply = HelperReply.pong(build: "4", executablePath: "/x")
        let decodedReply = try JSONDecoder().decode(HelperReply.self, from: JSONEncoder().encode(reply))
        guard case .pong(let build, let path) = decodedReply else {
            Issue.record("Decoded as \(decodedReply)")
            return
        }
        #expect(build == "4" && path == "/x")
    }
}
