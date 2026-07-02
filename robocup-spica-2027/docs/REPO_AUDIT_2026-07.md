# Spica2D リポジトリ総合監査レポート

Date: 2026-07-02
Auditor: Claude (Fable 5) — 8ドメイン並列レビュー + ドメイン別敵対的検証 + gap critic (multi-agent workflow, 19 agents / 578 tool calls / ~1.56M tokens) + main-loop での独自裏取り
Scope: robocup-spica-2027 全体（externals/src と logs の生成物は対象外、ただし証拠としては参照）
確定件数: **90 confirmed / 2 refuted / 1 uncertain**（raw 98 → dedup 85 + gap 8）

---

## 0. エグゼクティブサマリ

このリポジトリの最大の問題はコードでも統計でもなく、**「測定器が壊れたまま結論を量産してきた」**ことにある。監査で確定した事実のうち、プロジェクトの結論を直接無効化するものが5つある：

1. **Spica は全試合コーチ無しで戦っていた**（S1）。Vanilla は online coach が 11人全員に heterogeneous player type を割り当てるのに対し、Spica 側は sample_coach バイナリ自体がビルドされておらず、全員 default type のまま。**これまでの全対戦成績（PSG-loop 60 iter、N=30 bisect 群、-0.633〜-1.067 という数字、「Phase 5 は net-negative」という結論）は、このハンデ込みの測定**であり、Phase 5 の効果とコーチ不在の効果を分離できていない。
2. **N=30 ゲートですら検出力不足**（S2）。実測 σ≈0.91 に対し N=30 の最小検出可能効果は **0.66 goals/match**。プロジェクトが追ってきた効果量（0.05〜0.2）の検出には **N≈330〜1300/arm** が必要。N=1 で回した PSG-loop は論外として、昨日敷いた N=30 ゲートも「大きい効果専用」と明記して運用する必要がある。
3. **Phase 5 の C++ 層は地雷原**（S3群）。2モジュールは一度も実行されたことがなく（TRS の #ifdef 未定義、counter_press の linkage 不一致）、SmartClearance は敵陣で「シュート失敗→コーナーへ蹴り捨て」という自発的ターンオーバーを量産する形で誤発火し、CDM ドロップは間違った unum（攻撃的 MF の 7番）をビルドアップから引き抜いていた。
4. **再現性が構造的に欠落**（S4群）。EXTERNALS.lock は fresh clone では何もピンしない。5つの実験 YAML が同一の可変 snapshot パスを指しながら「別バイナリを測った」と主張している。乱数 seed は記録すらされていない。バイナリの sha256 も残らない。**アーカイブされた 211 試合のうち、厳密に再現可能なものは 0 件**。
5. **ツール群に沈黙の失敗が多発**（S5群）。tournament 集計はラベル照合バグで常に games=0（Phase 9c「REV is best edition」の tourney_summary.json は空集計）、32-0 の偽試合が match_completed として統計に混入し得る、aggregate は match_status を見ずにスコアを合算する。

一方で救いもある：**評価 harness の設計思想（attestation、regime gate、resumable batch、機械可読 metrics）は健全**で、修正はほぼ全て局所的。最優先の修正（コーチビルド1行 + 検証 assert）だけで、プロジェクトの全結論を「測り直せる」状態に戻せる。

---

## 1. 監査手法

- **Survey**: 8ドメイン（shell harness / python eval / C++ phase5 / patch機構 / 統計手法 / 設定整合性 / 欠落アイデア / docs・process）を並列レビュー。各 finder は実ファイルを読み、file:line と引用を伴う finding のみ提出。
- **Dedup**: 98 raw → 85 unique（13 merged）。
- **Verify**: ドメイン別の敵対的検証。各 finding についてファイルを再読、反証を試み、REFUTED をデフォルトに judged。stats 系は計算を再実行。バイナリ実在確認には nm / ls / grep を使用。
- **Gap-check**: 完全性 critic が未カバー領域（paper/, tdp/, 生成系スクリプト等）を走査、8件追加（全confirmed）。
- **Main-loop 独自検証**: S1（コーチ不在）は試合ログ（rcl の change_player_type メッセージ）で決定的に裏取り。検出力計算は実測 σ から再計算。

---

## 2. S級 — プロジェクトの結論を変える発見

### S1. Spica は全試合コーチ無し（コーチ vs ノーコーチのハンデ戦だった）

`scripts/setup_cyrus_snapshots.sh:94` が v3 snapshot の再ビルドで `make -j"$JOBS" sample_player` **のみ**をビルドする（vanilla snapshot は元ビルドの全ターゲットを保持）。結果：

- `cyrus-team-v3-snapshot/build/src/sample_coach` — **存在しない**（実機確認済）
- `cyrus-team-vanilla-snapshot/build/src/sample_coach` — 存在する

試合ログでの決定的証拠（iter62_tmr_left match_000001 の rcl）：
```
0,75 Recv CYRUS_VANILLA_Coach: (change_player_type 1 0)
0,75 Recv CYRUS_VANILLA_Coach: (change_player_type 9 3)
...（計11本、全ポジションに hetero type 割当）
```
SPICA 側の coach 接続は **ゼロ行**。start.sh は coach バイナリ不在でも黙って先へ進み、run_smoke_match.sh の完了判定（server exit 0 + .rcg 存在）はこれを検出しない。

**影響**: RCSS2D で hetero type（スピード・スタミナ・キック性能の最適化割当）の有無は決定的な戦力差。この session の全結論——iter timeline の -0.967〜-0.633、V1/V2 bisect、「Phase 5 framework は net-negative」——は全て**このハンデを含んだ値**。「Phase 5 が悪い」のか「コーチがいないのが悪い」のか、現データからは分離不能。過去の PSG-loop 60 iter も同じ snapshot 機構の上で走っていた場合、同様に汚染されている。

**修正**（1行 + 保険）: `make -j"$JOBS" sample_player sample_coach` に変更し、DONE 宣言前に両バイナリの存在を assert。その後**全ベンチマークを再測定**。

### S2. 検出力の構造問題 — N=30 ゲートも「大効果専用」

実測 per-match σ（7バッチ平均）= 0.913。two-sample、α=.05、power=.80 で必要な N/arm:

| 検出したい Δ (goals/match) | 必要 N/arm | 実時間 (1.4min/match, 直列) |
|---|---|---|
| 0.1 | ~1,309 | ~30.5 h |
| 0.2 | ~328 | ~7.7 h |
| 0.3 | ~146 | ~3.4 h |
| 0.4 | ~82 | ~1.9 h |
| 0.6 | ~37 | ~0.9 h |

**N=30 の MDE ≈ 0.66 goals/match**。PSG-loop が1回の変更で狙う効果（0.05〜0.2）はその 3〜13 分の1であり、N=1 は勿論、N=30 ですら個別 iter の accept/reject 判定には使えない。使える運用は (a) 大効果（component 丸ごと ON/OFF）の判定、(b) 複数変更の束の判定、(c) 変更を貯めて長バッチで判定、のいずれか。

さらに悪いことに、**CRN（共通乱数）による分散削減の道も現状塞がっている**：rcssserver 19.0.0 は `server::random_seed` が**コンパイルアウト**されており（serverparam.cpp:962 コメントアウト）、`player::random_seed` は hetero 生成にしか効かず、librcsc はクライアント RNG を `std::random_device` から seed する。`experiments/seeded_vanilla_repro.yaml` は**効かない seed をピンして「環境ドリフトは不可避」と誤結論する設計**になっている（finding #61）。正攻法は notes/2026-06-26 に既にスケッチされている librcsc への env-var seed パッチ（~30分）→ サーバ側 seed 再有効化 → paired t-test 対応、の順。

### S3. Phase 5 C++ 層の地雷原（5件が high）

| # | 場所 | 内容 |
|---|---|---|
| S3a | defense_block.cpp:309 | `CYRUS_PHASE5_TERRITORY_RECOVERY` をどのビルドも定義しない → TerritoryRecoveryState の**唯一の消費側が常にコンパイルアウト**。nm でシンボル不在を確認済。「クリア後の押し上げ」機構は**一度も存在したことがない**。iter 35 の TRS bias bump (8,5)→(12,8) が「3rd WIN を生んだ」という journal の解釈は、**実行されないコードの定数をチューニングして N=1 の運を拾った**もの。 |
| S3b | counter_press_state.cpp:147 | strong override をグローバル名前空間に定義したが、chance_signal.cpp の宣言は `namespace cyrus_phase5` 内 → **マングル名が別物でリンクされず**、weak stub（-1 を返す）が常に使われる。chance_signal の W_PRESS 項（0.10）は**恒久的にゼロ**。nm で `T counter_press_last_recovery_cycle()` vs `W cyrus_phase5::...` を確認済。 |
| S3c | bhv_smart_clearance.cpp:81 | **ボール位置ガードが無い** + path 判定が `op.x >= 0.0 continue`（敵陣の敵を全無視）。これが hold_ball の先頭に注入されているため、**敵陣でのシュート失敗・パス失敗のフォールバックが全て「2.7 m/s でコーナーへ蹴り捨て」**になる。敵陣では実質無条件で candidate 1 (45,±30) が採用される。得点力低下（測定された 0.5-1.0 差）の直接容疑者。 |
| S3d | bhv_smart_clearance.cpp:94 | 2.7 m/s の one-step kick の総到達距離は 2.7/0.06 = **45m**。自陣 x≈-25 から (45,30) を狙うとボールは **x≈16 で停止 = 自ら禁止帯 (10<x<25) のド真ん中に届ける**。禁止帯チェックは「ターゲット座標」にしか掛かっておらず、候補は x=45/28 なので**このチェックは論理的に常に false（死んだ検査）**。 |
| S3e | defense_block.cpp:88 | F433 の holding CDM は 5/6（同ファイルのコメント自身がそう書いている）のに、右サイド攻撃時に **7番（攻撃的左ハーフ pp_lh）をドロップ**させる。intercept_discipline.cpp も同じ誤り（6/7 をゲート）。**右サイドのビルドアップのたびに攻撃の頭数を1枚削る**。 |

その他: Body_KickOneStep の戻り値未チェック（成功と偽って TRS trigger + true 返却）、intercept_discipline は先頭 `return true;` の kill-switch 済み stub（~40行が dead）、chance_signal の項が [0,1] を逸脱、TerritoryRecoveryState はプロセス毎 singleton なので「チーム状態」にならない（11プロセスで独立）。

### S4. 再現性の構造的欠落

| # | 場所 | 内容 |
|---|---|---|
| S4a | fetch_externals.sh:154 | **EXTERNALS.lock は fresh clone では読まれない**。lock の SHA は「dir が既に在るときの skip 判定」にしか使われず、externals/src は gitignore なので新環境では常に branch tip を再解決して lock を上書き。EXTERNALS.md の「lock がピンを保証する」という記述と正反対。 |
| S4b | experiments/iter1_left.yaml 他4本 | iter1/iter19/v1/v2/iter62 の5つの YAML が**全て同じ `spica325_left.sh` → 同じ可変 snapshot パス**を起動する。「どのバイナリを測ったか」は YAML から復元不能で、今 re-run すると **iter-62 バイナリの結果が「iter_1 の成績」として記録される**。バイナリ sha256 の記録も無い。 |
| S4c | run_smoke_match.sh:153 | **乱数 seed が未記録**。server.out に `Simulator Random Seed: <time(0)>` が出力されているのに metadata.json に拾っていない。アーカイブ 211 試合はどれも原理的に再現不能。 |
| S4d | spica325_noTMR_left.sh:6 | iter-62 baseline（headline A/B の片側）の snapshot **を作るスクリプトがリポジトリに存在しない**（手作業コピーで作られた）。 |
| S4e | symmetrize_f433.py:5 | Y対称化（journal が KEEP している変更）の根拠 note `2026-06-27_side_clone.md` が**存在しない**。 |

### S5. 沈黙の失敗（測定データ汚染経路）

| # | 場所 | 内容 |
|---|---|---|
| S5a | run_spica_tournament.sh:106 | 集計が `home_team in ["REV","MERGE","ORIG","V"]` で照合するが、CSV に入るのは in-game 名（SPICA_REV 等）→ **全 edition が games=0 / mean=null**。Phase 9c の「REV is best edition」判断の機械集計は空だった（判断自体は notes の手動観測に依拠）。約4時間の計算が無出力に終わる構造。 |
| S5b | run_smoke_match.sh:283 | match_completed 判定 =「server exit 0 + .rcg 存在」のみ。**2チーム接続の検証なし**。同名チーム設定では 32-0 の偽試合が valid として記録される（実際に発生、resume はそれを再検査しない）。parse 側は `-vs-null` の失敗形まで**知っているのに**（regex に `|null` がある）誰も reject しない。 |
| S5c | aggregate_results.py:152 | スコア集計ループが **match_status を見ない**。timeout 試合の部分スコアが metrics.json に在れば mean/CI に混入し、completed>=30 なら RESEARCH_GRADE に昇格し得る。 |
| S5d | parse_match_result.py:52 | 一次スコアパーサ（SCORE_LINE）は実サーバ出力と**一致したことが一度もない**（211/211 試合が "no score line found"）。全試合が rcg ファイル名 regex という単一障害点で拾われている。 |
| S5e | combine_balanced_legs.py:116 | 片 leg の summary.csv が欠けると**黙って単 leg 統計を COMBINED と名乗る**。 |

---

## 3. 統計手法の問題（この session の自分の作業への自己批判を含む）

監査は直近の notes（自分が昨日書いたもの）にも敵対的検証を掛けた。確定した過大主張：

1. **「iter_19 は negative-significant」は多重比較で死ぬ**。5比較同時の FWER は 22.6%。CI 上限 -0.009 という際どさは Bonferroni（z=2.576 → ±0.559）どころか如何なる補正でも生き残らない。
2. **「monotonic improvement +0.434, Real signal, not noise」は過大**。隣接 iter 間の差は全て CI が 0 を跨ぐ。点推定の単調性は有意性ではない。
3. **「side-correction 後、全変種が有意に負」は加法補正の仮定を明示していない**（Vanilla mirror の -0.100 自体 CI [-0.443,+0.243] で不確か。補正の SE を伝播させると境界例は変わり得る）。
4. **iter-62 results note の Verdict 節に数字の取り違え**（"4 goals vs 1" と書いたが実測は 3 vs 4。後段の表は正しいが Verdict 文が旧稿のまま）。
5. z=1.96 使用（t(29)=2.045 が正）で全 CI が 4.3% 狭い。draws 30-45% のデータに正規近似 goal-diff という選択も再考余地（Skellam / match-points / Bradley-Terry）。
6. defense_block.cpp 内には **n=4, n=6 で accept/revert した定数**がコメント付きで焼き込まれている（プロトコル違反の化石）。
7. n=3 SMOKE_ONLY で「Cyrus 越え達成」を宣言した note が残存（2026-06-25_phase5_beats_vanilla.md）— deprecation banner なし。PSG_LOOP_JOURNAL も同様に「best known config (P(W)=43%)」を banner なしで掲示し続けている。

**→ ただし S1（コーチ不在）により、上記 notes の数値自体が全て再測定対象。**

---

## 4. 検証済みアイデア（やる価値があると judged されたもの）

| 優先 | アイデア | 根拠 |
|---|---|---|
| ◎ | **parser / gate の unit test**（tests/ には attestation テストのみ）。S5b/S5c/S5d はテストがあれば全部初日に捕まった | aggregate_results.py:229 |
| ◎ | **CI（GitHub Actions）**: doctor + make test + parser tests + batch dry-run は bash+python だけで走る | .github/ 不在 |
| ○ | **librcsc seed パッチ → CRN paired design**（順序重要: vendor patch → server seed 再有効化 → paired t-test。いきなり paired 実装は無意味 — #80 参照） | notes/2026-06-26 に設計済 |
| ○ | **psg_ledger を N=30 バッチの回帰テストに**（through-ball goal template の生存確認を自動化） | psg_ledger.py:111 |
| ○ | **並列試合実行**: port を launcher まで貫通させれば 4-core で実質 2-3x。ただし S3 系の修正が先（壊れた binary を速く測っても無意味） | run_smoke_match.sh:158 |
| △ | **定数の 1-D sweep**: apply_phase5.sh 内の凍結定数（wedge 50, cross 35, TMR 40 等）を env 化して grid。ただし N 問題（S2）が先に解決していること | apply_phase5.sh:581 |

---

## 5. 監査で棄却されたもの（誠実性のための記録）

- 「setup_cyrus_snapshots の cp -a が stale dep path を残す」→ **REFUTED**。スクリプトは v3 を re-cmake しており正しい。（この session で踏んだ実害は、スクリプトを通さず手コピーした noTMR snapshot で起きたもの。つまり S4d の「スクリプト化されていない snapshot」問題の実証例であって、スクリプトのバグではない）
- 「cyrus_vs_cyrus_smoke.yaml の experiment_id とファイル名の不一致」→ REFUTED（実害なし）
- UNCERTAIN 1件: 「全判断が単一 opponent（Vanilla）依存」— 事実だが、wrighteaglebase が fetch 済みなので multi-opponent 化のコストは低い（→ 推奨アクションに包含）

---

## 6. 優先アクションプラン

**Phase A — 測定器の修理（全てに先行、~1日）**
1. setup_cyrus_snapshots.sh: `sample_player sample_coach` 両ビルド + 存在 assert（S1）
2. run_smoke_match.sh: 試合妥当性チェック（2チーム接続・チーム名相異・away!=null）で invalid を弾く（S5b）
3. aggregate_results.py: match_completed のみ集計 + `len(goal_diffs)==completed` を gate に追加（S5c）、z→t
4. parse_match_result.py: 実サーバ出力形式（`'X' vs 'Y'` + `Score: a - b`）を一次パーサに（S5d）+ 回帰テスト
5. metadata.json に server.out の Simulator Random Seed と両バイナリ sha256 を記録（S4b/S4c）
6. fetch_externals.sh: lock 優先ダウンロードに修正（S4a）
7. run_spica_tournament.sh: NAME2LABEL マップ（S5a）

**Phase B — 再測定（測定器修理後、~1-2日）**
8. コーチ有り Spica(iter-62) vs Vanilla N=30 — **「Phase 5 は net-negative」が本当かをここで初めて判定できる**
9. コーチ有りで V1/V2 bisect 再走（必要なら）

**Phase C — C++ 地雷除去（各変更は Phase B の正しい測定器でゲート）**
10. S3a/S3b の dead code を「定義して生かす」か「消す」か判定（生かすなら N=30 で効果測定）
11. SmartClearance: ball.x ガード + 到達点チェック + execute() 戻り値（S3c/S3d + 既知の戻り値問題）
12. CDM unum 修正 5/6（S3e）

**Phase D — 方法論の底上げ**
13. librcsc seed パッチ → CRN → paired compare（分散削減で実効 N を稼ぐ）
14. multi-opponent（wrighteagle は fetch 済み、helios-base ビルド済み）
15. unit tests + CI
16. notes への deprecation banner（journal、phase5_beats_vanilla、bisect notes に S1 の注記）

---

## 7. 総括

「なぜ強くならないのか」への監査としての回答は3層になる：

1. **測定層**: N=1 評価（後に N=30 でも効果量に対し不足）で意思決定してきた。さらに測定自体がコーチ不在ハンデで系統的に歪んでいた。
2. **実装層**: Phase 5 の一部は実行すらされておらず、実行されている部分の一部（SmartClearance の敵陣誤発火、CDM 取り違え）は積極的に害をなしていた可能性が高い。
3. **プロセス層**: 良い protocol 文書が存在するのに、それを強制する仕組み（テスト・CI・gate の自動化）が無く、文書と実装が乖離した。

逆に言えば、**Phase A の7項目（どれも局所修正）を済ませて再測定するまで、「Spica が Vanilla に勝てない」という命題は未証明**。このリポジトリで一番もったいないのは、harness の設計思想は良いのに、それ自身をテストする文化が無かったことに尽きる。

---

## Appendix: 全 confirmed findings（90件）

severity → category 順。file:line は検証時に補正済みの位置。

| Sev | Category | Location | Finding |
|---|---|---|---|
| high | bug | `scripts/run_spica_tournament.sh:106` | The tournament aggregation matches summary.csv team columns against the edition labels REV/MERGE/ORIG/V, but those columns contain the in-game team names (SP... |
| high | bug | `scripts/run_smoke_match.sh:283` | match_completed is declared from (server exit 0 + any .rcg exists) with no check that two distinct teams actually connected, so same-team or one-side-missing... |
| high | bug | `scripts/run_batch_matches.sh:240` | Resuming a previously failed match re-runs it into an un-wiped directory, and run_smoke_match.sh then picks an arbitrary first .rcg, so a stale partial .rcg ... |
| high | bug | `externals/patches/cyrus-team/src/phase5/bhv_smart_clearance.cpp:63` | Bhv_SmartClearance has no ball-position guard and its path check ignores all opponents at x>=0, so every hold_ball fallback anywhere on the pitch (including ... |
| high | bug | `externals/patches/cyrus-team/src/phase5/bhv_smart_clearance.cpp:94` | Clearance targets are physically unreachable by a one-step 2.7 m/s kick, so the ball's actual resting point routinely lands inside the very 10<x<25 forbidden... |
| high | bug | `externals/patches/cyrus-team/src/phase5/bhv_smart_clearance.cpp:114` | Body_KickOneStep(...).execute(agent) return value is unchecked: when the kick internally degrades to HoldBall/StopBall or fails outright, the behavior still ... |
| high | bug | `externals/patches/cyrus-team/src/phase5/defense_block.cpp:309` | CYRUS_PHASE5_TERRITORY_RECOVERY is never defined by any build script or CMake patch, so the only consumer of TerritoryRecoveryState is compiled out: the 'tea... |
| high | bug | `externals/patches/cyrus-team/src/phase5/counter_press_state.cpp:147` | The 'strong overrides' for the chance-signal counter-press hooks are defined at global scope, but chance_signal.cpp declares and weakly defines them inside n... |
| high | bug | `externals/patches/cyrus-team/src/phase5/defense_block.cpp:88` | CDM-drop targets the wrong unum: F433's holding CDMs are 5 and 6 (as the file's own comment states), but is_build_up_drop_cdm drops unum 7 — Cyrus's pp_lh at... |
| high | process | `notes/PSG_LOOP_JOURNAL.md:20` | The PSG-loop journal records WIN/'best known config'/P(W) performance claims and KEEP decisions from N=1 matches, directly violating CLAUDE.md's 'Do not clai... |
| high | reproducibility | `scripts/fetch_externals.sh:154` | EXTERNALS.lock never pins anything: the locked SHA is only used to skip fetching when the source dir already exists; a fresh checkout re-resolves branch tips... |
| high | reproducibility | `experiments/iter1_left.yaml:6` | Five experiment YAMLs that claim five different Spica binaries all launch the same mutable git-ignored snapshot path, so the recorded N=30 bisect claims are ... |
| high | reproducibility | `scripts/team_launchers/spica_rev_left.sh:10` | All six tournament edition launchers (spica_{rev,merge,orig}_{left,right}.sh) pass -f formation directories (formations-dt-{rev,merge,orig}) that do not exis... |
| high | reproducibility | `scripts/symmetrize_f433.py:37` | The Y-symmetrized F433 formation set — a journal-KEPT change whose removal is explicitly listed under 'Failed approaches (DO NOT REPEAT)' — is absent from th... |
| high | stats | `scripts/setup_cyrus_snapshots.sh:94` | Spica snapshots are built with `make sample_player` only after `rm -rf build`, so they have no sample_coach binary while the Vanilla snapshot does — every Sp... |
| high | stats | `externals/patches/cyrus-team/apply_phase5.sh:242` | Per-file sentinel guards skip whole patch steps, so later-added sub-patches never install on already-patched trees, and no post-apply verification exists — t... |
| high | stats | `docs/EVALUATION_PROTOCOL.md:43` | The N=30 RESEARCH_GRADE gate is powered only for effects ~3-13x larger than the effects the project actually chases (0.05-0.2 goals/match), so the accept/hol... |
| high | stats | `notes/2026-06-28_phase5_component_bisect.md:38` | The sole 'negative-significant' bisect result (iter_19 vs iter_62, CI [-0.858, -0.009]) is one of five simultaneous uncorrected 95% tests and does not surviv... |
| high | stats | `notes/2026-06-28_phase5_component_bisect.md:129` | The headline 'Every measured Spica variant is significantly worse than Vanilla after side-correction' rests on an additive correction taken from a single sta... |
| high | stats | `notes/PSG_LOOP_JOURNAL.md:18` | The journal mandated as required reading each iteration still presents N=1-based 'Current best known config' (P(W)=43%) and 'Working approaches (KEEP)' claim... |
| high | stats | `notes/2026-06-28_psg_iter62_results.md:132` | The results note's Verdict claims 'iter-62 makes Spica325 score more goals. 4 goals in 30 matches vs 1 goal for baseline — a 4x ratio', which is false: on-di... |
| high | stats | `evaluation/aggregate_results.py:152` | Score statistics and win counts pool every match that has a metrics.json, with no match_status filter, so non-completed matches can contaminate mean_goal_dif... |
| medium | bug | `scripts/fetch_externals.sh:138` | finalize_lock rewrites EXTERNALS.lock from only this run's records, so a single failed fetch (or Ctrl-C, via the EXIT trap) permanently deletes the failed/un... |
| medium | bug | `experiments/v1_no_step7_left.yaml:4` | YAML home_team labels (SPICA_V1, SPICA_V2, SPICA325_ITER1/19/62) never reach the server — all recorded matches actually played as team 'SPICA325' — and the h... |
| medium | bug | `evaluation/aggregate_results.py:187` | completed_observed_real compares aggregate counts instead of per-match identity, so an attested failed match can mask an unattested completed match |
| medium | bug | `scripts/analyze_rev_matches.py:147` | Unguarded per-match reads crash the whole analysis: missing metrics.json raises FileNotFoundError, a null away_score raises TypeError, and zero REV matches r... |
| medium | bug | `externals/patches/cyrus-team/src/phase5/counter_press_state.h:26` | CounterPressState's outputs (aggression_multiplier, counter_press_active, just_won_in_opp_half) have zero call sites in any patched tree — the module is tick... |
| medium | bug | `externals/patches/cyrus-team/src/phase5/counter_press_state.cpp:66` | Possession-transition detection requires a direct Ours→Theirs (or Theirs→Ours) flip between consecutive updates, but real turnovers are pass interceptions th... |
| medium | fragility | `scripts/run_smoke_match.sh:158` | The server port is effectively hardcoded to 6000: RCSS_PORT only changes the server side while the Cyrus launchers/start.sh never receive -p, and nothing che... |
| medium | fragility | `scripts/run_smoke_match.sh:218` | cleanup_processes only signals the process group while the timeout wrapper PID is still alive, so player/coach processes that outlive a normally-exited serve... |
| medium | fragility | `externals/patches/cyrus-team/apply_phase5.sh:510` | Inconsistent failure modes: anchor misses in steps 3-7b sys.exit(1), but Step 1 missing sources, the PHASE9 left-bias mirror, Step 8's CMake hook, and Step 9... |
| medium | fragility | `scripts/team_launchers/cyrus_vanilla_right.sh:7` | Every launcher regenerates its .start_patched_*.sh via `sed > file` inside the shared snapshot dir on each invocation, so two concurrent matches using the sa... |
| medium | fragility | `scripts/compare_summaries.py:83` | compare_summaries.py compares raw mean_goal_diff (home minus away) with no check that the two summaries share team identities or side orientation — and summa... |
| medium | fragility | `docs/BASELINE_EVALUATION.md:18` | Both protocol docs overstate compare_summaries.py's refusal: the script unconditionally prints the full side-by-side table plus the delta and its 95% CI befo... |
| medium | fragility | `evaluation/parse_match_result.py:52` | The primary score parser (SCORE_LINE against server.out) matches zero real rcssserver outputs — all 211 recorded matches fell through to the rcg-filename reg... |
| medium | fragility | `scripts/combine_balanced_legs.py:116` | If one leg's summary.csv is missing, the script silently degrades to single-leg statistics labeled COMBINED, because the JSON fallback looks for keys ('per_m... |
| medium | fragility | `externals/patches/cyrus-team/src/phase5/territory_recovery_state.h:8` | Singleton 'team state' cannot cross process boundaries: each of the 11 players runs in its own process, so TerritoryRecoveryState::trigger() called by the cl... |
| medium | fragility | `externals/patches/cyrus-team/src/phase5/defense_block.h:32` | defense_block.h documents wing-backs as unums 5/8 (3-2-5 mapping) while the implementation returns 3/4 (F433 mapping); if Formation is ever switched back to ... |
| medium | fragility | `externals/patches/cyrus-team/src/build_f325_formations.py:34` | A superseded F325 generator remains committed with the same output paths as the live generator but an incompatible unum convention (wing-backs at 5/8 instead... |
| medium | fragility | `scripts/probe_rcssserver.sh:71` | probe_rcssserver.sh and setup/SERVER_CONTRACT.md check/document config lookup paths (~/.rcssserver-server.conf etc.) that the deployed rcssserver 19.0.0 does... |
| medium | idea | `evaluation/aggregate_results.py:229` | The RESEARCH_GRADE gate and result parser — the code that decides scientific validity — have zero unit tests (tests/ contains only test_attestation.sh), and ... |
| medium | idea | `scripts/psg_ledger.py:111` | psg_ledger.py already extracts per-goal through-ball flags and kick chains, but nothing runs it over N=30 batches — the 'did the through-ball goal template s... |
| medium | idea | `Makefile:34` | No CI exists (no .github/ directory) although 'make test', the batch dry-run, and parser unit tests need only bash+python3+pyyaml and would run in under 2 mi... |
| medium | process | `scripts/doctor.sh:77` | doctor.sh hard-requires helios-base and librcsc-config — which the current Spica-vs-Vanilla experiments do not use — while never checking the dependencies th... |
| medium | process | `scripts/run_spica_tournament.sh:84` | The tournament unconditionally `rm -rf`s each leg's prior experiment directory, silently destroying earlier match logs/metrics in violation of the project ru... |
| medium | process | `scripts/build_externals.sh:217` | build_cmake_in_prefix unconditionally runs `make install`, but cyrus-team's generated Makefile has no install target, so `make build-externals` exits non-zer... |
| medium | process | `scripts/setup_cyrus_snapshots.sh:54` | setup_cyrus_snapshots.sh is not idempotent despite its header claim: on any second run the PHASE5_F325 sentinel check die()s, so snapshots can only be refres... |
| medium | process | `notes/2026-06-25_phase5_beats_vanilla.md:1` | A strength claim ('Cyrus 越え達成' — surpassed Cyrus) was published from an n=3 SMOKE_ONLY run in direct violation of the protocol's hard rule, and the note stil... |
| medium | process | `README.md:70` | README documents make real-smoke as running cyrus_vs_cyrus_smoke.yaml (a yaml whose start commands are UNVERIFIED-by-design) and a build-externals order that... |
| medium | process | `docs/CHANGE_EVALUATION_PROTOCOL.md:1` | The N=30 eval gate declared 'now ENFORCED' (candidate AND immediate-parent RESEARCH_GRADE batches + compare + reject-if-negative-significant) exists only in ... |
| medium | process | `CLAUDE.md:23` | CLAUDE.md's harness-phase framing is stale and its rule unverifiable: it still says the immediate focus is harness engineering and forbids agent-behavior cha... |
| medium | process | `scripts/combine_balanced_legs.py:74` | The balanced-legs significance tool bypasses every protocol gate (sample_regime, run_reality_status) and includes rows from non-completed matches |
| medium | reproducibility | `scripts/run_batch_matches.sh:261` | Experiment YAMLs carry CWD-relative launcher paths that are validated and passed to rcssserver verbatim, so running the batch from any directory other than t... |
| medium | reproducibility | `scripts/team_launchers/spica325_noTMR_left.sh:6` | The launcher for the RESEARCH_GRADE iter-62 baseline points at externals/src/cyrus-team-v3-noTMR-snapshot, a tree that no committed script creates. |
| medium | reproducibility | `scripts/run_smoke_match.sh:153` | The per-match random seed is neither set nor recorded: rcssserver prints 'Simulator Random Seed: <time(0)>' into server.out, but the harness's metadata.json ... |
| medium | reproducibility | `experiments/iter62_tmr_left.yaml:24` | iter62_tmr_left.yaml says num_matches: 10 and 'N=10 same-side leg', but the recorded RESEARCH_GRADE batch ran 30 matches via an unversioned CLI override, so ... |
| medium | reproducibility | `notes/PSG_LOOP_JOURNAL.md:93` | The journal violates its own 'Update at the END of each iteration' rule and CLAUDE.md's machine-readability standard: iter 060 is left '(TBD)', iterations 61... |
| medium | stats | `scripts/run_spica_tournament.sh:53` | The tournament runs n=4 matches per pair (N=2 per leg) against a documented N>=30 RESEARCH_GRADE gate, and its final ranking JSON strips the sample_regime gu... |
| medium | stats | `evaluation/aggregate_results.py:217` | Both CI code paths hardcode z=1.96 where t critical values apply (t(29)=2.045 per batch, t(~58)=2.002 for deltas), producing systematically anti-conservative... |
| medium | stats | `notes/2026-06-28_phase5_component_bisect.md:148` | Point estimates from CIs that all cross zero are asserted as established, additive component contributions ('Step 7 +0.4, Step 5 +0.3, Step 7b +0.2. They sta... |
| medium | stats | `docs/CHANGE_EVALUATION_PROTOCOL.md:47` | The protocol mandates two independent batches against a common opponent and defers paired/common-random-number designs indefinitely, discarding a 2-4x effect... |
| medium | stats | `experiments/seeded_vanilla_repro.yaml:34` | The reproducibility experiment pins the wrong RNG (player::random_seed seeds only heterogeneous-player generation, not the simulator noise RNG), so its state... |
| medium | stats | `notes/2026-06-28_psg_bisect_results.md:36` | The headline claim 'Spica has been monotonically getting stronger ... a +0.434 gain ... Real signal, not noise' is falsified by the note's own table (iter_1 ... |
| medium | stats | `externals/patches/cyrus-team/src/phase5/defense_block.cpp:128` | Tuning decisions baked into the code were accepted/reverted on n=4 and n=6 match samples, contradicting the project's own N>=30 RESEARCH_GRADE evaluation gate. |
| medium | stats | `externals/patches/cyrus-team/src/phase5/chance_signal.cpp:96` | Chance-signal component terms are not kept in [0,1] as designed — mom_term is unclamped (can exceed 2) and cone_term can go negative — and the downstream ev ... |
| low | bug | `scripts/make_highlights.sh:113` | Clip start times assume the video timeline begins at playback cycle 0, but render_match_video.sh starts ffmpeg ~2 seconds after rcssmonitor begins playing, s... |
| low | bug | `evaluation/parse_match_result.py:193` | An explicitly passed --rcg is only prioritized when it is NOT already in the glob results, so with multiple rcg files the score silently comes from the alpha... |
| low | bug | `scripts/match_report.py:236` | Goal timestamps are inflated 6x: 'mins = cycle / 600 * 6' contradicts the correct 'total_cycles/600' minute conversion eleven lines earlier |
| low | fragility | `scripts/run_batch_matches.sh:61` | Option parsing dies with no error message when a value-taking flag is last on the command line: the second `shift` fails under set -e after the value was def... |
| low | fragility | `scripts/build_externals.sh:203` | Two parallel librcsc installs (externals/install: helios librcsc.so.19; externals/install-cyrus: cyrus fork librcsc.so.18) expose identical header/library na... |
| low | fragility | `scripts/build_externals.sh:212` | build_cmake_in_prefix deletes the existing build tree (rm -rf "$dir/build") before knowing the rebuild will succeed, so a failed cyrus-team rebuild destroys ... |
| low | fragility | `.gitignore:16` | A literal '~/' directory (containing ~/.rcssserver/server.conf etc.) accumulates inside the repo working tree and is papered over with a gitignore rule inste... |
| low | fragility | `docs/REALITY_ATTESTATION.md:104` | The documented reality_evidence schema names a key 'server_binary_is_elf' that attest_runtime.py never writes — the code emits 'server_binary_format' and 'se... |
| low | fragility | `scripts/attest_runtime.py:97` | gather() parses metadata.json without exception handling, so a truncated/corrupt metadata.json crashes the attestation despite the module docstring promising... |
| low | fragility | `scripts/psg_ledger.py:52` | rcg2txt is invoked without existence or return-code checks and its stderr is discarded, so a missing tool crashes with a raw traceback and a corrupt rcg yiel... |
| low | fragility | `externals/patches/cyrus-team/src/phase5/intercept_discipline.cpp:83` | Phase-8 intercept gate is a kill-switched stub: 'return true;' as the first statement makes the remaining ~40 lines of intercept_safe_for_unum unreachable, s... |
| low | fragility | `externals/patches/cyrus-team/src/phase5/defense_block.cpp:142` | Dead code across the modules: vertical_compression() is exported but never called (and its formula 'ball.x - 2.0' is meaningless as a compression cap), is_fa... |
| low | fragility | `scripts/render_match_video.sh:100` | cleanup gives ffmpeg only 0.5 s between SIGTERM and SIGKILL to finalize the mp4, and the success check is only 'file is non-empty', so a truncated recording ... |
| low | idea | `externals/patches/cyrus-team/apply_phase5.sh:144` | Dead code: F325_BODY is read into a shell variable and never used (the heredoc Python re-reads the same file via argv[2]). |
| low | idea | `externals/patches/cyrus-team/apply_phase5.sh:581` | All tactical tuning constants are frozen literals inside apply_phase5.sh heredocs; small 1-D grid sweeps over the proven Step 7 bonuses are feasible (~35-40 ... |
| low | idea | `notes/2026-06-26_phase9b_f325_deadend.md:77` | Common-random-numbers paired design via server seeds is currently near-zero-value: serverparam random_seed is compiled out of rcssserver 19.0.0 and the repo'... |
| low | process | `scripts/run_match.sh` | scripts/run_match.sh is a 0-byte, non-executable placeholder that is referenced by nothing — dead file inviting confusion with run_smoke_match.sh. |
| low | process | `scripts/team_launchers/_tmp_vanilla_LL_right.sh:1` | Four _tmp_-prefixed launcher scripts are committed; two are load-bearing for a committed experiment and two are dead, unreferenced junk. |
| low | process | `README.md:20` | README 'Near-term milestones' checkboxes are all unchecked although five of six are provably complete, and the Naming table still calls robocup-spica-2027 a ... |
| low | process | `docs/EVALUATION_PROTOCOL.md:43` | EVALUATION_PROTOCOL.md's regime table still says RESEARCH_GRADE triggers on 'completed_matches >= 30' alone, but the aggregator (and REALITY_ATTESTATION.md) ... |
| low | process | `scripts/evaluate_logs.py:1` | evaluate_logs.py is a 0-byte file shipped in scripts/ |
| low | process | `scripts/team_launchers/helios_3_2_5_right.sh:4` | The launcher's comment claims 'only normal-formation.conf is overridden' while its -f flag points helios at experiments/helios_3_2_5_formations, which contai... |
| low | process | `paper/TDP_skeleton.md:1` | The RoboCup 2027 team description paper deliverable is a 0-byte file, and the tdp/ directory contains only .gitkeep — the project's qualification artifact na... |
| low | reproducibility | `scripts/symmetrize_f433.py:5` | The empirical justification for the F433 symmetrization cites notes/2026-06-27_side_clone.md, a file that does not exist in the repository. |
| low | stats | `docs/EVALUATION_PROTOCOL.md:26` | With 20-47% of matches ending in draws and goal_diff supported on {-4..+3}, the normal-approximation mean-goal-diff CI is a fragile primary statistic; comple... |

---

## Appendix B: 監査メタデータ

- Workflow: 8 finders (parallel) → dedup → 8 batch-verifiers (per-domain, adversarial) → gap critic → gap verify
- Agents: 19 / tool calls: 578 / subagent tokens: ~1.56M / wall clock: ~91 min
- 検証の verdict 分布: 90 CONFIRMED / 2 REFUTED / 1 UNCERTAIN
- Main-loop 独自検証: S1 (rcl の change_player_type 証拠), S2 (実測σからの power 再計算)
- 監査自身の限界: (1) 実行時挙動の一部は静的読解のみ（UNCERTAIN 判定で明示）、(2) C++ の findings は cyrus-team 本体との整合を vanilla snapshot ソースで確認したが全 call-site の網羅ではない、(3) 90件のうち低深刻度の一部は verifier の1パス判定
