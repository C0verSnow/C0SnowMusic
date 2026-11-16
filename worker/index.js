const MAX_AUDIO_BYTES = 20_000_000;
const MAX_JSON_BYTES = 4_000_000;
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

export default {
  async fetch(request, env) {
    try { return await route(request, env); }
    catch (error) {
      if (error instanceof APIError) return json({ error: error.message }, error.status, error.headers);
      // Upstream exceptions can contain the Bot token in their URL.
      console.error('Music API request failed', error?.name ?? 'Error');
      return json({ error: 'Service unavailable; retry later.' }, 503);
    }
  },
};

async function route(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (path === '/api/telegram/webhook' && request.method === 'POST') return webhook(request, env);
  const user = authenticate(request, env);
  if (path === '/api/tracks' && request.method === 'GET') {
    const search = (url.searchParams.get('search') ?? '').slice(0, 200);
    const source = url.searchParams.get('source_id');
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit')) || 30));
    const offset = Math.max(0, Number(url.searchParams.get('offset')) || 0);
    const rows = source
      ? await all(env, 'SELECT * FROM tracks WHERE source_id = ?', source)
      : await all(env, 'SELECT * FROM tracks WHERE title LIKE ? OR artist LIKE ? ORDER BY created_at DESC, id LIMIT ? OFFSET ?', `%${search}%`, `%${search}%`, limit, offset);
    return json({ items: await presentTracks(env, rows) });
  }
  if (path === '/api/tracks' && request.method === 'POST') return upload(request, env);
  if (path === '/api/favorites/snapshots' && request.method === 'POST') {
    const id = crypto.randomUUID();
    await env.DB.batch([
      stmt(env, "DELETE FROM favorite_snapshots WHERE user_id = ? AND created_at < datetime('now', '-1 day')", user),
      stmt(env, 'INSERT INTO favorite_snapshots(id, user_id) VALUES (?, ?)', id, user),
    ]);
    return json({ id }, 201);
  }
  const snapshot = path.match(/^\/api\/favorites\/snapshots\/([a-f0-9-]{36})(?:\/(commit))?$/);
  if (snapshot && ['PUT', 'POST'].includes(request.method)) {
    if (!await first(env, 'SELECT id FROM favorite_snapshots WHERE id = ? AND user_id = ?', snapshot[1], user)) fail(404, 'Snapshot not found.');
    const body = await bodyJSON(request);
    if (!snapshot[2] && request.method === 'PUT') {
      if (!Array.isArray(body.tracks) || body.tracks.length < 1 || body.tracks.length > 20) fail(400, 'Send 1 to 20 tracks per chunk.');
      const tracks = body.tracks.map(validateTrack);
      await env.DB.batch(tracks.flatMap(track => [trackStatement(env, track), stmt(env, 'INSERT OR IGNORE INTO favorite_snapshot_tracks VALUES (?, ?)', snapshot[1], track.id)]));
      return json({ ok: true });
    }
    if (snapshot[2] && request.method === 'POST') {
      const actual = await first(env, 'SELECT COUNT(*) AS count FROM favorite_snapshot_tracks WHERE snapshot_id = ?', snapshot[1]);
      if (body.complete !== true || !Number.isSafeInteger(body.count) || body.count !== actual.count) fail(409, 'Snapshot is incomplete.');
      await env.DB.batch([
        stmt(env, "DELETE FROM favorites WHERE user_id = ? AND origin = 'youtube'", user),
        stmt(env, "INSERT INTO favorites SELECT ?, track_id, 'youtube' FROM favorite_snapshot_tracks WHERE snapshot_id = ?", user, snapshot[1]),
        stmt(env, 'DELETE FROM favorite_snapshots WHERE id = ?', snapshot[1]),
      ]);
      return json({ count: actual.count });
    }
  }
  if (path === '/api/favorites/sync' && request.method === 'POST') {
    const body = await bodyJSON(request);
    if (!Array.isArray(body.tracks) || body.tracks.length > 20 || body.complete !== true) fail(400, 'Use staged snapshots for more than 20 favorites.');
    const tracks = body.tracks.map(validateTrack);
    const statements = tracks.map(track => trackStatement(env, track));
    statements.push(stmt(env, "DELETE FROM favorites WHERE user_id = ? AND origin = 'youtube'", user));
    for (const track of tracks) statements.push(stmt(env, "INSERT OR IGNORE INTO favorites VALUES (?, ?, 'youtube')", user, track.id));
    await env.DB.batch(statements);
    return json({ count: tracks.length });
  }
  if (path === '/api/favorites' && request.method === 'GET') {
    const offset = Math.max(0, Number(url.searchParams.get('offset')) || 0);
    const rows = await all(env, 'SELECT DISTINCT t.* FROM tracks t JOIN favorites f ON f.track_id = t.id WHERE f.user_id = ? ORDER BY t.title, t.id LIMIT 100 OFFSET ?', user, offset);
    return json({ items: await presentTracks(env, rows) });
  }
  if (path === '/api/home' && request.method === 'GET') {
    const history = await all(env, 'SELECT t.* FROM tracks t JOIN plays p ON p.track_id = t.id WHERE p.user_id = ? ORDER BY p.played_at DESC LIMIT 20', user);
    const trending = await all(env, 'SELECT t.*, SUM(p.play_count) AS count FROM tracks t JOIN plays p ON p.track_id = t.id GROUP BY t.id ORDER BY count DESC LIMIT 20');
    return json({ history, trending });
  }
  const trackRoute = path.match(/^\/api\/tracks\/([A-Za-z0-9_-]+)(?:\/(content|send|favorite|play))?$/);
  if (trackRoute) {
    const [, id, action] = trackRoute;
    const track = await first(env, 'SELECT * FROM tracks WHERE id = ?', id);
    if (!track) fail(404, 'Track not found.');
    if (!action && request.method === 'GET') return json(await presentTrack(env, track));
    if (action === 'content' && ['GET', 'HEAD'].includes(request.method)) return content(request, env, id);
    if (action === 'send' && request.method === 'POST') {
      const chat = JSON.parse(env.SEND_CHAT_IDS ?? '{}')[user];
      if (!chat) fail(403, 'No authorized Telegram recipient configured.');
      const object = await playableObject(env, id, false);
      const sent = await telegram(env, 'sendAudio', { chat_id: chat, audio: object.tg_file_id });
      return json({ message_id: sent.message_id });
    }
    if (action === 'favorite' && ['PUT', 'DELETE'].includes(request.method)) {
      if (request.method === 'PUT') await stmt(env, "INSERT OR IGNORE INTO favorites VALUES (?, ?, 'app')", user, id).run();
      else await stmt(env, "DELETE FROM favorites WHERE user_id = ? AND track_id = ? AND origin = 'app'", user, id).run();
      return json({ favorite: request.method === 'PUT' });
    }
    if (action === 'play' && request.method === 'POST') {
      await stmt(env, 'INSERT INTO plays(user_id, track_id) VALUES (?, ?) ON CONFLICT(user_id, track_id) DO UPDATE SET play_count = play_count + 1, played_at = CURRENT_TIMESTAMP', user, id).run();
      return json({ ok: true });
    }
  }
  const file = path.match(/^\/api\/files\/([a-f0-9]{64})$/);
  if (file && request.method === 'GET') {
    const row = await first(env, 'SELECT id, sha256, size_bytes, mime_type, status FROM audio_files WHERE sha256 = ?', file[1]);
    if (!row) fail(404, 'File not found.');
    return json(row);
  }
  const job = path.match(/^\/api\/jobs\/([A-Za-z0-9_-]+)(?:\/(reconcile))?$/);
  if (job && !job[2] && request.method === 'GET') {
    const row = await first(env, 'SELECT id, status, retry_count, retry_after, error_message FROM upload_jobs WHERE id = ?', job[1]);
    if (!row) fail(404, 'Job not found.');
    return json(row);
  }
  if (job?.[2] && request.method === 'POST') {
    if (request.headers.get('X-Admin-Key') !== env.ADMIN_KEY || !env.ADMIN_KEY) fail(403, 'Administrator required.');
    const body = await bodyJSON(request);
    const pending = await first(env, 'SELECT * FROM upload_jobs WHERE id = ?', job[1]);
    if (!pending || !['pending', 'uncertain'].includes(pending.status)) fail(409, 'Job does not need reconciliation.');
    if (body.not_sent === true) {
      await stmt(env, "UPDATE upload_jobs SET status = 'failed', error_message = 'Confirmed not sent', updated_at = CURRENT_TIMESTAMP WHERE id = ?", pending.id).run();
    } else {
      if (!Number.isSafeInteger(body.message_id) || body.message_id <= 0 || typeof body.file_id !== 'string' || typeof body.file_unique_id !== 'string') fail(400, 'Supply the actual Telegram receipt.');
      await commitReceipt(env, pending.audio_file_id, pending.id, { message_id: body.message_id, audio: body }, env.TELEGRAM_STORAGE_CHAT_ID);
    }
    return json({ ok: true });
  }
  fail(404, 'Not found.');
}

async function upload(request, env) {
  if (Number(request.headers.get('Content-Length')) > MAX_AUDIO_BYTES + 65536) fail(413, 'Cloud Bot delivery is limited to 20 MB.');
  const form = await new Response(await limitedBody(request, MAX_AUDIO_BYTES + 65536), { headers: { 'Content-Type': request.headers.get('Content-Type') ?? '' } }).formData();
  const audio = form.get('audio');
  let metadata;
  try { metadata = JSON.parse(form.get('track')); } catch { fail(400, 'Invalid track.'); }
  const track = validateTrack(metadata);
  if (!(audio instanceof File) || audio.size < 1 || audio.size > MAX_AUDIO_BYTES) fail(413, 'Audio must be between 1 byte and 20 MB.');
  if (!['audio/mp4', 'audio/mpeg'].includes(audio.type)) fail(415, 'Upload real M4A or MP3 audio.');
  const bytes = await audio.arrayBuffer();
  if (!audioSignature(new Uint8Array(bytes), audio.type)) fail(415, 'Audio signature does not match its format.');
  const hash = await sha256(bytes);
  if (form.get('sha256') !== hash) fail(400, 'SHA-256 does not match the audio bytes.');
  const fileID = `aud_${hash}`;
  const jobID = `upl_${hash}`;
  await env.DB.batch([
    trackStatement(env, track),
    stmt(env, "INSERT OR IGNORE INTO audio_files VALUES (?, ?, ?, ?, 'pending', CURRENT_TIMESTAMP)", fileID, hash, audio.size, audio.type),
    stmt(env, 'INSERT OR IGNORE INTO track_files VALUES (?, ?)', track.id, fileID),
  ]);
  const existing = await first(env, "SELECT id FROM telegram_objects WHERE audio_file_id = ? AND status = 'active'", fileID);
  if (existing) return json(await presentTrack(env, await first(env, 'SELECT * FROM tracks WHERE id = ?', track.id)));
  const claimed = await stmt(env, "INSERT INTO upload_jobs(id, idempotency_key, audio_file_id, status) VALUES (?, ?, ?, 'pending') ON CONFLICT(idempotency_key) DO UPDATE SET status = 'pending', retry_count = retry_count + 1, updated_at = CURRENT_TIMESTAMP WHERE upload_jobs.status = 'failed' AND upload_jobs.retry_after <= ? RETURNING id", jobID, hash, fileID, Date.now()).first();
  if (!claimed) {
    const current = await first(env, 'SELECT status, retry_after FROM upload_jobs WHERE id = ?', jobID);
    const headers = current.retry_after > Date.now() ? { 'Retry-After': String(Math.ceil((current.retry_after - Date.now()) / 1000)) } : {};
    return json({ error: 'Upload pending or needs reconciliation.', job_id: jobID, status: current.status }, 409, headers);
  }
  const payload = new FormData();
  payload.set('chat_id', env.TELEGRAM_STORAGE_CHAT_ID);
  payload.set('audio', audio, audio.type === 'audio/mp4' ? `${hash}.m4a` : `${hash}.mp3`);
  payload.set('title', track.title); payload.set('performer', track.artist);
  try {
    const receipt = await telegram(env, 'sendAudio', payload);
    await commitReceipt(env, fileID, jobID, receipt, env.TELEGRAM_STORAGE_CHAT_ID);
  } catch (error) {
    const rejected = error instanceof TelegramError && error.definite;
    await stmt(env, 'UPDATE upload_jobs SET status = ?, error_message = ?, retry_after = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?', rejected ? 'failed' : 'uncertain', rejected ? 'Telegram rejected upload' : 'Verify Telegram receipt before retrying', error.retryAfter ?? 0, jobID).run();
    if (rejected) await stmt(env, "UPDATE audio_files SET status = 'failed' WHERE id = ?", fileID).run();
    throw error;
  }
  return json(await presentTrack(env, await first(env, 'SELECT * FROM tracks WHERE id = ?', track.id)), 201);
}

async function webhook(request, env) {
  if (!env.TELEGRAM_WEBHOOK_SECRET || request.headers.get('X-Telegram-Bot-Api-Secret-Token') !== env.TELEGRAM_WEBHOOK_SECRET) fail(401, 'Invalid webhook secret.');
  const update = await bodyJSON(request);
  const message = update.channel_post ?? update.message;
  if (!message || String(message.chat?.id) !== env.TELEGRAM_STORAGE_CHAT_ID) return json({ ok: true });
  const audio = message.audio ?? message.document;
  if (!audio || !['audio/mpeg', 'audio/mp4'].includes(audio.mime_type)) return json({ ok: true });
  if (typeof audio.file_id !== 'string' || typeof audio.file_unique_id !== 'string' || !Number.isSafeInteger(audio.file_size) || audio.file_size <= 0 || !Number.isSafeInteger(message.message_id)) fail(400, 'Invalid Telegram audio.');
  const jobID = `tg_${message.chat.id}_${message.message_id}`;
  if (await first(env, 'SELECT id FROM upload_jobs WHERE id = ?', jobID)) return json({ ok: true });
  const botID = env.TELEGRAM_BOT_TOKEN.split(':')[0];
  const known = await first(env, 'SELECT audio_file_id FROM telegram_objects WHERE bot_id = ? AND tg_file_unique_id = ?', botID, audio.file_unique_id);
  let fileID = known?.audio_file_id;
  let hash = null;
  if (!fileID && audio.file_size <= MAX_AUDIO_BYTES) {
    const file = await telegram(env, 'getFile', { file_id: audio.file_id });
    const response = await fetch(telegramFileURL(env, file.file_path));
    if (!response.ok) fail(502, 'Telegram file could not be read.');
    const bytes = await limitedBody(response, MAX_AUDIO_BYTES);
    if (bytes.byteLength !== audio.file_size || !audioSignature(new Uint8Array(bytes), audio.mime_type)) fail(502, 'Telegram audio bytes do not match metadata.');
    hash = await sha256(bytes);
    fileID = `aud_${hash}`;
  }
  fileID ??= `aud_${crypto.randomUUID()}`;
  const track = { id: `tg_${message.chat.id}_${message.message_id}`, source_id: null, title: audio.title || audio.file_name || 'Telegram audio', artist: audio.performer || '', album: '', cover_url: null };
  await env.DB.batch([
    stmt(env, 'INSERT OR IGNORE INTO audio_files VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)', fileID, hash, audio.file_size, audio.mime_type, audio.file_size > MAX_AUDIO_BYTES ? 'hash_pending' : 'ready'),
    trackStatement(env, track),
    stmt(env, 'INSERT OR IGNORE INTO track_files VALUES (?, ?)', track.id, fileID),
    stmt(env, 'INSERT OR IGNORE INTO telegram_objects VALUES (?, ?, ?, ?, ?, ?, ?, ?)', jobID, fileID, botID, audio.file_id, audio.file_unique_id, String(message.chat.id), message.message_id, 'active'),
    stmt(env, "INSERT OR IGNORE INTO upload_jobs(id, idempotency_key, audio_file_id, status) VALUES (?, ?, ?, 'ready')", jobID, jobID, fileID),
  ]);
  return json({ ok: true });
}

async function content(request, env, id) {
  const object = await playableObject(env, id, true);
  const size = object.size_bytes;
  const range = parseRange(request.headers.get('Range'), size);
  const headers = { 'Content-Type': object.mime_type, 'Content-Length': String(range ? range.end - range.start + 1 : size), 'Accept-Ranges': 'bytes', 'Cache-Control': 'private, no-store' };
  if (range) headers['Content-Range'] = `bytes ${range.start}-${range.end}/${size}`;
  if (request.method === 'HEAD') return new Response(null, { status: range ? 206 : 200, headers });
  let file;
  try { file = await telegram(env, 'getFile', { file_id: object.tg_file_id }); }
  catch (error) {
    if (error instanceof TelegramError && error.status === 404) {
      await env.DB.batch([
        stmt(env, "UPDATE telegram_objects SET status = 'missing' WHERE id = ?", object.id),
        stmt(env, "UPDATE audio_files SET status = 'missing' WHERE id = ?", object.audio_file_id),
        stmt(env, "UPDATE upload_jobs SET status = 'failed', error_message = 'Telegram audio missing', updated_at = CURRENT_TIMESTAMP WHERE audio_file_id = ? AND status = 'ready'", object.audio_file_id),
      ]);
    }
    throw error;
  }
  // Telegram does not promise Range support. Slice its full stream ourselves.
  const upstream = await fetch(telegramFileURL(env, file.file_path));
  if (!upstream.ok || !upstream.body) {
    if (upstream.status === 404) await env.DB.batch([
      stmt(env, "UPDATE audio_files SET status = 'missing' WHERE id = ?", object.audio_file_id),
      stmt(env, "UPDATE telegram_objects SET status = 'missing' WHERE id = ?", object.id),
      stmt(env, "UPDATE upload_jobs SET status = 'failed', error_message = 'Telegram audio missing', updated_at = CURRENT_TIMESTAMP WHERE audio_file_id = ? AND status = 'ready'", object.audio_file_id),
    ]);
    fail(502, 'Telegram media unavailable.');
  }
  const length = upstream.headers.get('Content-Length');
  if (length && Number(length) !== size) { await upstream.body.cancel(); fail(502, 'Telegram media size changed.'); }
  return new Response(sliceStream(upstream.body, range?.start ?? 0, range?.end ?? size - 1), { status: range ? 206 : 200, headers });
}

export function sliceStream(stream, start, end) {
  const reader = stream.getReader();
  let position = 0;
  return new ReadableStream({
    async pull(controller) {
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) { controller.error(new Error('Incomplete Telegram audio')); return; }
          const from = Math.max(0, start - position);
          const to = Math.min(value.length, end + 1 - position);
          position += value.length;
          if (to > from) controller.enqueue(value.subarray(from, to));
          if (position > end) { controller.close(); await reader.cancel(); return; }
          if (to > from) return;
        }
      } catch (error) { controller.error(error); }
    },
    cancel(reason) { return reader.cancel(reason); },
  });
}

export function parseRange(value, size) {
  if (!value) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(value);
  if (!match || (!match[1] && !match[2])) fail(416, 'Unsupported byte range.', { 'Content-Range': `bytes */${size}` });
  const start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
  const end = match[1] && match[2] ? Math.min(size - 1, Number(match[2])) : size - 1;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= size || (!match[1] && Number(match[2]) === 0)) fail(416, 'Unsatisfiable byte range.', { 'Content-Range': `bytes */${size}` });
  return { start, end };
}

async function playableObject(env, id, download) {
  const row = await first(env, `SELECT o.*, a.size_bytes, a.mime_type FROM telegram_objects o JOIN audio_files a ON a.id = o.audio_file_id JOIN track_files tf ON tf.audio_file_id = a.id WHERE tf.track_id = ? AND o.status = 'active' AND a.status IN ('ready','hash_pending') ORDER BY a.size_bytes LIMIT 1`, id);
  if (!row) fail(404, 'No available audio for this track.');
  if (download && row.size_bytes > MAX_AUDIO_BYTES) fail(413, 'This file requires a Local Bot API delivery service.');
  return row;
}

async function presentTrack(env, track) {
  return (await presentTracks(env, [track]))[0];
}

async function presentTracks(env, tracks) {
  if (!tracks.length) return [];
  const rows = await all(env, `SELECT tf.track_id, a.id, a.sha256, a.size_bytes, a.mime_type, a.status FROM audio_files a JOIN track_files tf ON tf.audio_file_id = a.id WHERE tf.track_id IN (${tracks.map(() => '?').join(',')})`, ...tracks.map(track => track.id));
  const grouped = new Map();
  for (const { track_id, ...file } of rows) {
    if (!grouped.has(track_id)) grouped.set(track_id, []);
    grouped.get(track_id).push({ ...file, available: file.status === 'ready' && file.size_bytes <= MAX_AUDIO_BYTES });
  }
  return tracks.map(track => ({ ...track, files: grouped.get(track.id) ?? [], content_path: `/api/tracks/${track.id}/content` }));
}

async function commitReceipt(env, fileID, jobID, message, chatID) {
  const audio = message.audio;
  if (!audio?.file_id || !audio.file_unique_id || !message.message_id) fail(502, 'Telegram upload receipt incomplete; reconcile before retrying.');
  await env.DB.batch([
    stmt(env, 'INSERT INTO telegram_objects VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET tg_file_id = excluded.tg_file_id, tg_file_unique_id = excluded.tg_file_unique_id, message_id = excluded.message_id, status = excluded.status', jobID, fileID, env.TELEGRAM_BOT_TOKEN.split(':')[0], audio.file_id, audio.file_unique_id, chatID, message.message_id, 'active'),
    stmt(env, "UPDATE audio_files SET status = 'ready' WHERE id = ?", fileID),
    stmt(env, "UPDATE upload_jobs SET status = 'ready', error_message = NULL, retry_after = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?", jobID),
  ]);
}

async function telegram(env, method, body) {
  const multipart = body instanceof FormData;
  const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, { method: 'POST', headers: multipart ? {} : { 'Content-Type': 'application/json' }, body: multipart ? body : JSON.stringify(body) });
  let result;
  try { result = await response.json(); } catch { throw new TelegramError(502, false); }
  if (!response.ok || !result.ok) {
    const code = result.error_code ?? response.status;
    const retryAfter = code === 429 ? Date.now() + Math.max(1, result.parameters?.retry_after ?? 30) * 1000 : 0;
    throw new TelegramError(code === 429 ? 429 : code === 400 ? 404 : 502, code >= 400 && code < 500, retryAfter);
  }
  return result.result;
}

function telegramFileURL(env, path) {
  if (typeof path !== 'string' || !/^[A-Za-z0-9_./-]+$/.test(path) || path.includes('..')) fail(502, 'Invalid Telegram file path.');
  return `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${path}`;
}

function authenticate(request, env) {
  const key = request.headers.get('Authorization')?.replace(/^Bearer /, '');
  const keys = JSON.parse(env.API_KEYS ?? '{}');
  const user = key && Object.hasOwn(keys, key) ? keys[key] : null;
  if (typeof user !== 'string' || !user) fail(401, 'Invalid device API key.');
  return user;
}

function validateTrack(value) {
  if (!value || typeof value.source_id !== 'string' || !VIDEO_ID.test(value.source_id) || typeof value.title !== 'string' || !value.title.trim() || value.title.length > 500 || (value.artist != null && (typeof value.artist !== 'string' || value.artist.length > 500)) || (value.album != null && (typeof value.album !== 'string' || value.album.length > 500))) fail(400, 'Invalid track metadata.');
  if (value.cover_url != null && (typeof value.cover_url !== 'string' || value.cover_url.length > 2048 || !/^https:\/\//.test(value.cover_url))) fail(400, 'Invalid artwork URL.');
  return { id: `yt_${value.source_id}`, source_id: value.source_id, title: value.title.trim(), artist: value.artist ?? '', album: value.album ?? '', cover_url: value.cover_url ?? null };
}

function trackStatement(env, track) {
  return stmt(env, 'INSERT INTO tracks(id, source_id, title, artist, album, cover_url) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title = excluded.title, artist = excluded.artist, album = excluded.album, cover_url = excluded.cover_url', track.id, track.source_id, track.title, track.artist, track.album, track.cover_url);
}
function audioSignature(bytes, type) {
  if (type === 'audio/mp4') return bytes.length >= 12 && String.fromCharCode(...bytes.subarray(4, 8)) === 'ftyp';
  return bytes.length >= 3 && ((bytes[0] === 73 && bytes[1] === 68 && bytes[2] === 51) || (bytes[0] === 255 && (bytes[1] & 224) === 224));
}
async function sha256(bytes) { return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(byte => byte.toString(16).padStart(2, '0')).join(''); }
async function bodyJSON(request) {
  try { return JSON.parse(new TextDecoder().decode(await limitedBody(request, MAX_JSON_BYTES))); }
  catch (error) { if (error instanceof APIError) throw error; fail(400, 'Invalid JSON.'); }
}
async function limitedBody(response, maximum) {
  if (!response.body) fail(400, 'Request body required.');
  const reader = response.body.getReader();
  const chunks = []; let size = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > maximum) { await reader.cancel(); fail(413, 'Request is too large.'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes.buffer;
}
function stmt(env, sql, ...params) { return env.DB.prepare(sql).bind(...params); }
async function first(env, sql, ...params) { return stmt(env, sql, ...params).first(); }
async function all(env, sql, ...params) { return (await stmt(env, sql, ...params).all()).results; }
function json(body, status = 200, headers = {}) { return Response.json(body, { status, headers: { 'Cache-Control': 'private, no-store', ...headers } }); }
function fail(status, message, headers) { throw new APIError(status, message, headers); }
class APIError extends Error {
  constructor(status, message, headers = {}) { super(message); this.status = status; this.headers = headers; }
}
class TelegramError extends APIError {
  constructor(status, definite, retryAfter = 0) {
    super(status, status === 429 ? 'Telegram rate limit; retry after the indicated delay.' : 'Telegram request failed.', retryAfter ? { 'Retry-After': String(Math.ceil((retryAfter - Date.now()) / 1000)) } : {});
    this.definite = definite; this.retryAfter = retryAfter;
  }
}
