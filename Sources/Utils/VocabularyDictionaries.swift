import Foundation

/// Vocabulary dictionary for model prefill prompt
public struct VocabularyDictionary: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let description: String
    public let category: String
    public let terms: [String]

    public init(id: String, name: String, description: String, category: String, terms: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.terms = terms
    }
}

/// Manager for predefined vocabulary dictionaries
public class VocabularyDictionariesManager {
    public static let shared = VocabularyDictionariesManager()

    private init() {}

    /// All available predefined dictionaries
    public let predefinedDictionaries: [VocabularyDictionary] = [
        // PHP Development
        VocabularyDictionary(
            id: "php-development",
            name: "PHP Development",
            description: "PHP development terms",
            category: "Programming",
            terms: [
                "PHP", "namespace", "use", "class", "interface", "trait", "extends", "implements",
                "public", "private", "protected", "static", "final", "abstract",
                "function", "method", "property", "variable", "constant",
                "array", "string", "integer", "float", "boolean", "null",
                "if", "else", "elseif", "switch", "case", "break", "continue",
                "foreach", "for", "while", "do", "return",
                "try", "catch", "finally", "throw", "exception",
                "composer", "autoload", "require", "include",
                "PHPStan", "PHPUnit", "PSR", "Symfony", "Laravel",
                "doctrine", "eloquent", "PDO", "mysqli",
                "session", "cookie", "header", "request", "response",
                "JSON", "XML", "API", "REST", "SOAP",
                "dependency injection", "service container",
                "middleware", "controller", "model", "view", "router",
                "validation", "authentication", "authorization",
                "database", "query", "migration", "seeder",
                "cache", "redis", "memcached",
                "queue", "job", "worker", "cron",
                "MikoPBX", "Asterisk", "FreePBX"
            ]
        ),

        // IP Telephony
        VocabularyDictionary(
            id: "ip-telephony",
            name: "IP Telephony",
            description: "IP telephony and VoIP terms",
            category: "Telephony",
            terms: [
                "SIP", "RTP", "RTCP", "SDP", "VoIP",
                "Asterisk", "FreePBX", "MikoPBX",
                "extension", "trunk", "route", "dial plan", "dialplan",
                "codec", "G.711", "G.729", "Opus", "GSM", "iLBC",
                "DTMF", "IVR", "queue", "ring group",
                "call forward", "call transfer", "call park",
                "voicemail", "conference", "music on hold", "MOH",
                "caller ID", "DID", "DDI", "DOD",
                "register", "invite", "bye", "cancel", "ack",
                "NAT", "STUN", "TURN", "ICE",
                "jitter", "latency", "packet loss", "MOS",
                "softphone", "hardphone", "IP phone",
                "provider", "gateway", "PBX", "PABX",
                "analog", "digital", "ISDN", "PRI", "BRI",
                "failover", "redundancy", "high availability",
                "CDR", "call detail record", "call logging",
                "callback", "auto dialer", "predictive dialer",
                "WebRTC", "SIP.js", "PJSIP", "chan_sip",
                "AMI", "AGI", "ARI", "manager",
                "outbound route", "inbound route",
                "pickup", "follow me", "time condition"
            ]
        ),

        // Cloud Code & DevOps
        VocabularyDictionary(
            id: "cloud-devops",
            name: "Cloud & DevOps",
            description: "Cloud services and DevOps commands",
            category: "Infrastructure",
            terms: [
                "Docker", "container", "image", "Dockerfile", "docker-compose",
                "Kubernetes", "K8s", "pod", "deployment", "service", "ingress",
                "kubectl", "helm", "namespace", "configmap", "secret",
                "AWS", "EC2", "S3", "RDS", "Lambda", "CloudWatch",
                "Azure", "GCP", "Google Cloud Platform",
                "CI/CD", "Jenkins", "GitLab CI", "GitHub Actions",
                "pipeline", "build", "deploy", "release", "artifact",
                "Git", "repository", "commit", "push", "pull", "merge", "branch",
                "pull request", "code review", "merge conflict",
                "nginx", "Apache", "HAProxy", "load balancer",
                "SSL", "TLS", "certificate", "HTTPS",
                "DNS", "domain", "subdomain", "A record", "CNAME",
                "firewall", "VPN", "proxy", "reverse proxy",
                "monitoring", "metrics", "logs", "alerts",
                "Prometheus", "Grafana", "ELK", "Elasticsearch", "Kibana",
                "backup", "restore", "snapshot", "replication",
                "scaling", "autoscaling", "horizontal", "vertical",
                "microservices", "API gateway", "service mesh",
                "Terraform", "Ansible", "infrastructure as code",
                "bash", "shell", "script", "cron", "systemd"
            ]
        ),

        // Database & SQL
        VocabularyDictionary(
            id: "database-sql",
            name: "Database & SQL",
            description: "Database and SQL commands",
            category: "Database",
            terms: [
                "SQL", "database", "table", "column", "row", "record",
                "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
                "WHERE", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN",
                "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET",
                "primary key", "foreign key", "unique", "index", "constraint",
                "transaction", "commit", "rollback", "savepoint",
                "MySQL", "PostgreSQL", "SQLite", "MariaDB", "Oracle",
                "MongoDB", "NoSQL", "document", "collection",
                "schema", "migration", "seed", "dump", "restore",
                "optimization", "query plan", "explain", "analyze",
                "replication", "master", "slave", "sharding",
                "ACID", "isolation", "consistency", "durability",
                "stored procedure", "trigger", "view", "function",
                "varchar", "integer", "timestamp", "datetime", "text"
            ]
        ),

        // Web Development
        VocabularyDictionary(
            id: "web-development",
            name: "Web Development",
            description: "Web development and frontend",
            category: "Web",
            terms: [
                "HTML", "CSS", "JavaScript", "TypeScript",
                "React", "Vue", "Angular", "Svelte",
                "component", "props", "state", "hook", "effect",
                "DOM", "virtual DOM", "Shadow DOM",
                "event", "listener", "handler", "callback",
                "async", "await", "promise", "fetch",
                "webpack", "Vite", "bundler", "transpiler",
                "Babel", "ESLint", "Prettier",
                "npm", "yarn", "pnpm", "package.json",
                "module", "import", "export", "default",
                "responsive", "mobile-first", "media query",
                "flex", "grid", "CSS Grid", "Flexbox",
                "SASS", "LESS", "PostCSS", "Tailwind",
                "SEO", "meta tags", "Open Graph",
                "accessibility", "ARIA", "semantic HTML",
                "Progressive Web App", "PWA", "service worker",
                "REST API", "GraphQL", "WebSocket"
            ]
        )
    ]

    /// Get dictionaries by IDs
    public func getDictionaries(byIds ids: [String]) -> [VocabularyDictionary] {
        return predefinedDictionaries.filter { ids.contains($0.id) }
    }

    /// Get all terms from selected dictionaries
    public func getTerms(fromDictionaryIds ids: [String]) -> [String] {
        let dictionaries = getDictionaries(byIds: ids)
        let allTerms = dictionaries.flatMap { $0.terms }
        // Remove duplicates
        return Array(Set(allTerms))
    }

    /// Build prefill prompt from selected dictionaries and custom text
    public func buildPrefillPrompt(dictionaryIds: [String], customPrompt: String) -> String {
        var components: [String] = []

        // Add custom prompt
        if !customPrompt.isEmpty {
            components.append(customPrompt)
        }

        // Add terms from dictionaries (limit to 100 terms to avoid overloading prefill)
        let terms = getTerms(fromDictionaryIds: dictionaryIds)
        if !terms.isEmpty {
            let limitedTerms = Array(terms.prefix(100))
            let termsString = limitedTerms.joined(separator: ", ")
            components.append("Technical vocabulary: \(termsString)")
        }

        let result = components.joined(separator: ". ")
        LogManager.transcription.debug("Built prefill prompt (\(result.count) chars) with \(dictionaryIds.count) dictionaries")
        return result
    }
}
