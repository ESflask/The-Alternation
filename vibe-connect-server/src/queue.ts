// src/queue.ts — 非同期タスクキュー (Agent 2)
//
// iPhoneからの指示を受け取り、Claude Code CLI を child_process.spawn で
// 非同期起動する。標準出力/標準エラーをリアルタイムに ANSI 除去して
// メモリ内タスクの logs に蓄積し、ポーリング (GET /api/tasks/:id) で返す。
//
// 【Claude CLI の非対話フラグに関する注意】
// IMPLEMENTATION_PLAN の指示は `claude -y "指示"` だが、実際の Claude Code CLI の
// 非対話実行は `-p / --print` や `--dangerously-skip-permissions` である可能性が高く、
// 環境・バージョンで異なりうる。よって既定引数は ['-y', instruction] としつつ、
// 環境変数 CLAUDE_ARGS で前置フラグ群を上書きできるようにしている。
// CLAUDE_BIN を mock/mock-claude.sh に差し替えれば claude 未インストールでもテスト可能。

import { spawn } from 'child_process';
import { v4 as uuidv4 } from 'uuid';
import { Task } from './types';

/** メモリ内タスク管理ストア。プロセス生存中のみ有効（ステートレス設計）。 */
const tasks = new Map<string, Task>();

/**
 * ANSI エスケープ / カーソル制御シーケンスを除去する。
 * 依存を追加せず正規表現ヘルパで対応（CSI / OSC / 単一制御シーケンスを広くカバー）。
 * 参考: 一般的な ansi-regex 相当パターン。
 */
const ANSI_PATTERN = new RegExp(
  [
    '[\\u001B\\u009B][[\\]()#;?]*',
    '(?:(?:(?:[a-zA-Z\\d]*(?:;[a-zA-Z\\d]*)*)?\\u0007)',
    '|(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PRZcf-ntqry=><~]))',
  ].join(''),
  'g',
);

function stripAnsi(input: string): string {
  return input.replace(ANSI_PATTERN, '');
}

/** ISO8601 の現在時刻文字列。 */
function nowIso(): string {
  return new Date().toISOString();
}

/**
 * Claude CLI へ渡す引数配列を組み立てる。
 * 常に配列で渡し shell:false と組み合わせることでシェルインジェクションを回避する。
 * instruction は必ず独立した1引数として末尾に付与する（クオート不要・安全）。
 *
 * model/effort は指定時のみ、それぞれ独立した2要素（`--model <id>` / `--effort <level>`）
 * として既定フラグと instruction の間に挿入する。値の妥当性検証は呼び出し側
 * (routes/tasks.ts のホワイトリスト) が担い、ここでは truthy なら付与する。
 * 組み立て順: [...既定フラグ, '--model', model?, '--effort', effort?, instruction]
 */
function buildClaudeArgs(
  instruction: string,
  opts?: { model?: string; effort?: string },
): string[] {
  const raw = process.env.CLAUDE_ARGS;
  const flags = raw && raw.trim() !== '' ? raw.trim().split(/\s+/) : ['-y'];
  const model = opts?.model;
  const effort = opts?.effort;
  return [
    ...flags,
    ...(model ? ['--model', model] : []),
    ...(effort ? ['--effort', effort] : []),
    instruction,
  ];
}

/**
 * タスクを生成し Claude CLI を非同期起動。生成直後の Task を返す（spawn 完了は待たない）。
 * opts.model / opts.effort は spawn 引数にのみ使用し、Task には格納しない
 * （types.ts の Task 型は不変・後方互換のため）。
 */
export function createTask(
  instruction: string,
  opts?: { model?: string; effort?: string },
): Task {
  const id = uuidv4();
  const timestamp = nowIso();

  const task: Task = {
    task_id: id,
    status: 'processing',
    instruction,
    logs: '',
    error: null,
    exit_code: null,
    created_at: timestamp,
    updated_at: timestamp,
  };
  tasks.set(id, task);

  const bin = process.env.CLAUDE_BIN || 'claude';
  const workspace = process.env.TARGET_WORKSPACE_PATH;
  let cwd = workspace;
  if (!cwd) {
    cwd = process.cwd();
    console.warn(
      `[queue] TARGET_WORKSPACE_PATH 未設定のため cwd に ${cwd} を使用します。` +
        ` .env で対象リポジトリの絶対パスを設定してください。`,
    );
  }

  const args = buildClaudeArgs(instruction, opts);

  // logs への追記ヘルパ（ANSI 除去 + updated_at 更新）。
  const appendLog = (chunk: Buffer | string): void => {
    const text = stripAnsi(typeof chunk === 'string' ? chunk : chunk.toString('utf8'));
    task.logs += text;
    task.updated_at = nowIso();
  };

  try {
    const child = spawn(bin, args, {
      cwd,
      shell: false, // 配列引数 + shell:false でシェルインジェクションを回避
      env: process.env,
      // stdin を明示的に閉じる。claude -p は stdin を 3 秒待って
      // "no stdin data received" 警告を出すため、ignore で即座に本処理へ進ませる。
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    child.stdout.on('data', appendLog);
    child.stderr.on('data', appendLog);

    // spawn 失敗（ENOENT: claude 未インストール 等）や実行時エラー。
    child.on('error', (err: Error) => {
      task.status = 'failed';
      task.error = err.message;
      task.updated_at = nowIso();
      console.error(`[queue] task ${id} プロセス起動エラー: ${err.message}`);
    });

    // プロセス終了。終了コード 0 で completed、それ以外は failed。
    child.on('exit', (code: number | null, signal: NodeJS.Signals | null) => {
      task.exit_code = code;
      if (code === 0) {
        task.status = 'completed';
      } else {
        // 既に error(ENOENT等)で failed 済みでも上書き整合させる。
        task.status = 'failed';
        if (!task.error) {
          task.error =
            signal !== null
              ? `Process terminated by signal ${signal}`
              : `Process exited with code ${code}`;
        }
      }
      task.updated_at = nowIso();
    });
  } catch (err) {
    // spawn の同期例外（不正なオプション等）に対する保険。
    const message = err instanceof Error ? err.message : String(err);
    task.status = 'failed';
    task.error = message;
    task.updated_at = nowIso();
    console.error(`[queue] task ${id} spawn 同期例外: ${message}`);
  }

  return task;
}

/** id からタスクを取得。無ければ undefined。 */
export function getTask(id: string): Task | undefined {
  return tasks.get(id);
}

/** 全タスク一覧を配列で返す。 */
export function listTasks(): Task[] {
  return Array.from(tasks.values());
}
