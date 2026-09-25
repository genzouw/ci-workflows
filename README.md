# ci-workflows

genzouw 配下の公開リポジトリで共通利用する reusable CI workflows（統一CIベースライン）。

## 提供ワークフロー

| ワークフロー                    | 内容                                                                              | job 名 (= check context)                                 | paths フィルタ推奨                                                                                                       |
| ------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `gitleaks.yml`                  | シークレット漏洩スキャン（全ブランチ履歴）                                        | `Scan for leaked secrets`                                | なし（常時実行）                                                                                                         |
| `trivy.yml`                     | 脆弱性・設定ミス・シークレットの fs スキャン                                      | `Trivy filesystem scan`                                  | なし（常時実行）                                                                                                         |
| `zizmor.yml`                    | GitHub Actions ワークフローのセキュリティ監査                                     | `zizmor`                                                 | なし（常時実行）                                                                                                         |
| `actionlint.yml`                | ワークフロー lint + SHAピン留め強制 + pull_request_target 禁止                    | `actionlint`                                             | `.github/workflows/**`, `.github/actions/**`                                                                             |
| `markdownlint.yml`              | Markdown lint（設定は呼び出し元の `.markdownlint-cli2.jsonc`）                    | `markdownlint-cli2`                                      | `**/*.md`                                                                                                                |
| `hadolint.yml`                  | Dockerfile lint（Dockerfile が無ければスキップ）                                  | `Hadolint (Dockerfile lint)`                             | `**/Dockerfile*`                                                                                                         |
| `shellcheck.yml`                | シェルスクリプト lint + composite action の `run:` lint（対象が無ければスキップ） | `ShellCheck (shell script lint)`                         | `**/*.sh`, `.github/actions/**`                                                                                          |
| `free-policy.yml`               | 完全無料ポリシー違反の検出（secrets ホワイトリスト等）                            | `Free-only policy check`                                 | なし（常時実行）                                                                                                         |
| `dependency-review.yml`         | PR で追加・更新される依存の脆弱性とライセンスを判定（PR 限定）                    | `dependency-review (new dependencies)`                   | なし（`pull_request` のみ）                                                                                              |
| `pinact.yml`                    | Action 参照のアノテーション整合 + リリース経過日数（cooldown）                    | `pinact (action pin verification)`                       | `.github/workflows/**`, `.github/actions/**`, `.pinact.yaml`, `.pinact.yml`, `.github/pinact.yaml`, `.github/pinact.yml` |
| `typos.yml`                     | ソースコード・ドキュメント横断のスペルミス検出                                    | `typos (spell check)`                                    | なし（常時実行）                                                                                                         |
| `semantic-pr.yml`               | PR タイトルの Conventional Commits 準拠を検査（PR 限定）                          | `semantic-pr (conventional commits)`                     | なし（`pull_request` のみ）                                                                                              |
| `lychee.yml`                    | ドキュメント中のリンク切れ検出（外部 HTTP を伴う）                                | `lychee (broken link check)`                             | `**/*.md`, `**/*.html`, `lychee.toml`                                                                                    |
| `fallow.yml`                    | TS/JS の変更ファイル品質ゲート（未使用コード・重複・複雑度）（PR 限定）           | `fallow (changed-file quality gate)`                     | TS/JS の各拡張子, `**/package.json`, `.fallowrc.*`, `fallow.toml`                                                        |
| `renovate-config-validator.yml` | Renovate 設定 (`renovate.json` 系) の構文検証（設定が無ければスキップ）           | `renovate-config-validator (renovate.json syntax check)` | `renovate.json*`, `.github/renovate.json*`, `.gitlab/renovate.json*`, `.renovaterc*`                                     |

## 提供 composite action

| action                           | 内容                                                                             |
| -------------------------------- | -------------------------------------------------------------------------------- |
| `.github/actions/setup-gitleaks` | gitleaks 公式リリースバイナリのチェックサム検証つきインストール（既定 `8.30.1`） |

`gitleaks` のバージョンはこの action の `inputs.version` の既定値を単一の信頼できる情報源 (Single Source of Truth) とする。
`gitleaks.yml` (本リポジトリの reusable workflow) と、呼び出し側リポジトリが独自に持つ gitleaks 実行ワークフローの
両方がこの action を経由することで、`run:` ブロック内に `GITLEAKS_VERSION` を二重管理する状態を解消する
（`run:` 内の文字列は Renovate の既定では更新対象外だが、`uses:` の SHA ピンは対象になる）。

```yaml
- name: Setup gitleaks
  uses: genzouw/ci-workflows/.github/actions/setup-gitleaks@<full-commit-SHA> # vX.Y.Z

- name: Run gitleaks
  run: gitleaks detect --no-git --source . --redact --no-banner
```

- バージョンを一時的に固定したい場合のみ `with: { version: '8.30.1' }` で上書きする。通常は指定しない
- 参照は reusable workflow と同じく **full-length commit SHA でピン留め**すること。更新は Renovate (`github-actions` manager) が自動でPRを出す

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

- 参照は **full-length commit SHA でピン留め**すること（actionlint が強制する）。更新は各リポジトリの Renovate (`github-actions` manager) が自動でPRを出す
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
- **`.github/renovate.json` の `minimumReleaseAge` と同じ値にすること。**
  値がずれていると、Renovate が出した更新 PR が `pinact` の min-age で落ち続ける

```json
// .github/renovate.json
{
  "minimumReleaseAge": "7 days"
}
```

> [!NOTE]
> `minimumReleaseAge` を満たさない更新を、Renovate は PR にせず保留する。
> Dependency Dashboard の Issue に「Pending Status Checks」として並ぶので、
> 更新が止まって見える場合はまずそこを確認すること。
> なお脆弱性修正は `vulnerabilityAlerts` で `minimumReleaseAge: null` にしてあるため保留されない。
> この場合だけは `pinact` の min-age に引っかかり得るので、必要なら `.pinact.yaml` の
> `rules[].min_age` で当該 Action を個別に緩める。

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
> Renovate の PR タイトルは、`semanticCommits` が `"disabled"` だと
> `Update X to vY` になり本検査で落ちる。既定値の `"auto"` はコミット履歴からの
> 判定で、履歴の内容によっては `"disabled"` と判定される。
> 展開先の `.github/renovate.json` では `"semanticCommits": "enabled"` を明示し、
> `github-actions` manager に `"semanticCommitType": "ci"` を指定すること。

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

## `fallow.yml`（TS/JS の変更ファイル品質ゲート）

[fallow](https://github.com/fallow-rs/fallow) でリポジトリを依存グラフとして読み、**その PR が変更したファイル**の未使用コード・重複・複雑度を判定する。TS/JS を持たないリポジトリから呼ばれた場合は「対象が無ければスキップ」する（`hadolint.yml` / `shellcheck.yml` と同じ方式）。

### 既存の検査との役割分担（重複ではない）

|                  | 各リポジトリの ESLint                | `fallow.yml`                                          |
| ---------------- | ------------------------------------ | ----------------------------------------------------- |
| 解析の単位       | 1 ファイル（ファイル内で閉じた規則） | リポジトリ全体の依存グラフ                            |
| 検出できるもの   | 未使用変数、構文上の不備             | 未使用 export・到達不能ファイル・循環依存・コピペ重複 |
| ファイルをまたぐ | 見ない                               | 見る                                                  |

`typos.yml` は綴り、`markdownlint.yml` は Markdown 構造、`trivy.yml` / `gitleaks.yml` は脆弱性とシークレットを見るもので、いずれもコード品質は扱わない。

### knip を持つリポジトリは当面の配布対象から外す

上の比較は ci-workflows 配下の既存ワークフローと「各リポジトリの ESLint」を見たもので、配布先リポジトリの実体を確認すると **2 本が既に knip を持っている**。

| リポジトリ      | knip                                                         |
| --------------- | ------------------------------------------------------------ |
| `toique`        | `.github/workflows/knip.yml` / `package.json` に `knip` 依存 |
| `hyakuninissyu` | 同上 + `knip.jsonc`                                          |

knip は未使用 export・到達不能ファイル・未使用依存を検出するツールで、fallow の dead-code 検出と守備範囲が正面から重なる。重なったまま両方を回すと困ることが 2 つある。

1. **誤検知の除外設定が二重管理になる。** knip の除外は `knip.jsonc` の `entry` / `project` / `ignoreDependencies` に積み上がっているが、fallow はこのファイルを読まない。同じ「これは未使用ではない」という事実を 2 つの設定ファイルで維持することになる
2. **両者の判定が既に食い違っている。** 上表のとおり hyakuninissyu はフルスキャンで dead-code 75 件だが、knip は緑のままである。この 75 件が本物の負債なのか `knip.jsonc` で意図的に除外されている対象なのかを切り分けないまま配布すると、開発者は 2 つのツールの言い分を毎 PR で突き合わせることになる

**判断: `toique` / `hyakuninissyu` は当面の配布対象から外す。** 配布先は knip を持たない `monopo` / `kakezan-manabo` / `dice-api` とする。将来 fallow へ寄せる場合は `knip.jsonc` の除外を fallow の設定へ移す作業（`fallow migrate` が knip 設定の変換を持つ）と、上記 75 件の切り分けを済ませてから、knip の廃止と同時に行う。

なお AGENTS.md 1.1 の「既に導入済みのツールと機能が重複する追加」は ci-workflows 自身を対象にした条項だが、reusable workflow は配布した瞬間に配布先へ実質同じ状況を生むため、ここでも同じ基準で判断している。

### なぜ `command: audit`（変更ファイル限定）なのか

導入時点の実測で、対象リポジトリはいずれも既存コードに指摘を持っている。

| リポジトリ     | フルスキャンの結果                    |
| -------------- | ------------------------------------- |
| hyakuninissyu  | dead-code 75 件 / 重複 5 / 複雑度 9   |
| toique         | dead-code 12 件 / 重複 16 / 複雑度 36 |
| monopo         | dead-code 2 件 / 重複 13 / 複雑度 33  |
| kakezan-manabo | dead-code 16 件 / 複雑度 6            |
| dice-api       | dead-code 5 件                        |

フルスキャンを赤検知にすると、その PR と無関係な負債で全 PR が落ちて検査として機能しない。`audit` は merge-base からの変更ファイルに判定を限定するため、既存の負債を無視して「これから増えるもの」だけを止められる。`trivy.yml`（今あるものの報告）と `dependency-review.yml`（これから増えるものの遮断）の関係と同じで、本ワークフローは後者にあたる。

### トリガーの制約

`audit` は base との merge-base を必要とするため、**スタブのトリガーは `pull_request` のみ**にすること。checkout は `fetch-depth: 0` で行っている（reusable workflow 側で設定済み）。

これは散文の約束ではなく、**reusable workflow 側が強制する**。`github.event.pull_request.base.sha` が空になる呼ばれ方（`push` / `merge_group` など）では `::error::` + exit 2 で落ちる。CLI の merge-base 自動検出に委ねると、`main` 上での実行では merge-base が HEAD 自身になり、**変更ファイル 0 件のまま `audit` が pass してジョブが緑になる**（起動しているように見えて何も検査していない状態）ため。

```yaml
name: fallow

on:
  pull_request:
    branches: [main, master]
    paths:
      - '**/*.ts'
      - '**/*.tsx'
      - '**/*.mts'
      - '**/*.cts'
      - '**/*.js'
      - '**/*.jsx'
      - '**/*.mjs'
      - '**/*.cjs'
      - '**/*.vue'
      - '**/*.svelte'
      - '**/package.json'
      - '.fallowrc.json'
      - '.fallowrc.jsonc'
      - 'fallow.toml'
      - '.fallow.toml'
      - '.github/workflows/fallow.yml'

concurrency:
  group: fallow-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  fallow:
    uses: genzouw/ci-workflows/.github/workflows/fallow.yml@<full-commit-SHA> # vX.Y.Z
```

### 入力

| 入力             | 既定   | 用途                                                                                    |
| ---------------- | ------ | --------------------------------------------------------------------------------------- |
| `version`        | `""`   | fallow CLI のバージョン。空なら本ワークフロー側の既定値（`FALLOW_VERSION`、SSoT）を使う |
| `fail_on_issues` | `true` | `false` にすると指摘があっても job は成功する（段階導入用）                             |

`version` 入力そのものの既定値は空文字で、実際に使われるバージョンは `.github/workflows/fallow.yml` の `FALLOW_VERSION` が持つ。**バージョンのリテラルをこの表に書かない**のは、手動更新（Dependabot の対象外）で片方だけ直り README が古い値を指し続けるのを避けるため。現在の値は [`fallow.yml` の `FALLOW_VERSION`](.github/workflows/fallow.yml) を参照すること。

### 公式 Action（`fallow-rs/fallow`）を使わない理由

本リポジトリと配布先リポジトリはいずれも Actions の許可リストが **`selected`**（`github_owned` + `verified` + 個別許可パターン）に設定されている。許可されていないサードパーティ Action を参照したワークフローは、**実行される前に `startup_failure` で落ちる**。

この失敗は check context を報告しないため、**PR のチェック一覧にも `gh pr checks` にも現れない**（緑に見えるが実際には何も実行されていない）。実際に公式 Action 版を push して確認した挙動である。

```console
$ gh run list --branch <branch> --json name,conclusion
fallow      startup_failure   ← チェック一覧には出ない
```

Action を使うには対象全リポジトリの許可リスト変更が必要で、かつ許可リストは genzouw.com の Terraform 側にあるため、CI の定義とは別の場所で二重管理になる。CLI は npm から取得してローカルで完結するためこの制約を受けない。`gitleaks` / `hadolint` を公式バイナリの直接実行にしているのと同じ判断。

副次的な利点として、PR コメント用トークンの発行先（`api.fallow.cloud`）を含む外部 SaaS への経路が構成から完全に消える。

### 解析前に依存をインストールする

`node_modules` が無いと fallow は各パッケージの `exports` / conditional exports を読めず、「import と依存が誤報告されうる」と自ら警告する。実測でも差が出た。

| dice-api            | dead-code の検出                        |
| ------------------- | --------------------------------------- |
| `node_modules` あり | 5 件                                    |
| `node_modules` なし | **6 件**（未解決 import が 1 件増える） |

そのため解析の前に依存をインストールする。インストーラは **npm に一本化**している。Node.js と npm だけが runner にプリインストールされているためで、bun / pnpm を入れるには公式 Action か野良スクリプトが必要になり、前者は許可リスト（`selected`）に阻まれ、後者は供給網リスクを持ち込む。

- `package-lock.json` があれば `npm ci`、無ければ `npm install`
- **`npm ci` が失敗したら `npm install` にフォールバックする。** lockfile と `package.json` がずれていると `npm ci` は `EUSAGE` で必ず落ちる（dice-api が実際にこの状態で、`Missing: cac@6.7.14 from lock file`）。ここで諦めると、誤検知が出やすいリポジトリほど `node_modules` 無しで解析されることになるため、lockfile を無視してでも依存を入れる方へ倒している
- `bun.lock` しか無いリポジトリ（toique / monopo / hyakuninissyu）では lockfile どおりの解決にはならないが、fallow が必要とするのは各パッケージの `exports` 情報であってバージョンの厳密一致ではない
- `--ignore-scripts` を付けて `postinstall` を実行しない。依存を「読む」だけが目的で、ビルドも実行もしないため
- **`npm install` にも失敗したら、解析を行わずに `::error::` + exit 2 で終了する。** `node_modules` 無しの解析は誤検知が増えることが上表のとおり実測で分かっており、そのまま走らせると「根拠の弱い赤」で無関係な PR を落とすことになる。exit 2 は「fallow 自体の失敗」と同じ扱いで、`fail_on_issues` と無関係に常に失敗する
- `package.json` を持たないリポジトリでは依存のインストールを飛ばすが、同じ理由で `::warning::` を残す。黙って続けると「精度の落ちた解析が緑だった」状態を見分けられなくなるため

### 指摘の出しかた（アノテーション + ジョブサマリー）

解析は **1 回だけ**走らせて JSON を中間成果物（`${{ runner.temp }}/fallow-audit.json`）にし、そこから `fallow report --from` で 2 つの表示面を描画する。

| 表示面               | 形式                 | 出る場所                     |
| -------------------- | -------------------- | ---------------------------- |
| インラインの指摘     | `github-annotations` | PR の Files changed の該当行 |
| 一覧（件数と内訳表） | `github-summary`     | Actions のジョブサマリー     |

`--format human` を標準出力に流すだけだと、赤くなった開発者は Actions のジョブログを開いて該当行まで遡らないと何を指摘されたのか分からない。`fail_on_issues: false`（段階導入用）ではジョブが緑のまま結果がログの奥に埋まるため、「報告のみ」が誰にも報告されない状態になる。

どちらの形式もログベースの workflow command / job summary なので、**write 権限を持たない fork PR でも描画される**（`permissions: contents: read` のまま使える）。描画の失敗は `|| true` で握りつぶし、判定結果（audit の終了コード）には影響させない。

### CLI バージョンの更新は手動

CLI は npm 経由で取得されるため SHA ピン留めができず、バージョン固定が再現性を保つ唯一の手段になる。そのため本ワークフローの `version` 入力の既定値を単一の信頼できる情報源 (SSoT) とする。

**`package.json` などのマニフェストではないため Dependabot の更新対象外**であり、更新は手動で行う（`gitleaks` のバージョンを composite action の `inputs.version` 既定値で一元管理しているのと同じ運用）。

手動更新のときは次の 2 点を守る。

- **公開から 7 日を越えたバージョンだけを選ぶ。** 本リポジトリは `.github/dependabot.yml` の `cooldown.default-days` と `.pinact.yaml` の `min_age.value` で「公開直後の上流を取り込まない」を 7 日と定めているが、`FALLOW_VERSION` は `env:` の文字列なので Dependabot の cooldown も pinact の `min_age` も届かない。機械が検査しない経路なので、人の目で守る
- **README の「入力」表の記述も併せて直す。**

また、外部バイナリを取る既存 6 経路（`actionlint.yml` / `hadolint.yml` / `lychee.yml` / `pinact.yml` / `trivy.yml` / `.github/actions/setup-gitleaks/action.yml`）は `.sha256` を併せて取得して `sha256sum -c` で照合しているが、**fallow だけはこの照合を持たない**。npm レジストリ経由の取得にはリリースごとの公開チェックサムが無いためで、代わりに npm レジストリの整合性と fallow 自身のバイナリ署名検証（`fallow --version` が `verified: yes ... signed` を出す）に委ねている。任意コード実行の面は `npx --yes --ignore-scripts` で `postinstall` を実行しないことで抑えている。

### 終了コードの扱い

| コード | 意味                    | 本ワークフローの挙動                    |
| ------ | ----------------------- | --------------------------------------- |
| 0      | 指摘なし / verdict pass | 成功                                    |
| 1      | 指摘あり / verdict fail | `fail_on_issues` に従う（既定は失敗）   |
| 2 以上 | fallow 自体の失敗       | **`fail_on_issues` と無関係に常に失敗** |

fallow が定義している終了コードは 0〜8 と 10〜13（4〜6 は runtime coverage サイドカー、7 はネットワーク障害、10〜13 はアップロード系）だが、本ワークフローは `case` の `*)` で 2 以上を一括して落とすため、個別に列挙しない（[fallow README「Output and exit codes」](https://github.com/fallow-rs/fallow#output-and-exit-codes)）。

指摘の検出と fallow 自体の故障を区別している。区別しないと、CLI が壊れて何も解析していない状態が「指摘なし」と同じ緑になる。

ただし `npx` は**パッケージの解決に失敗したときも exit 1 を返す**ため、終了コードだけでは「指摘あり」と区別できない。`fail_on_issues: false` の構成だと、fallow が一度も動いていないのに「指摘を検出したが成功扱いにする」という事実と異なる警告とともに緑になる。そのため audit の前に `fallow --version` で取得可否を単独で確認し、失敗した場合は `fail_on_issues` と無関係に exit 2 で落とす（取得に成功していれば `npx` のキャッシュに載るため、続く audit でダウンロードは発生しない）。

### 課金について

静的解析部分は MIT ライセンスで、ライセンスキー・API キー・Secrets をいずれも必要としない（[LICENSE](https://github.com/fallow-rs/fallow/blob/main/LICENSE) / [docs.fallow.tools](https://docs.fallow.tools/)「Free static analysis of code and styles」）。有料なのは本番トレースを取り込む Fallow Runtime だけで、本ワークフローはこれを使わない。

## `renovate-config-validator.yml`（Renovate 設定の構文検証）

`actionlint.yml` の検査対象は `.github/workflows/**` と `.github/actions/**` だけで、`renovate.json` は見ない。
`schedule` の cron 書式や存在しないオプション名を書き間違えても、Renovate が実行時に設定エラーを報告するまで気づけず、依存更新 PR が黙って止まる。

`renovate-config-validator` は Renovate 自身と同じスキーマ検証を行う。Renovate 本体の探索対象（`lib/config/app-strings.ts` の `configFileNames`）に揃えた次のいずれかが存在すれば検証し、どれも無ければスキップして成功する。

- `renovate.json` / `renovate.jsonc` / `renovate.json5`
- `.github/renovate.json` / `.github/renovate.jsonc` / `.github/renovate.json5`
- `.gitlab/renovate.json` / `.gitlab/renovate.jsonc` / `.gitlab/renovate.json5`
- `.renovaterc` / `.renovaterc.json` / `.renovaterc.jsonc` / `.renovaterc.json5`

`package.json` 内の `renovate` キーは、`package.json` の存在だけでは設定の有無を判定できないため対象外（検証もされない）。

### 仕様

| 項目               | 内容                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| バージョン         | 既定値は workflow の `RENOVATE_VERSION`（`inputs.version` で上書き可）。SHA ピンできない npm 経由の取得のため、この既定値が単一の信頼できる情報源 |
| 判定               | `--strict`。非推奨オプションなどの警告も失敗にする                                                                       |
| Node.js            | 24 を `actions/setup-node` で入れる（renovate 44 系の engines が `^24.11.0`）                                            |
| install スクリプト | `--ignore-scripts` で実行しない。ただし RE2 で正規表現（`matchStrings` など）を検証するため、`re2` だけ `npm rebuild` で有効化する。RE2 を読み込めなければ失敗にする |

- バージョンの更新は**手動**（`env:` の文字列は Renovate の更新対象外）。公開から 7 日を越えたバージョンだけを選ぶこと。バージョンは workflow の `RENOVATE_VERSION` にだけ書く（README には数値を書かない）
- 検出したファイルだけを引数に渡し、`--no-global` で repo config として検証する。`--no-global` が無いと global config として検証され、repo config に対して誤検知する。引数を渡さないと `package.json` 内の `renovate` キーまで検証対象になり、上記の対象外の方針と食い違うため

### 呼び出し側スタブ

`paths` を Renovate 設定に絞る（GitHub の `paths` は `{,c,5}` のようなブレース展開に対応しないため `*` で書く）。設定を触らない PR で Node.js と renovate を取得しないための絞り込みで、必須チェックにする場合は paths フィルタを付けないこと（運用契約 2 と同じ理由）。

```yaml
name: Renovate config

on:
  pull_request:
    branches: [main, master]
    paths:
      - 'renovate.json*'
      - '.github/renovate.json*'
      - '.gitlab/renovate.json*'
      - '.renovaterc*'

concurrency:
  group: renovate-config-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  renovate-config-validator:
    uses: genzouw/ci-workflows/.github/workflows/renovate-config-validator.yml@<full-commit-SHA> # vX.Y.Z
```

## 運用契約（重要）

1. **job の `name` を変更しない。** 呼び出し側では `<スタブjob名> / <本体job名>`（例: `gitleaks / Scan for leaked secrets`）が check context になり、genzouw.com の Terraform（`terraform/environments/github/main.tf` の `common_required_checks`）が必須チェック名として参照している。変更する場合は Terraform と同時に更新すること
2. `gitleaks` / `trivy` / `zizmor` には **paths フィルタを付けない**（必須チェックのため、context が報告されないPRが発生するとマージ不能になる）
3. **reusable workflow 側に workflow レベルの `concurrency` を定義しない。** 呼び出し元スタブと同一グループ名になると「Canceling since a deadlock was detected」で startup_failure する。concurrency はスタブ側でのみ定義する
4. 破壊的変更（job 名変更・チェックの厳格化）はタグのメジャーバージョンを上げる
5. **破壊的変更には Conventional Commits の `!` または `BREAKING CHANGE:` を必ず付ける。** タグは `auto-tag.yml` がコミットメッセージだけを見て自動採番するため、job 名を変えたのに `!` を付けないと、コミット種別に応じて minor（`feat:` 等）または patch（`fix:` / `ci:` 等）としてリリースされ、呼び出し側の必須チェックが黙って壊れる（後述）
6. **`fallow.yml` は本リポジトリでは自己検査されない。** ci-workflows は TS/JS を持たないため `detect` ステップが必ず `found=false` を返し、`Install dependencies` と `Audit changed files` は一度も実行されない（本リポジトリの PR では 5 秒で success する）。`markdownlint.yml` / `typos.yml` が自リポジトリで実動作するのとは対照的に、`case` の分岐ミス・`ENFORCE` の比較崩れ・`installed` フラグの取り違えなど **actionlint が構文で拾えない種類の壊れ方は緑のまま通る**。この 100 行超の bash を変更したときは、TS/JS を持つ対象リポジトリの PR で実挙動を確認すること。導入時は draft PR で次の 6 パターンを確認した
   - TS/JS 無し（`detect` でスキップ）
   - `package-lock.json` あり（`npm ci` 成功）
   - `npm ci` が `EUSAGE` で失敗 → `npm install` へフォールバック
   - `bun.lock` のみ（`npm install` で近似）
   - 変更ファイルに新規の指摘あり（`fail_on_issues: true` で失敗）
   - 同上を `fail_on_issues: false`（`::warning::` を残して成功）

## リリース

**main へマージすると `auto-tag.yml` がタグを自動で作成する。** 手動でタグを打つ必要はない。呼び出し側は Renovate がタグに対応する SHA へ自動更新する。

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
