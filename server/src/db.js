'use strict';
const { Pool, types } = require('pg');

// int8 columns (folder colors are ARGB ints > 2^31) come back as strings by default.
types.setTypeParser(20, (value) => Number(value));

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

module.exports = { pool };
