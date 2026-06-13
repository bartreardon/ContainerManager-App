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

// MARK: - Data-driven templates

/// A single configurable input on a template's create form.
struct StackTemplateField: Identifiable {
    enum Kind {
        case text
        case password
        case port
        case directory
    }

    let key: String
    let label: String
    var placeholder: String = ""
    var defaultValue: String = ""
    var kind: Kind = .text

    var id: String { key }
}

enum StackTemplateError: LocalizedError {
    case missing(String)
    case invalidPort(String)

    var errorDescription: String? {
        switch self {
        case .missing(let label): "\(label) is required."
        case .invalidPort(let value): "“\(value)” is not a valid port number."
        }
    }
}

/// A ready-made stack: the fields its create form shows, and a builder that turns
/// the collected values into a `StackSpec`.
struct StackTemplateDef: Identifiable {
    let id: String
    let name: String
    let summary: String
    let systemImage: String
    let fields: [StackTemplateField]
    let build: ([String: String]) throws -> StackSpec
}

enum StackTemplates {
    static let all: [StackTemplateDef] = [
        wordpress,
        postgres,
        postgresAdminer,
        mailpit,
        gitea,
        codeServer,
        nginxStatic,
    ]

    // MARK: Helpers

    private static func value(_ values: [String: String], _ key: String) -> String {
        (values[key] ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func port(_ values: [String: String], _ key: String, label: String) throws -> Int {
        let raw = value(values, key)
        guard let port = Int(raw), port > 0, port <= 65535 else {
            throw StackTemplateError.invalidPort(raw)
        }
        return port
    }

    // MARK: WordPress + MariaDB

    static let wordpress = StackTemplateDef(
        id: "wordpress",
        name: "WordPress + MariaDB",
        summary: "A WordPress site backed by a MariaDB database, each on a persistent volume.",
        systemImage: "globe",
        fields: [
            StackTemplateField(key: "name", label: "Stack name", placeholder: "mysite", defaultValue: "mysite"),
            StackTemplateField(key: "password", label: "Database password", defaultValue: "wordpress", kind: .password),
            StackTemplateField(key: "port", label: "Web port", placeholder: "8080", defaultValue: "8080", kind: .port),
        ]
    ) { values in
        let name = value(values, "name").sanitizedResourceName
        let password = value(values, "password")
        let webPort = try port(values, "port", label: "Web port")
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "db", displayName: "MariaDB", image: "mariadb:11",
                    env: [
                        "MARIADB_ROOT_PASSWORD=\(password)",
                        "MARIADB_DATABASE=wordpress",
                        "MARIADB_USER=wordpress",
                        "MARIADB_PASSWORD=\(password)",
                    ],
                    volumes: ["\(name)-dbdata:/var/lib/mysql"], publishPorts: []
                ),
                StackServiceSpec(
                    key: "web", displayName: "WordPress", image: "wordpress:latest",
                    env: [
                        "WORDPRESS_DB_HOST=\(StackToken.ip("db")):3306",
                        "WORDPRESS_DB_USER=wordpress",
                        "WORDPRESS_DB_PASSWORD=\(password)",
                        "WORDPRESS_DB_NAME=wordpress",
                    ],
                    volumes: ["\(name)-wpdata:/var/www/html"], publishPorts: ["\(webPort):80"]
                ),
            ],
            webServiceKey: "web", webPort: webPort
        )
    }

    // MARK: PostgreSQL (standalone)

    static let postgres = StackTemplateDef(
        id: "postgres",
        name: "PostgreSQL",
        summary: "A standalone PostgreSQL database on a persistent volume, published for apps to connect to.",
        systemImage: "cylinder.split.1x2",
        fields: [
            StackTemplateField(key: "name", label: "Stack name", placeholder: "postgres", defaultValue: "postgres"),
            StackTemplateField(key: "password", label: "Password", defaultValue: "postgres", kind: .password),
            StackTemplateField(key: "database", label: "Database name", placeholder: "app", defaultValue: "app"),
            StackTemplateField(key: "port", label: "Port", placeholder: "5432", defaultValue: "5432", kind: .port),
        ]
    ) { values in
        let name = value(values, "name").sanitizedResourceName
        let password = value(values, "password")
        let database = value(values, "database")
        let hostPort = try port(values, "port", label: "Port")
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "db", displayName: "PostgreSQL", image: "postgres:17",
                    env: [
                        "POSTGRES_PASSWORD=\(password)",
                        "POSTGRES_DB=\(database.isEmpty ? "app" : database)",
                    ],
                    volumes: ["\(name)-pgdata:/var/lib/postgresql/data"],
                    publishPorts: ["\(hostPort):5432"]
                )
            ],
            webServiceKey: nil, webPort: nil
        )
    }

    // MARK: PostgreSQL + Adminer

    static let postgresAdminer = StackTemplateDef(
        id: "postgres-adminer",
        name: "PostgreSQL + Adminer",
        summary: "A PostgreSQL database plus Adminer, a web UI to browse and query it.",
        systemImage: "tablecells",
        fields: [
            StackTemplateField(key: "name", label: "Stack name", placeholder: "pgstack", defaultValue: "pgstack"),
            StackTemplateField(key: "password", label: "Database password", defaultValue: "postgres", kind: .password),
            StackTemplateField(key: "database", label: "Database name", placeholder: "app", defaultValue: "app"),
            StackTemplateField(key: "port", label: "Adminer web port", placeholder: "8080", defaultValue: "8080", kind: .port),
        ]
    ) { values in
        let name = value(values, "name").sanitizedResourceName
        let password = value(values, "password")
        let database = value(values, "database")
        let webPort = try port(values, "port", label: "Adminer web port")
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "db", displayName: "PostgreSQL", image: "postgres:17",
                    env: [
                        "POSTGRES_PASSWORD=\(password)",
                        "POSTGRES_DB=\(database.isEmpty ? "app" : database)",
                    ],
                    volumes: ["\(name)-pgdata:/var/lib/postgresql/data"], publishPorts: []
                ),
                StackServiceSpec(
                    key: "web", displayName: "Adminer", image: "adminer:latest",
                    env: [
                        "ADMINER_DEFAULT_SERVER=\(StackToken.ip("db"))",
                    ],
                    volumes: [], publishPorts: ["\(webPort):8080"]
                ),
            ],
            webServiceKey: "web", webPort: webPort
        )
    }

    // MARK: Mailpit

    static let mailpit = StackTemplateDef(
        id: "mailpit",
        name: "Mailpit (email testing)",
        summary: "A local SMTP server with a web inbox: send mail to the SMTP port, read it in the browser.",
        systemImage: "envelope",
        fields: [
            StackTemplateField(key: "name", label: "Stack name", placeholder: "mailpit", defaultValue: "mailpit"),
            StackTemplateField(key: "webPort", label: "Web inbox port", placeholder: "8025", defaultValue: "8025", kind: .port),
            StackTemplateField(key: "smtpPort", label: "SMTP port", placeholder: "1025", defaultValue: "1025", kind: .port),
        ]
    ) { values in
        let name = value(values, "name").sanitizedResourceName
        let webPort = try port(values, "webPort", label: "Web inbox port")
        let smtpPort = try port(values, "smtpPort", label: "SMTP port")
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "mailpit", displayName: "Mailpit", image: "axllent/mailpit:latest",
                    env: ["MP_DATA_FILE=/data/mailpit.db"],
                    volumes: ["\(name)-data:/data"],
                    publishPorts: ["\(webPort):8025", "\(smtpPort):1025"]
                )
            ],
            webServiceKey: "mailpit", webPort: webPort
        )
    }

    // MARK: Gitea

    static let gitea = StackTemplateDef(
        id: "gitea",
        name: "Gitea (Git server)",
        summary: "A self-hosted Git service — single container on SQLite, with a web UI and git-over-SSH, on a persistent volume.",
        systemImage: "arrow.triangle.branch",
        fields: [
            StackTemplateField(key: "name", label: "Stack name", placeholder: "gitea", defaultValue: "gitea"),
            StackTemplateField(key: "webPort", label: "Web port", placeholder: "3000", defaultValue: "3000", kind: .port),
            StackTemplateField(key: "sshPort", label: "SSH port", placeholder: "2222", defaultValue: "2222", kind: .port),
        ]
    ) { values in
        let name = value(values, "name").sanitizedResourceName
        let webPort = try port(values, "webPort", label: "Web port")
        let sshPort = try port(values, "sshPort", label: "SSH port")
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "gitea", displayName: "Gitea", image: "gitea/gitea:latest",
                    env: ["USER_UID=1000", "USER_GID=1000"],
                    volumes: ["\(name)-data:/data"],
                    publishPorts: ["\(webPort):3000", "\(sshPort):22"]
                )
            ],
            webServiceKey: "gitea", webPort: webPort
        )
    }

    // MARK: code-server (VS Code in the browser)

    static let codeServer = StackTemplateDef(
        id: "code-server",
        name: "code-server (VS Code)",
        summary: "VS Code in your browser with a persistent workspace. Sign in with the password below.",
        systemImage: "chevron.left.forwardslash.chevron.right",
        fields: [
            StackTemplateField(key: "name", label: "Stack name", placeholder: "code-server", defaultValue: "code-server"),
            StackTemplateField(key: "password", label: "Password", defaultValue: "changeme", kind: .password),
            StackTemplateField(key: "port", label: "Web port", placeholder: "8443", defaultValue: "8443", kind: .port),
        ]
    ) { values in
        let name = value(values, "name").sanitizedResourceName
        let password = value(values, "password")
        let webPort = try port(values, "port", label: "Web port")
        // The linuxserver image starts as root, chowns /config to PUID:PGID, then
        // drops privileges — so a fresh (root-owned) volume is usable, unlike the
        // codercom image which runs as a non-root user and can't write to it.
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "web", displayName: "code-server", image: "linuxserver/code-server:latest",
                    env: [
                        "PASSWORD=\(password)",
                        "PUID=1000",
                        "PGID=1000",
                        "TZ=Etc/UTC",
                        "DEFAULT_WORKSPACE=/config/workspace",
                    ],
                    volumes: ["\(name)-config:/config"],
                    publishPorts: ["\(webPort):8443"]
                )
            ],
            webServiceKey: "web", webPort: webPort
        )
    }

    // MARK: Nginx + host folder

    static let nginxStatic = StackTemplateDef(
        id: "nginx-static",
        name: "Nginx + host folder",
        summary: "Serve a folder from your Mac as a static site — edit on the host, refresh the browser.",
        systemImage: "doc.richtext",
        fields: [
            StackTemplateField(key: "name", label: "Stack name", placeholder: "site", defaultValue: "site"),
            StackTemplateField(key: "folder", label: "Folder to serve", placeholder: "Choose a folder…", kind: .directory),
            StackTemplateField(key: "port", label: "Web port", placeholder: "8080", defaultValue: "8080", kind: .port),
        ]
    ) { values in
        let name = value(values, "name").sanitizedResourceName
        let folder = value(values, "folder")
        guard !folder.isEmpty else { throw StackTemplateError.missing("Folder to serve") }
        let webPort = try port(values, "port", label: "Web port")
        return StackSpec(
            name: name,
            networkName: "\(name)-net",
            services: [
                StackServiceSpec(
                    key: "web", displayName: "Nginx", image: "nginx:alpine",
                    env: [],
                    volumes: ["\(folder):/usr/share/nginx/html:ro"],
                    publishPorts: ["\(webPort):80"]
                )
            ],
            webServiceKey: "web", webPort: webPort
        )
    }
}
