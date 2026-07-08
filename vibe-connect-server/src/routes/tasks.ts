// src/routes/tasks.ts — タスク関連 API ルーティング (Agent 2)
//
// index.ts で `app.use('/api/tasks', tasksRouter)` として mount される想定なので、
// このファイル内のパスは '/' (POST) と '/:id' (GET)。
// JSON 形状は CONTRACTS.md §2 に厳密準拠。

import { Router, Request, Response } from 'express';
import { createTask, getTask } from '../queue';

const router = Router();

// model / effort のホワイトリスト（CONTRACTS-FEATURES2.md §A の正準定義）。
// 未知値・型不一致は「無視＝付けない」方針（400 にはしない、後方互換）。
const ALLOWED_MODELS = ['opus', 'sonnet', 'haiku', 'fable'] as const;
const ALLOWED_EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'] as const;

/** ホワイトリストに含まれる文字列のみ返し、それ以外は undefined。 */
function pickAllowed(value: unknown, allowed: readonly string[]): string | undefined {
  return typeof value === 'string' && allowed.includes(value) ? value : undefined;
}

/**
 * POST /api/tasks
 * body: { instruction: string, model?: 'opus'|'sonnet'|'haiku'|'fable', effort?: 'low'|'medium'|'high'|'xhigh'|'max' }
 * 指示を受け取り Claude CLI を非同期起動、202 でタスクIDを返す。
 * instruction は必須（無ければ 400）。model/effort は任意でホワイトリスト検証し、
 * 不正・未知値は無視する（後方互換：未指定なら現状動作のまま）。
 */
router.post('/', (req: Request, res: Response) => {
  const { instruction, model, effort } = req.body ?? {};

  if (typeof instruction !== 'string' || instruction.trim() === '') {
    return res.status(400).json({ error: 'instruction is required' });
  }

  const opts = {
    model: pickAllowed(model, ALLOWED_MODELS),
    effort: pickAllowed(effort, ALLOWED_EFFORTS),
  };

  const task = createTask(instruction, opts);

  return res.status(202).json({
    task_id: task.task_id,
    status: 'processing',
    message: 'Task successfully dispatched to Claude Code.',
  });
});

/**
 * GET /api/tasks/:id
 * ポーリング先。タスクの現在ステータスと ANSI 除去済みログを返す。
 */
router.get('/:id', (req: Request, res: Response) => {
  const task = getTask(req.params.id);

  if (!task) {
    return res.status(404).json({ error: 'task not found' });
  }

  return res.status(200).json({
    task_id: task.task_id,
    status: task.status,
    logs: task.logs,
    error: task.error,
  });
});

export default router;
