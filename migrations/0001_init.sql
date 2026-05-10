CREATE TABLE IF NOT EXISTS sessions (
    id              TEXT PRIMARY KEY,
    agent           TEXT NOT NULL,
    profile         TEXT,
    spec_json       TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'queued',
    queued_at       TEXT NOT NULL,
    started_at      TEXT,
    finished_at     TEXT,
    exit_code       INTEGER,
    outcome_summary TEXT,
    usage_json      TEXT,
    log_path        TEXT NOT NULL,
    parent_session  TEXT,
    tags_json       TEXT
);

CREATE INDEX IF NOT EXISTS sessions_status_idx  ON sessions(status);
CREATE INDEX IF NOT EXISTS sessions_agent_idx   ON sessions(agent);
CREATE INDEX IF NOT EXISTS sessions_queued_idx  ON sessions(queued_at);
CREATE INDEX IF NOT EXISTS sessions_parent_idx  ON sessions(parent_session);

CREATE TABLE IF NOT EXISTS session_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    ts          TEXT NOT NULL,
    kind        TEXT NOT NULL,
    payload     TEXT
);

CREATE INDEX IF NOT EXISTS session_events_sid_idx ON session_events(session_id, ts);
