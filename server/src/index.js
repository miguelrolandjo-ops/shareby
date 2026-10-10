'use strict';
const express = require('express');
const { pool } = require('./db');
const { authRouter, requireAuth } = require('./auth');
const { syncRouter } = require('./sync');
const { foldersRouter } = require('./folders');
const { previewRouter } = require('./preview');

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '2mb' }));

app.get('/health', async (_req, res, next) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

app.use('/auth', authRouter);
app.use(requireAuth);             // everything below needs a session
app.use('/sync', syncRouter);
app.use('/folders', foldersRouter);
app.use('/preview', previewRouter);

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (!err.expose) console.error(err);
  res.status(err.status || 500).json({ error: err.expose ? err.message : 'Something went wrong on the server' });
});

if (require.main === module) {
  const port = Number(process.env.PORT || 8080);
  app.listen(port, () => console.log(`Shareby API listening on http://localhost:${port}`));
}

module.exports = { app };
