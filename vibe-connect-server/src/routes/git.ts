// VibeConnect Git操作API ルーター (Agent 3)
// CONTRACTS.md §2 の diff/commit JSON形状、§3 のルーター契約に準拠。
// mount: app.use('/api/git', gitRouter) → 本ファイル内のパスは '/diff' と '/commit'。
import { Router, Request, Response } from 'express';
import { execFile } from 'child_process';

const router = Router();

// 対象リポジトリの絶対パス。未設定なら process.cwd() にフォールバックしつつ warn。
function resolveWorkspacePath(): string {
  const target = process.env.TARGET_WORKSPACE_PATH;
  if (target && target.trim() !== '') {
    return target;
  }
  console.warn(
    '[git] TARGET_WORKSPACE_PATH が未設定です。process.cwd() にフォールバックします:',
    process.cwd()
  );
  return process.cwd();
}

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number | null; // プロセス終了コード（起動失敗時は null）
  failedToStart: boolean; // git バイナリが見つからない (ENOENT) 等
}

// execFile を Promise 化するローカルヘルパ。
// shell:false でシェルを介さず、引数はそのまま git に渡す（インジェクション回避）。
// 非ゼロ終了でも reject せず結果を返す（stderr を応答に利用したいため）。
function runGit(args: string[], cwd: string): Promise<ExecResult> {
  return new Promise((resolve) => {
    execFile(
      'git',
      args,
      { cwd, shell: false, maxBuffer: 1024 * 1024 * 64 },
      (error, stdout, stderr) => {
        if (error) {
          const e = error as NodeJS.ErrnoException & { code?: number | string };
          // 非ゼロ終了なら code は数値の終了コード、起動失敗なら 'ENOENT' 等の文字列。
          const numericCode = typeof e.code === 'number' ? e.code : null;
          const failedToStart = typeof e.code === 'string';
          resolve({
            stdout: stdout ?? '',
            stderr: stderr ?? '',
            code: numericCode,
            failedToStart,
          });
          return;
        }
        resolve({ stdout: stdout ?? '', stderr: stderr ?? '', code: 0, failedToStart: false });
      }
    );
  });
}

// GET /diff — 対象リポジトリの変更を取得（CONTRACTS.md §2）。
router.get('/diff', async (_req: Request, res: Response) => {
  const cwd = resolveWorkspacePath();
  try {
    // 1. 変更検出は git status --porcelain。出力が空でなければ has_changes: true。
    const status = await runGit(['status', '--porcelain'], cwd);
    if (status.failedToStart) {
      res.status(500).json({ error: 'git コマンドを実行できません（git が見つかりません）。' });
      return;
    }
    if (status.code !== 0) {
      // 非gitディレクトリ等
      res.status(500).json({ error: (status.stderr || 'git status に失敗しました。').trim() });
      return;
    }

    const porcelain = status.stdout;
    if (porcelain.trim() === '') {
      res.status(200).json({ has_changes: false, diff: '' });
      return;
    }

    // 2. 差分本文は staged + unstaged 双方を含む git diff HEAD を基本とし、
    //    失敗する場合（初回コミット無し等）は git diff にフォールバック。
    let diffResult = await runGit(['diff', 'HEAD'], cwd);
    if (diffResult.code !== 0) {
      diffResult = await runGit(['diff'], cwd);
    }
    let diff = diffResult.stdout;

    // 3. 未追跡ファイルは git diff に含まれないため、末尾に注記として列挙。
    const untracked = porcelain
      .split('\n')
      .filter((line) => line.startsWith('??'))
      .map((line) => line.slice(3).trim())
      .filter((p) => p.length > 0);
    if (untracked.length > 0) {
      const notes = untracked.map((p) => `# untracked: ${p}`).join('\n');
      diff = diff.length > 0 ? `${diff}\n${notes}\n` : `${notes}\n`;
    }

    res.status(200).json({ has_changes: true, diff });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'git diff の取得に失敗しました。';
    res.status(500).json({ error: message });
  }
});

// POST /commit — body { message } を検証し、git add -A → git commit -m <message>（CONTRACTS.md §2）。
router.post('/commit', async (req: Request, res: Response) => {
  const rawMessage: unknown = (req.body ?? {}).message;
  const message = typeof rawMessage === 'string' ? rawMessage.trim() : '';
  if (message === '') {
    res.status(400).json({ success: false, message: 'commit message is required' });
    return;
  }

  const cwd = resolveWorkspacePath();
  try {
    // git add -A で新規ファイルも取り込む（git commit -am では未追跡を拾えないため）。
    const add = await runGit(['add', '-A'], cwd);
    if (add.failedToStart) {
      res
        .status(500)
        .json({ success: false, message: 'git コマンドを実行できません（git が見つかりません）。' });
      return;
    }
    if (add.code !== 0) {
      res.status(500).json({ success: false, message: (add.stderr || 'git add に失敗しました。').trim() });
      return;
    }

    // message は execFile の引数として渡すため、シェルを介さずインジェクションを回避。
    const commit = await runGit(['commit', '-m', message], cwd);
    if (commit.code === 0) {
      res.status(200).json({ success: true, message: 'Changes committed successfully.' });
      return;
    }

    // 「nothing to commit」等はクラッシュさせず正常応答（200 success:false）。
    const combined = `${commit.stdout}\n${commit.stderr}`.toLowerCase();
    if (combined.includes('nothing to commit') || combined.includes('no changes added')) {
      res.status(200).json({ success: false, message: 'Nothing to commit.' });
      return;
    }

    // その他のエラーは 500 { success:false, message:<stderr> }。
    res.status(500).json({
      success: false,
      message: (commit.stderr || commit.stdout || 'git commit に失敗しました。').trim(),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'git commit に失敗しました。';
    res.status(500).json({ success: false, message });
  }
});

export default router;
