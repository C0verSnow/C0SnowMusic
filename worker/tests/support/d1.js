// Execute both Workers' real SQL against SQLite, with the D1 result shape.
export class D1 {
  constructor(database) { this.database = database; }
  prepare(sql) {
    const query = this.database.prepare(sql);
    const statement = (params = []) => ({
      bind: (...values) => statement(values),
      async first(column) {
        const row = query.get(...params) ?? null;
        return column && row ? row[column] : row;
      },
      async all() { return { success: true, results: query.all(...params) }; },
      async run() {
        const result = query.run(...params);
        return { success: true, meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) } };
      },
    });
    return statement();
  }
  async batch(statements) {
    this.database.exec('BEGIN');
    try {
      const results = [];
      for (const statement of statements) results.push(await statement.run());
      this.database.exec('COMMIT');
      return results;
    } catch (error) { this.database.exec('ROLLBACK'); throw error; }
  }
}
