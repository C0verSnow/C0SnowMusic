"""仅在远端 CI 执行；使用模拟接口，不需要真实账号。"""

import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.parse import urlencode

import requests

from scripts.download_favorite import (
    Bilibili, DownloadError, detect_extension, run, safe_name, sign_wbi,
)

NAV = {"isLogin": True, "mid": 123, "wbi_img": {
    "img_url": "https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png",
    "sub_url": "https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png",
}}
AUDIO = b"\x00\x00\x00\x18ftypM4A " + b"audio bytes"


def response(payload=None, chunks=None, headers=None):
    item = Mock()
    item.__enter__ = Mock(return_value=item)
    item.__exit__ = Mock(return_value=False)
    item.json.return_value = payload
    item.headers = headers or {}
    item.iter_content.side_effect = lambda **kwargs: iter(chunks or [])
    return item


class ScriptTests(unittest.TestCase):
    def client(self):
        session = requests.Session()
        session.cookies.set("SESSDATA", "test-only", domain=".bilibili.com")
        return Bilibili(session)

    def test_wbi_known_key_and_filter(self):
        params = {"foo": "a!'()* b", "bar": 123}
        signed = sign_wbi(params, **{
            "image_url": NAV["wbi_img"]["img_url"],
            "sub_url": NAV["wbi_img"]["sub_url"], "now": 1702204169,
        })
        self.assertEqual(signed["foo"], "a b")
        query = urlencode([("bar", "123"), ("foo", "a b"), ("wts", "1702204169")])
        expected = hashlib.md5((query + "ea1db124af3c7062474693fa704f4ff8").encode()).hexdigest()
        self.assertEqual(signed["w_rid"], expected)
        self.assertNotIn("wts", params)

    def test_bad_wbi_key(self):
        with self.assertRaises(DownloadError):
            sign_wbi({}, "https://example.org/a.png", "https://example.org/b.png")

    def test_filename(self):
        self.assertEqual(safe_name("../../歌:名\n"), "_.._歌_名_")
        self.assertLessEqual(len(safe_name("歌" * 300).encode()), 180)
        self.assertEqual(safe_name("..."), "未命名歌曲")

    def test_format_detection(self):
        self.assertEqual(detect_extension(AUDIO), ".m4a")
        self.assertEqual(detect_extension(b"fLaCxyz"), ".flac")
        self.assertEqual(detect_extension(b"ID3xyz"), ".mp3")
        with self.assertRaises(DownloadError):
            detect_extension(b"<html>error</html>")

    def test_login_wait_confirm(self):
        client = self.client()
        client.sleep = Mock()
        client.api = Mock(side_effect=[
            {"url": "https://example.org/scan", "qrcode_key": "key"},
            {"code": 86101}, {"code": 86090}, {"code": 0}, NAV,
        ])
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(client.login(Path(root)), NAV)
            self.assertEqual((Path(root) / "bilibili.png").read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(client.sleep.call_count, 2)

    def test_login_expired(self):
        client = self.client()
        client.api = Mock(side_effect=[{"url": "https://example.org", "qrcode_key": "key"}, {"code": 86038}])
        with tempfile.TemporaryDirectory() as root, self.assertRaisesRegex(DownloadError, "过期"):
            client.login(Path(root))

    def test_login_timeout(self):
        client = self.client()
        client.clock = Mock(side_effect=[0, 200])
        client.api = Mock(return_value={"url": "https://example.org", "qrcode_key": "key"})
        with tempfile.TemporaryDirectory() as root, self.assertRaisesRegex(DownloadError, "超时"):
            client.login(Path(root))

    def test_login_missing_cookie(self):
        client = Bilibili()
        client.api = Mock(side_effect=[{"url": "https://example.org", "qrcode_key": "key"}, {"code": 0}])
        with tempfile.TemporaryDirectory() as root, self.assertRaisesRegex(DownloadError, "Cookie"):
            client.login(Path(root))

    def test_login_server_not_logged_in(self):
        client = self.client()
        client.api = Mock(side_effect=[{"url": "https://example.org", "qrcode_key": "key"}, {"code": 0}, {"isLogin": False}])
        with tempfile.TemporaryDirectory() as root, self.assertRaisesRegex(DownloadError, "登录成功"):
            client.login(Path(root))

    def test_first_nonempty_folder(self):
        client = self.client()
        video = {"bvid": "BVtest", "type": 2}
        client.api = Mock(side_effect=[{"list": [{"id": 10}, {"id": 20}]},
                                       {"medias": []}, {"info": {"id": 20}, "medias": [video]}])
        self.assertEqual(client.first_favorite(123), ({"id": 20}, video))
        self.assertEqual(client.api.call_args.args[1]["media_id"], 20)
        self.assertEqual(client.api.call_args.args[1]["order"], "mtime")

    def test_folder_pagination(self):
        client = self.client()
        video = {"bvid": "BVtest"}
        client.api = Mock(side_effect=[{"count": 2, "list": [{"id": 10}]},
                                       {"list": [{"id": 10}], "has_more": True},
                                       {"list": [{"id": 20}], "has_more": False},
                                       {"medias": []}, {"medias": [video]}])
        self.assertEqual(client.first_favorite(123), ({"id": 20}, video))

    def test_empty_account(self):
        client = self.client()
        client.api = Mock(return_value={"list": []})
        with self.assertRaisesRegex(DownloadError, "非空收藏夹"):
            client.first_favorite(123)

    def test_explicit_folder(self):
        client = self.client()
        client.api = Mock(return_value={"medias": [{"bv_id": "BVtest"}]})
        self.assertEqual(client.first_favorite(123, 42)[0]["id"], 42)
        self.assertEqual(client.api.call_count, 1)

    def test_invalid_first_video_not_skipped(self):
        client = self.client()
        client.api = Mock(return_value={"medias": [{"title": "失效视频"}, {"bvid": "BVtest"}]})
        with self.assertRaises(DownloadError):
            client.first_favorite(123, 42)

    def test_audio_first_page_highest_bandwidth(self):
        client = self.client()
        details = {"pages": [{"cid": 11}, {"cid": 22}]}
        track = {"base_url": "https://cdn.example.org/a", "bandwidth": 100}
        client.api = Mock(side_effect=[details, {"dash": {"audio": [
            {"baseUrl": "https://cdn.example.org/b", "bandwidth": 50}],
            "flac": {"audio": track}}}])
        self.assertEqual(client.audio({"bvid": "BVtest"}, NAV), (details, {"cid": 11}, track))
        self.assertEqual(client.api.call_args.args[1]["cid"], "11")

    def test_audio_missing(self):
        client = self.client()
        client.api = Mock(side_effect=[{"pages": [{"cid": 11}]}, {"dash": {"audio": []}}])
        with self.assertRaisesRegex(DownloadError, "独立音轨"):
            client.audio({"bvid": "BVtest"}, NAV)

    def test_removed_video(self):
        client = self.client()
        client.api = Mock(return_value={"pages": []})
        with self.assertRaisesRegex(DownloadError, "失效"):
            client.audio({"bvid": "BVtest"}, NAV)

    @patch("scripts.download_favorite.requests.get")
    def test_download_backups_without_cookie(self, get):
        get.side_effect = [requests.ConnectionError("secret URL"), response(chunks=[AUDIO])]
        client = self.client()
        with tempfile.TemporaryDirectory() as root:
            path = client.download({"baseUrl": "https://cdn.example.org/a", "backupUrl": ["https://cdn.example.org/b"]}, Path(root), "歌名")
            self.assertEqual(path.name, "歌名.m4a")
            self.assertEqual(path.read_bytes(), AUDIO)
        self.assertNotIn("Cookie", get.call_args.kwargs["headers"])

    @patch("scripts.download_favorite.requests.get")
    def test_incomplete_download_removed(self, get):
        get.return_value = response(chunks=[AUDIO], headers={"Content-Length": "9999"})
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(DownloadError):
                self.client().download({"baseUrl": "https://cdn.example.org/a"}, Path(root), "歌名")
            self.assertEqual(list(Path(root).iterdir()), [])

    @patch("scripts.download_favorite.requests.get")
    def test_stream_failure_removed(self, get):
        item = response()
        def failing_chunks(**kwargs):
            yield AUDIO
            raise requests.ConnectionError("secret")
        item.iter_content.side_effect = failing_chunks
        get.return_value = item
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(DownloadError):
                self.client().download({"baseUrl": "https://cdn.example.org/a"}, Path(root), "歌名")
            self.assertEqual(list(Path(root).iterdir()), [])

    @patch("scripts.download_favorite.requests.get")
    def test_existing_file_preserved(self, get):
        get.return_value = response(chunks=[AUDIO])
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / "歌名.m4a").write_bytes(b"old")
            path = self.client().download({"baseUrl": "https://cdn.example.org/a"}, Path(root), "歌名")
            self.assertEqual(path.name, "歌名 (1).m4a")
            self.assertEqual((Path(root) / "歌名.m4a").read_bytes(), b"old")

    def test_api_error_redacted(self):
        client = self.client()
        client.session.get = Mock(side_effect=requests.ConnectionError("SESSDATA=secret"))
        with self.assertRaises(DownloadError) as error:
            client.api("/test")
        self.assertNotIn("secret", str(error.exception))

    def test_api_business_error(self):
        client = self.client()
        client.session.get = Mock(return_value=response({"code": -101, "message": "secret"}))
        with self.assertRaisesRegex(DownloadError, "-101"):
            client.api("/test")

    @patch("scripts.download_favorite.requests.get")
    def test_whole_flow_and_metadata(self, get):
        get.return_value = response(chunks=[AUDIO])
        client = self.client()
        payloads = [
            {"url": "https://example.org/scan", "qrcode_key": "key"},
            {"code": 0}, NAV, {"list": [{"id": 42}]},
            {"info": {"id": 42, "title": "收藏夹"}, "medias": [{"bvid": "BVtest", "title": "歌名"}]},
            {"bvid": "BVtest", "title": "歌名", "pages": [{"cid": 11}]},
            {"dash": {"audio": [{"baseUrl": "https://cdn.example.org/a", "bandwidth": 50}]}},
        ]
        client.session.get = Mock(side_effect=[response({"code": 0, "data": data}) for data in payloads])
        with patch("scripts.download_favorite.Bilibili", return_value=client), tempfile.TemporaryDirectory() as root:
            audio, md = run(Path(root))
            self.assertEqual(audio.name, "歌名.m4a")
            self.assertEqual(md.name, "歌名.MD")
            self.assertIn("BVtest", md.read_text())
            self.assertNotIn("SESSDATA", md.read_text())
            self.assertTrue((Path(root) / "bilibili.png").exists())
            self.assertEqual(len(list(Path(root).iterdir())), 3)


if __name__ == "__main__":
    unittest.main()
