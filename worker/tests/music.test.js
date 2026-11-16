import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import worker from '../index.js';

const nativeFetch = globalThis.fetch;
const fixture = readFileSync(new URL('../../MusicApp/Resources/Fixtures/Fixture.mp3', import.meta.url));
const track = { source_id: 'abcdefghijk', title: 'A real test tone', artist: 'CI', album: 'Integration' };
let db, env, server, origin, uploads, mode, telegramBytes;
class D1 {
  prepare(sql) {
    const query = db.prepare(sql);
    return { bind: (...params) => ({
      async first() { return query.get(...params) ?? null; },
      async all() { return { results: query.all(...params) }; },
      async run() { return query.run(...params); },
    }) };
  }
  async batch(statements) {
    db.exec('BEGIN');
    try {
      const results = [];
      for (const statement of statements) results.push(await statement.run());
      db.exec('COMMIT'); return results;
    } catch (error) { db.exec('ROLLBACK'); throw error; }
  }
}
before(async () => {
  server = createServer(async (request, response) => {
    if (request.url.startsWith('/file/')) {
      response.writeHead(200, { 'Content-Length': telegramBytes.length });
      response.end(telegramBytes); return;
    }
    for await (const _ of request) { /* Consume the actual multipart request. */ }
    const method = request.url.split('/').at(-1);
    if (method === 'sendAudio') {
      uploads++;
      if (mode === 'rate-limit') { response.writeHead(429); response.end(JSON.stringify({ ok: false, error_code: 429, parameters: { retry_after: 60 } })); return; }
      if (mode === 'uncertain') { response.writeHead(502); response.end('Upstream error'); return; }
      response.end(JSON.stringify({ ok: true, result: { message_id: 123, audio: { file_id: 'tg-file', file_unique_id: 'tg-unique' } } })); return;
    }
    if (method === 'getFile') {
      if (mode === 'missing') { response.writeHead(400); response.end(JSON.stringify({ ok: false, error_code: 400 })); return; }
      response.end(JSON.stringify({ ok: true, result: { file_path: 'music/tone.mp3' } })); return;
    }
    response.writeHead(404); response.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  globalThis.fetch = (url, init) => nativeFetch(String(url).replace('https://api.telegram.org', origin), init);
});
after(async () => { globalThis.fetch = nativeFetch; await new Promise(resolve => server.close(resolve)); db.close(); });
beforeEach(() => {
  db?.close(); db = new DatabaseSync(':memory:');
  for (const path of ['0001_music.sql', '0002_favorite_snapshots.sql']) db.exec(readFileSync(new URL(`../migrations/${path}`, import.meta.url), 'utf8'));
  env = { DB: new D1(), API_KEYS: '{"device":"owner","other":"another"}', TELEGRAM_BOT_TOKEN: '123:secret-token', TELEGRAM_STORAGE_CHAT_ID: '-100123', TELEGRAM_WEBHOOK_SECRET: 'webhook-secret', SEND_CHAT_IDS: '{"owner":"789"}', ADMIN_KEY: 'admin' };
  uploads = 0; mode = 'ok'; telegramBytes = fixture;
});
function call(path, { method = 'GET', body, key = 'device', headers = {} } = {}) {
  const h = { Authorization: `Bearer ${key}`, ...headers };
  if (body && !(body instanceof FormData)) { h['Content-Type'] = 'application/json'; body = JSON.stringify(body); }
  return worker.fetch(new Request(`https://music.test${path}`, { method, headers: h, body }), env);
}
async function upload(metadata = track, bytes = fixture, suppliedHash) {
  const form = new FormData();
  const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(x => x.toString(16).padStart(2, '0')).join('');
  form.set('track', JSON.stringify(metadata)); form.set('sha256', suppliedHash ?? hash);
  form.set('audio', new File([bytes], 'tone.mp3', { type: 'audio/mpeg' }));
  return call('/api/tracks', { method: 'POST', body: form });
}

test('authentication covers catalog and media, and invalid metadata never uploads', async () => {
  assert.equal((await call('/api/tracks', { key: 'invalid' })).status, 401);
  assert.equal((await upload({ ...track, source_id: '../bad' })).status, 400);
  assert.equal((await upload(track, fixture, 'a'.repeat(64))).status, 400);
  assert.equal((await upload(track, Buffer.from('<html>bad</html>'))).status, 415);
  assert.equal(uploads, 0);
});
test('real MP3 upload hashes actual bytes and reuses one file for two tracks', async () => {
  const first = await upload(); assert.equal(first.status, 201);
  const saved = await first.json();
  assert.equal(saved.files[0].available, true);
  assert.equal(saved.files[0].sha256.length, 64);
  assert.equal((await upload({ ...track, source_id: '12345678901' })).status, 200);
  assert.equal(uploads, 1);
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM audio_files').get().count, 1);
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM track_files').get().count, 2);
  assert.equal((await call(`/api/files/${saved.files[0].sha256}`)).status, 200);
  assert.doesNotMatch(JSON.stringify(saved), /tg-file|secret-token|-100123/);
});
test('206 byte ranges and suffixes match real MP3 bytes when Telegram ignores Range', async () => {
  await upload();
  for (const [range, start, end] of [['bytes=10-199', 10, 200], ['bytes=-40', fixture.length - 40, fixture.length], ['bytes=25-', 25, fixture.length]]) {
    const response = await call('/api/tracks/yt_abcdefghijk/content', { headers: { Range: range } });
    assert.equal(response.status, 206);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), fixture.subarray(start, end));
    assert.equal(response.headers.get('Content-Length'), String(end - start));
    assert.equal(response.headers.get('Content-Range'), `bytes ${start}-${end - 1}/${fixture.length}`);
  }
  const head = await call('/api/tracks/yt_abcdefghijk/content', { method: 'HEAD' });
  assert.equal(head.status, 200); assert.equal((await head.arrayBuffer()).byteLength, 0);
  for (const range of ['bytes=999999999-', 'bytes=-0', 'bytes=10-2', 'bytes=1-2,5-6']) {
    const response = await call('/api/tracks/yt_abcdefghijk/content', { headers: { Range: range } });
    assert.equal(response.status, 416); assert.equal(response.headers.get('Content-Range'), `bytes */${fixture.length}`);
  }
});
test('uncertain upload never sends again until an administrator confirms it was not sent', async () => {
  mode = 'uncertain'; assert.equal((await upload()).status, 502);
  const pending = await upload(); assert.equal(pending.status, 409);
  const job = (await pending.json()).job_id;
  assert.equal(uploads, 1);
  assert.equal((await call(`/api/jobs/${job}`)).status, 200);
  assert.equal((await call(`/api/jobs/${job}/reconcile`, { method: 'POST', body: { not_sent: true } })).status, 403);
  assert.equal((await call(`/api/jobs/${job}/reconcile`, { method: 'POST', body: { not_sent: true }, headers: { 'X-Admin-Key': 'admin' } })).status, 200);
  mode = 'ok'; assert.equal((await upload()).status, 201); assert.equal(uploads, 2);
});
test('Telegram 429 persists retry deadline and does not immediately upload again', async () => {
  mode = 'rate-limit'; const response = await upload();
  assert.equal(response.status, 429); assert.equal(response.headers.get('Retry-After'), '60');
  const next = await upload(); assert.equal(next.status, 409); assert.ok(Number(next.headers.get('Retry-After')) >= 59);
  assert.equal(uploads, 1);
});
test('missing Telegram audio changes persistent file status', async () => {
  await upload(); mode = 'missing';
  assert.equal((await call('/api/tracks/yt_abcdefghijk/content')).status, 404);
  const saved = await (await call('/api/tracks/yt_abcdefghijk')).json();
  assert.equal(saved.files[0].status, 'missing'); assert.equal(saved.files[0].available, false);
});
test('staged favorites require complete count, remain isolated and unfavorite keeps Telegram audio', async () => {
  await upload();
  await call('/api/tracks/yt_abcdefghijk/favorite', { method: 'PUT', key: 'other' });
  const snapshot = await (await call('/api/favorites/snapshots', { method: 'POST' })).json();
  const path = `/api/favorites/snapshots/${snapshot.id}`;
  assert.equal((await call(path, { method: 'PUT', body: { tracks: [track] } })).status, 200);
  assert.equal((await call(`${path}/commit`, { method: 'POST', body: { complete: true, count: 2 } })).status, 409);
  assert.equal((await call(`${path}/commit`, { method: 'POST', body: { complete: true, count: 1 }, key: 'other' })).status, 404);
  assert.equal((await call(`${path}/commit`, { method: 'POST', body: { complete: true, count: 1 } })).status, 200);
  assert.equal((await (await call('/api/favorites')).json()).items.length, 1);
  const empty = await (await call('/api/favorites/snapshots', { method: 'POST' })).json();
  await call(`/api/favorites/snapshots/${empty.id}/commit`, { method: 'POST', body: { complete: true, count: 0 } });
  assert.equal((await (await call('/api/favorites')).json()).items.length, 0);
  assert.equal((await (await call('/api/favorites', { key: 'other' })).json()).items.length, 1);
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM telegram_objects').get().count, 1);
  assert.equal((await call('/api/tracks/yt_abcdefghijk/content')).status, 200);
});
test('webhook verifies channel and secret, hashes audio and deduplicates delivery', async () => {
  const update = { update_id: 1, channel_post: { message_id: 9, chat: { id: -100123 }, audio: { file_id: 'file', file_unique_id: 'unique', file_size: fixture.length, mime_type: 'audio/mpeg', title: 'Tone' } } };
  assert.equal((await call('/api/telegram/webhook', { method: 'POST', body: update })).status, 401);
  const options = { method: 'POST', body: update, headers: { 'X-Telegram-Bot-Api-Secret-Token': 'webhook-secret' } };
  assert.equal((await call('/api/telegram/webhook', options)).status, 200);
  assert.equal((await call('/api/telegram/webhook', options)).status, 200);
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM tracks').get().count, 1);
  assert.equal(db.prepare('SELECT sha256 FROM audio_files').get().sha256.length, 64);
});
test('large webhook files have no invented hash and cannot use cloud delivery', async () => {
  const body = { channel_post: { message_id: 8, chat: { id: -100123 }, audio: { file_id: 'big', file_unique_id: 'large', file_size: 25000000, mime_type: 'audio/mpeg' } } };
  await call('/api/telegram/webhook', { method: 'POST', body, headers: { 'X-Telegram-Bot-Api-Secret-Token': 'webhook-secret' } });
  const file = db.prepare('SELECT * FROM audio_files').get();
  assert.equal(file.sha256, null); assert.equal(file.status, 'hash_pending');
  const id = db.prepare('SELECT id FROM tracks').get().id;
  assert.equal((await call(`/api/tracks/${id}/content`)).status, 413);
});
test('send uses configured recipient, and real play events populate community trending', async () => {
  await upload();
  assert.equal((await call('/api/tracks/yt_abcdefghijk/send', { method: 'POST', key: 'other' })).status, 403);
  assert.equal((await call('/api/tracks/yt_abcdefghijk/send', { method: 'POST' })).status, 200);
  await call('/api/tracks/yt_abcdefghijk/play', { method: 'POST' });
  const home = await (await call('/api/home')).json();
  assert.equal(home.history[0].source_id, track.source_id); assert.equal(home.trending[0].count, 1);
});
