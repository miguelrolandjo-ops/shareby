/** The server couldn't be reached (offline, timeout, Nginx can't reach the API). */
export class ApiUnreachable extends Error {
  constructor(cause?: unknown) {
    super("Can't reach Shareby. Check your connection and try again.", { cause });
  }
}

/** The server answered with an error. */
export class ApiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

type Json = Record<string, unknown>;

/** REST client. Same-origin `/api` in production (Nginx proxies it), so no CORS. */
export class ApiClient {
  constructor(private readonly base: string, private readonly token: () => string | null) {}

  private async send(method: 'GET' | 'POST', path: string, body?: Json): Promise<Json> {
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    const token = this.token();
    if (token) headers.authorization = `Bearer ${token}`;

    let res: Response;
    try {
      res = await fetch(this.base + path, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(12_000),
      });
    } catch (e) {
      throw new ApiUnreachable(e);
    }
    // Nginx answers 502/504 when the API process is down: treat like offline.
    if (res.status === 502 || res.status === 503 || res.status === 504) throw new ApiUnreachable(res.status);

    let data: Json = {};
    try {
      const parsed: unknown = await res.json();
      if (parsed && typeof parsed === 'object') data = parsed as Json;
    } catch {
      // non-JSON body
    }
    if (res.ok) return data;
    throw new ApiError(res.status, typeof data.error === 'string' ? data.error : `Request failed (${res.status})`);
  }

  devLogin(email: string, displayName: string, provider: string) {
    return this.send('POST', '/auth/dev', { email, display_name: displayName, provider });
  }
  googleLogin(idToken: string) {
    return this.send('POST', '/auth/google', { id_token: idToken });
  }
  push(ops: Json[]) {
    return this.send('POST', '/sync/push', { ops });
  }
  pull(since: string | null) {
    return this.send('GET', '/sync/pull' + (since ? `?since=${encodeURIComponent(since)}` : ''));
  }
  invite(folderId: string, email: string, role: string) {
    return this.send('POST', `/folders/${folderId}/invites`, { email, role });
  }
  preview(url: string) {
    return this.send('GET', `/preview?url=${encodeURIComponent(url)}`);
  }
}
