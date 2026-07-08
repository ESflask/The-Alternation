// VibeConnect バックエンド 共有型定義
// CONTRACTS.md §3 の型契約と完全一致させること（フィールド名/型は固定）。

export type TaskStatus = 'processing' | 'completed' | 'failed';

export interface Task {
  task_id: string;
  status: TaskStatus;
  instruction: string;
  logs: string;
  error: string | null;
  exit_code: number | null;
  created_at: string; // ISO8601
  updated_at: string; // ISO8601
}
