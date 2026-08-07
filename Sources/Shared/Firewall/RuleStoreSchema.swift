import Foundation

enum RuleStoreSchema {
    static let migrationsBootstrap = """
    PRAGMA journal_mode=WAL;
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at REAL NOT NULL
    );
    """

    static let version1 = """
    CREATE TABLE IF NOT EXISTS rules (
        id TEXT PRIMARY KEY,
        process_bundle_id TEXT,
        process_path TEXT,
        process_name TEXT,
        remote_host TEXT,
        remote_ip TEXT,
        remote_port INTEGER,
        direction TEXT,
        action TEXT,
        scope TEXT,
        priority INTEGER,
        profile TEXT,
        group_name TEXT,
        notes TEXT,
        enabled INTEGER,
        temporary INTEGER,
        created_at REAL,
        expires_at REAL,
        last_used_at REAL,
        hit_count INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_rules_profile ON rules(profile);
    CREATE INDEX IF NOT EXISTS idx_rules_process ON rules(process_path);
    CREATE INDEX IF NOT EXISTS idx_rules_host ON rules(remote_host);

    CREATE TABLE IF NOT EXISTS connections (
        id TEXT PRIMARY KEY,
        pid INTEGER,
        process_name TEXT,
        process_path TEXT,
        process_bundle_id TEXT,
        local_port INTEGER,
        remote_host TEXT,
        remote_ip TEXT,
        remote_port INTEGER,
        direction TEXT,
        status TEXT,
        protocol_name TEXT,
        bytes_in INTEGER,
        bytes_out INTEGER,
        country TEXT,
        country_code TEXT,
        latitude REAL,
        longitude REAL,
        first_seen REAL,
        last_seen REAL
    );
    CREATE INDEX IF NOT EXISTS idx_conn_status ON connections(status);
    CREATE INDEX IF NOT EXISTS idx_conn_pid ON connections(pid);
    CREATE INDEX IF NOT EXISTS idx_conn_last_seen ON connections(last_seen DESC);

    CREATE TABLE IF NOT EXISTS profiles (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE,
        mode TEXT,
        icon TEXT,
        is_active INTEGER
    );

    CREATE TABLE IF NOT EXISTS blocklists (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE,
        url TEXT,
        enabled INTEGER,
        last_updated REAL,
        entry_count INTEGER
    );

    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
    );
    """

    static let version2 = """
    ALTER TABLE rules ADD COLUMN code_team_id TEXT;
    ALTER TABLE rules ADD COLUMN requires_signature INTEGER DEFAULT 0;
    ALTER TABLE connections ADD COLUMN code_team_id TEXT;
    ALTER TABLE connections ADD COLUMN signing_status TEXT;
    CREATE TABLE IF NOT EXISTS sightings (
        kind TEXT NOT NULL,
        key TEXT NOT NULL,
        first_seen REAL NOT NULL,
        last_seen REAL NOT NULL,
        PRIMARY KEY (kind, key)
    );
    CREATE INDEX IF NOT EXISTS idx_sightings_last ON sightings(last_seen DESC);
    """

    static let defaultProfiles: [Profile] = [
        Profile(name: "default", mode: .alert, icon: "shield", isActive: true),
        Profile(name: "home", mode: .silentAllow, icon: "house"),
        Profile(name: "public-wifi", mode: .alert, icon: "wifi.exclamationmark"),
        Profile(name: "lockdown", mode: .silentDeny, icon: "lock.shield")
    ]

    static let defaultBlocklists: [BlocklistInfo] = [
        BlocklistInfo(name: "1Hosts (Lite)", url: "https://o0.pages.dev/Lite/hosts.txt"),
        BlocklistInfo(name: "OISD (small)", url: "https://small.oisd.nl/"),
        BlocklistInfo(name: "StevenBlack unified", url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"),
        BlocklistInfo(name: "AdGuard DNS", url: "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"),
        BlocklistInfo(name: "HaGeZi Multi Light", url: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/light.txt"),
        BlocklistInfo(name: "URLhaus", url: "https://urlhaus.abuse.ch/downloads/hostfile/"),
        BlocklistInfo(name: "Anti-PopAds", url: "https://raw.githubusercontent.com/Yhonay/antipopads/master/hosts"),
        BlocklistInfo(name: "Peter Lowe", url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext")
    ]
}
