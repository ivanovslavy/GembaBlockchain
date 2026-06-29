import { createWriteStream, mkdirSync, renameSync, existsSync } from "node:fs";
import { createGzip } from "node:zlib";
import { createReadStream, unlinkSync } from "node:fs";
import { join } from "node:path";

// Append-only JSONL writers with gzip rotation (disk budget). One logger per run.
export class RunLogger {
  constructor(runId, baseDir, rotateLines = 200000) {
    this.dir = join(baseDir, runId);
    mkdirSync(this.dir, { recursive: true });
    this.rotate = rotateLines;
    this.streams = {};
    this.counts = {};
    this.seq = {};
  }
  _stream(name) {
    if (!this.streams[name]) {
      this.streams[name] = createWriteStream(join(this.dir, `${name}.jsonl`), { flags: "a" });
      this.counts[name] = 0; this.seq[name] = 0;
    }
    return this.streams[name];
  }
  write(name, obj) {
    const s = this._stream(name);
    s.write(JSON.stringify(obj) + "\n");
    if (++this.counts[name] >= this.rotate) this._rotate(name);
  }
  _rotate(name) {
    const s = this.streams[name];
    s.end();
    const cur = join(this.dir, `${name}.jsonl`);
    const rolled = join(this.dir, `${name}.${this.seq[name]++}.jsonl`);
    if (existsSync(cur)) {
      renameSync(cur, rolled);
      const gz = createWriteStream(rolled + ".gz");
      createReadStream(rolled).pipe(createGzip()).pipe(gz).on("finish", () => { try { unlinkSync(rolled); } catch {} });
    }
    delete this.streams[name]; this.counts[name] = 0;
  }
  async close() {
    await Promise.all(Object.values(this.streams).map((s) => new Promise((r) => s.end(r))));
  }
}
