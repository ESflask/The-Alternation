// src/routes/history.ts — Claude Code の既存ローカル履歴を「閲覧インポート」用に取り出す
//
// index.ts で `app.use('/api/history', historyRouter)`。
// ~/.claude/projects/<encoded>/*.jsonl（1ファイル=1セッション）を読み、user/assistant のテキストを抽出する。
// scope=sandbox（TARGET_WORKSPACE_PATH のみ・既定） / scope=all（全プロジェクト）。
// 変換は表示用スナップショット：thinking / tool_use / tool_result は除外し text ブロックのみ。

import { Router, Request, Response } from 'express';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

const router = Router();

function encodePath(p: string): string {
  return p.replace(/[^A-Za-z0-9]/g, '-');
}

function scopeDirs(scope: string): string[] {
  const projectsDir = path.join(os.homedir(), '.claude', 'projects');
  let dirs: string[] = [];
  try {
    dirs = fs.readdirSync(projectsDir)
      .map(d => path.join(projectsDir, d))
      .filter(d => { try { return fs.statSync(d).isDirectory(); } catch { return false; } });
  } catch {
    return [];
  }
  if (scope === 'all') return dirs;
  const ws = process.env.TARGET_WORKSPACE_PATH;
  if (!ws) return dirs;
  const enc = encodePath(ws);
  return dirs.filter(d => path.basename(d) === enc);
}

/** content（string or blocks[]）から text だけを取り出す。 */
function extractText(content: any): string {
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content
      .filter((b: any) => b && b.type === 'text' && typeof b.text === 'string')
      .map((b: any) => b.text)
      .join('\n')
      .trim();
  }
  return '';
}

/** user 行が tool_result のみ（＝ツール出力でユーザー発話ではない）か。 */
function isToolResultOnly(content: any): boolean {
  return Array.isArray(content) && content.length > 0
    && content.every((b: any) => b && b.type !== 'text');
}

// GET /api/history/sessions?scope=sandbox|all
router.get('/sessions', (req: Request, res: Response) => {
  const scope = req.query.scope === 'all' ? 'all' : 'sandbox';
  const dirs = scopeDirs(scope);
  const sessions: any[] = [];

  for (const dir of dirs) {
    let files: string[] = [];
    try { files = fs.readdirSync(dir).filter(f => f.endsWith('.jsonl')); } catch { continue; }

    for (const f of files) {
      let content = '';
      try { content = fs.readFileSync(path.join(dir, f), 'utf8'); } catch { continue; }

      let firstUser = '';
      let count = 0;
      let startedAt = '';
      let lastAt = '';

      for (const line of content.split('\n')) {
        if (!line || (line.indexOf('"user"') === -1 && line.indexOf('"assistant"') === -1)) continue;
        let o: any;
        try { o = JSON.parse(line); } catch { continue; }
        const t = o.type;
        if (t !== 'user' && t !== 'assistant') continue;
        const c = o.message?.content;
        if (t === 'user' && isToolResultOnly(c)) continue;
        const text = extractText(c);
        if (!text) continue;
        if (!startedAt) startedAt = o.timestamp || '';
        lastAt = o.timestamp || lastAt;
        count++;
        if (t === 'user' && !firstUser) firstUser = text;
      }

      if (count === 0) continue;
      sessions.push({
        id: f.replace(/\.jsonl$/, ''),
        title: (firstUser || '(無題のセッション)').slice(0, 60),
        messageCount: count,
        startedAt,
        lastAt,
      });
    }
  }

  sessions.sort((a, b) => (b.lastAt || '').localeCompare(a.lastAt || ''));
  return res.status(200).json({ scope, sessions });
});

// GET /api/history/:id?scope=sandbox|all
router.get('/:id', (req: Request, res: Response) => {
  const scope = req.query.scope === 'all' ? 'all' : 'sandbox';
  const id = req.params.id;
  if (!/^[A-Za-z0-9._-]+$/.test(id)) {
    return res.status(400).json({ error: 'invalid session id' });
  }

  let file = '';
  for (const dir of scopeDirs(scope)) {
    const p = path.join(dir, id + '.jsonl');
    if (fs.existsSync(p)) { file = p; break; }
  }
  if (!file) return res.status(404).json({ error: 'session not found' });

  let content = '';
  try { content = fs.readFileSync(file, 'utf8'); } catch { return res.status(500).json({ error: 'read failed' }); }

  const messages: any[] = [];
  for (const line of content.split('\n')) {
    if (!line || (line.indexOf('"user"') === -1 && line.indexOf('"assistant"') === -1)) continue;
    let o: any;
    try { o = JSON.parse(line); } catch { continue; }
    const t = o.type;
    if (t !== 'user' && t !== 'assistant') continue;
    const c = o.message?.content;
    if (t === 'user' && isToolResultOnly(c)) continue;
    const text = extractText(c);
    if (!text) continue;
    messages.push({ role: t, text, timestamp: o.timestamp || null });
  }

  return res.status(200).json({ id, count: messages.length, messages });
});

export default router;
