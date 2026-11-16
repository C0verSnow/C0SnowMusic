CREATE TABLE favorite_snapshots (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE favorite_snapshot_tracks (
  snapshot_id TEXT NOT NULL REFERENCES favorite_snapshots(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL REFERENCES tracks(id),
  PRIMARY KEY (snapshot_id, track_id)
);
