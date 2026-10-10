'use strict';
const fs = require('fs');
const path = require('path');
const { pool } = require('./db');

(async () => {
  const sql = fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8');
  await pool.query(sql);
  console.log('Schema applied');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
