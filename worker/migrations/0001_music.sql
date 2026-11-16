PRAGMA foreign_keys = ON;
CREATE TABLE tracks (
  id TEXT PRIMARY KEY,
  source_id TEXT UNIQUE,
  title TEXT NOT NULL,
  artist TEXT NOT NULL DEFAULT '',
  album TEXT NOT NULL DEFAULT '',
  cover_url TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE audio_files (
  id TEXT PRIMARY KEY,
  sha256 TEXT UNIQUE CHECK (sha256 IS NULL OR length(sha256) = 64),
  size_bytes INTEGER NOT NULL CHECK (size_bytes > 0),
  mime_type TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending','ready','failed','missing','hash_pending')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE track_files (
  track_id TEXT NOT NULL REFERENCES tracks(id),
  audio_file_id TEXT NOT NULL REFERENCES audio_files(id),
  PRIMARY KEY (track_id, audio_file_id)
);
CREATE TABLE telegram_objects (
  id TEXT PRIMARY KEY,
  audio_file_id TEXT NOT NULL REFERENCES audio_files(id),
  bot_id TEXT NOT NULL,
  tg_file_id TEXT NOT NULL,
  tg_file_unique_id TEXT NOT NULL,
  chat_id TEXT NOT NULL,
  message_id INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','missing')),
  UNIQUE (chat_id, message_id)
);
CREATE TABLE upload_jobs (
  id TEXT PRIMARY KEY,
  idempotency_key TEXT NOT NULL UNIQUE,
  audio_file_id TEXT REFERENCES audio_files(id),
  status TEXT NOT NULL CHECK (status IN ('pending','ready','failed','uncertain')),
  retry_count INTEGER NOT NULL DEFAULT 0,
  retry_after INTEGER NOT NULL DEFAULT 0,
  error_message TEXT,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE favorites (
  user_id TEXT NOT NULL,
  track_id TEXT NOT NULL REFERENCES tracks(id),
  origin TEXT NOT NULL CHECK (origin IN ('app','youtube')),
  PRIMARY KEY (user_id, track_id, origin)
);
CREATE TABLE plays (
  user_id TEXT NOT NULL,
  track_id TEXT NOT NULL REFERENCES tracks(id),
  played_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  play_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, track_id)
);
CREATE INDEX idx_tracks_title ON tracks(title);
CREATE INDEX idx_tracks_artist ON tracks(artist);
CREATE INDEX idx_telegram_audio ON telegram_objects(audio_file_id, status);
CREATE INDEX idx_telegram_unique ON telegram_objects(bot_id, tg_file_unique_id);
CREATE INDEX idx_favorites_user ON favorites(user_id, origin);
