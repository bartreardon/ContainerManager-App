//
//  PrivilegedOperations.swift
//  ContainerManagerHelper
//

import Foundation
import Security
import Synchronization

/// Everything here executes as root, so every input from the app is re-checked: the
/// request's authorization, the domain, the package's signature.
///
/// Requests are handled synchronously on their session's queue — the app opens a session
/// per request — and changes run one at a time.
final class PrivilegedOperations: Sendable {
    private struct Activity {
        var busy = false
        var last = Date()
    }

    private let activity = Mutex(Activity())
    private let oneAtATime = Mutex(())

    /// True when nothing has happened for `interval` and nothing is running.
    func isIdle(for interval: TimeInterval) -> Bool {
        activity.withLock { !$0.busy && Date().timeIntervalSince($0.last) >= interval }
    }

    func perform(_ request: HelperRequest) -> HelperReply {
        if case .ping = request {
            activity.withLock { $0.last = Date() }
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
            return .pong(build: build, executablePath: Bundle.main.executablePath ?? "")
        }
        return oneAtATime.withLock { _ in
            activity.withLock { $0.busy = true }
            defer { activity.withLock { $0.busy = false; $0.last = Date() } }
            return change(request)
        }
    }

    private func change(_ request: HelperRequest) -> HelperReply {
        do {
            switch request {
            case .ping:
                return .failed(message: "Unexpected ping.")
            case .installPackage(let path, let authorization):
                try Authorization.check(authorization)
                return .done(output: try PackageInstall.install(from: path))
            case .uninstallContainer(let authorization):
                try Authorization.check(authorization)
                return .done(output: try Uninstall.run())
            case .createResolver(let domain, let authorization):
                try Authorization.check(authorization)
                try Resolver.create(domain)
                return .done(output: "")
            case .deleteResolver(let domain, let authorization):
                try Authorization.check(authorization)
                try Resolver.delete(domain)
                return .done(output: "")
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}

struct HelperError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Authorization

enum Authorization {
    /// Defines the right once, on the system's `is-admin` rule: admins pass silently,
    /// anyone else is asked for an administrator's name and password.
    static func defineRightIfNeeded() {
        guard AuthorizationRightGet(HelperIdentity.authorizationRight, nil) != errAuthorizationSuccess else {
            return
        }
        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess, let authRef else { return }
        defer { AuthorizationFree(authRef, []) }
        AuthorizationRightSet(
            authRef, HelperIdentity.authorizationRight, kAuthorizationRuleIsAdmin as CFString,
            "Container Manager wants to change the container tool or local DNS." as CFString, nil, nil)
    }

    static func check(_ externalForm: Data) throws {
        var form = AuthorizationExternalForm()
        guard externalForm.count == MemoryLayout.size(ofValue: form) else {
            throw HelperError("The request's authorization is malformed.")
        }
        withUnsafeMutableBytes(of: &form) { _ = externalForm.copyBytes(to: $0) }

        var authRef: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&form, &authRef) == errAuthorizationSuccess, let authRef else {
            throw HelperError("The request's authorization is invalid.")
        }
        defer { AuthorizationFree(authRef, []) }

        let status = HelperIdentity.authorizationRight.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(authRef, &rights, nil, [.extendRights], nil)
            }
        }
        guard status == errAuthorizationSuccess else {
            throw HelperError("Not authorized: an administrator needs to approve this.")
        }
    }
}

// MARK: - Commands

enum Command {
    /// Runs a system tool by absolute path with a minimal environment; output is
    /// stdout and stderr together.
    static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Install

enum PackageInstall {
    static let stagingRoot = "/Library/Application Support/\(HelperIdentity.helperIdentifier)"
    static let maximumSize: off_t = 1 << 30

    static func install(from path: String) throws -> String {
        guard path.hasPrefix("/") else { throw HelperError("The package path must be absolute.") }
        let staged = try stage(path)
        defer { try? FileManager.default.removeItem(atPath: (staged as NSString).deletingLastPathComponent) }

        // Judged on the staged copy, which nobody but root can change.
        let pkgutil = try Command.run("/usr/sbin/pkgutil", ["--check-signature", staged])
        let spctl = try Command.run("/usr/sbin/spctl", ["-a", "-vv", "-t", "install", staged])
        guard pkgutil.status == 0, PackageSignature.pkgutilAccepts(pkgutil.output),
            spctl.status == 0, PackageSignature.spctlAccepts(spctl.output)
        else {
            throw HelperError("The package isn't Apple's notarized container installer, so it wasn't installed.")
        }

        let result = try Command.run("/usr/sbin/installer", ["-pkg", staged, "-target", "/"])
        guard result.status == 0 else {
            throw HelperError("installer failed (\(result.status)).\n\(result.output)")
        }
        return result.output
    }

    /// Copies the package into a fresh root-only directory through a descriptor opened
    /// without following links, so what's verified and installed is what was read.
    private static func stage(_ source: String) throws -> String {
        let input = open(source, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard input >= 0 else { throw HelperError("Couldn't open the downloaded package.") }
        defer { close(input) }
        var info = stat()
        guard fstat(input, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw HelperError("The downloaded package isn't a regular file.")
        }
        guard info.st_size > 0, info.st_size <= maximumSize else {
            throw HelperError("The downloaded package is an unexpected size.")
        }

        try FileManager.default.createDirectory(
            atPath: stagingRoot, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .ownerAccountID: 0, .groupOwnerAccountID: 0])
        var template = Array("\(stagingRoot)/install.XXXXXX".utf8CString)
        guard let directory = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress) }) else {
            throw HelperError("Couldn't create a staging directory.")
        }
        let destination = String(cString: directory) + "/container-installer.pkg"

        let output = open(destination, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw HelperError("Couldn't stage the package.") }
        defer { close(output) }
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        while true {
            let count = read(input, &buffer, buffer.count)
            guard count >= 0 else { throw HelperError("Couldn't read the downloaded package.") }
            if count == 0 { break }
            guard write(output, buffer, count) == count else { throw HelperError("Couldn't stage the package.") }
        }
        return destination
    }
}

// MARK: - Uninstall

enum Uninstall {
    static func run() throws -> String {
        let id = UninstallPlan.packageIdentifier
        let info = try Command.run("/usr/sbin/pkgutil", ["--pkg-info", id])
        guard info.status == 0 else {
            throw HelperError("container wasn't installed from Apple's package, so there's nothing to uninstall here.")
        }
        guard try Command.run("/usr/bin/pgrep", ["-x", "container-apiserver"]).status != 0 else {
            throw HelperError("container's services are still running. Stop them first.")
        }
        let files = try Command.run("/usr/sbin/pkgutil", ["--only-files", "--files", id])
        let directories = try Command.run("/usr/sbin/pkgutil", ["--only-dirs", "--files", id])
        let plan = try UninstallPlan.make(
            packageInfo: info.output, files: files.output, directories: directories.output)

        var removed = 0
        for file in plan.files {
            let path = try safePath(file)
            if unlink(path) == 0 { removed += 1 }
        }
        for directory in plan.directories {
            _ = rmdir(try safePath(directory))  // Fails harmlessly if something else lives there.
        }
        _ = try Command.run("/usr/sbin/pkgutil", ["--forget", id])
        return "Removed \(removed) files."
    }

    /// The absolute path, provided no component from /usr/local down is a symlink —
    /// otherwise an unlink could land outside /usr/local on a Mac where it's user-owned.
    private static func safePath(_ relative: String) throws -> String {
        var path = UninstallPlan.root
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw HelperError("/usr/local isn't a directory.")
        }
        let components = relative.split(separator: "/")
        for (index, component) in components.enumerated() {
            path += "/" + component
            guard lstat(path, &info) == 0 else { return path }  // Already gone.
            let isLast = index == components.count - 1
            if (info.st_mode & S_IFMT) == S_IFLNK && !isLast {
                throw HelperError("\(path) is a symbolic link, so uninstalling stopped.")
            }
        }
        return path
    }
}

// MARK: - DNS resolver

enum Resolver {
    static func create(_ domain: String) throws {
        let path = try path(for: domain)
        let contents = ResolverDomain.contents(for: domain)
        if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
            guard existing == contents else {
                throw HelperError("\(path) already exists with different contents.")
            }
            return
        }
        let temporary = path + ".tmp"
        unlink(temporary)
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw HelperError("Couldn't write \(path).") }
        let data = Array(contents.utf8)
        let written = write(descriptor, data, data.count)
        close(descriptor)
        guard written == data.count, rename(temporary, path) == 0 else {
            unlink(temporary)
            throw HelperError("Couldn't write \(path).")
        }
        reloadDNS()
    }

    static func delete(_ domain: String) throws {
        let path = try path(for: domain)
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard unlink(path) == 0 else { throw HelperError("Couldn't remove \(path).") }
        reloadDNS()
    }

    private static func path(for domain: String) throws -> String {
        guard ResolverDomain.isValid(domain) else { throw HelperError("“\(domain)” isn't a valid domain.") }
        let directory = ResolverDomain.directory
        var info = stat()
        if lstat(directory, &info) != 0 {
            guard mkdir(directory, 0o755) == 0 else { throw HelperError("Couldn't create \(directory).") }
        } else if (info.st_mode & S_IFMT) != S_IFDIR {
            throw HelperError("\(directory) isn't a directory.")
        }
        return directory + "/" + ResolverDomain.fileName(for: domain)
    }

    private static func reloadDNS() {
        _ = try? Command.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }
}

// MARK: - Idle exit

/// Exits once idle, so the next request launches whatever binary is in the app bundle —
/// a freshly updated one included. Long enough to stay clear of launchd's respawn throttle.
enum IdleExit {
    static func start(operations: PrivilegedOperations) {
        Task.detached {
            while true {
                try? await Task.sleep(for: .seconds(30))
                if operations.isIdle(for: 60) { exit(0) }
            }
        }
    }
}
