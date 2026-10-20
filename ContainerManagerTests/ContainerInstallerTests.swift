//
//  ContainerInstallerTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// container 1.6.0 was published with only `container-installer-unsigned.pkg`, which the
/// updater can't verify. It has to fall back to the newest signed release and say why.
struct ContainerInstallerTests {
    static func release(
        _ tag: String, signed: Bool = true, draft: Bool = false, prerelease: Bool = false
    ) -> GitHub.Release {
        var assets = [asset("container-installer-unsigned.pkg"), asset("container-dSYM.zip")]
        if signed { assets.append(asset("container-\(tag)-installer-signed.pkg")) }
        return GitHub.Release(tagName: tag, draft: draft, prerelease: prerelease, assets: assets)
    }

    static func asset(_ name: String) -> GitHub.Release.Asset {
        GitHub.Release.Asset(name: name, browserDownloadURL: URL(string: "https://example.com/\(name)")!)
    }

    @Test("An unsigned newest release falls back to the signed one before it")
    func unsignedNewest() {
        let lookup = ContainerInstaller.newestSigned([
            Self.release("1.6.0", signed: false), Self.release("1.5.0"), Self.release("1.4.1"),
        ])
        #expect(lookup.signed?.version == "1.5.0")
        #expect(lookup.signed?.pkgURL.lastPathComponent == "container-1.5.0-installer-signed.pkg")
        #expect(lookup.unsignedNewer == "1.6.0")
    }

    @Test("The newest signed release is chosen, whatever order GitHub lists them in")
    func newestSigned() {
        let lookup = ContainerInstaller.newestSigned([
            Self.release("1.5.0"), Self.release("1.6.0"), Self.release("1.4.1"),
        ])
        #expect(lookup.signed?.version == "1.6.0")
        #expect(lookup.unsignedNewer == nil)
    }

    @Test("Drafts, prereleases and unparseable tags are skipped")
    func skipsUnpublished() {
        let lookup = ContainerInstaller.newestSigned([
            Self.release("1.7.0", draft: true), Self.release("1.7.0-rc1", prerelease: true),
            Self.release("nightly"), Self.release("1.6.0"),
        ])
        #expect(lookup.signed?.version == "1.6.0")
        #expect(lookup.unsignedNewer == nil)
    }

    @Test("No signed release at all reports the newest as unsigned")
    func noneSigned() {
        let lookup = ContainerInstaller.newestSigned([Self.release("1.6.0", signed: false)])
        #expect(lookup.signed == nil)
        #expect(lookup.unsignedNewer == "1.6.0")
        #expect(ContainerInstaller.newestSigned([]).unsignedNewer == nil)
    }
}
