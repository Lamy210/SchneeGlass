# S01 ローカル常駐リソース計測

[Issue #589](https://github.com/Lamy210/SchneeGlass/issues/589)の実機測定用。アプリを変更せず、macOS標準のps/lsofを使って指定PIDだけを観測する。ネットワーク通信・sudo・新規entitlement・対象プロセスへのsignal送信は行わない。

## 実行手順

1. exact-main候補appを通常起動し、Activity MonitorでSchneeGlassのPIDを確認する。使い捨てfolderのみ使用する。
2. 下記の例でローカルの一時ファイルを新規作成して計測する（30分相当、31 samples）。PIDは実際の値に置換する。

```sh
report="$(mktemp "${TMPDIR:-/tmp}/schneeglass-soak.XXXXXX")" || exit 1
python3 Scripts/sample-process-resources.py --pid 12345 --interval 60 --samples 31 > "$report"
```

24時間相当は --samples 1441。終了コード0と予定行数（header + samples）を確認する。中断・timeout・観測不能・プロセス変更は非0終了であり、残存CSVを完全な結果として扱わない。再起動の計測は別runに分離する。

## 指標

- elapsed_seconds: monotonic elapsed、各観測完了時点。観測時間やsleep/wakeで実間隔にズレが生じ得る。遅延時は実際の観測開始時刻を基準に次回時刻を更新し、遅れた分の連続計測は行わない。予定サンプル数は維持するため、所要時間は延び得る。
- cpu_percent_ps: macOS psのCPU推定値（瞬時値/厳密な区間平均ではない、100%を超え得る）。
- rss_kib: psのresident set size、KiB。physical footprintやリークの確定値ではない。
- fd_count: lsofの数値descriptor fieldの個数。cwd/txt等の疑似entryは除外する。lsofが警告・失敗した場合、0を補わず停止する。

PID、起動時刻、実行ファイル名を観測前後およびサンプル間で照合し、変更を拒否する。psの起動時刻は秒精度なので同秒・同コマンドでのPID再使用を完全に区別できない。観測結果の一貫性を確保するため意図的に別PIDへの自動追従は行わない。

## 証跡と限界

CSVへPID、実行ファイルpath、folder名、raw lsof、bookmarkは書かない。raw結果は公開repoへcommitしない。共有する場合は人がレビューした集計のみ。exact-main SHA、artifact digest、OS build/CPU、Glass数、操作開始終了、完了/中断を別途記録する。

監視件数・UI latency・physical footprint・sleep/wakeの動作自体はこのツールでは測定しない。#589の別手順で実測する。観測のoverheadも区別して評価する。数値SLOは未確定。macOS実機のSchneeGlass smoke testと長時間試験が必要。Canonical CIには使い捨ての /bin/sleep 子プロセスを用いる実ps/lsof smoke fixtureがあり、SchneeGlass以外を拒否する本番既定動作・実コマンド形式・FD集計・同一性検証を確認する。これはアプリ実機QAやOSのスリープ復帰試験とは異なる。

## 集計と比較

計測コマンドの正常終了を確認した直後に、同じ予定サンプル数/間隔を指定して集計する（ローカル標準入力のみ）。

```sh
python3 Scripts/summarize-process-resources.py --expected-samples 31 --interval 60 < "$report"
```

終了したrunの行数・順序・列・有限の非負数値・elapsed単調性を厳格に検証する。不完全なCSV、余剰行、文字列混入は非0終了とし集計を出さない。行数が一致することは計測終了コードや証跡の真正性の証明ではない。

サンプラー出力と集計器の接続契約は`Scripts/test-summarize-process-resources.py`のsynthetic統合fixtureで検証する。sleep/wake相当の観測遅延（キャッチアップせず間隔超過1件を保持）と、観測中断時の部分CSVが集計器で拒否されるケースを、外部コマンドや実ユーザーデータなしで確認する。このfixtureは実macOSのsleep/wake・リソース値を測定するものではない。

出力は集計JSON。各指標のmin/median/p95（nearest rank）/max、先頭と末尾の非重複20%サンプル窓（各最低1件）のmedian差、実経過時間、隣接観測間隔の最大値、予定間隔の2倍超の間隔件数を出す。1件のみの場合は窓比較不可としてnull。観測間隔のしきい値判定はCSVに記録された経過時間を十進数のまま比較し、報告用の最大間隔は小数第6位で丸める。しきい値に極めて近い場合、表示された最大間隔と超過件数が同じ精度で判断できないことがある。通常のサンプラー出力は経過時間が小数第3位まで。p95は時間重みなしの記述統計であり、間隔超過は診断情報であってsleepの証明ではない。

比較時は同一OS/architecture/app SHA/window条件/Glass数/操作負荷で繰り返し測定し、条件の異なる集計を混同しない。RSS差やFD差はリークの確定、CPU上限の判定、v1.0受入の自動PASSには使わない。生CSVや個人情報を公開しない。
