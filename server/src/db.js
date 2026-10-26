'use strict';
const fs = require('fs');
const { Pool, types } = require('pg');

// int8 columns (folder colors are ARGB ints > 2^31) come back as strings by default.
types.setTypeParser(20, (value) => Number(value));

/**
 * SSL for hosted Postgres (Supabase requires it).
 *   DATABASE_SSL=off      plain connection (local Docker Postgres)
 *   DATABASE_SSL=require  encrypted (default when the host isn't local)
 *   DATABASE_CA_CERT=path also verify the server against that CA (Supabase:
 *                         Project Settings > Database > SSL certificate)
 * sslmode in the URL is removed because node-postgres would let it override these settings.
 */
function poolConfig(env = process.env) {
  const url = new URL(env.DATABASE_URL || 'postgres://shareby:shareby@localhost:5432/shareby');
  url.searchParams.delete('sslmode');
  const local = ['localhost', '127.0.0.1', 'db', '::1'].includes(url.hostname);
  const mode = (env.DATABASE_SSL || (local ? 'off' : 'require')).toLowerCase();
  let ssl = false;
  if (mode !== 'off' && mode !== 'false') {
    ssl = env.DATABASE_CA_CERT
      ? { ca: fs.readFileSync(env.DATABASE_CA_CERT, 'utf8'), rejectUnauthorized: true }
      : { rejectUnauthorized: false };
  }
  return {
    connectionString: url.toString(),
    ssl,
    // The Supabase free tier allows few pooled connections; a handful is plenty for this API.
    max: Number(env.DATABASE_POOL_MAX || 5),
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
    keepAlive: true,
  };
}

// All tables live in the "shareby" schema (see schema.sql). Set once per new connection
// (not via a startup option, which Supabase's pooler may not pass on); the pool waits for it
// before handing the connection out.
const pool = new Pool({
  ...poolConfig(),
  onConnect: (client) => client.query('SET search_path TO shareby, public'),
});

// A dropped idle connection (pooler restart, network blip) must not crash the process.
pool.on('error', (err) => console.error('Postgres pool error:', err.message));

module.exports = { pool, poolConfig };
