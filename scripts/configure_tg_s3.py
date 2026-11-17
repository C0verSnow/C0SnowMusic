#!/usr/bin/env python3
"""Deploy verified remote-CI TG-S3 artifacts, preserve the webhook, and copy old audio."""
import argparse
import hashlib
import json
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

from configure_music_backend import ROOT, KEYS, load_settings, bot

S3_KEYS = ('TGS3_ACCESS_KEY_ID', 'TGS3_SECRET_ACCESS_KEY')
MUSIC_URL = 'https://c0snow-music-api.f1515xcn.workers.dev'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['deploy', 'migrate', 'check'])
    parser.add_argument('--env-file', type=Path, default=ROOT / '.env')
    parser.add_argument('--artifact', type=Path, default=ROOT / 'Vendor/tg-s3')
    args = parser.parse_args()
    settings = load_settings(args.env_file)
    if args.operation == 'deploy':
        verify_artifact(args.artifact)
        ensure_credentials(args.env_file)
        settings = load_settings(args.env_file, KEYS + S3_KEYS)
        webhook = bot(settings, 'getWebhookInfo')['url']
        bootstrap(args.artifact, settings)
        with tempfile.TemporaryDirectory(prefix='c0versnow-tgs3-') as directory:
            storage_secrets = Path(directory) / 'storage.json'
            storage_secrets.write_text(json.dumps({'TG_BOT_TOKEN': settings['TELEGRAM_BOT_TOKEN']}))
            storage_secrets.chmod(0o600)
            run('storage/tg-s3/wrangler.toml', 'deploy', str(args.artifact.resolve() / 'worker.mjs'), '--no-bundle', '--secrets-file', str(storage_secrets))
            run('worker/wrangler.toml', 'd1', 'migrations', 'apply', 'c0snow-music', '--remote')
            gateway_secrets = Path(directory) / 'gateway.json'
            gateway_secrets.write_text(json.dumps({key: settings[key] for key in S3_KEYS}))
            gateway_secrets.chmod(0o600)
            run('worker/wrangler.toml', 'deploy', str(args.artifact.resolve() / 'gateway/index.js'), '--no-bundle', '--secrets-file', str(gateway_secrets))
        if bot(settings, 'getWebhookInfo')['url'] != webhook:
            raise RuntimeError('Webhook changed unexpectedly; investigate before continuing.')
        print('Deployed verified artifacts without local compilation; existing webhook preserved.')
    if args.operation == 'migrate':
        migrate(settings)
    api(settings, '/api/tracks?limit=1')
    print('Protected music catalog responds normally. No credentials were printed.')


def verify_artifact(directory):
    expected = json.loads((ROOT / 'storage/tg-s3/upstream.json').read_text())
    if json.loads((directory / 'upstream.json').read_text()) != expected:
        raise RuntimeError('Artifact does not match the pinned upstream revision.')
    manifest = json.loads((directory / 'sha256.json').read_text())
    for required in ['worker.mjs', 'schema.sql', 'gateway/index.js', 'upstream.json']:
        if required not in manifest:
            raise RuntimeError('Artifact lacks required file: ' + required)
    for name, digest in manifest.items():
        path = directory / name
        if not path.resolve().is_relative_to(directory.resolve()) or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError('Artifact integrity verification failed.')
    print('Verified upstream revision and all packaged file digests. Download ZIP must also match GitHub artifact digest.')


def ensure_credentials(path):
    # Preserve generated keys across retries, rather than silently rotating live credentials.
    load_settings(path, ())
    lines = path.read_text().splitlines()
    names = {line.split('=', 1)[0].strip() for line in lines if '=' in line and not line.lstrip().startswith('#')}
    generated = {'TGS3_ACCESS_KEY_ID': 'C0M' + secrets.token_hex(10).upper(), 'TGS3_SECRET_ACCESS_KEY': secrets.token_urlsafe(40)}
    with path.open('a') as stream:
        for key, value in generated.items():
            if key not in names:
                stream.write('\n' + key + '=' + value + '\n')
    path.chmod(0o600)


def bootstrap(artifact, settings):
    run('storage/tg-s3/wrangler.toml', 'd1', 'execute', 'c0snow-tg-s3', '--remote', '--file', str(artifact.resolve() / 'schema.sql'), '--yes')
    values = [settings['TELEGRAM_STORAGE_CHAT_ID'], settings['TGS3_ACCESS_KEY_ID'], settings['TGS3_SECRET_ACCESS_KEY']]
    chat, access, secret = ["'" + value.replace("'", "''") + "'" for value in values]
    sql = f"""INSERT OR IGNORE INTO buckets(name, created_at, tg_chat_id, is_public) VALUES ('c0snow-audio', datetime('now'), {chat}, 0);
INSERT INTO credentials(access_key_id, secret_access_key, name, buckets, permission)
VALUES ({access}, {secret}, 'c0versnow music gateway', 'c0snow-audio', 'readwrite')
ON CONFLICT(access_key_id) DO UPDATE SET secret_access_key = excluded.secret_access_key, buckets = excluded.buckets, permission = excluded.permission, is_active = 1;
"""
    with tempfile.TemporaryDirectory(prefix='c0versnow-tgs3-sql-') as directory:
        path = Path(directory) / 'bootstrap.sql'
        path.write_text(sql); path.chmod(0o600)
        run('storage/tg-s3/wrangler.toml', 'd1', 'execute', 'c0snow-tg-s3', '--remote', '--file', str(path), '--yes', sensitive=True)
    print('Initialized private bucket and bucket-scoped gateway credential.')


def migrate(settings):
    seen = set(); offset = 0
    while True:
        tracks = api(settings, f'/api/tracks?limit=100&offset={offset}')['items']
        for track in tracks:
            for file in track['files']:
                digest = file['sha256']
                if not digest or digest in seen or not file['available']:
                    continue
                seen.add(digest)
                api(settings, f'/api/files/{digest}/migrate', method='POST')
                request = api_request(settings, track['content_path'])
                with urllib.request.urlopen(request, timeout=120) as response:
                    data = response.read(20_000_001)
                    storage = response.headers.get('X-Music-Storage')
                if storage != 'tg-s3' or len(data) != file['size_bytes'] or hashlib.sha256(data).hexdigest() != digest:
                    raise RuntimeError('Migrated audio verification failed: ' + digest)
                print('Verified migrated audio: ' + digest + ' (' + str(len(data)) + ' bytes). Original retained.')
        if len(tracks) < 100:
            break
        offset += len(tracks)
    print('Migration completed: ' + str(len(seen)) + ' distinct ready audio files.')


def api_request(settings, path, method='GET'):
    key = next(iter(json.loads(settings['API_KEYS'])))
    return urllib.request.Request(MUSIC_URL + path, method=method, headers={'Authorization': 'Bearer ' + key, 'X-Admin-Key': settings['ADMIN_KEY'], 'User-Agent': 'c0versnowmusic-StorageUpgrade/1.0'})


def api(settings, path, method='GET'):
    try:
        with urllib.request.urlopen(api_request(settings, path, method), timeout=120) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError('Music API returned HTTP ' + str(error.code) + '; verify storage before retrying.') from None


def run(config, *arguments, sensitive=False):
    result = subprocess.run(['wrangler', *arguments, '--config', str(ROOT / config)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if not sensitive:
        print(result.stdout, end='')
    if result.returncode:
        raise RuntimeError('Wrangler operation failed' + ('; bootstrap output withheld because it may contain credentials.' if sensitive else '.'))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Storage configuration failed: ' + type(error).__name__, file=sys.stderr)
        sys.exit(1)
