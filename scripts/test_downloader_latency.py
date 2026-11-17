"""Remote-only regression: real yt-dlp sessions, HTTP transfers and player cache."""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import tempfile
from threading import Thread
import unittest

from yt_dlp.extractor.youtube import YoutubeIE as UpstreamYoutubeIE
from yt_dlp.utils import DownloadError

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("downloader", root / "MusicApp/Resources/Python/c0snow_downloader.py")
downloader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(downloader)


class DownloaderLatencyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.audio = (root / "MusicApp/Resources/Fixtures/Fixture-Online.m4a").read_bytes()
        (self.directory / "audio.m4a").write_bytes(self.audio)
        self.paths = []
        paths = self.paths

        class Handler(SimpleHTTPRequestHandler):
            def do_GET(self):
                paths.append(self.path)
                if self.path.startswith("/s/player/"):
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"var signatureTimestamp = 12345;")
                else:
                    super().do_GET()

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=self.directory))
        self.thread = Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        base = f"http://127.0.0.1:{self.server.server_port}"

        # Replace only YouTube's remote metadata boundary. The app's _download,
        # yt-dlp player cache, format selection and HTTP downloader remain real.
        class YoutubeIE(UpstreamYoutubeIE):
            def _real_initialize(self):
                pass

            def _real_extract(self, url):
                video_id = self._match_id(url)
                self._load_player(video_id, base + "/s/player/abcdef12/player_ias.vflset/en_US/base.js")
                return {"id": video_id, "title": "Synthetic audio", "url": base + "/audio.m4a",
                        "ext": "m4a", "vcodec": "none", "acodec": "aac", "duration": 3}

        self.extractor = YoutubeIE

    def tearDown(self):
        downloader._close_session()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def request(self, name, cookies=None):
        directory = self.directory / name
        directory.mkdir()
        request = {"directory": str(directory), "video_id": "abcdefghijk",
                   "extractor_cache": str(self.directory / "cache"), "cookies": json.dumps(cookies or [])}
        downloader._active_directory = directory
        session = downloader._download_session(request, directory)
        return request, directory, session

    def test_consecutive_downloads_reuse_player_source_and_write_to_current_directory(self):
        request, first, session = self.request("first")
        session.add_info_extractor(self.extractor())
        self.assertEqual(downloader._download(request, first), 3)
        request, second, reused = self.request("second")
        self.assertIs(reused, session)
        self.assertEqual(downloader._download(request, second), 3)
        self.assertEqual((first / "audio.m4a").read_bytes(), self.audio)
        self.assertEqual((second / "audio.m4a").read_bytes(), self.audio)
        self.assertEqual(sum(path.startswith("/s/player/") for path in self.paths), 1)
        self.assertEqual(self.paths.count("/audio.m4a"), 2)
        self.assertEqual(len(session._progress_hooks), 1)
        self.assertIn("Downloading audio", (second / "diagnostics.jsonl").read_text())

    def test_account_change_closes_old_session_and_preserves_only_disk_extractor_cache(self):
        cookie = {"name": "SID", "value": "first-account", "domain": ".youtube.com", "path": "/",
                  "secure": True, "httpOnly": True}
        _, _, session = self.request("first", [cookie])
        session.cache.store("c0snow-test", "player", {"timestamp": 12345})
        closed = []
        session.add_close_hook(lambda: closed.append(True))
        cookie["value"] = "second-account"
        _, _, replacement = self.request("second", [cookie])
        self.assertIsNot(session, replacement)
        self.assertEqual(closed, [True])
        self.assertEqual([item.value for item in replacement.cookiejar if item.name == "SID"], ["second-account"])
        self.assertEqual(replacement.cache.load("c0snow-test", "player"), {"timestamp": 12345})
        self.assertIsNone(replacement.params.get("cookiefile"))
        cache_contents = "".join(p.read_text() for p in (self.directory / "cache").rglob("*.json"))
        self.assertNotIn("first-account", cache_contents)
        self.assertNotIn("second-account", cache_contents)
        _, _, anonymous = self.request("anonymous")
        self.assertFalse(any(item.name == "SID" for item in anonymous.cookiejar))

    def test_cancelled_download_does_not_issue_requests_or_reuse_failed_session(self):
        request, directory, session = self.request("cancelled")
        session.add_info_extractor(self.extractor())
        (directory / "cancel").touch()
        with self.assertRaises(DownloadError):
            downloader._download(request, directory)
        self.assertEqual(self.paths, [])
        (directory / "cancel").unlink()
        original = downloader._download_progress

        def cancel_on_progress(status):
            (directory / "cancel").touch()
            original(status)

        session._progress_hooks[:] = [cancel_on_progress]
        with self.assertRaises(DownloadError):
            downloader._download(request, directory)
        self.assertIsNone(downloader._session)
        next_request, next_directory, next_session = self.request("recovery")
        next_session.add_info_extractor(self.extractor())
        self.assertEqual(downloader._download(next_request, next_directory), 3)
        self.assertEqual((next_directory / "audio.m4a").read_bytes(), self.audio)


if __name__ == "__main__":
    unittest.main()
