'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { validateRules } = require('../src/rules');
const rules = require('../src/rules.json');

test('every platform and title rule is well formed', () => {
  validateRules();
});

test('the app ships the same rules file it can fetch from the server', () => {
  const bundled = path.join(__dirname, '..', '..', 'app', 'assets', 'rules.json');
  assert.deepEqual(JSON.parse(fs.readFileSync(bundled, 'utf8')), rules);
});

test('Instagram titles lose the "Name on Instagram:" prefix, in English and Indonesian', () => {
  const rule = new RegExp(rules.platforms.find((p) => p.key === 'instagram').titleRules[0], 'is');
  assert.equal('Mia on Instagram: nasi goreng'.match(rule).groups.title, 'nasi goreng');
  assert.equal('Mia di Instagram: nasi goreng'.match(rule).groups.author, 'Mia');
});
