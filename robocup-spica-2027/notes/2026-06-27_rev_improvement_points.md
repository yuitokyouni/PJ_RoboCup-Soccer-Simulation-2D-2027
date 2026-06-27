# REV 改善ポイント — 全12試合詳細解析

Date: 2026-06-27
Source: `scripts/analyze_rev_matches.py` over 12 REV tournament matches

## サマリ

| metric | value |
|---|---|
| 得点 / 試合 | 0.33 (4 in 12) |
| 失点 / 試合 | 0.50 (6 in 12) |
| 失点 zone | **6/6 が DEF-C** (自陣中央) |
| **失点 前提条件** | **6/6 が set piece 由来** (corner / kick-in / free kick / indirect FK) |
| 得点 zone | 4/4 が ATT-C (相手中央) |
| 得点 phase | 早 2 / 中 2 / 遅 0 |
| 失点 phase | 早 1 / 中 3 / 遅 2 |

## 失点 6 ゴール詳細

| # | cycle | ball pos | preamble | 形 | 主な問題 |
|---|---|---|---|---|---|
| G1 | 317 | (-45.3, +0.5) | kickoff→corner→play→**goal** | コーナーキック | u4 (RB) +14.2y で離脱、CB両方+y、-y がら空き |
| G2 | 2905 | (-52.4, -4.1) | play→GK catch→**back_pass**→indirect FK→**goal** | 自陣 PA 内 indirect FK | GK へのバックパスで PA 内 FK 献上、壁形成失敗 |
| G3 | 2761 | (-45.8, +2.6) | foul→indirect FK→play→kick-in→**goal** | 連続 set piece | u4 (RB) +20y で離脱、CB+CDM が+y側集中 |
| G4 | 5284 | (-43.7, +4.1) | kick-in→play→foul→free kick→**goal** | 終盤 FK | DL 高い (x=-30〜-43)、ball が DL より深く侵入 |
| G5 | 3969 | (-43.4, -0.2) | FK→play→foul→FK→**goal** | 連続 FK | DL 高い (x=-34〜-41)、u4(+16y)/u8(+12y) 偏り |
| G6 | 4903 | (-47.5, +1.6) | foul→FK→play→kick-in→**goal** | 中央 set piece | DL タイト(-40〜-43) だが ball を間で抜かれる |

## 攻撃 4 ゴール詳細

全 4 ゴール: ball x>+41, |y|<6 (相手 PA 中央)
- cyc 743 (+44.8, -4.2) ← MERGE 戦
- cyc 937 (+41.8, -5.8) ← ORIG 戦
- cyc 2551 (+43.4, -1.5) ← MERGE 戦
- cyc 3325 (+46.9, -1.8) ← ORIG 戦

備考:
- **vs V (Vanilla) は 1 ゴールのみ** (cyc 743, 同点 1-0)
- **全得点が中央侵入** — wing 攻撃から得点ゼロ
- **全得点が y<0** — Y-sym 後も +Y 攻撃使えてない (formation は対称化したが行動が片寄ったまま)

## Set piece 戦績

| event | 獲得 | 失う | 比率 |
|---|---|---|---|
| free_kick | 75 | 73 | 50.7% (互角) |
| kick_in | 34 | 18 | 65.4% (優位) |
| indirect_free_kick | 3 | 5 | 37.5% (劣勢) |
| goal_kick | 7 | 8 | 46.7% |

→ **set piece 獲得数 (=圧力かけてる証拠) は同等以上**。なのに**失点はすべて opponent の set piece 由来** = set piece 防御の方が落ち穂。

---

# 改善ポイント (優先度順)

## P0 — 失点の根本: set piece 防御 (期待効果 +1.0 goal/match)

### #1. GK へのバックパス禁止 (G2 直接原因)

**症状**: cyc 2905 で味方が GK に意図的バックパス → GK が手で取ったため indirect FK in PA → 即失点。

**コード仕様**:
- `Strategy::getSafeReceiver()` or `BhvPassKickFindReceiver` で GK を pass 候補から除外
- ボール保持時の `clearance` logic でも GK 方向のクリアを禁止
- 例外: GK が前進してフィールドプレーヤーとして振る舞っているケース (ほぼ無視可能)

**ファイル候補**:
- `src/chain_action/bhv_pass_kick_find_receiver.cpp`
- `src/clearance.cpp` (Phase 5c で作った)

### #2. RB / WB の set-piece 時 drop-back (G1, G3, G4, G5)

**症状**: 自陣 set piece 守備で u4 (RB) が y=+14〜+20 の wide 位置に残り、PA 内人数不足。

**コード仕様**:
- defensive set piece (relevant set piece by opponent within 30m of own goal) detection
- RB/LB の target position を `formation.get(unum, ball)` ではなく **PA 内マーキング位置に override**
- u4 → (x = -45, y = +5), u3 → (x = -45, y = -5) 程度

**ファイル候補**:
- `src/bhv_set_play.cpp` または `src/role_*.cpp`
- 既存 Phase 5e `defense_block.cpp::modulate_position` に set piece の hook 追加

### #3. CB ペア の Y 軸均等分散 (G1, G3 直接原因)

**症状**: 自陣 set piece 守備で CB 2 枚 (u2, u5) が両方 +y 側 (+4, +8 など)、-y がら空き。

**コード仕様**:
- 自陣 set piece 守備時、CB pair の Y を強制対称化 (u2 → +5, u5 → -5 or vice versa, ball.y に応じ向き決定)
- 既存 formation の pair 機能を defensive set piece で使う

**ファイル候補**:
- `src/role_center_back.cpp` (if exists) or `src/bhv_basic_move.cpp`

### #4. CDM の deep set piece 時 wall 形成 (G2, G6)

**症状**: PA 内 / 接近距離の FK で defensive wall (4-5 人) を形成せず、ボールが defender 間を抜ける。

**コード仕様**:
- ball within 20m of own goal AND set piece against → CDM (u6, u7) を ball-to-goal line 上に配置
- 既存 `bhv_set_play_their_free_kick.cpp` 系の patch

## P1 — 失点の構造的問題

### #5. Defensive line 高さ管理 (G4, G5)

**症状**: ball at x<-35 なのに defensive line が x=-30 〜 -35 に維持されてる。high-line breakthrough。

**コード仕様**:
- defensive line 上限 = `min(formation.def_x, ball.x - 5)` のような cap
- 既存 `defense_block.cpp` に追加

### #6. 連続 set piece 後の集中力 (G3, G5)

**症状**: foul → FK → play → foul → FK → goal という連鎖が複数 (G3, G5, G4)。最初の FK で態勢崩れ、回復前に次の play で抜かれる。

**コード仕様**:
- set piece 後 30 cycles 間は defensive shape を formation 値より +3m 深く取る (Phase 5e に追加)

## P2 — 攻撃 (得点 0.33/試合の倍増)

### #7. Wing 攻撃の活用 (全得点が中央)

**症状**: 4 得点すべて y<0 中央 (|y|<6)。**+Y 側からの得点ゼロ**。Y-symmetrization で formation 対称化したが、行動 (パス選択、ドリブル) が依然 -Y 偏重。

**コード仕様**:
- `ChainAction` の pass scoring で y>0 receiver にもボーナス
- WB (u3, u4) の上がり trigger を +Y 側でも対称的に発火
- Phase 5b の `chance_signal` を Y-mirror で +Y にも

**ファイル候補**:
- `src/chain_action/actgen_*.cpp` (Phase 5b で触ったやつ)
- Phase 5e の `wing_back_push` rule

### #8. クロスからの得点パターン追加

**症状**: 全得点が中央侵入 from 中央。クロス→ヘッドの ゴールパターンゼロ (たぶん試合データに無い)。

**コード仕様**:
- WB が高い位置 (x>+30) でボール持った時、cross 候補が ChainAction に入っているか確認
- F433 で WB がいない場合、IF (u9, u10) が wide pass 受けに走る trigger

### #9. 終盤 phase の得点ゼロ問題

**症状**: phase late (4000-6000) で得点ゼロ。stamina 切れ or 集中切れ。

**コード仕様**:
- stamina 残量に応じ aggressive pressing を抑制
- 終盤 (cycle > 4500) で formation を 1 forward 増やす (一時的 3-2-5 化)

## P3 — その他

### #10. -Y 偏重の活用

逆に -Y 攻撃は機能している (得点 4/4 が y<0)。Y-sym で +Y 強化と並行して、**-Y は維持** すべき。

実装上は #7 が +Y 強化なので、-Y は触らない方向で。

---

# 推奨実装順

1. **#1 (GK back-pass)** — 最小コード変更で 1 ゴール救済 (G2)
2. **#3 (CB Y 均等)** — formation で対称化したのに行動が偏ってるので片付け、G1/G3 救済
3. **#2 (WB drop)** — Phase 5e 既存 rule 拡張で実装容易、G1/G3/G4/G5 で効く
4. **#4 (defensive wall)** — set piece 別 hook 必要、G2/G6
5. **#5 (DL height)** — 既存 `defense_block` 拡張、G4/G5
6. **#7 (+Y 攻撃活性化)** — 攻撃軸の調整、ChainAction 触る
7. **#9 (終盤 substitution)** — 大きい変更だが late phase 0 得点は無視できない

#1–#5 だけで現在の 6 失点のうち少なくとも 3-4 を回避できる見込み。  
1試合あたり 失点 0.50 → 0.20 になれば mean goal_diff 改善 +0.30。  
これだけで REV vs V の -0.50 → -0.20 まで近づく可能性。

## 検証順

`#1 → #3 → #2 → #4` の段階的 commit、各段階で n=4 smoke vs Vanilla、最後に n=30 balanced で本確認。
