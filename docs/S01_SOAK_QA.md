# S01 実機QA計画

Status: Proposed — 試験未実施・SLO未承認。Issue #589 と v1.0ロードマップのS01測定条件を統一する。実機の利用可否・最終的な試験範囲は所有者が確認する。

## 1. 試験条件

| シナリオ | Glass数 | 観測間隔 | 予定サンプル数 | 条件 |
| --- | --- | --- | --- | --- |
| idle baseline | 1 / 4 / 8 / 16 各別run | 5秒 | 361 | 60秒warmup後30分、外部変更なし |
| burst | 1 / 4 / 8 / 16 各別run | 5秒 | 121 | 10分、使い捨てfolderのみ |
| 予備soak | 8 | 60秒 | 481 | 8時間 |
| 本soak | 16 | 60秒 | 1441 | 24時間 |
| lifecycle / reconnect | 4 / 16 | 5秒 | 実施時間に応じて事前決定 | 8回の閉開・再接続、停止対象の残存確認 |
| sleep/wake | 4 / 16 | 60秒 | 実施時間に応じて事前決定 | 10回、復帰後の内容・監視・操作確認 |
| 外部volume / display | 4 / 16 | 5秒 | 実施時間に応じて事前決定 | 切断、復帰、対象同一性、画面到達性 |

各Glassのfolder fixtureは0/500/501 regular filesを含む。短時間baselineでは件数条件を別runで測定し、soakでは混合fixtureの内訳を記録する。macOS 15/26ごとに対応する実機、CPU architecture、OS buildを確認し、未確保組合せはBLOCKEDと記録する。予備soakは本soakを代替しない。

予定サンプル数は「予定秒数 ÷ 観測間隔 + 1」。既存CLIは5〜3600秒・1〜10000 samplesのみ対応する。1秒のps/lsof観測は要求しない。実経過時間・計測間隔の欠損は集計で別途確認し、サンプル数だけで所定時間の観測を証明しない。過度な遅延や計測負荷は記録してレビューし、睡眠による観測欠損を正常なidleデータと混ぜない。プロセス再起動時は新runに分ける。

## 2. 証跡

- exact candidate source SHA、Actions run/artifact ID、内側ZIP SHA-256、version/build、OS build、CPU architecture、RAM、表示環境、言語。
- fixture種別と件数、Glass数、各操作の回数・開始終了、計測条件、予定/実サンプル数、実経過時間、最大観測gap、計測プロセスの終了状態。
- CPU/RSS/FDのmin/median/p95/maxと前後窓差分。観測間隔の欠損および測定overheadを区別する。
- watcher数、security scope acquire/release、UI latency p50/p95、physical footprintは既存ps/lsofサンプラーの対象外。実測方法を確立し、未計測ならNOT RUNまたはBLOCKEDと明記する。UI latencyは操作開始から最終表示反映までのmonotonic elapsedとし、操作種別を混合しない。
- crash/hang、復旧結果、ファイルの原本非変更、意図しない上書き/削除の有無、未解決リスク。使い捨てfixtureの事前/事後状態を比較する。

公開証跡に絶対path、実ファイル名、raw bookmark、PID、raw CSVを含めない。ローカル計測は [LOCAL_RESOURCE_SAMPLING.md](LOCAL_RESOURCE_SAMPLING.md) の既存ツールを使用する。

### Watcher lifecycleのローカル診断

対象候補を起動する前にmacOSのTerminalで以下を開始する。実機でログ形式と取得可否を確認する。

```sh
log stream --level default --predicate 'subsystem == "io.github.lamy210.schneeglass" AND category == "watcher-lifecycle"'
```

初期化時の0、監視登録成功後、native stop/invalidate/releaseとstream finish後の `active_watchers` 件数だけを出力する。イベント受信ごとのログや定期polling、ファイル名・path・ID・bookmarkの出力は行わない。duplicate stopは件数の変化を報告しない。監視の登録/解放数はFileEventHubが管理する登録済みセッション数であって、OS内部の実リソース全数やsecurity scope数ではない。既知の使い捨てGlassを順次開閉して件数変化と0への復帰を照合する。ログ欠落・途中起動・別プロセス混入は完全な証跡として扱わない。raw logは公開せず人が確認した集計のみを記録する。実機ログ取得は未検証。

## 3. 合否

- FAIL: crash/hang、意図しないmutation、原本喪失、権限逸脱、誤ったfolder identity、復旧不能、確認された監視/アクセス解放不均衡。
- BLOCKED: 実機/計測手段/候補不足、必要証跡の欠落、失敗した計測、判定基準未確定。未実施はPASSとしない。
- PASS: 全必須シナリオで操作結果・安全性・証跡を確認し、レビュー済み数値予算内であること。数値予算確定前の正常な計測はbaseline取得としてのみ記録する。
- idle CPU中央値1%以下は仮説。RSS/FD/latency/physical footprintの予算は比較可能な実測を得てレビュー後に決定する。RSS/FD差だけでリークを断定しない。
- 500-item snapshotの既存CI ceiling（worst 0.5秒未満）は維持し、実機SLOに転用しない。

本計画はS01の受入条件を緩和せず、実機QA完了、#589 close、#520 owner QA承認、正式公開を意味しない。
