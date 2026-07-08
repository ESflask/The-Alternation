// VibeConnect 中継APIサーバー エントリーポイント
// Express の初期化・共通ミドルウェア・ヘルスチェック・ルーターmount・エラーハンドリングを担う。
import 'dotenv/config';
import express, { NextFunction, Request, Response } from 'express';
import cors from 'cors';

// ルーターは他エージェントが並行作成中（未存在でも import 記述は契約通りに置く）。
// CONTRACTS.md §3 の mount 契約に従う。
import tasksRouter from './routes/tasks';
import gitRouter from './routes/git';
import filesRouter from './routes/files';
import titleRouter from './routes/title';
import usageRouter from './routes/usage';
import historyRouter from './routes/history';

const app = express();

// 共通ミドルウェア
app.use(cors());
app.use(express.json());

// 生存確認 GET /health → 200 { status, uptime }
app.get('/health', (_req: Request, res: Response) => {
  res.status(200).json({ status: 'ok', uptime: process.uptime() });
});

// ルーターmount（CONTRACTS.md §3）
app.use('/api/tasks', tasksRouter); // → POST '/' , GET '/:id'
app.use('/api/git', gitRouter); //     → GET '/diff' , POST '/commit'
app.use('/api/files', filesRouter); // → GET '/tree' , GET '/read' , PUT '/write'
app.use('/api/title', titleRouter); // → POST '/' （チャットの自動タイトル生成）
app.use('/api/usage', usageRouter); // → GET '/' （ローカル使用量の集計）
app.use('/api/history', historyRouter); // → GET '/sessions' , GET '/:id' （既存履歴の閲覧インポート）

// 未処理ルートの 404 JSON ハンドラ
app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: 'not found' });
});

// 共通エラーハンドラ（500 JSON）
app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  const message = err instanceof Error ? err.message : 'internal server error';
  console.error('[error]', message);
  res.status(500).json({ error: message });
});

const PORT = Number(process.env.PORT) || 3000;

// Tailscale越しにiPhoneから届くよう 0.0.0.0 で待ち受ける。
app.listen(PORT, '0.0.0.0', () => {
  console.log(`VibeConnect server listening on 0.0.0.0:${PORT}`);
  console.log(`iPhoneからは Tailscale IP を用いて  http://<TAILSCALE_IP>:${PORT}  でアクセスしてください。`);
});

export default app;
