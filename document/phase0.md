決定版アーキテクチャ v2.1
── 「MAU 1 万 × 月額 ≤ ¥7,000」 で “冷えない” UX とランウェイ 1.5 年を両立 ──

1. 達成条件（しきい値ゆるめ）
区分	指標	新しきい値
コスト	日次請求額	¥450 超 → 即アラート
月次請求額	¥7,000 超 → 機能凍結＋コスト削減スプリント
UX	GET /timeline	p95 < 600 ms / p90 < 400 ms
Write 系	< 150 ms
撤退	DAU/MAU	< 30 % かつ 3 ヶ月赤字 → 終了

2. 主な変更点（v2.0 → v2.1）
項目	v2.0	v2.1（¥7k 上限）	理由
Cloud Run	min_instances=0	min_instances=1（1 vCPU / 512 MiB, concurrency 40）	コールドスタート排除（+≈¥2.1k/月）
cloud.google.com
Firestore 読取枠	30 M/月	40 M/月（TL auto-refresh 12 回/日想定）	UX 余裕を確保。¥+600 /月
firebase.google.com
キャッシュ	Redis はオプション	Phase-1 で M1 Basic を検討（¥3 k/月；導入は p95 悪化時）	予算 7 k に収まる範囲で余力あり
ログ保持	0.1 % INFO / 7 日	ERROR のみ / 7 日（超過 5 GiB→¥0.8k）
firebase.google.com
予算を UX に振り分け
日次アラート閾値	¥300	¥450	idle 課金増分を吸収
退出ライン	月 ¥5 k	月 ¥7 k	指示どおり緩和

3. 改定後コンポーネント
レイヤ	サービス & 主要設定	備考
フロント	Firebase Hosting + Cloud CDN	Asia 帯域 $0.08/GB
firebase.google.com
API	Cloud Run (min=1, 1 vCPU/512 MiB, concurrency 40)	idle $0.0000035 / s, <span style="white-space:nowrap;">≈ ¥2.1k/月</span>
cloud.google.com
DB	Firestore Regional (Tokyo)
Write Fan-out /inbox	読取 $0.038/100k, 書込 $0.115/100k
firebase.google.com
認証	Firebase Auth (メール/Google/X)	SMS 無効＋Device Fingerprint
ストレージ	Cloud Storage Standard (Tokyo)	$0.023/GB-月
cloud.google.com
CDN 転送料	Cloud CDN MISS	APAC < 10 TiB⇒$0.09/GB
cloud.google.com
非同期	Cloud Tasks	≤10 min ジョブ
監視	Cloud Monitoring + Budget Alert	Billing Export→Firestore 集計
IaC	Terraform (+ drift 検知 CI)	変更は PR 必須

4. 月額コスト試算（USD→¥155 換算）
項目	想定利用	¥
Cloud Run idle	1 vCPU + 0.5 GiB × 720 h	≈ 2,100
Firestore Reads	40 M/月	2,356
Firestore Writes	1 M/月	178
Firebase Hosting 転送	50 GB	620
Cloud Storage	30 GB	107
CDN MISS egress	7.5 GB	105
Cloud Logging 超過	10 GiB	775
合計		≈ 6,250

余剰 ≈ ¥750 —— Redis M1 (Basic) を投入しても 総額 ≈ ¥9 k。Redis は SLO 悪化時にのみ拡張。

5. 防御的運用（抜粋）
Firestore 40 M/月 上振れ

CloudScheduler + Cloud Function で日次集計し 45 M 超で警告。

p95 600 ms 超え

1 週継続 → Redis M1 PoC。

月 ¥7 k 超

機能凍結／min_instances↓／画像圧縮率↑ で即是正。

Bot 流入

レート制限 30 req/min & Cloud Armor OWASP。

ログ肥大

ERROR 以外即削除フラグ、超過 ¥0.30/GB で自動 purge。

6. 次の一手
収益化タイムラインを 3 か月以内に明示（広告 / プレミアムタグ等）。

Redis M1 導入手順 を IaC 化しておき、スロットリング解除を 1h で実施できる体制を整備。

テストシナリオ（TL flood /画像連投）を CI に組み込み、Firestore 読取と CDN HIT 率を継続測定。