//
//  StackTemplate.swift
//  ContainerManager
//

import Foundation

/// One container within a stack. `env` values may contain `${IP:<key>}` tokens that
/// the orchestrator substitutes with the runtime IP of an earlier service.
struct StackServiceSpec: Identifiable {
    let key: String
    var displayName: String
    var image: String
    var env: [String]
    var volumes: [String]
    var publishPorts: [String]

    var id: String { key }
}

/// A multi-container stack to stand up: a dedicated network plus services started in order.
struct StackSpec {
    var name: String
    var networkName: String
    var services: [StackServiceSpec]
    /// Which service exposes the browser-facing port.
    var webServiceKey: String?
    /// Host port the web service publishes (for the "Open" affordance).
    var webPort: Int?
}

enum StackLabels {
    static let stack = "com.containermanager.stack"
    static let role = "com.containermanager.stack.role"
    static let url = "com.containermanager.stack.url"
}

/// Token used inside service env to reference another service's runtime IP, e.g.
/// `WORDPRESS_DB_HOST=${IP:db}:3306`.
enum StackToken {
    static func ip(_ key: String) -> String { "${IP:\(key)}" }
}

enum StackTemplates {
    /// WordPress backed by MariaDB on a dedicated network, each with a persistent volume.
    /// WordPress reaches the database by its injected IP — no DNS setup required.
    static func wordpress(name rawName: String, dbPassword: String, webPort: Int) -> StackSpec {
        let name = rawName.sanitizedResourceName
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "db",
                    displayName: "MariaDB",
                    image: "mariadb:11",
                    env: [
                        "MARIADB_ROOT_PASSWORD=\(dbPassword)",
                        "MARIADB_DATABASE=wordpress",
                        "MARIADB_USER=wordpress",
                        "MARIADB_PASSWORD=\(dbPassword)",
                    ],
                    volumes: ["\(name)-dbdata:/var/lib/mysql"],
                    publishPorts: []
                ),
                StackServiceSpec(
                    key: "web",
                    displayName: "WordPress",
                    image: "wordpress:latest",
                    env: [
                        "WORDPRESS_DB_HOST=\(StackToken.ip("db")):3306",
                        "WORDPRESS_DB_USER=wordpress",
                        "WORDPRESS_DB_PASSWORD=\(dbPassword)",
                        "WORDPRESS_DB_NAME=wordpress",
                    ],
                    volumes: ["\(name)-wpdata:/var/www/html"],
                    publishPorts: ["\(webPort):80"]
                ),
            ],
            webServiceKey: "web",
            webPort: webPort
        )
    }
}
