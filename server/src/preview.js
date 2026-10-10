'use strict';
const express = require('express');
const { ah, HttpError } = require('./util');

const previewRouter = express.Router();

// Basic SSRF guard: refuse obvious private/loopback hosts. (Does not cover DNS rebinding;
// put this behind an egress proxy in production.)
function isPrivateHost(host) {
  const h = host.toLowerCase().replace(/^\[|\]$/g, '');
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal') || h === '::1') return true;
  const m = h.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return false;
  const [a, b] = [Number(m[1]), Number(m[2])];
  return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254)
    || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

const decode = (s) => s
  .replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#0?39;/g, "'")
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>');

function meta(html, key) {
  const tag = html.match(new RegExp(`<meta[^>]+(?:property|name)=["']${key}["'][^>]*>`, 'i'));
  if (!tag) return null;
  const content = tag[0].match(/content=["']([^"']*)["']/i);
  return content ? decode(content[1]).trim() || null : null;
}

/** GET /preview?url=... -> { title, image, site } from Open Graph tags, for card thumbnails. */
previewRouter.get('/', ah(async (req, res) => {
  let target;
  try {
    target = new URL(String(req.query.url || ''));
  } catch {
    throw new HttpError(400, 'url must be a full http(s) link');
  }
  if (!/^https?:$/.test(target.protocol) || isPrivateHost(target.hostname)) {
    throw new HttpError(400, 'That link cannot be previewed');
  }
  let html = '';
  try {
    const response = await fetch(target, {
      redirect: 'follow',
      signal: AbortSignal.timeout(6000),
      headers: { 'user-agent': 'Mozilla/5.0 (compatible; SharebyPreview/0.1)', accept: 'text/html' },
    });
    html = (await response.text()).slice(0, 600_000);
  } catch {
    return res.json({ title: null, image: null, site: null });
  }
  const titleTag = html.match(/<title[^>]*>([^<]*)<\/title>/i);
  res.json({
    title: meta(html, 'og:title') || (titleTag ? decode(titleTag[1]).trim() || null : null),
    image: meta(html, 'og:image') || meta(html, 'twitter:image'),
    site: meta(html, 'og:site_name'),
  });
}));

module.exports = { previewRouter, isPrivateHost };
