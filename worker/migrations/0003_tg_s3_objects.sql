CREATE TABLE tg_s3_objects (
  audio_file_id TEXT PRIMARY KEY REFERENCES audio_files(id),
  object_key TEXT NOT NULL UNIQUE,
  etag TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','missing')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
