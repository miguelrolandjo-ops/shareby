'use strict';

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
    this.expose = true;
  }
}

/** Express 4 does not catch async errors; wrap handlers so they reach the error middleware. */
const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (v) => typeof v === 'string' && UUID_RE.test(v);

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const isEmail = (v) => typeof v === 'string' && EMAIL_RE.test(v);

module.exports = { HttpError, ah, isUuid, isEmail };
