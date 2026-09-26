import { Pool } from 'pg';

const raw = process.env.DATABASE_URL || '';
let url;
try { url = new URL(raw); } catch { /* Report below without echoing the secret. */ }

if (!url || !['postgres:', 'postgresql:'].includes(url.protocol) ||
    !url.username || !url.password || !url.hostname || url.pathname === '/' ||
    /[<>]/.test(raw)) {
  console.error('DATABASE_URL must be the complete Neon PostgreSQL connection string with no placeholders.');
  process.exit(1);
}
if (process.env.APPLE_BUNDLE_ID !== 'com.onepalebluedot.helipad') {
  console.error('APPLE_BUNDLE_ID must match the iOS app bundle ID.');
  process.exit(1);
}

const pool = new Pool({ connectionString: raw, max: 1, connectionTimeoutMillis: 8000 });
try {
  const { rows } = await pool.query(
    "SELECT has_schema_privilege(current_user, current_schema(), 'CREATE') AS can_create"
  );
  if (!rows[0]?.can_create) {
    console.error('Database role cannot create the family tables.');
    process.exitCode = 1;
  } else {
    console.log('Neon connection, schema permission, and Apple bundle ID are ready.');
  }
} catch (error) {
  console.error(`Neon connection failed (${error.code || error.name}).`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
