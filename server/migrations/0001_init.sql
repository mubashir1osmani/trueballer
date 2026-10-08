-- Accounts, plans, and usage counts only. Note text, tasks, grades and
-- calendar data never reach this database; they stay on the student's phone.
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  plan TEXT NOT NULL DEFAULT 'free',
  plan_expires_at INTEGER,
  ai_consent_at INTEGER
);

-- One row per sign-in provider so a student can link Apple and Google.
CREATE TABLE identities (
  provider TEXT NOT NULL CHECK (provider IN ('apple', 'google')),
  subject TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (provider, subject)
);
CREATE INDEX identities_user ON identities(user_id);

-- Daily request counts for quota enforcement. No content is stored.
CREATE TABLE usage (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  requests INTEGER NOT NULL DEFAULT 0,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);
