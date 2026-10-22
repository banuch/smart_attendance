import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { createPool } from './db.js';

const config = loadConfig();
const pool = createPool(config.db);
const server = createApp({ pool, config }).listen(config.port, () => {
  console.log(`Smart Attendance API listening on :${config.port} (day boundary: ${config.timezone})`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => pool.end().then(() => process.exit(0)));
  });
}
