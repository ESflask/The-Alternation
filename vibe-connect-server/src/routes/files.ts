// VibeConnect ファイルAPI ルーター (Agent: ファイルAPI担当)
// CONTRACTS-FEATURES.md §A の tree/read/write JSON形状・mount契約に準拠。
// mount: app.use('/api/files', filesRouter) → 本ファイル内のパスは '/tree' '/read' '/write'。
import { Router, Request, Response } from 'express';
import * as fs from 'fs/promises';
import * as path from 'path';

const router = Router();

// ---- 定数 -------------------------------------------------------------

// テキスト読み取りの上限。これを超える場合は先頭のみ返して truncated:true。
const MAX_READ_BYTES = 2 * 1024 * 1024; // 2MB
// 巨大 or バイナリ判定時に返す先頭プレビューのバイト数（数KB）。
const PREVIEW_BYTES = 8 * 1024; // 8KB
// ツリー一覧から常に除外するディレクトリ名（少なくとも .git は除外）。
const EXCLUDED_DIR_NAMES = new Set(['.git', 'node_modules']);

// ---- ルート解決 -------------------------------------------------------

// 対象ワークスペースの絶対パス。未設定なら process.cwd() にフォールバックしつつ warn。
function resolveWorkspacePath(): string {
  const target = process.env.TARGET_WORKSPACE_PATH;
  if (target && target.trim() !== '') {
    return target;
  }
  console.warn(
    '[files] TARGET_WORKSPACE_PATH が未設定です。process.cwd() にフォールバックします:',
    process.cwd()
  );
  return process.cwd();
}

// ---- パストラバーサル対策 --------------------------------------------

// path.relative の結果がルート外を指すか判定する。
// '' はルート自身（＝内側）。'..' 始まりや絶対パスは外側。
// （'..foo' のような '..' で始まる正当なディレクトリ名を誤検出しないよう厳密に判定）
function isRelOutside(rel: string): boolean {
  if (rel === '') return false;
  if (path.isAbsolute(rel)) return true;
  return rel === '..' || rel.startsWith('..' + path.sep);
}

// realpath ベースでシンボリックリンクによるルート外脱出を弾く。
// resolved が未存在（新規書き込み等）の場合は、最も近い既存の祖先を realpath して検証する。
// 予期しない I/O エラー（root 未存在・EACCES 等）は throw し、呼び出し側で 500 にする。
async function realWithinRoot(root: string, resolved: string): Promise<boolean> {
  const realRoot = await fs.realpath(root);
  let current = resolved;
  for (;;) {
    try {
      const real = await fs.realpath(current);
      const rel = path.relative(realRoot, real);
      return !isRelOutside(rel);
    } catch (err) {
      const e = err as NodeJS.ErrnoException;
      if (e.code === 'ENOENT') {
        const parent = path.dirname(current);
        if (parent === current) return false; // FS ルートまで遡っても見つからず
        current = parent;
        continue;
      }
      throw err;
    }
  }
}

interface SafePath {
  resolved: string; // 検証済みの絶対パス
  relPosix: string; // ルート相対（'/' 区切り、ルートは ''）
}

// 受け取った相対パスを安全に解決する。
// - 文字列正規化（path.resolve）→ path.relative がルート外なら null。
// - realpath でシンボリックリンクによる脱出も検証。
// 戻り値 null は「invalid path」、throw は予期しない I/O エラー。
async function resolveSafe(rel: string): Promise<SafePath | null> {
  const root = resolveWorkspacePath();
  const resolved = path.resolve(root, rel);
  const relToRoot = path.relative(root, resolved);
  if (isRelOutside(relToRoot)) {
    return null;
  }
  const inside = await realWithinRoot(root, resolved);
  if (!inside) {
    return null;
  }
  return { resolved, relPosix: relToRoot.split(path.sep).join('/') };
}

// クエリ/ボディの path を string に強制する。
// undefined/null は allowUndefined=true のとき '' として許容（tree のルート指定）。
// 配列・オブジェクト等は不正入力として null。
function coerceRel(raw: unknown, allowUndefined: boolean): string | null {
  if (raw === undefined || raw === null) {
    return allowUndefined ? '' : null;
  }
  return typeof raw === 'string' ? raw : null;
}

// ---- GET /tree --------------------------------------------------------
// ルート相対ディレクトリの一覧。ディレクトリ優先→名前昇順。.git/node_modules は除外。
router.get('/tree', async (req: Request, res: Response) => {
  const rel = coerceRel(req.query.path, true);
  if (rel === null) {
    res.status(400).json({ error: 'invalid path' });
    return;
  }

  try {
    const safe = await resolveSafe(rel);
    if (!safe) {
      res.status(400).json({ error: 'invalid path' });
      return;
    }

    const stat = await fs.stat(safe.resolved);
    if (!stat.isDirectory()) {
      res.status(400).json({ error: 'not a directory' });
      return;
    }

    const dirents = await fs.readdir(safe.resolved, { withFileTypes: true });
    const entries: Array<{
      name: string;
      path: string;
      type: 'file' | 'dir';
      size: number | null;
    }> = [];

    for (const dirent of dirents) {
      if (EXCLUDED_DIR_NAMES.has(dirent.name)) continue;

      const childAbs = path.join(safe.resolved, dirent.name);
      const childRel = path
        .relative(resolveWorkspacePath(), childAbs)
        .split(path.sep)
        .join('/');

      let type: 'file' | 'dir';
      let size: number | null;
      try {
        // シンボリックリンクも追って実体で判定。
        const s = await fs.stat(childAbs);
        if (s.isDirectory()) {
          type = 'dir';
          size = null;
        } else {
          type = 'file';
          size = s.size;
        }
      } catch {
        // 壊れたシンボリックリンク等は Dirent の情報でフォールバック。
        type = dirent.isDirectory() ? 'dir' : 'file';
        size = null;
      }

      entries.push({ name: dirent.name, path: childRel, type, size });
    }

    // ディレクトリ優先 → 名前昇順。
    entries.sort((a, b) => {
      if (a.type !== b.type) return a.type === 'dir' ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    res.status(200).json({ path: safe.relPosix, entries });
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === 'ENOENT') {
      res.status(404).json({ error: 'not found' });
      return;
    }
    if (e.code === 'ENOTDIR') {
      res.status(400).json({ error: 'not a directory' });
      return;
    }
    const message = err instanceof Error ? err.message : 'failed to read directory';
    res.status(500).json({ error: message });
  }
});

// ---- GET /read --------------------------------------------------------
// テキストファイルの内容。2MB超は先頭のみ、NULバイト検出（バイナリ）は空にして truncated:true。
router.get('/read', async (req: Request, res: Response) => {
  const rel = coerceRel(req.query.path, false);
  if (rel === null || rel === '') {
    res.status(400).json({ error: 'invalid path' });
    return;
  }

  try {
    const safe = await resolveSafe(rel);
    if (!safe) {
      res.status(400).json({ error: 'invalid path' });
      return;
    }

    const stat = await fs.stat(safe.resolved);
    if (!stat.isFile()) {
      res.status(400).json({ error: 'not a file' });
      return;
    }

    let buffer: Buffer;
    let truncated = false;

    if (stat.size > MAX_READ_BYTES) {
      // 巨大ファイルは先頭 PREVIEW_BYTES のみ読む。
      const fh = await fs.open(safe.resolved, 'r');
      try {
        const preview = Buffer.alloc(PREVIEW_BYTES);
        const { bytesRead } = await fh.read(preview, 0, PREVIEW_BYTES, 0);
        buffer = preview.subarray(0, bytesRead);
      } finally {
        await fh.close();
      }
      truncated = true;
    } else {
      buffer = await fs.readFile(safe.resolved);
    }

    // NULバイトを含めばバイナリとみなし content を空にする。
    if (buffer.includes(0)) {
      res.status(200).json({ path: safe.relPosix, content: '', truncated: true });
      return;
    }

    res.status(200).json({
      path: safe.relPosix,
      content: buffer.toString('utf8'),
      truncated,
    });
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === 'ENOENT') {
      res.status(404).json({ error: 'not found' });
      return;
    }
    if (e.code === 'EISDIR') {
      res.status(400).json({ error: 'not a file' });
      return;
    }
    const message = err instanceof Error ? err.message : 'failed to read file';
    res.status(500).json({ error: message });
  }
});

// ---- PUT /write -------------------------------------------------------
// body { path, content } を検証しファイルへ書き込む。親ディレクトリは必要に応じて作成。
router.put('/write', async (req: Request, res: Response) => {
  const body = (req.body ?? {}) as { path?: unknown; content?: unknown };
  const rel = coerceRel(body.path, false);
  const content = body.content;

  if (rel === null || rel === '') {
    res.status(400).json({ success: false, message: 'invalid path' });
    return;
  }
  if (typeof content !== 'string') {
    res.status(400).json({ success: false, message: 'content must be a string' });
    return;
  }

  try {
    const safe = await resolveSafe(rel);
    if (!safe) {
      res.status(400).json({ success: false, message: 'invalid path' });
      return;
    }

    // 親ディレクトリが無ければ作成（ルート内であることは検証済み）。
    await fs.mkdir(path.dirname(safe.resolved), { recursive: true });
    await fs.writeFile(safe.resolved, content, 'utf8');

    res.status(200).json({ success: true, message: 'saved' });
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === 'EISDIR') {
      res.status(400).json({ success: false, message: 'path is a directory' });
      return;
    }
    const message = err instanceof Error ? err.message : 'failed to write file';
    res.status(500).json({ success: false, message });
  }
});

export default router;
