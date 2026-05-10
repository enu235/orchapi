ALTER TABLE sessions ADD COLUMN external_task_json TEXT;
ALTER TABLE sessions ADD COLUMN writeback_status TEXT;
ALTER TABLE sessions ADD COLUMN writeback_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE sessions ADD COLUMN writeback_last_error TEXT;
CREATE INDEX IF NOT EXISTS sessions_writeback_idx ON sessions(writeback_status);
