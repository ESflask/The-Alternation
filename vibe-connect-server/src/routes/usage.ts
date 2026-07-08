// src/routes/usage.ts — Claude Code のローカル使用量集計 API（自前パーサ・依存ゼロ）
//
// index.ts で `app.use('/api/usage', usageRouter)` として mount。
// ~/.claude/projects/<encoded-path>/*.jsonl の assistant 行にある message.usage を集計する。
// scope=all（全プロジェクト） / scope=sandbox（TARGET_WORKSPACE_PATH のみ）。
// ※ 実測トークンはログ由来で正確。コストは概算料金表による「推定」。公式請求やプラン残枠とは別物。

import { Router, Request, Response } from 'express';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

const router = Router();

// モデル別 概算料金（USD / 100万トークン）。推定値。
interface Price { input: number; output: number; cacheWrite: number; cacheRead: number; }
const PRICING: Record<string, Price> = {
  opus:   { input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5 },
  sonnet: { input: 3,  output: 15, cacheWrite: 3.75,  cacheRead: 0.3 },
  haiku:  { input: 1,  output: 5,  cacheWrite: 1.25,  cacheRead: 0.1 },
  fable:  { input: 3,  output: 15, cacheWrite: 3.75,  cacheRead: 0.3 },
};

function modelFamily(model: string): string {
  const m = model.toLowerCase();
  for (const k of ['opus', 'sonnet', 'haiku', 'fable']) {
    if (m.includes(k)) return k;
  }
  return model;
}
function priceFor(model: string): Price {
  return PRICING[modelFamily(model)] ?? PRICING.sonnet;
}

interface Bucket {
  inputTokens: number; outputTokens: number;
  cacheReadTokens: number; cacheCreationTokens: number;
  totalTokens: number; costUSD: number; requests: number;
}
function emptyBucket(): Bucket {
  return { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, totalTokens: 0, costUSD: 0, requests: 0 };
}
interface Sample { input: number; output: number; cacheRead: number; cacheCreation: number; }
function addToBucket(b: Bucket, u: Sample, cost: number): void {
  b.inputTokens += u.input;
  b.outputTokens += u.output;
  b.cacheReadTokens += u.cacheRead;
  b.cacheCreationTokens += u.cacheCreation;
  b.totalTokens += u.input + u.output + u.cacheRead + u.cacheCreation;
  b.costUSD += cost;
  b.requests += 1;
}

/** Claude のプロジェクトディレクトリ名の符号化（例 /Users/x/Python_pjs/vibe-sandbox → -Users-x-Python-pjs-vibe-sandbox）。 */
function encodePath(p: string): string {
  return p.replace(/[^A-Za-z0-9]/g, '-');
}

router.get('/', (req: Request, res: Response) => {
  const scope = req.query.scope === 'sandbox' ? 'sandbox' : 'all';
  const projectsDir = path.join(os.homedir(), '.claude', 'projects');

  let dirs: string[] = [];
  try {
    dirs = fs.readdirSync(projectsDir)
      .map(d => path.join(projectsDir, d))
      .filter(d => { try { return fs.statSync(d).isDirectory(); } catch { return false; } });
  } catch {
    return res.status(200).json({ scope, error: 'no-logs', periods: null, byModel: [] });
  }

  if (scope === 'sandbox') {
    const ws = process.env.TARGET_WORKSPACE_PATH;
    if (ws) {
      const enc = encodePath(ws);
      dirs = dirs.filter(d => path.basename(d) === enc);
    }
  }

  const now = Date.now();
  const day = 24 * 3600 * 1000;
  const t = new Date();
  const startOfToday = new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
  const monthStart = new Date(t.getFullYear(), t.getMonth(), 1).getTime();

  const periods = {
    today: emptyBucket(), last7d: emptyBucket(), thisMonth: emptyBucket(), allTime: emptyBucket(),
  };
  const byModelMap: Record<string, Bucket & { model: string }> = {};

  let scannedFiles = 0;
  let skippedFiles = 0;
  const MAX_FILE = 80 * 1024 * 1024; // 80MB 超のファイルはスキップ（保険）

  for (const dir of dirs) {
    let files: string[] = [];
    try {
      files = fs.readdirSync(dir).filter(f => f.endsWith('.jsonl')).map(f => path.join(dir, f));
    } catch { continue; }

    for (const file of files) {
      let size = 0;
      try { size = fs.statSync(file).size; } catch { continue; }
      if (size > MAX_FILE) { skippedFiles++; continue; }

      let content = '';
      try { content = fs.readFileSync(file, 'utf8'); } catch { continue; }
      scannedFiles++;

      for (const line of content.split('\n')) {
        if (!line || line.indexOf('"usage"') === -1) continue;
        let o: any;
        try { o = JSON.parse(line); } catch { continue; }
        if (o?.type !== 'assistant') continue;
        const usageRaw = o.message?.usage;
        if (!usageRaw) continue;

        const u: Sample = {
          input: usageRaw.input_tokens || 0,
          output: usageRaw.output_tokens || 0,
          cacheRead: usageRaw.cache_read_input_tokens || 0,
          cacheCreation: usageRaw.cache_creation_input_tokens || 0,
        };
        const model: string = o.message?.model || 'unknown';
        const p = priceFor(model);
        const cost = (u.input * p.input + u.output * p.output
          + u.cacheCreation * p.cacheWrite + u.cacheRead * p.cacheRead) / 1e6;

        const ts = Date.parse(o.timestamp || '') || 0;
        addToBucket(periods.allTime, u, cost);
        if (ts >= startOfToday) addToBucket(periods.today, u, cost);
        if (ts >= now - 7 * day) addToBucket(periods.last7d, u, cost);
        if (ts >= monthStart) addToBucket(periods.thisMonth, u, cost);

        const fam = modelFamily(model);
        const bm = byModelMap[fam] || (byModelMap[fam] = { model: fam, ...emptyBucket() });
        addToBucket(bm, u, cost);
      }
    }
  }

  const byModel = Object.values(byModelMap)
    .filter(m => m.totalTokens > 0)          // <synthetic> 等の0トークン行は除外
    .sort((a, b) => b.costUSD - a.costUSD);

  return res.status(200).json({
    scope,
    generatedAt: new Date().toISOString(),
    scannedFiles,
    skippedFiles,
    note: 'ローカルの Claude Code ログ由来の実測トークン。コストは概算料金表による推定です（公式の請求額やプラン残枠とは別）。',
    periods,
    byModel,
  });
});

export default router;
