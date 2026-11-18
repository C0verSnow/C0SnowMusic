// Uses the upstream TG-S3 S3 interface; pinned source and deployment are in storage/tg-s3/.
export class TgS3Store {
  constructor(env) {
    if (!env.TGS3_ENDPOINT || !env.TGS3_BUCKET || !env.TGS3_ACCESS_KEY_ID || !env.TGS3_SECRET_ACCESS_KEY) {
      throw new TgS3Error('TG-S3 storage is not configured.');
    }
    this.env = env;
  }

  async head(hash) {
    const response = await this.request('HEAD', hash);
    if (response.status === 404) return null;
    checkResponse(response);
    const size = Number(response.headers.get('Content-Length'));
    const etag = response.headers.get('ETag');
    if (response.headers.get('x-amz-meta-sha256') !== hash || !Number.isSafeInteger(size) || size < 1 || !etag) {
      throw new TgS3Error('TG-S3 object metadata does not match the audio.');
    }
    return { key: `audio/${hash}`, etag, size };
  }

  async put(hash, bytes, contentType) {
    const response = await this.request('PUT', hash, {
      body: bytes,
      headers: { 'Content-Type': contentType, 'Content-Length': String(bytes.byteLength), 'x-amz-meta-sha256': hash, 'If-None-Match': '*' },
    });
    // A completed earlier request may already have created this content-addressed object.
    if (response.status === 412) {
      const stored = await this.head(hash);
      if (stored?.size === bytes.byteLength) return stored;
    }
    checkResponse(response);
    const etag = response.headers.get('ETag');
    if (!etag) throw new TgS3Error('TG-S3 upload receipt is incomplete.');
    return { key: `audio/${hash}`, etag, size: bytes.byteLength };
  }

  async content(hash, method, range) {
    const response = await this.request(method, hash, { headers: range ? { Range: range } : {} });
    if (![404, 416].includes(response.status)) checkResponse(response);
    return response;
  }

  async warmCache(hash) {
    const response = await this.request('GET', hash);
    checkResponse(response);
    await response.body?.pipeTo(new WritableStream());
  }

  async request(method, hash, { body, headers = {} } = {}) {
    const url = new URL(`/${this.env.TGS3_BUCKET}/audio/${hash}`, this.env.TGS3_ENDPOINT);
    const request = await signS3Request(url, method, this.env, body, headers);
    try { return await (this.env.TGS3 ? this.env.TGS3.fetch(request) : fetch(request)); }
    catch { throw new TgS3Error('TG-S3 request failed; verify the object before retrying an upload.'); }
  }
}

export async function signS3Request(url, method, env, body, extraHeaders = {}) {
  const date = new Date().toISOString().replace(/[-:]|\.\d{3}/g, '');
  const day = date.slice(0, 8);
  const region = 'us-east-1';
  const scope = `${day}/${region}/s3/aws4_request`;
  const payloadHash = hex(await crypto.subtle.digest('SHA-256', body ?? new ArrayBuffer(0)));
  const canonicalHeaders = `host:${url.host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${date}\n`;
  const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
  const canonical = [method, url.pathname, '', canonicalHeaders, signedHeaders, payloadHash].join('\n');
  const digest = hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonical)));
  const stringToSign = `AWS4-HMAC-SHA256\n${date}\n${scope}\n${digest}`;
  let key = new TextEncoder().encode(`AWS4${env.TGS3_SECRET_ACCESS_KEY}`);
  for (const value of [day, region, 's3', 'aws4_request']) key = await hmac(key, value);
  const signature = hex(await hmac(key, stringToSign));
  return new Request(url, {
    method, body,
    headers: {
      ...extraHeaders,
      'x-amz-date': date,
      'x-amz-content-sha256': payloadHash,
      Authorization: `AWS4-HMAC-SHA256 Credential=${env.TGS3_ACCESS_KEY_ID}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`,
    },
  });
}

async function hmac(key, value) {
  const signingKey = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return crypto.subtle.sign('HMAC', signingKey, new TextEncoder().encode(value));
}
function hex(buffer) { return [...new Uint8Array(buffer)].map(byte => byte.toString(16).padStart(2, '0')).join(''); }
function checkResponse(response) {
  if (response.ok) return;
  throw new TgS3Error(`TG-S3 storage returned HTTP ${response.status}.`, response.status, response.headers.get('Retry-After'));
}
export class TgS3Error extends Error {
  constructor(message, upstreamStatus = 503, retryAfter) {
    super(message);
    this.status = upstreamStatus === 429 ? 429 : 502;
    this.definite = upstreamStatus >= 400 && upstreamStatus < 500;
    this.headers = retryAfter ? { 'Retry-After': retryAfter } : {};
    this.retryAfter = retryAfter ? Date.now() + Number(retryAfter) * 1000 : 0;
  }
}
