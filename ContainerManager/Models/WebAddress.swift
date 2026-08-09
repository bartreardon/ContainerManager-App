//
//  WebAddress.swift
//  ContainerManager
//

import Foundation

/// Guessing a URL scheme from a port number.
///
/// There is nothing in a container's configuration that says whether a port speaks TLS,
/// so this is a convention, not a fact: the ports conventionally used for TLS get
/// `https`, everything else gets `http`. Getting it wrong costs a redirect or a warning
/// in the browser, which is why the ports are also shown as plain text to copy.
enum WebAddress {
    private nonisolated static let tlsPorts: Set<UInt16> = [443, 8443]

    nonisolated static func scheme(forPort port: UInt16) -> String {
        tlsPorts.contains(port) ? "https" : "http"
    }

    /// A URL for reaching `port` on `host`.
    nonisolated static func url(host: String, port: UInt16) -> URL? {
        URL(string: "\(scheme(forPort: port))://\(host):\(port)")
    }
}
