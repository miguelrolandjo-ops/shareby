'use strict';
const crypto = require('crypto');
const express = require('express');
const rules = require('./rules.json');

/**
 * Platform and title-cleaning rules. The app ships the same table and keeps working offline;
 * on pull-to-refresh it fetches this one, so a platform changing its title format (or a new
 * platform) is a server edit, not an app release. Data only, never code: regexes use named
 * groups `title` and `author`, flags are always "is".
 */
const body = JSON.stringify(rules);
const etag = `"${crypto.createHash('sha1').update(body).digest('hex').slice(0, 16)}"`;

/** Throws if any rule would not compile, so a bad edit fails at boot and in tests. */
function validateRules(table = rules) {
  if (!Number.isInteger(table.version) || !Array.isArray(table.platforms)) throw new Error('rules: bad shape');
  const keys = new Set();
  for (const p of table.platforms) {
    if (!/^[a-z0-9_-]{1,32}$/.test(p.key) || keys.has(p.key)) throw new Error(`rules: bad or duplicate key ${p.key}`);
    keys.add(p.key);
    if (!/^#[0-9a-f]{6}$/i.test(p.color)) throw new Error(`rules: ${p.key} has a bad colour`);
    if (!Array.isArray(p.hosts) || p.hosts.length === 0) throw new Error(`rules: ${p.key} has no hosts`);
    for (const r of p.titleRules ?? []) new RegExp(r, 'is'); // eslint-disable-line no-new
  }
}
validateRules();

const rulesRouter = express.Router();

/** Public: the rules hold nothing private, and signed-out devices use them too. */
rulesRouter.get('/', (req, res) => {
  res.set('ETag', etag).set('Cache-Control', 'public, max-age=300');
  if (req.headers['if-none-match'] === etag) return res.status(304).end();
  return res.type('application/json').send(body);
});

module.exports = { rulesRouter, validateRules };
