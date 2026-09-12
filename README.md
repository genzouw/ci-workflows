# ci-workflows

genzouw 配下の公開リポジトリで共通利用する reusable CI workflows（統一CIベースライン）。

## 提供ワークフロー

| ワークフロー       | 内容                                                           | job 名 (= check context)         | paths フィルタ推奨     |
| ------------------ | -------------------------------------------------------------- | -------------------------------- | ---------------------- |
| `gitleaks.yml`     | シークレット漏洩スキャン（全ブランチ履歴）                     | `Scan for leaked secrets`        | なし（常時実行）       |
| `trivy.yml`        | 脆弱性・設定ミス・シークレットの fs スキャン                   | `Trivy filesystem scan`          | なし（常時実行）       |
| `zizmor.yml`       | GitHub Actions ワークフローのセキュリティ監査                  | `zizmor`                         | なし（常時実行）       |
| `actionlint.yml`   | ワークフロー lint + SHAピン留め強制 + pull_request_target 禁止 | `actionlint`                     | `.github/workflows/**` |
| `markdownlint.yml` | Markdown lint（設定は呼び出し元の `.markdownlint-cli2.jsonc`） | `markdownlint-cli2`              | `**/*.md`              |
| `hadolint.yml`     | Dockerfile lint（Dockerfile が無ければスキップ）               | `Hadolint (Dockerfile lint)`     | `**/Dockerfile*`       |
| `shellcheck.yml`   | シェルスクリプト lint（`.sh` が無ければスキップ）              | `ShellCheck (shell script lint)` | `**/*.sh`              |
| `free-policy.yml`  | 完全無料ポリシー違反の検出（secrets ホワイトリスト等）         | `Free-only policy check`         | なし（常時実行）       |

## 提供 composite action

| action                            | 内容                                                                     |
| --------------------------------- | ------------------------------------------------------------------------ |
| `.github/actions/setup-gitleaks`  | gitleaks 公式リリースバイナリのチェックサム検証つきインストール（既定 `8.30.1`） |

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

## 使い方（呼び出し側スタブ）

```yaml
name: Gitleaks

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
  schedule:
    - cron: "0 20 * * 0"
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

## リリース

タグ `vX.Y.Z` を打つ。呼び出し側は Dependabot がタグに対応する SHA へ自動更新する。
