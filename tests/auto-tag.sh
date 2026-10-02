#!/usr/bin/env bash
#
# auto-tag.yml のタグ付け判定をフィクスチャで検証する。
#
# auto-tag.yml は main への push でしか実行されず、判定を変えても PR 上では動作を
# 確かめられない。ワークフローの `run:` を yq で取り出し、一時ディレクトリに作った
# git リポジトリでそのまま実行して、作られるタグ (またはスキップ) を期待値と突き合わせる。
# タグを作る `gh api` はスタブに差し替え、呼び出しの引数だけを記録する。
#
# 使い方:
#   bash tests/auto-tag.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/auto-tag.yml"
step_name='Create release tag'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

script="$tmp/auto-tag.sh"
STEP_NAME="$step_name" yq -r \
  '.jobs.auto-tag.steps[] | select(.name == strenv(STEP_NAME)) | .run' "$workflow" > "$script"
if ! grep -q 'set -euo pipefail' "$script"; then
  echo "auto-tag.yml から run: を取り出せませんでした (ステップ名: ${step_name})" >&2
  exit 2
fi

# 実行者の git 設定 (署名・フック・既定ブランチ名など) に結果が左右されないようにする。
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# gh のスタブ。タグを作る API 呼び出しの引数を記録するだけで、何も作らない。
gh_log="$tmp/gh.log"
mkdir -p "$tmp/stub"
cat > "$tmp/stub/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$gh_log"
EOF
chmod +x "$tmp/stub/gh"

# --- フィクスチャ ---------------------------------------------------------

repo=""
repo_seq=0

put() {
  mkdir -p "$(dirname "$repo/$1")"
  cat > "$repo/$1"
}

commit() {
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$1"
}

# reusable workflow (workflow_call あり)。コメントの有無では判定が変わらないこと。
put_reusable() {
  put "$1" <<'EOF'
on:
  workflow_call:
  push:
jobs: {}
EOF
}

# 他リポジトリへ配布しないワークフロー (workflow_call なし)。
# コメントに workflow_call と書いてあっても reusable と判定されないこと。
put_internal() {
  put "$1" <<'EOF'
# 本ワークフローは workflow_call を持たない。
on:
  push:
jobs: {}
EOF
}

# touch_file <パス>: 末尾にコメント行を足して内容を変える。
touch_file() {
  echo "# changed" >> "$repo/$1"
}

# reusable 1 つ・配布しないワークフロー 1 つ・composite action 1 つを持ち、
# v1.0.0 のタグが付いたリポジトリを作る。
new_repo() {
  repo_seq=$((repo_seq + 1))
  repo="$tmp/repo-$repo_seq"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  put_reusable .github/workflows/lint.yml
  put_internal .github/workflows/release.yml
  put .github/actions/setup/action.yml <<'EOF'
runs:
  using: composite
  steps: []
EOF
  put README.md <<'EOF'
# fixture
EOF
  commit "chore: 初期コミット"
  git -C "$repo" tag v1.0.0
}

# --- 実行と照合 -----------------------------------------------------------

out=""
status=0
total=0
failed=0

run_auto_tag() {
  : > "$gh_log"
  set +e
  out="$(
    cd "$repo" && env PATH="$tmp/stub:$PATH" GH_TOKEN=dummy REPO=owner/repo \
      HEAD_SHA="$(git -C "$repo" rev-parse HEAD)" GITHUB_STEP_SUMMARY="$tmp/summary" \
      bash "$script" 2>&1
  )"
  status=$?
  set -e
}

report() {
  total=$((total + 1))
  if [ "$1" = ok ]; then
    echo "ok - $2"
  else
    failed=$((failed + 1))
    echo "not ok - $2"
    echo "    $3"
    echo "    --- gh の呼び出し"
    sed 's/^/    /' "$gh_log"
    echo "    --- 出力 (終了コード: $status)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

# expect_tag <説明> <期待するタグ>: HEAD にそのタグを 1 つだけ作ること。
expect_tag() {
  run_auto_tag
  local want
  want="repos/owner/repo/git/refs -f ref=refs/tags/$2 -f sha=$(git -C "$repo" rev-parse HEAD)"
  if [ "$status" -eq 0 ] && [ "$(cat "$gh_log")" = "api $want" ]; then
    report ok "$1"
  else
    report ng "$1" "期待: タグ $2 を HEAD に作成"
  fi
}

# expect_skip <説明>: タグを作らずに成功すること。
expect_skip() {
  run_auto_tag
  if [ "$status" -eq 0 ] && [ ! -s "$gh_log" ] && [[ "$out" == *"タグ付けをスキップします"* ]]; then
    report ok "$1"
  else
    report ng "$1" "期待: タグを作らずにスキップ"
  fi
}

# expect_fail <説明>: タグを作らず、スキップもせず、失敗で終わること。
expect_fail() {
  run_auto_tag
  if [ "$status" -ne 0 ] && [ ! -s "$gh_log" ] && [[ "$out" != *"タグ付けをスキップします"* ]]; then
    report ok "$1"
  else
    report ng "$1" "期待: タグを作らずに失敗"
  fi
}

# --- タグを打たない変更 ---
new_repo
touch_file README.md
commit "docs: README を更新"
expect_skip "CI 定義以外の変更だけならスキップする"

new_repo
touch_file .github/workflows/release.yml
commit "ci: 配布しないワークフローを変更"
expect_skip "workflow_call を持たないワークフローの変更だけならスキップする"

new_repo
put_internal .github/workflows/lint-test.yml
commit "test: 配布しないワークフローを追加"
expect_skip "workflow_call を持たないワークフローの追加だけならスキップする"

new_repo
git -C "$repo" rm -q .github/workflows/release.yml
commit "ci: 配布しないワークフローを削除"
expect_skip "workflow_call を持たないワークフローの削除だけならスキップする"

new_repo
git -C "$repo" mv .github/workflows/release.yml .github/workflows/publish.yml
commit "ci: 配布しないワークフローをリネーム"
expect_skip "workflow_call を持たないワークフローのリネームだけならスキップする"

# --- タグを打つ変更 ---
new_repo
touch_file .github/workflows/lint.yml
commit "fix: reusable workflow を修正"
expect_tag "reusable workflow の変更ならタグを打つ (fix は patch)" v1.0.1

new_repo
touch_file .github/workflows/lint.yml
touch_file .github/workflows/release.yml
commit "fix: reusable と配布しないワークフローを同時に変更"
expect_tag "配布しないワークフローと reusable を同時に変えたらタグを打つ" v1.0.1

new_repo
put_reusable .github/workflows/format.yml
commit "feat: reusable workflow を追加"
expect_tag "reusable workflow の追加ならタグを打つ (feat は minor)" v1.1.0

new_repo
git -C "$repo" rm -q .github/workflows/lint.yml
commit "feat!: reusable workflow を削除"
expect_tag "reusable workflow の削除ならタグを打つ (! は major)" v2.0.0

new_repo
put_internal .github/workflows/lint.yml
commit "fix: reusable workflow から workflow_call を外す"
expect_tag "workflow_call を外す変更ならタグを打つ" v1.0.1

new_repo
put_reusable .github/workflows/release.yml
commit "fix: 配布しないワークフローに workflow_call を足す"
expect_tag "workflow_call を足す変更ならタグを打つ" v1.0.1

# git がリネームとして検出する (内容がほぼ同じ) 形にする。リネーム検出が効いたままだと
# 差分に新パスしか出ず、変更前に reusable だったことを見落とす。
new_repo
put .github/workflows/lint.yml <<'EOF'
on:
  workflow_call:
  push:
jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: echo lint
      - run: echo done
EOF
commit "fix: reusable workflow を修正"
git -C "$repo" tag v1.0.1
git -C "$repo" mv .github/workflows/lint.yml .github/workflows/check.yml
grep -v 'workflow_call' "$repo/.github/workflows/check.yml" > "$tmp/check.yml"
mv "$tmp/check.yml" "$repo/.github/workflows/check.yml"
commit "fix: reusable workflow をリネームして workflow_call を外す"
expect_tag "reusable workflow をリネームして workflow_call を外したらタグを打つ" v1.0.2

new_repo
touch_file .github/actions/setup/action.yml
commit "fix: composite action を修正"
expect_tag "composite action の変更ならタグを打つ" v1.0.1

new_repo
put .github/workflows/list.yml <<'EOF'
on: [push, workflow_call]
jobs: {}
EOF
commit "fix: on を配列で書いた reusable workflow を追加"
expect_tag "on が配列でも workflow_call を見つける" v1.0.1

new_repo
put .github/workflows/broken.yml <<'EOF'
on: [push
jobs: {}
EOF
commit "fix: YAML として読めないワークフローを追加"
expect_tag "YAML として読めないワークフローは配布物として扱い、タグを打つ" v1.0.1

new_repo
put .github/workflows/notes.txt <<'EOF'
memo
EOF
commit "fix: YAML 以外のファイルを追加"
expect_tag "workflows 配下の YAML 以外のファイルは従来どおり対象にする" v1.0.1

# --- 既存タグが無い初回リリース ---
new_repo
git -C "$repo" tag -d v1.0.0 > /dev/null
expect_tag "初回リリース: reusable workflow があればタグを打つ" v0.0.1

new_repo
git -C "$repo" tag -d v1.0.0 > /dev/null
git -C "$repo" rm -q -r .github/workflows/lint.yml .github/actions
commit "chore: 配布物を削除"
expect_skip "初回リリース: 配布しないワークフローしか無ければスキップする"

# --- 失敗で終わるべき経路 ---
# git diff が失敗したとき、差分なしと見なして「スキップ」で正常終了しないこと
# (タグを打たない側へ無言で倒れる)。git のスタブは diff だけを失敗させ、ほかは本物へ渡す。
# フィクスチャを作る git と HEAD_SHA の算出は run_auto_tag の env の外で動くため、
# スタブの影響を受けない。
new_repo
touch_file .github/workflows/lint.yml
commit "fix: reusable workflow を修正"
real_git="$(command -v git)"
cat > "$tmp/stub/git" <<EOF
#!/bin/sh
if [ "\$1" = diff ]; then
  echo "fatal: stub" >&2
  exit 128
fi
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/stub/git"
expect_fail "git diff が失敗したらスキップせずに失敗する"
rm "$tmp/stub/git"

echo ""
if [ "$total" -eq 0 ]; then
  echo "テストを 1 件も実行していません" >&2
  exit 2
fi
echo "${total} 件中 ${failed} 件失敗"
[ "$failed" -eq 0 ]
