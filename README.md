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

## 運用契約（重要）

1. **job の `name` を変更しない。** 呼び出し側では `<スタブjob名> / <本体job名>`（例: `gitleaks / Scan for leaked secrets`）が check context になり、genzouw.com の Terraform（`terraform/environments/github/main.tf` の `common_required_checks`）が必須チェック名として参照している。変更する場合は Terraform と同時に更新すること
2. `gitleaks` / `trivy` / `zizmor` には **paths フィルタを付けない**（必須チェックのため、context が報告されないPRが発生するとマージ不能になる）
3. 破壊的変更（job 名変更・チェックの厳格化）はタグのメジャーバージョンを上げる

## リリース

タグ `vX.Y.Z` を打つ。呼び出し側は Dependabot がタグに対応する SHA へ自動更新する。
