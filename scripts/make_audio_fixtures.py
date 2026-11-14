#!/usr/bin/env python3
"""Create synthetic, non-copyrighted audio for remote iOS integration tests."""
from pathlib import Path
import math
import shutil
import struct
import subprocess
import wave

root = Path(__file__).resolve().parents[1] / "MusicApp/Resources/Fixtures"
root.mkdir(parents=True, exist_ok=True)
source = root / "Test Tone.wav"
with wave.open(str(source), "wb") as audio:
    audio.setparams((1, 2, 44_100, 0, "NONE", "not compressed"))
    audio.writeframes(b"".join(struct.pack("<h", int(2_000 * math.sin(2 * math.pi * 440 * frame / 44_100))) for frame in range(44_100 * 3)))
for name, options in [
    ("Fixture.mp3", ["-c:a", "libmp3lame"]),
    ("Fixture.flac", ["-c:a", "flac"]),
    ("Fixture.m4a", ["-c:a", "aac"]),
    ("Fixture.aac", ["-c:a", "aac", "-f", "adts"]),
    ("Fixture-ALAC.m4a", ["-c:a", "alac"]),
    ("Fixture.aiff", ["-c:a", "pcm_s16be"]),
    ("Fixture-24bit-96k.flac", ["-c:a", "flac", "-sample_fmt", "s32", "-ar", "96000", "-ac", "2"]),
    ("Fixture-24bit-96k.wav", ["-c:a", "pcm_s24le", "-ar", "96000", "-ac", "2"]),
]:
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source), *options,
                    "-metadata", "title=雪の音", "-metadata", "artist=C0Snow CI", "-metadata", "album=Offline Fixtures",
                    "-metadata", "track=2", "-metadata", "genre=Test", "-metadata", "date=2026",
                    "-metadata", "lyrics=[00:00.00]First line\n[00:01.00]Second line", str(root / name)], check=True)
shutil.copyfile(root / "Fixture.mp3", root / "中文 日本語 & ♫.mp3")
(root / "Corrupt.flac").write_bytes(b"not an audio file")
(root / "Fixture.lrc").write_text("[offset:100]\n[00:00.00]First line\n[00:01.00][00:02.00]Second line\n", encoding="utf-8")
print(f"Created {len(list(root.iterdir()))} synthetic fixtures in {root}")
