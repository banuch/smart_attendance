/** Reads settings from environment variables (see .env.example). */
export function loadConfig(env = process.env) {
  const jwtSecret = env.JWT_SECRET;
  if (!jwtSecret || jwtSecret.length < 32) {
    throw new Error('JWT_SECRET must be set to a random string of 32+ characters');
  }
  const timezone = env.APP_TIMEZONE || 'UTC';
  // Throws RangeError for an unknown zone, so typos fail at start-up.
  new Intl.DateTimeFormat('en-CA', { timeZone: timezone });

  return {
    port: Number(env.PORT) || 8080,
    db: {
      host: env.DB_HOST || '127.0.0.1',
      port: Number(env.DB_PORT) || 3306,
      user: env.DB_USER || 'attendance',
      password: env.DB_PASSWORD || '',
      database: env.DB_NAME || 'smart_attendance',
    },
    jwtSecret,
    tokenTtl: env.TOKEN_TTL || '30d',
    uploadDir: env.UPLOAD_DIR || './uploads',
    // Public origin used in photo links, e.g. https://attendance.example.com.
    // Derived from the request when empty.
    publicUrl: (env.PUBLIC_URL || '').replace(/\/+$/, ''),
    corsOrigins: (env.CORS_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean),
    // Time zone that decides which calendar day a punch belongs to.
    timezone,
    faceMatchThreshold: Number(env.FACE_MATCH_THRESHOLD) || 0.55,
    maxGpsAccuracyMeters: Number(env.MAX_GPS_ACCURACY_METERS) || 50,
  };
}
