// Boots a real (userspace) PostgreSQL via embedded-postgres, loads the schema +
// RLS, gives gemba_app a dev password, then runs the RLS integration test against
// it as the non-superuser gemba_app role. Lets us actually exercise RLS without a
// system Postgres or Docker. Dev tooling only — not committed as a dependency.
import EmbeddedPostgres from 'embedded-postgres';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const PORT = 5439;

const epg = new EmbeddedPostgres({
  databaseDir: '/tmp/gemba-pgdata',
  user: 'postgres',
  password: 'postgres',
  port: PORT,
  persistent: false,
});

let code = 1;
try {
  await epg.initialise();
  await epg.start();
  await epg.createDatabase('gemba');

  // Load schema + RLS as superuser, then set the gemba_app password.
  const admin = new pg.Client({ host: 'localhost', port: PORT, user: 'postgres', password: 'postgres', database: 'gemba' });
  await admin.connect();
  await admin.query(readFileSync(join(root, 'db', 'schema.sql'), 'utf8'));
  await admin.query("ALTER ROLE gemba_app WITH PASSWORD 'devpassword'");
  await admin.end();

  const url = `postgres://gemba_app:devpassword@localhost:${PORT}/gemba`;
  const res = spawnSync('node', ['--test', 'test/integration/rls.test.js'], {
    cwd: root,
    stdio: 'inherit',
    env: { ...process.env, DATABASE_URL: url },
  });
  code = res.status ?? 1;
} finally {
  await epg.stop();
}
process.exit(code);
