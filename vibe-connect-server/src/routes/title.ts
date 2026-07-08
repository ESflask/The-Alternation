// src/routes/title.ts — チャットの自動タイトル生成 API
//
// index.ts で `app.use('/api/title', titleRouter)` として mount される。
// iOS 側が最初のやり取りの後に呼び、Claude（haiku・高速安価）に短いタイトルを付けさせる。
// タスクキューは通さず、その場で claude -p を1回だけ実行して同期的に返す。
// 失敗・タイムアウト時は 200 + { title: "" } を返し、クライアントは元の既定名にフォールバックする。

import { Router, Request, Response } from 'express';
import { execFile } from 'child_process';

const router = Router();

// ANSI エスケープ除去（queue.ts と同方針）。
const ANSI = /\x1b\[[0-9;]*m/g;

/** CLAUDE_ARGS（既定 '-p'）を前置フラグ配列にする。title は必ず print モードで実行。 */
function printFlags(): string[] {
  const raw = process.env.CLAUDE_ARGS;
  const flags = raw && raw.trim() !== '' ? raw.trim().split(/\s+/) : ['-p'];
  return flags.includes('-p') || flags.includes('--print') ? flags : ['-p', ...flags];
}

/**
 * POST /api/title
 * body: { text: string }  // 最初のユーザー指示
 * → { title: string }     // 3〜6語程度の短いタイトル（生成不可なら ""）
 */
router.post('/', (req: Request, res: Response) => {
  const { text } = req.body ?? {};
  if (typeof text !== 'string' || text.trim() === '') {
    return res.status(400).json({ error: 'text is required' });
  }

  const bin = process.env.CLAUDE_BIN || 'claude';
  const prompt =
    'Create a very short chat title (3 to 6 words) that summarizes the user request below. ' +
    'Use the same language as the request. ' +
    'Output ONLY the title text — no surrounding quotes, no trailing punctuation, no preamble, no explanation.\n\n' +
    'Request: ' + text.slice(0, 500);

  const args = [...printFlags(), '--model', 'haiku', prompt];

  execFile(
    bin,
    args,
    { timeout: 25_000, maxBuffer: 1 << 20 },
    (err, stdout) => {
      if (err) {
        return res.status(200).json({ title: '' });
      }
      let title = (stdout || '').replace(ANSI, '').trim();
      // 1行目のみ・前後の引用符/カギ括弧を除去・長さ制限。
      title = (title.split('\n')[0] || '').trim()
        .replace(/^["'“”「」]+|["'“”「」]+$/g, '')
        .trim();
      if (title.length > 40) title = title.slice(0, 40).trim();
      return res.status(200).json({ title });
    }
  );
});

export default router;
