/** Calendar day (`yyyy-MM-dd`) of [date] in [timeZone]. */
export function dateKey(date, timeZone) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

/** JS Date → MySQL DATETIME(3) literal in UTC. */
export const toSqlTime = (date) => date.toISOString().slice(0, 23).replace('T', ' ');

/** MySQL DATETIME string (UTC) → ISO 8601, or null. */
export const fromSqlTime = (s) => (s ? `${s.replace(' ', 'T')}Z` : null);
