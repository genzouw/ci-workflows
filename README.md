# ci-workflows

genzouw 配下の公開リポジトリで共通利用する reusable CI workflows（統一CIベースライン）。

## 提供ワークフロー

| ワークフロー            | 内容                                                                              | job 名 (= check context)               | paths フィルタ推奨                                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `gitleaks.yml`          | シークレット漏洩スキャン（全ブランチ履歴）                                        | `Scan for leaked secrets`              | なし（常時実行）                                                                                                         |
| `trivy.yml`             | 脆弱性・設定ミス・シークレットの fs スキャン                                      | `Trivy filesystem scan`                | なし（常時実行）                                                                                                         |
| `zizmor.yml`            | GitHub Actions ワークフローのセキュリティ監査                                     | `zizmor`                               | なし（常時実行）                                                                                                         |
| `actionlint.yml`        | ワークフロー lint + SHAピン留め強制 + pull_request_target 禁止                    | `actionlint`                           | `.github/workflows/**`, `.github/actions/**`                                                                             |
| `markdownlint.yml`      | Markdown lint（設定は呼び出し元の `.markdownlint-cli2.jsonc`）                    | `markdownlint-cli2`                    | `**/*.md`                                                                                                                |
| `hadolint.yml`          | Dockerfile lint（Dockerfile が無ければスキップ）                                  | `Hadolint (Dockerfile lint)`           | `**/Dockerfile*`                                                                                                         |
| `shellcheck.yml`        | シェルスクリプト lint + composite action の `run:` lint（対象が無ければスキップ） | `ShellCheck (shell script lint)`       | `**/*.sh`, `.github/actions/**`                                                                                          |
| `free-policy.yml`       | 完全無料ポリシー違反の検出（secrets ホワイトリスト等）                            | `Free-only policy check`               | なし（常時実行）                                                                                                         |
| `dependency-review.yml` | PR で追加・更新される依存の脆弱性とライセンスを判定（PR 限定）                    | `dependency-review (new dependencies)` | なし（`pull_request` のみ）                                                                                              |
| `pinact.yml`            | Action 参照のアノテーション整合 + リリース経過日数（cooldown）                    | `pinact (action pin verification)`     | `.github/workflows/**`, `.github/actions/**`, `.pinact.yaml`, `.pinact.yml`, `.github/pinact.yaml`, `.github/pinact.yml` |
| `typos.yml`             | ソースコード・ドキュメント横断のスペルミス検出                                    | `typos (spell check)`                  | なし（常時実行）                                                                                                         |
| `semantic-pr.yml`       | PR タイトルの Conventional Commits 準拠を検査（PR 限定）                          | `semantic-pr (conventional commits)`   | なし（`pull_request` のみ）                                                                                              |
| `lychee.yml`            | ドキュメント中のリンク切れ検出（外部 HTTP を伴う）                                | `lychee (broken link check)`           | `**/*.md`, `**/*.html`, `lychee.toml`                                                                                    |

## 提供 composite action

| action                           | 内容                                                                             |
| -------------------------------- | -------------------------------------------------------------------------------- |
| `.github/actions/setup-gitleaks` | gitleaks 公式リリースバイナリのチェックサム検証つきインストール（既定 `8.30.1`） |

`gitleaks` のバージョンはこの action の `inputs.version` の既定値を単一の信頼できる情報源 (Single Source of Truth) とする。
`gitleaks.yml` (本リポジトリの reusable workflow) と、呼び出し側リポジトリが独自に持つ gitleaks 実行ワークフローの
両方がこの action を経由することで、`run:` ブロック内に `GITLEAKS_VERSION` を二重管理する状態を解消する
（`run:` 内の文字列は Dependabot の更新対象外だが、`uses:` の SHA ピンは対象になる）。

```yaml
- name: Setup gitleaks
  uses: genzouw/ci-workflows/.github/actions/setup-gitleaks@<full-commit-SHA> # vX.Y.Z

- name: Run gitleaks
  run: gitleaks detect --no-git --source . --redact --no-banner
```

- バージョンを一時的に固定したい場合のみ `with: { version: '8.30.1' }` で上書きする。通常は指定しない
- 参照は reusable workflow と同じく **full-length commit SHA でピン留め**すること。更新は Dependabot (`github-actions` ecosystem) が自動でPRを出す

## composite action（`.github/actions/**`）の検証範囲

composite action は `.github/workflows/**` の外にあるため、ワークフロー向けの lint がそのままでは届かない。本リポジトリでは以下の形で穴を埋めている。

| 検証内容                        | 担当                                                                 | 備考                                                                                            |
| ------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `uses:` の SHA ピン留め強制     | `actionlint.yml`「Reject non-SHA action references in `uses:`」      | 走査対象は `.github/workflows` と `.github/actions`（後者はディレクトリが存在する場合のみ）     |
| `run:` ブロックの shell lint    | `shellcheck.yml`「Run shellcheck on composite action `run:` blocks」 | `run:` を抽出し、GitHub Actions の式を固定トークンへ置換して `shellcheck` に渡す                |
| `run:` ステップの `shell:` 必須 | 同上                                                                 | composite action では `shell:` が必須で、欠落すると実行時にクラッシュするため lint 時に落とす   |
| セキュリティ監査                | `zizmor.yml`                                                         | リポジトリ全体を走査するが `continue-on-error: true` のためビルドは落とさない（SARIF 報告のみ） |
| 完全無料ポリシー                | `free-policy.yml`                                                    | 走査対象に `action.yml` / `action.yaml` を含む                                                  |

`actionlint` 本体は composite action のスキーマを検証できない（`action.yml` を渡すと workflow スキーマとして解釈し `"jobs" section is missing` で失敗する）。そのため composite action の YAML スキーマ全体の検証は未カバーであり、上表のとおり `shell:` 必須の 1 点のみを個別に検証している。

`run:` からの抽出時に付与する行番号は元の `action.yml` の行番号と一致するため、報告された位置をそのまま該当行として読める。`shell: python` / `pwsh` などのステップは shellcheck の対象から除外される。

### 呼び出し側スタブの `paths` について

reusable workflow 側の `push` / `pull_request` の `paths` は**本リポジトリのセルフテスト用**であり、呼び出し側には効かない。composite action を持つリポジトリでは、スタブ側の `paths` にも `.github/actions/**` を追加すること（追加しないと composite action だけを変更したコミットで lint が起動しない）。

```yaml
on:
  pull_request:
    branches: [main, master]
    paths:
      - '**/*.sh'
      - '.github/actions/**'
```

## 使い方（呼び出し側スタブ）

```yaml
name: Gitleaks

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
  schedule:
    - cron: '0 20 * * 0'
  workflow_dispatch:

concurrency:
  group: gitleaks-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  security-events: write

jobs:
  gitleaks:
    uses: genzouw/ci-workflows/.github/workflows/gitleaks.yml@<full-commit-SHA> # vX.Y.Z
```

- 参照は **full-length commit SHA でピン留め**すること（actionlint が強制する）。更新は各リポジトリの Dependabot (`github-actions` ecosystem) が自動でPRを出す
- トリガー・concurrency・permissions は**スタブ側**で定義する（本リポジトリの各ワークフローに付いている `push` / `pull_request` トリガーは本リポジトリ自身のセルフテスト用）

## `dependency-review.yml`（新規依存のゲート）

### `trivy.yml` との役割分担（重複ではない）

|            | `trivy.yml`                                                | `dependency-review.yml`                 |
| ---------- | ---------------------------------------------------------- | --------------------------------------- |
| 走査範囲   | ツリー全体（既存の依存を含む）                             | PR の差分で**追加・更新された依存**のみ |
| 判定       | `--exit-code 0` で**報告のみ**（SARIF を Security タブへ） | 閾値以上なら**PR を落とす**             |
| ライセンス | 見ない                                                     | `deny-licenses` で判定できる            |
| 目的       | 今あるものの可視化                                         | これから増やすものの遮断                |

`trivy.yml` を報告のみにしているのは、既存の負債で CI を赤くしないための意図的な設定である。
その結果、**脆弱な依存の追加を止める検査は現状ひとつも無い**。本ワークフローがその役割を担う。

GitHub Actions も依存グラフの対象に含まれるため、`package.json` などのマニフェストを持たない
リポジトリでも `uses:` の更新が検査対象になる。

### トリガーの制約

本 Action は base と head の比較を前提とするため、**`pull_request` 以外では動かない**。
スタブのトリガーは `pull_request` のみにすること（`push` を足すと失敗する）。

```yaml
name: dependency-review

on:
  pull_request:
    branches: [main, master]

concurrency:
  group: dependency-review-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  dependency-review:
    uses: genzouw/ci-workflows/.github/workflows/dependency-review.yml@<full-commit-SHA> # vX.Y.Z
```

### 閾値と例外

| 入力               | 既定             | 用途                                     |
| ------------------ | ---------------- | ---------------------------------------- |
| `fail_on_severity` | `high`           | `low` / `moderate` / `high` / `critical` |
| `deny_licenses`    | 空（検査しない） | 例: `AGPL-3.0, GPL-3.0`                  |
| `allow_ghsas`      | 空               | 修正版が無い等の暫定例外                 |
| `config_file`      | 空               | 細かい制御は設定ファイルで行う           |

PR へのサマリーコメント投稿（`comment-summary-in-pr`）は `pull-requests: write` を要するため、
最小権限を保つ目的で無効にしている。結果は job summary で読む。

## `pinact.yml`（Action 参照の cooldown とアノテーション検証）

`actionlint.yml` の「Reject non-SHA action references」は `uses:` が 40 桁 SHA であることしか見ない。
SHA ピン留めを通過したあとに残る次の 2 つの穴を、`pinact.yml` が GitHub API 経由で塞ぐ。

| 穴                 | 具体例                                                                | `pinact.yml` の検査                                            |
| ------------------ | --------------------------------------------------------------------- | -------------------------------------------------------------- |
| アノテーション詐称 | `@<悪意のある SHA> # v1.2.3` と書けば、レビューでは `v1.2.3` に見える | `--verify`: コメントのタグが指す SHA と実際の pin が一致するか |
| 取り込みが早すぎる | 上流が侵害された直後のリリースを SHA 固定で取り込む                   | `--min-age`: pin した commit が指定日数より古いか              |

### `actionlint.yml` との役割分担（重複ではない）

|              | `actionlint.yml` の grep               | `pinact.yml`                                                       |
| ------------ | -------------------------------------- | ------------------------------------------------------------------ |
| 検査対象     | `uses:` の**書式**（40 桁 SHA か）     | pin の**中身**（タグとの一致・経過日数）                           |
| ネットワーク | 不要                                   | GitHub API を使う（`GITHUB_TOKEN` はレート制限回避の読み取りのみ） |
| 位置づけ     | API 制限や障害時も効き続ける即時ゲート | 書式ゲートを通ったものに対する追加検査                             |

`pinact` は実行時に書式チェックも同時に行うが、それは副産物であり、本ワークフローを追加する目的は上表の 2 行である。

### 閾値の設定

- 既定は **7 日**。スタブ側で `with: { min_age: 3 }` のように上書きできる（`0` で経過日数チェックを無効化）
- 呼び出し元に `.pinact.yaml` / `.github/pinact.yaml` がある場合、`--min-age` は渡さず設定ファイルを優先する
  （CLI フラグは設定ファイルの `rules[].min_age` より優先されるため、渡すと Action 単位の例外指定を握り潰す）
- **`.github/dependabot.yml` の `cooldown.default-days` と同じ値にすること。**
  値がずれていると、Dependabot が出した更新 PR が `pinact` の min-age で落ち続ける

```yaml
# .github/dependabot.yml
updates:
  - package-ecosystem: 'github-actions'
    cooldown:
      default-days: 7 # .pinact.yaml の min_age.value と揃える
```

> [!NOTE]
> Dependabot は頻繁にリリースされる Action について「最新リリースが cooldown 未経過なら更新を行わない」
> 挙動が報告されている（[dependabot-core#13691](https://github.com/dependabot/dependabot-core/issues/13691)）。
> 更新が止まって見える場合はこれを疑うこと。

### 終了コード

| コード | 意味                                                                             | 対処                                                                                                                       |
| ------ | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| 1      | SHA でピン留めされていない                                                       | `pinact run` で SHA へ置換する                                                                                             |
| 2      | 自動修正不可（アノテーションと SHA の不一致、または cooldown 未経過）            | アノテーション不一致なら `pinact run` でコメントを実際の SHA に合わせる。cooldown 未経過なら指定日数が経過してから取り込む |
| 3      | GitHub API エラー・CLI フラグの不正な組み合わせなど、pinact 自体の予期しない失敗 | ワークフローのログを確認し、pinact 自体の実行エラーに対処する                                                              |

## `typos.yml`（スペルミス検出）

既存の lint はいずれも**綴り**を見ていない。

| 既存の検査         | 見ているもの                                          | スペル |
| ------------------ | ----------------------------------------------------- | ------ |
| `markdownlint.yml` | Markdown の構造（見出し階層・箇条書き・行末空白など） | 見ない |
| `shellcheck.yml`   | シェルの構文・クォート・未定義変数                    | 見ない |
| `actionlint.yml`   | ワークフローのスキーマ・式・シェル                    | 見ない |
| `hadolint.yml`     | Dockerfile のベストプラクティス                       | 見ない |

`typos` は「よくある綴り間違い」の辞書に基づく検出で、未知語を片端から報告する
一般的なスペルチェッカとは異なり誤検知が少ない。そのため PR を落とす検査として運用できる。
日本語の文章は辞書に載らないため素通りする。

### 誤検知が出たときの逃がし方

呼び出し元リポジトリのルートに `_typos.toml`（`.typos.toml` / `typos.toml` も可）を置く。

```toml
# 固有名詞・意図的な綴りを辞書へ追加する
[default.extend-words]
ans = "ans"

# ファイル単位で除外する
[files]
extend-exclude = ["vendor/**", "*.min.js"]
```

スタブ側で対象を絞ることもできる。

```yaml
jobs:
  typos:
    uses: genzouw/ci-workflows/.github/workflows/typos.yml@<full-commit-SHA> # vX.Y.Z
    with:
      files: 'src docs README.md'
```

## `semantic-pr.yml`（PR タイトルの規約検査）

`AGENTS.md` 4 章は「コミットメッセージおよび PR タイトルは Conventional Commits に従う」と
定めているが、これを機械的に検査する仕組みが無かった。squash merge では **PR タイトルが
そのままデフォルトブランチのコミットメッセージになる**ため、崩れたタイトルは履歴に恒久的に残る。

### 既定で許可する type

`build` / `chore` / `ci` / `docs` / `feat` / `fix` / `perf` / `refactor` / `revert` / `style` / `test`

### 入力

| 入力                     | 既定                     | 用途                                                                                                               |
| ------------------------ | ------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `types`                  | 上記 11 種（改行区切り） | 許可する type を絞る・増やす                                                                                       |
| `require_scope`          | `false`                  | scope を必須にする                                                                                                 |
| `validate_single_commit` | `true`                   | コミットが 1 つだけの PR では、squash merge 時に GitHub がそのコミットメッセージを既定に使うため、そちらも検査する |

### `pull_request_target` を使わない

本 Action の上流 README は `pull_request_target` を推奨しているが、本リポジトリでは
`actionlint.yml` が `pull_request_target` を禁止している（fork PR からのシークレット漏洩対策）。
本検査はタイトルの**読み取りだけ**で書き込みを伴わないため、fork からの PR で
読み取り専用トークンになっても成立する。スタブのトリガーは `pull_request` のみにすること。

```yaml
name: semantic-pr

on:
  pull_request:
    branches: [main, master]
    types: [opened, edited, reopened, ready_for_review, synchronize]

concurrency:
  group: semantic-pr-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  pull-requests: read

jobs:
  semantic-pr:
    uses: genzouw/ci-workflows/.github/workflows/semantic-pr.yml@<full-commit-SHA> # vX.Y.Z
```

> [!NOTE]
> Dependabot の PR タイトルは、`.github/dependabot.yml` の `commit-message.prefix` を
> 設定していないと `Bump X from A to B` になり本検査で落ちる。
> 展開先では `prefix: "ci"` / `include: "scope"` の設定を先に入れること。

## `lychee.yml`（リンク切れ検出）

`markdownlint.yml` は Markdown の**構造**しか見ないため、リンクの書式が正しければ
参照先が消えていても通過する。外部サービスの終了やリポジトリのリネームで URL が
静かに死ぬのは、ドキュメント中心の公開リポジトリで実際に起きている。

| 検査               | リンクの書式                | リンク先の生死 |
| ------------------ | --------------------------- | -------------- |
| `markdownlint.yml` | 見る（MD034 bare URL など） | 見ない         |
| `lychee.yml`       | 見ない                      | **見る**       |

### 公式 Action を使わない理由

本リポジトリの Actions 設定は `allowed_actions: selected`（許可リスト方式）で、
`lycheeverse` は許可リストに含まれていない。`uses: lycheeverse/lychee-action@<SHA>` は
ジョブの失敗ではなく **`startup_failure`** になり、チェック自体が出現しない。

そのため公式 Action ではなく、リリースバイナリを **公式 `.sha256` で検証**してから導入する
（`actionlint.yml` / `trivy.yml` と同じ方式）。許可リストの変更を依頼せずに導入できる。

### 不安定さへの対処

外部ホストへ HTTP を出すため、他のワークフローより不安定になりやすい。既定で次を入れている。

- `--max-retries 3`：一時的な失敗を再試行する
- `--accept 200,204,206,429`：レート制限（429）を失敗扱いにしない
- `--cache --max-cache-age 1d` + `actions/cache`：同じ URL への再問い合わせを減らす
- `schedule`（毎週月曜 06:00 JST）：差分が無くてもリンク腐敗を定期的に拾う

ボット避けで恒久的に 4xx / 999 を返すホスト（LinkedIn・X など）は、
呼び出し元リポジトリのルートに `lychee.toml` を置いて除外する。

```toml
exclude = [
  '^https://www\.linkedin\.com/',
  '^https://(x|twitter)\.com/',
]
```

### 段階導入

既にリンク腐敗があるリポジトリでは、片付けるまで `fail: false` で報告のみにできる
（`free-policy.yml` の `enforce` と同じ考え方）。結果は job summary に出る。

```yaml
jobs:
  lychee:
    uses: genzouw/ci-workflows/.github/workflows/lychee.yml@<full-commit-SHA> # vX.Y.Z
    with:
      fail: false
```

## `free-policy.yml`（完全無料ポリシーチェック）

各リポジトリの `AGENTS.md` 1 章「公開 OSS で完全無料の SaaS・AI・ツールのみを利用する」のうち、**構文的に判定できる違反パターンのみ**を検出する。

### 検出するもの

| #   | 検出内容                                                                                 | 根拠                                        |
| --- | ---------------------------------------------------------------------------------------- | ------------------------------------------- |
| 1   | `GITHUB_TOKEN` 以外の `secrets.*` 参照、および `secrets: inherit`                        | 従量課金 API キーの Secrets 登録は MUST NOT |
| 2   | 従量課金 API キーを示す変数名（`*_API_KEY` / `*_API_TOKEN` / プロバイダ名付きの鍵・URL） | 同上（`vars.*` や平文での指定も検出する）   |
| 3   | 課金可能な LLM / 検索 API のエンドポイントホスト名                                       | OpenAI 互換エンドポイント経由も MUST NOT    |

キー名のブラックリスト維持を避けるため、1 は**ホワイトリスト方式**（`GITHUB_TOKEN` 以外はすべて違反）を採る。

走査対象は `.github/` 配下の YAML と composite action 定義（`action.yml` / `action.yaml`）のみ。ポリシーが禁止しているのは「CI/CD および自動化ワークフローへの組み込み」であり、`AGENTS.md` や README がポリシー解説として鍵名を列挙しているのを誤検知しないための限定である。

### 検出しないもの（レビュー運用でカバー）

- 有料プラン / 有料トライアル / クレジットカード登録を要する SaaS の導入
- リポジトリオーナーへの新規 Secret 発行依頼
- そのサービスが「無料枠」型かどうかの判定

いずれも意味的な判断が必要で、CI では誤検知・見逃しの両方が避けられないため実装しない。なお **Action の SHA ピン留め強制は `actionlint.yml` と `zizmor` が既にカバー**しているため、本ワークフローでは重複して実装していない。

### 段階導入と例外

- `enforce`（boolean、既定 `true`）を `false` にすると、違反を検出しても job は成功し `::warning::` のみを出す。新規導入時は `false` で誤検知を観察し、問題がなければ `true`（既定）へ切り替える
- 正当な例外は、対象行に `free-policy: allow <理由>` を含むコメントを書くことで除外する。別ファイルの allowlist ではなく行内マーカー方式にしているのは、例外の追加が必ず差分レビューに現れるようにするため

```yaml
jobs:
  free-policy:
    uses: genzouw/ci-workflows/.github/workflows/free-policy.yml@<full-commit-SHA> # vX.Y.Z
    with:
      enforce: false # 誤検知観察中。観察後に削除して既定の true に戻す
```

## 運用契約（重要）

1. **job の `name` を変更しない。** 呼び出し側では `<スタブjob名> / <本体job名>`（例: `gitleaks / Scan for leaked secrets`）が check context になり、genzouw.com の Terraform（`terraform/environments/github/main.tf` の `common_required_checks`）が必須チェック名として参照している。変更する場合は Terraform と同時に更新すること
2. `gitleaks` / `trivy` / `zizmor` には **paths フィルタを付けない**（必須チェックのため、context が報告されないPRが発生するとマージ不能になる）
3. **reusable workflow 側に workflow レベルの `concurrency` を定義しない。** 呼び出し元スタブと同一グループ名になると「Canceling since a deadlock was detected」で startup_failure する。concurrency はスタブ側でのみ定義する
4. 破壊的変更（job 名変更・チェックの厳格化）はタグのメジャーバージョンを上げる
5. **破壊的変更には Conventional Commits の `!` または `BREAKING CHANGE:` を必ず付ける。** タグは `auto-tag.yml` がコミットメッセージだけを見て自動採番するため、job 名を変えたのに `!` を付けないと、コミット種別に応じて minor（`feat:` 等）または patch（`fix:` / `ci:` 等）としてリリースされ、呼び出し側の必須チェックが黙って壊れる（後述）

## リリース

**main へマージすると `auto-tag.yml` がタグを自動で作成する。** 手動でタグを打つ必要はない。呼び出し側は Dependabot がタグに対応する SHA へ自動更新する。

`auto-tag.yml` は本リポジトリ自身のリリース運用専用であり、**reusable workflow ではない**（他リポジトリへ配布しない）。`.github/workflows/` 配下で `workflow_call` を持たない唯一のファイルである。

### 採番の規則

直近の `vX.Y.Z` タグを起点に、そこから HEAD までのコミットメッセージで bump を決める。**判定対象はルールごとに件名（1行目）と本文で異なる**: `<type>!:` と `feat:` はコミット件名だけを見て判定し、`BREAKING CHANGE:` は Conventional Commits の仕様どおり本文のフッターだけを見る。件名まで本文と一緒に判定すると、squash merge のコミット本文（= PR 本文がそのまま入る）中の地の文に `feat:` や `BREAKING CHANGE:` と読める行があるだけで誤爆するため。

| コミット                                    | 判定対象     | bump  |
| ------------------------------------------- | ------------ | ----- |
| `<type>!:`                                  | 件名         | major |
| 本文に `BREAKING CHANGE:`                   | 本文フッター | major |
| `feat:`                                     | 件名         | minor |
| それ以外（`fix:` / `ci:` / `refactor:` 等） | -            | patch |

複数該当する場合は最も強いものを採用する。PR タイトルの Conventional Commits 準拠は `semantic-pr.yml` が別途強制しているため、squash merge のコミット件名は必ずこの形式になる。

### タグを打たない条件

- 直近タグ以降に **`.github/workflows/` と `.github/actions/` のいずれも変更されていない**場合はスキップする。呼び出し側が参照するのはこの 2 つだけなので、README だけの更新でタグ番号を消費しない。`auto-tag.yml` 自身（他リポジトリへ配布しない）の変更もこの判定から除外しており、`auto-tag.yml` だけを直した変更ではタグ番号を消費しない

算出した番号のタグが checkout 後に他プロセス（手動での先行タグ付け等）から作成されていた場合は、タグ作成 API 呼び出しが 422 で失敗し job が赤くなる。黙ってスキップする経路は設けていない（ローカル ref だけを見る事前ガードは実際の衝突を検出できないため）。

### 自動化の限界

**`auto-tag.yml` はコミットメッセージしか見ない。** job 名を変更したかどうかは判定していないため、運用契約 5 の `!` を付け忘れると、破壊的変更がコミット種別に応じて minor または patch（`fix:` / `ci:` 等）としてリリースされる。この取りこぼしは自動化では塞いでおらず、レビューで担保する。

### タグ作成に `git push` を使わない理由

`git push` でタグを打つには checkout に認証情報を残す（`persist-credentials: true`）必要があり、以後のステップすべてがその認証情報に触れられる状態になる。`gh api repos/{owner}/{repo}/git/refs` なら `GH_TOKEN` を必要なステップにだけ渡せばよく、他のワークフローで徹底している `persist-credentials: false` を崩さない。
