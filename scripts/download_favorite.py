#!/usr/bin/env python3
"""启动 C0SnowMusic 扫码播放；--download-only 保留旧版下载方式。"""

import argparse
import hashlib
import re
import sys
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.parse import urlencode, urlsplit

import qrcode
import requests

API = "https://api.bilibili.com"
PASSPORT = "https://passport.bilibili.com"
MIXIN = (
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
    22, 25, 54, 21, 56, 62, 6, 63, 57, 20, 34, 52, 59, 11, 36, 44,
)


class DownloadError(Exception):
    """可以直接展示给用户的错误，不包含 Cookie 和媒体签名地址。"""


def sign_wbi(params, image_url, sub_url, now=None):
    raw = Path(urlsplit(image_url).path).stem + Path(urlsplit(sub_url).path).stem
    if len(raw) != 64:
        raise DownloadError("B 站返回的 WBI key 格式不正确。")
    key = "".join(raw[i] for i in MIXIN)[:32]
    values = {**params, "wts": int(time.time() if now is None else now)}
    values = {k: re.sub(r"[!'()*]", "", str(v)) for k, v in values.items()}
    query = urlencode(sorted(values.items()))
    values["w_rid"] = hashlib.md5((query + key).encode()).hexdigest()
    return values


def safe_name(title):
    name = re.sub(r'[\x00-\x1f\x7f/\\:*?"<>|]', "_", str(title)).strip(" .")
    # 给扩展名和重名后缀留空间，也适用于 UTF-8 中文文件名。
    while len(name.encode("utf-8")) > 180:
        name = name[:-1]
    return name or "未命名歌曲"


def detect_extension(first_chunk):
    if first_chunk.startswith(b"fLaC"):
        return ".flac"
    if len(first_chunk) >= 12 and first_chunk[4:8] == b"ftyp":
        return ".m4a"
    if first_chunk.startswith(b"ID3") or (
        len(first_chunk) >= 2 and first_chunk[0] == 0xFF
        and first_chunk[1] & 0xE0 == 0xE0 and first_chunk[1] & 0x06 != 0
    ):
        return ".mp3"
    raise DownloadError("媒体响应不是已识别的音频，已停止保存。")


class Bilibili:
    def __init__(self, session=None, sleeper=time.sleep, clock=time.monotonic):
        self.session = session or requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Referer": "https://www.bilibili.com/",
        })
        self.sleep = sleeper
        self.clock = clock

    def api(self, path, params=None, base=API):
        try:
            with self.session.get(base + path, params=params, timeout=(10, 30)) as response:
                response.raise_for_status()
                payload = response.json()
        except (requests.RequestException, ValueError):
            raise DownloadError(f"B 站接口请求失败：{path}，请检查网络后重试。") from None
        if not isinstance(payload, dict):
            raise DownloadError(f"B 站接口响应格式不正确：{path}。")
        if payload.get("code") != 0:
            raise DownloadError(f"B 站接口拒绝请求：{path}，错误码 {payload.get('code')}。")
        if not isinstance(payload.get("data"), dict):
            raise DownloadError(f"B 站接口没有返回有效数据：{path}。")
        return payload["data"]

    def login(self, output_dir, timeout=180):
        qr = self.api("/x/passport-login/web/qrcode/generate", base=PASSPORT)
        png = output_dir / "bilibili.png"
        qrcode.make(qr["url"]).save(png)
        print(f"二维码已保存：{png}。请用 B 站客户端扫码并确认。", flush=True)
        deadline = self.clock() + timeout
        scanned = False
        while self.clock() < deadline:
            status = self.api("/x/passport-login/web/qrcode/poll",
                              {"qrcode_key": qr["qrcode_key"]}, base=PASSPORT)
            code = status.get("code")
            if code == 0:
                # requests 从 Set-Cookie 收集 Cookie；不从返回 URL 拼造登录凭据。
                if not any(c.name == "SESSDATA" for c in self.session.cookies):
                    raise DownloadError("扫码已确认，但没有收到登录 Cookie，请重新运行。")
                nav = self.api("/x/web-interface/nav")
                if not nav.get("isLogin") or not nav.get("mid"):
                    raise DownloadError("B 站尚未确认登录成功，请重新运行。")
                print("登录成功，正在读取收藏夹。", flush=True)
                return nav
            if code == 86038:
                raise DownloadError("二维码已过期，请重新运行生成新二维码。")
            if code == 86090 and not scanned:
                print("已扫码，请在 B 站客户端确认登录。", flush=True)
                scanned = True
            elif code not in (86101, 86090):
                raise DownloadError(f"扫码登录返回未知状态：{code}。")
            self.sleep(min(1.5, max(0, deadline - self.clock())))
        raise DownloadError("等待扫码超时，请重新运行。")

    def first_favorite(self, mid, folder_id=None):
        if folder_id is not None:
            folders = [{"id": folder_id}]
        else:
            data = self.api("/x/v3/fav/folder/created/list-all", {"up_mid": mid})
            folders = data.get("list") or []
            # list-all 未返回完整数据时，用分页接口按原顺序补齐。
            if data.get("count", len(folders)) > len(folders):
                folders = []
                page = 1
                while True:
                    data = self.api("/x/v3/fav/folder/created/list",
                                    {"up_mid": mid, "pn": page, "ps": 20})
                    batch = data.get("list") or []
                    folders.extend(batch)
                    if not data.get("has_more"):
                        break
                    if not batch:
                        raise DownloadError("收藏夹分页返回异常，无法确定第一首歌。")
                    page += 1
        for folder in folders:
            data = self.api("/x/v3/fav/resource/list", {
                "media_id": folder["id"], "pn": 1, "ps": 20,
                "order": "mtime", "platform": "web",
            })
            videos = data.get("medias") or []
            if videos:
                video = videos[0]
                if video.get("type", 2) != 2 or not (video.get("bvid") or video.get("bv_id")):
                    raise DownloadError("收藏夹第一条不是可下载的视频，未改选其他歌曲。")
                return data.get("info") or folder, video
        raise DownloadError("没有找到非空收藏夹，请先收藏一条视频。")

    def audio(self, video, nav):
        bvid = video.get("bvid") or video.get("bv_id")
        details = self.api("/x/web-interface/view", {"bvid": bvid})
        pages = details.get("pages") or []
        if not pages or not pages[0].get("cid"):
            raise DownloadError("收藏的第一条视频已失效或没有可播放的分 P。")
        keys = nav.get("wbi_img") or {}
        if not keys.get("img_url") or not keys.get("sub_url"):
            raise DownloadError("B 站未返回 WBI key，无法获取音频地址。")
        play = self.api("/x/player/wbi/playurl", sign_wbi({
            "bvid": bvid, "cid": pages[0]["cid"], "fnval": 4048,
            "fnver": 0, "fourk": 1,
        }, keys["img_url"], keys["sub_url"]))
        dash = play.get("dash") or {}
        tracks = list(dash.get("audio") or [])
        for group in ("dolby", "flac"):
            audio = (dash.get(group) or {}).get("audio")
            if isinstance(audio, dict):
                tracks.append(audio)
            elif isinstance(audio, list):
                tracks.extend(audio)
        tracks = [t for t in tracks if t.get("baseUrl") or t.get("base_url")]
        if not tracks:
            raise DownloadError("B 站没有提供独立音轨，可能受版权或账号权限限制。")
        track = max(tracks, key=lambda t: t.get("bandwidth") or 0)
        return details, pages[0], track

    def download(self, track, output_dir, name):
        urls = [track.get("baseUrl") or track.get("base_url")]
        urls.extend(track.get("backupUrl") or track.get("backup_url") or [])
        for url in dict.fromkeys(urls):
            parts = urlsplit(url)
            if parts.scheme != "https" or not parts.hostname:
                continue
            temporary = None
            try:
                # CDN 的域名可能不同；不把账号 Cookie 发送给媒体服务器。
                with requests.get(url, headers=dict(self.session.headers),
                                  stream=True, timeout=(10, 60)) as response:
                    response.raise_for_status()
                    if "text/" in response.headers.get("Content-Type", "").lower():
                        raise DownloadError("媒体服务器返回了文字页面。")
                    chunks = response.iter_content(chunk_size=65536)
                    first = next((c for c in chunks if c), b"")
                    extension = detect_extension(first)
                    suffix = 0
                    stem = name
                    while (output_dir / (stem + extension)).exists() or (output_dir / (stem + ".MD")).exists():
                        suffix += 1
                        stem = f"{name} ({suffix})"
                    destination = output_dir / (stem + extension)
                    size = 0
                    with tempfile.NamedTemporaryFile(dir=output_dir, suffix=".part", delete=False) as handle:
                        temporary = Path(handle.name)
                        handle.write(first)
                        size += len(first)
                        for chunk in chunks:
                            handle.write(chunk)
                            size += len(chunk)
                    expected = response.headers.get("Content-Length")
                    if expected and not response.headers.get("Content-Encoding") and size != int(expected):
                        raise DownloadError("媒体下载不完整。")
                    temporary.replace(destination)
                    return destination
            except (requests.RequestException, DownloadError, ValueError):
                # 不展示可能含临时令牌的媒体 URL，改试备用地址。
                continue
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
        raise DownloadError("音频下载失败，所有可用地址均无法下载完整音频。")


def run(output_dir, folder_id=None, login_timeout=180):
    output_dir.mkdir(parents=True, exist_ok=True)
    client = Bilibili()
    try:
        nav = client.login(output_dir, login_timeout)
        folder, video = client.first_favorite(nav["mid"], folder_id)
        details, page, track = client.audio(video, nav)
        title = str(details.get("title") or video.get("title") or "未命名歌曲")
        print(f"正在下载：{title}", flush=True)
        path = client.download(track, output_dir, safe_name(title))
        description = path.with_suffix(".MD")
        description.write_text(
            f"# {title.replace(chr(10), ' ').replace(chr(13), ' ')}\n\n"
            f"- 收藏夹：{folder.get('title', folder.get('id', ''))}\n"
            f"- 视频：https://www.bilibili.com/video/{details.get('bvid', video.get('bvid', video.get('bv_id')))}\n"
            f"- 分 P：第一 P（cid={page['cid']}）\n"
            f"- 音频文件：{path.name}\n"
            f"- 文件大小：{path.stat().st_size} 字节\n"
            f"- 格式：{path.suffix.lstrip('.')}（原始音轨，未转码）\n\n"
            "按 B 站返回顺序选择第一个非空的自建收藏夹，"
            "取按收藏时间倒序排列的第一条视频；指定收藏夹时只读取该收藏夹。\n"
            "歌名使用视频标题。Cookie 仅用于本次运行，不写入文件。\n",
            encoding="utf-8",
        )
        print(f"已保存：{path}\n已保存：{description}", flush=True)
        return path, description
    finally:
        client.session.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("/home/C0SnowMusic"))
    parser.add_argument("--folder-id", type=int, help="指定自建收藏夹 ID；默认取第一个非空收藏夹")
    parser.add_argument("--login-timeout", type=int, default=180, help="等待扫码的秒数，默认 180")
    parser.add_argument("--download-only", action="store_true", help="仅下载音轨，使用 issue #3 的旧版方式")
    parser.add_argument("--capture-evidence", action="store_true", help="播放时每隔 10 秒保存截图，共 6 张")
    args = parser.parse_args()
    if args.login_timeout <= 0 or (args.folder_id is not None and args.folder_id <= 0):
        parser.error("等待时间和收藏夹 ID 必须大于 0")
    if not args.download_only:
        executable = shutil.which("c0snowmusic")
        if not executable:
            print("请先安装远端 CI 生成的 C0SnowMusic deb，或使用 --download-only 下载音轨。", file=sys.stderr)
            return 1
        if args.folder_id is not None:
            parser.error("播放时请在软件页面输入收藏夹 ID")
        command = [executable, "--bilibili", "--bilibili-autoplay"]
        if args.capture_evidence:
            command.append(f"--evidence-dir={args.output_dir.resolve()}")
        return subprocess.call(command)
    try:
        run(args.output_dir, args.folder_id, args.login_timeout)
    except KeyboardInterrupt:
        print("\n已停止。", file=sys.stderr)
        return 130
    except (DownloadError, OSError, KeyError, TypeError) as error:
        message = str(error) if isinstance(error, DownloadError) else "数据或文件处理失败，请检查目录权限和接口数据。"
        print(f"失败：{message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
