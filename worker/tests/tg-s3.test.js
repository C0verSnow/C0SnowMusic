import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createServer } from 'node:http';
import music from '../index.js';
import { TgS3Store, signS3Request } from '../tg-s3-store.js';
import { D1 } from './support/d1.js';

// The upstream bundle is compiled from the pinned source by remote CI.
const upstream = (await import(pathToFileURL(resolve(process.env.TG_S3_WORKER_ENTRY)))).default;
const schema = readFileSync(resolve(process.env.TG_S3_SCHEMA), 'utf8');
const fixture = readFileSync(new URL('../../MusicApp/Resources/Fixtures/Fixture.mp3', import.meta.url));
const audio = Buffer.concat([fixture, fixture, fixture, fixture]);
const hash = createHash('sha256').update(audio).digest('hex');
const track = { source_id: 'abcdefghijk', title: 'TG-S3 integration', artist: 'CI' };
const nativeFetch = globalThis.fetch;
const nativeDigest = crypto.subtle.digest.bind(crypto.subtle);
let db, objectsDB, env, storageEnv, server, origin, documents, downloads, sentAudio, deleted, failure, pending, files, edge, r2;

before(async () => {
  // Workers provides MD5 for S3 ETags; Node WebCrypto provides only SHA algorithms.
  crypto.subtle.digest = (algorithm, bytes) => algorithm === 'MD5'
    ? Promise.resolve(Uint8Array.from(createHash('md5').update(new Uint8Array(bytes)).digest()).buffer)
    : nativeDigest(algorithm, bytes);
  server = createServer(async (request, response) => {
    try {
      if (request.url.startsWith('/file/')) {
        const bytes = files.get(request.url.split('/').at(-1));
        if (!bytes) { response.writeHead(404); response.end(); return; }
        downloads++;
        response.writeHead(200, { 'Content-Length': bytes.length }); response.end(bytes); return;
      }
      const chunks = []; for await (const chunk of request) chunks.push(chunk);
      const bytes = Buffer.concat(chunks);
      const method = request.url.split('/').at(-1);
      const multipart = request.headers['content-type']?.startsWith('multipart/');
      const payload = multipart ? await new Response(bytes, { headers: { 'Content-Type': request.headers['content-type'] } }).formData() : JSON.parse(bytes);
      if (method === 'sendDocument' || method === 'sendAudio') {
        if (method === 'sendDocument') documents++; else sentAudio++;
        const file = multipart ? payload.get(method === 'sendDocument' ? 'document' : 'audio') : null;
        assert.ok(file instanceof File, 'new documents and sent music must contain actual audio bytes');
        const id = `file-${files.size}`;
        files.set(id, Buffer.from(await file.arrayBuffer()));
        response.end(JSON.stringify({ ok: true, result: { message_id: files.size, [method === 'sendDocument' ? 'document' : 'audio']: { file_id: id, file_unique_id: `unique-${id}`, file_size: file.size } } })); return;
      }
      if (method === 'getFile') {
        const present = files.has(payload.file_id);
        response.writeHead(present ? 200 : 400);
        response.end(JSON.stringify(present ? { ok: true, result: { file_path: `music/${payload.file_id}` } } : { ok: false, error_code: 400 })); return;
      }
      if (method === 'deleteMessage') deleted++;
      response.writeHead(404); response.end();
    } catch (error) { response.writeHead(500); response.end(error.message); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  globalThis.fetch = (input, init) => nativeFetch(String(input instanceof Request ? input.url : input).replace('https://api.telegram.org', origin), init);
});
after(async () => {
  globalThis.fetch = nativeFetch; crypto.subtle.digest = nativeDigest;
  delete globalThis.caches;
  await new Promise(resolve => server.close(resolve));
  db.close(); objectsDB.close();
});
beforeEach(() => {
  db?.close(); objectsDB?.close();
  db = new DatabaseSync(':memory:'); objectsDB = new DatabaseSync(':memory:');
  for (const migration of ['0001_music.sql', '0002_favorite_snapshots.sql', '0003_tg_s3_objects.sql']) db.exec(readFileSync(new URL(`../migrations/${migration}`, import.meta.url), 'utf8'));
  objectsDB.exec(schema);
  objectsDB.prepare("INSERT INTO buckets(name, created_at, tg_chat_id) VALUES ('c0snow-audio', datetime('now'), '-100123')").run();
  objectsDB.prepare("INSERT INTO credentials(access_key_id, secret_access_key, buckets, permission) VALUES ('test-access', 'test-secret', 'c0snow-audio', 'readwrite')").run();
  documents = downloads = sentAudio = deleted = 0; failure = ''; pending = []; files = new Map(); edge = new Map(); r2 = new Map();
  globalThis.caches = { default: {
    async match(request) { return edge.get(request.url)?.clone(); },
    async put(request, response) { edge.set(request.url, response.clone()); },
    async delete(request) { return edge.delete(request.url); },
  } };
  storageEnv = { DB: new D1(objectsDB), TG_BOT_TOKEN: '123:test', S3_REGION: 'us-east-1', CACHE: {
    async get(key) {
      const item = r2.get(key);
      return item ? { customMetadata: item.metadata.customMetadata, async arrayBuffer() { return item.bytes.slice(0); } } : null;
    },
    async put(key, bytes, metadata) { r2.set(key, { bytes: bytes.slice(0), metadata }); },
    async delete(key) { r2.delete(key); },
  } };
  env = {
    DB: new D1(db), API_KEYS: '{"device":"owner"}', ADMIN_KEY: 'admin', SEND_CHAT_IDS: '{"owner":"789"}',
    TELEGRAM_BOT_TOKEN: '123:test', TELEGRAM_STORAGE_CHAT_ID: '-100123', AUDIO_STORAGE_BACKEND: 'tg-s3',
    TGS3_ENDPOINT: 'https://s3.test', TGS3_BUCKET: 'c0snow-audio', TGS3_ACCESS_KEY_ID: 'test-access', TGS3_SECRET_ACCESS_KEY: 'test-secret',
    TGS3: { async fetch(request) {
      if (failure === 'reject' && request.method === 'PUT') return new Response(null, { status: 429, headers: { 'Retry-After': '60' } });
      const response = await upstream.fetch(request, storageEnv, { waitUntil(promise) { pending.push(promise); } });
      if (failure === 'lost-receipt' && request.method === 'PUT' && response.ok) throw new Error('Connection closed after persistence');
      return response;
    } },
  };
});
function call(path, { method = 'GET', body, headers = {} } = {}) {
  if (body && !(body instanceof FormData)) { body = JSON.stringify(body); headers['Content-Type'] = 'application/json'; }
  return music.fetch(new Request(`https://music.test${path}`, { method, body, headers: { Authorization: 'Bearer device', ...headers } }), env);
}
async function upload(metadata = track) {
  const form = new FormData();
  form.set('track', JSON.stringify(metadata)); form.set('sha256', hash);
  form.set('audio', new File([audio], 'tone.mp3', { type: 'audio/mpeg' }));
  return call('/api/tracks', { method: 'POST', body: form });
}
async function content(options) { return call('/api/tracks/yt_abcdefghijk/content', options); }

test('real upstream verifies SigV4, persists a document, deduplicates, and rejects unauthorized access', async () => {
  const created = await upload(); assert.equal(created.status, 201, await created.clone().text());
  const record = await created.json(); assert.equal(record.files[0].available, true);
  assert.equal(objectsDB.prepare('SELECT COUNT(*) AS count FROM objects').get().count, 1);
  assert.equal((await upload({ ...track, source_id: '12345678901' })).status, 201);
  assert.equal(documents, 1);
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM track_files').get().count, 2);
  // Exercise the upstream conditional PUT, including its 412 recovery via HEAD.
  await new TgS3Store(env).put(hash, audio, 'audio/mpeg'); assert.equal(documents, 1); assert.equal(deleted, 0);
  const wrong = await signS3Request(new URL(`/c0snow-audio/audio/${hash}`, env.TGS3_ENDPOINT), 'GET', { ...env, TGS3_SECRET_ACCESS_KEY: 'wrong' });
  assert.equal((await env.TGS3.fetch(wrong)).status, 403);
  const publicRead = await env.TGS3.fetch(new Request(`${env.TGS3_ENDPOINT}/c0snow-audio/audio/${hash}`));
  assert.equal(publicRead.status, 403);
  assert.doesNotMatch(JSON.stringify(record), /test-secret|test-access|file-0/);
});
test('actual upstream GET, CDN and R2 cache hits preserve the complete MP3', async () => {
  await upload();
  for (const expectedCache of ['MISS', 'HIT', 'R2-HIT']) {
    if (expectedCache === 'R2-HIT') edge.clear();
    const response = await content(); assert.equal(response.status, 200);
    assert.equal(response.headers.get('X-Music-Storage'), 'tg-s3');
    assert.equal(response.headers.get('X-Cache'), expectedCache);
    assert.equal(response.headers.get('Cache-Control'), 'private, no-store');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), audio);
    await Promise.all(pending); pending = [];
  }
  assert.equal(downloads, 1); assert.equal(r2.size, 1);
});
test('Range, HEAD and invalid ranges retain the music API contract through real upstream', async () => {
  await upload();
  for (const [range, start, end] of [['bytes=10-199', 10, 200], ['bytes=-40', audio.length - 40, audio.length], ['bytes=25-', 25, audio.length]]) {
    const response = await content({ headers: { Range: range } });
    assert.equal(response.status, 206); assert.deepEqual(Buffer.from(await response.arrayBuffer()), audio.subarray(start, end));
    assert.equal(response.headers.get('Content-Range'), `bytes ${start}-${end - 1}/${audio.length}`);
  }
  for (const range of [undefined, 'bytes=10-199']) {
    const response = await content({ method: 'HEAD', headers: range ? { Range: range } : {} });
    assert.equal(response.status, range ? 206 : 200); assert.equal((await response.arrayBuffer()).byteLength, 0);
    assert.equal(response.headers.get('Content-Length'), String(range ? 190 : audio.length));
  }
  for (const range of ['bytes=-0', 'bytes=999999999-', 'bytes=10-2', 'bytes=1-2,5-6']) {
    const response = await content({ headers: { Range: range } });
    assert.equal(response.status, 416); assert.equal(response.headers.get('Content-Range'), `bytes */${audio.length}`);
  }
});
test('lost PUT response recovers from actual object HEAD without a second Telegram upload', async () => {
  failure = 'lost-receipt'; assert.equal((await upload()).status, 502);
  assert.equal(db.prepare('SELECT status FROM upload_jobs').get().status, 'uncertain');
  failure = ''; assert.equal((await upload()).status, 201);
  assert.equal(db.prepare('SELECT status FROM upload_jobs').get().status, 'ready'); assert.equal(documents, 1);
});
test('definite rate rejection keeps retry deadline and never uploads immediately again', async () => {
  failure = 'reject'; const response = await upload(); assert.equal(response.status, 429);
  assert.equal(response.headers.get('Retry-After'), '60');
  assert.equal((await upload()).status, 409); assert.equal(documents, 0);
  assert.equal(db.prepare('SELECT status FROM upload_jobs').get().status, 'failed');
});
test('legacy audio migrates without deleting originals, keeps favorites, and falls back if the S3 object disappears', async () => {
  env.AUDIO_STORAGE_BACKEND = 'telegram'; assert.equal((await upload()).status, 201);
  assert.deepEqual(Buffer.from(await (await content()).arrayBuffer()), audio);
  await call('/api/tracks/yt_abcdefghijk/favorite', { method: 'PUT' });
  env.AUDIO_STORAGE_BACKEND = 'tg-s3';
  const path = `/api/files/${hash}/migrate`;
  assert.equal((await call(path, { method: 'POST' })).status, 403);
  for (let n = 0; n < 2; n++) assert.equal((await call(path, { method: 'POST', headers: { 'X-Admin-Key': 'admin' } })).status, 200);
  const response = await content(); assert.equal(response.headers.get('X-Music-Storage'), 'tg-s3');
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), audio); await Promise.all(pending);
  assert.equal(documents, 1); assert.equal(deleted, 0);
  assert.equal(db.prepare('SELECT status FROM telegram_objects').get().status, 'active');
  assert.equal((await (await call('/api/favorites')).json()).items.length, 1);
  objectsDB.prepare('DELETE FROM objects').run();
  const fallback = await content(); assert.equal(fallback.status, 200);
  assert.deepEqual(Buffer.from(await fallback.arrayBuffer()), audio);
  assert.equal(db.prepare('SELECT status FROM audio_files').get().status, 'ready');
  assert.equal(db.prepare('SELECT status FROM tg_s3_objects').get().status, 'missing');
});
test('TG-S3 documents are sent to the configured recipient as real audio bytes', async () => {
  await upload();
  assert.equal((await call('/api/tracks/yt_abcdefghijk/send', { method: 'POST' })).status, 200);
  assert.equal(sentAudio, 1); assert.deepEqual(files.get('file-1'), audio);
});
