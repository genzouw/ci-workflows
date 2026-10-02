#!/usr/bin/env bash
#
# free-policy.yml の検出ロジックをフィクスチャで検証する。
#
# ワークフローの `run:` を yq で取り出し、一時ディレクトリに作った git リポジトリで
# そのまま実行して、終了コードと検出行を期待値と突き合わせる。スクリプトを複製せず
# ワークフローから取り出すのは、テスト対象と実物がずれないようにするため。
#
# フィクスチャはこのスクリプトが実行時に生成する。`.github/` 配下の YAML や
# `*/action.yml` としてリポジトリに置くと、本リポジトリのセルフスキャンが
# フィクスチャ自体を違反として検出するため。
#
# 使い方:
#   bash tests/free-policy.sh
#
# 環境変数:
#   FREE_POLICY_TEST_AWKS  検証に使う awk 実装 (空白区切り)。既定は awk / gawk / mawk の
#                          うち PATH にあるもの。指定した実装が無ければ失敗する。

set -euo pipefail

# 取り出した run: は mapfile と、空配列の "${a[@]}" 展開 (set -u 下) を使う。
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  echo "bash 4.4 以上が必要です (現在: ${BASH_VERSION})" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/free-policy.yml"
step_name='Scan CI definitions for free-only policy violations'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

scan="$tmp/scan.sh"
STEP_NAME="$step_name" yq -r \
  '.jobs.free-policy.steps[] | select(.name == strenv(STEP_NAME)) | .run' "$workflow" > "$scan"
if ! grep -q 'set -euo pipefail' "$scan"; then
  echo "free-policy.yml から run: を取り出せませんでした (ステップ名: ${step_name})" >&2
  exit 2
fi

# --- フィクスチャ ---------------------------------------------------------

# put <リポジトリ> <パス>: 標準入力の内容をファイルに書く。
put() {
  mkdir -p "$(dirname "$1/$2")"
  cat > "$1/$2"
}

# 走査対象は `git ls-files` で決まるため、インデックスに載せる (コミットは不要)。
init_repo() {
  git -C "$1" init -q
  git -C "$1" add -A
}

# 違反を含むリポジトリ。行番号は下の期待値と対応しているので、行を足すときは末尾に足す。
violations="$tmp/violations"
put "$violations" .github/workflows/ci.yml <<'EOF'
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      TOKEN: ${{ secrets.github_token }}
      ROLE: ${{ secrets.AWS_ROLE_ARN }}
      HOST: ${{ secrets['DEPLOY_HOST'] }}
      UPPER: ${{ SECRETS.DEPLOY_HOST }}
      EXTRA: ${{ secrets.GITHUB_TOKEN_EXTRA }}
      DYNAMIC: ${{ secrets[format('{0}', matrix.name)] }}
      WHOLE: ${{ toJSON(secrets) }}
      LITERAL: ${{ fromJSON('{"a":{"b":1}}').x || secrets.AWS_ROLE_ARN }}
      MULTI: ${{
        secrets.AWS_ROLE_ARN
        }}
      OTHER: ${{ steps.x.outputs.secrets.foo }}
      MARKED: ${{ secrets.UNLISTED }} # free-policy: allow テスト用の例外
    steps:
      - run: python -c "import secrets; print(f'EOF_{secrets.token_hex(8)}')"
      - run: cp .secrets.baseline /tmp/x
      - run: echo "$OPENAI_API_KEY"
      - run: echo "$REVIEWDOG_GITHUB_API_TOKEN"
      - run: curl https://api.openai.com/v1/models
  deploy:
    uses: ./.github/workflows/deploy.yml
    secrets: inherit
EOF
# パスに = を含む走査対象。awk は「名前=値」の形の引数を変数代入として扱う。
put "$violations" k=v/action.yml <<'EOF'
name: sample
runs:
  using: composite
  steps:
    - run: echo "${{ secrets.AWS_ROLE_ARN }} $MISTRAL_API_KEY"
      shell: bash
EOF
# リポジトリルート直下の Renovate 設定。
put "$violations" renovate.json <<'EOF'
{
  "hostRules": [
    { "matchHost": "example.com", "token": "{{ secrets.RENOVATE_NPM }}" }
  ]
}
EOF
# 不正な UTF-8 バイト (Latin-1 の 1 バイト) を含む行。
# shellcheck disable=SC2016 # 式と変数名は展開させず、文字列のままフィクスチャに書く。
printf '# \351 %s $GROQ_API_KEY https://api.groq.com\n' '${{ secrets.LATIN1 }}' \
  | put "$violations" .github/workflows/latin1.yml
# 走査対象外 (ポリシー解説や CI 定義でない YAML)。検出されてはならない。
put "$violations" README.md <<'EOF'
`${{ secrets.OPENAI_API_KEY }}` は使えません (https://api.openai.com)。
EOF
put "$violations" docs/ci.yml <<'EOF'
env:
  KEY: ${{ secrets.OPENAI_API_KEY }}
EOF
# 行内マーカー付きの行。
# ci.yml の MARKED は検出 1 の除外しか通らないため、secrets: inherit と検出 2 の除外を
# ここで通す。別ファイルにしているのは、ci.yml の行番号と期待値を動かさないため。
#   4 行目・9 行目: 除外される (プロバイダ名を含まない鍵名 / secrets: inherit)
#   5〜7 行目: マーカーがあっても除外されない (プロバイダ名付きの鍵名・課金 API の
#             ホスト名・小文字で書いたプロバイダ名付きの Secret 名)
#   12 行目: 除外される (プロバイダ名を名前の途中に含むだけの鍵名。ALEXA の EXA)
#   13〜15 行目: マーカーがあっても除外されない (動的な添字・secrets コンテキスト全体の
#               参照・静的な参照と動的な添字が同じ式にある行)
# 行番号は下の期待値と対応しているので、行を足すときは末尾に足す。
put "$violations" .github/workflows/marked.yml <<'EOF'
jobs:
  build:
    steps:
      - run: echo "$VENDOR_API_TOKEN" # free-policy: allow テスト用の例外
      - run: echo "$COHERE_API_KEY" # free-policy: allow テスト用の例外
      - run: curl https://api.mistral.ai/v1/models # free-policy: allow テスト用の例外
      - run: echo "${{ secrets.gemini_api_key }}" # free-policy: allow テスト用の例外
  deploy:
    secrets: inherit # free-policy: allow テスト用の例外
  extra:
    env:
      ALEXA: ${{ secrets.ALEXA_REFRESH_TOKEN }} # free-policy: allow テスト用の例外
      DYNAMIC: ${{ secrets[format('{0}_{1}', 'GEMINI', 'API_KEY')] }} # free-policy: allow テスト用の例外
      WHOLE: ${{ toJSON(secrets) }} # free-policy: allow テスト用の例外
      MIXED: ${{ secrets.UNLISTED || secrets[matrix.name] }} # free-policy: allow テスト用の例外
EOF
init_repo "$violations"

# 違反の無いリポジトリ。
clean="$tmp/clean"
put "$clean" .github/workflows/ci.yml <<'EOF'
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - run: echo ok
EOF
init_repo "$clean"

# 走査対象の無いリポジトリ。
empty="$tmp/empty"
put "$empty" README.md <<'EOF'
# empty
EOF
init_repo "$empty"

# --- 実行と照合 -----------------------------------------------------------

out=""
status=0
run_path="$PATH"
label=""
total=0
failed=0

# run_scan <リポジトリ> [NAME=value ...]: 取り出した run: を実行し、out と status に結果を入れる。
run_scan() {
  local dir="$1"
  shift
  # run: は mktemp -d した作業ディレクトリを消さない (ランナーは使い捨てのため)。
  # TMPDIR を $tmp に向けて、このスクリプトの trap でまとめて消す。
  # ジョブサマリは実行ごとに空にする (run: は追記するため、前の実行の内容が混ざる)。
  : > "$tmp/summary"
  set +e
  out="$(
    cd "$dir" && env -u ENFORCE -u ALLOWED_SECRETS \
      PATH="$run_path" TMPDIR="$tmp" GITHUB_STEP_SUMMARY="$tmp/summary" "$@" bash "$scan" 2>&1
  )"
  status=$?
  set -e
}

# 出力から検出行を「種別 パス:行」の形で取り出す。
# 種別: ref (検出 1 の secrets 参照) / inherit / key (検出 2) / host (検出 3) /
#       unknown (上記以外の見出し。期待値には現れない)
# 検出行には不正な UTF-8 バイトを含むものがあるため、バイト列として読む
# (UTF-8 ロケールの BSD awk は変換に失敗して異常終了する)。
hits() {
  printf '%s\n' "$out" | LC_ALL=C awk '
    /^■ .*secrets 参照/ { kind = "ref"; next }
    /^■ secrets: inherit/ { kind = "inherit"; next }
    /^■ .*変数名/ { kind = "key"; next }
    /^■ .*エンドポイント/ { kind = "host"; next }
    # 上のどれにも合致しない見出しは unknown として出力し、期待値との不一致で落とす。
    # 捨てると、検出を足してケースを足し忘れてもテストが通る。
    /^■ / { kind = "unknown"; next }
    /^$/ { kind = ""; next }
    kind != "" && match($0, /^[^:]+:[0-9]+:/) { print kind " " substr($0, 1, RLENGTH - 1) }
  ' | LC_ALL=C sort
}

report() {
  total=$((total + 1))
  if [ "$1" = ok ]; then
    echo "ok - [$label] $2"
  else
    failed=$((failed + 1))
    echo "not ok - [$label] $2"
    shift 2
    printf '    %s\n' "$@"
    echo "    --- 出力 (終了コード: $status)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

# expect_hits <説明> <期待する終了コード> <期待する検出行>
expect_hits() {
  local want got
  want="$(printf '%s\n' "$3" | sed '/^$/d' | LC_ALL=C sort)"
  got="$(hits)"
  if [ "$status" -eq "$2" ] && [ "$got" = "$want" ]; then
    report ok "$1"
  else
    report ng "$1" "期待する終了コード: $2" "--- 期待する検出行" "$want" "--- 実際の検出行" "$got"
  fi
}

# expect_output <説明> <期待する終了コード> <出力に含まれるべき文字列>
expect_output() {
  if [ "$status" -eq "$2" ] && [[ "$out" == *"$3"* ]]; then
    report ok "$1"
  else
    report ng "$1" "期待する終了コード: $2" "出力に含まれるべき文字列: $3"
  fi
}

# expect_no_chapter <説明>: ログとジョブサマリが AGENTS.md の章番号を案内していないこと。
# 章番号は呼び出し元のリポジトリごとに異なるため、固定の番号を出すと誤った章へ誘導する。
# 「AGENTS.md 1.1」のように数字が直後に続く形と、「AGENTS.md の 1 章」のように
# 同じ行の後ろに「<数字> 章」が続く形を分けて書く。間の文字数を {0,3} のように数えると、
# LC_ALL=C ではバイト数になり、助詞を挟む形の検出が grep の実装 (BSD / GNU) で変わる。
expect_no_chapter() {
  local found
  found="$(printf '%s\n' "$out" | cat - "$tmp/summary" | LC_ALL=C grep -nE 'AGENTS\.md([^0-9]*[0-9]+ *章| *[0-9])' || true)"
  if [ -s "$tmp/summary" ] && [ -z "$found" ]; then
    report ok "$1"
  else
    report ng "$1" "ジョブサマリが空でなく、章番号を含む行が無いことを期待" "--- 章番号を含む行" "$found"
  fi
}

# expect_abort <説明>: 異常終了し、「違反なし」とも報告していないこと。
expect_abort() {
  if [ "$status" -ne 0 ] && [[ "$out" != *"検出されませんでした"* ]]; then
    report ok "$1"
  else
    report ng "$1" "非ゼロの終了コードで、違反なしの報告が無いことを期待"
  fi
}

run_cases() {
  # --- 検出 1〜3 (allowed_secrets なし) ---
  local base_hits='
ref .github/workflows/ci.yml:8
ref .github/workflows/ci.yml:9
ref .github/workflows/ci.yml:10
ref .github/workflows/ci.yml:11
ref .github/workflows/ci.yml:12
ref .github/workflows/ci.yml:13
ref .github/workflows/ci.yml:14
ref .github/workflows/ci.yml:16
ref .github/workflows/latin1.yml:1
ref k=v/action.yml:5
ref .github/workflows/marked.yml:7
ref .github/workflows/marked.yml:13
ref .github/workflows/marked.yml:14
ref .github/workflows/marked.yml:15
ref renovate.json:3
inherit .github/workflows/ci.yml:28
key .github/workflows/ci.yml:23
key .github/workflows/ci.yml:24
key .github/workflows/latin1.yml:1
key .github/workflows/marked.yml:5
key k=v/action.yml:5
host .github/workflows/ci.yml:25
host .github/workflows/latin1.yml:1
host .github/workflows/marked.yml:6
'
  run_scan "$violations"
  expect_hits "allowed_secrets なし: 許可リスト外の参照・鍵名・エンドポイントを検出する" 1 "$base_hits"
  expect_no_chapter "違反時の案内に AGENTS.md の章番号を固定で出さない"
  expect_output "違反時の案内に、マーカーで除外できない行があることを書く" 1 'でも除外できない'
  expect_output "違反時の案内に、動的な secrets 参照はマーカーで除外できないことを書く" 1 'マーカーでは除外できない'

  # --- allowed_secrets あり (カンマ・空白・改行区切り、小文字も可) ---
  run_scan "$violations" ALLOWED_SECRETS=$'aws_role_arn, DEPLOY_HOST\nREVIEWDOG_GITHUB_API_TOKEN'
  expect_hits "allowed_secrets あり: 許可した名前だけが検出 1・検出 2 から外れる" 1 '
ref .github/workflows/ci.yml:11
ref .github/workflows/ci.yml:12
ref .github/workflows/ci.yml:13
ref .github/workflows/latin1.yml:1
ref .github/workflows/marked.yml:7
ref .github/workflows/marked.yml:13
ref .github/workflows/marked.yml:14
ref .github/workflows/marked.yml:15
ref renovate.json:3
inherit .github/workflows/ci.yml:28
key .github/workflows/ci.yml:23
key .github/workflows/latin1.yml:1
key .github/workflows/marked.yml:5
key k=v/action.yml:5
host .github/workflows/ci.yml:25
host .github/workflows/latin1.yml:1
host .github/workflows/marked.yml:6
'

  # --- enforce: false ---
  run_scan "$violations" ENFORCE=false
  expect_hits "enforce: false: 検出内容は変わらず、job は成功する" 0 "$base_hits"
  expect_output "enforce: false: 警告を出す" 0 '::warning::'

  # --- 違反なし・走査対象なし ---
  run_scan "$clean"
  expect_output "違反なし: 成功する" 0 '検出されませんでした'
  run_scan "$empty"
  expect_output "走査対象なし: スキップする" 0 'スキップします'

  # --- allowed_secrets の名前の検証 ---
  run_scan "$clean" ALLOWED_SECRETS=REVIEWDOG_GITHUB_API_TOKEN
  expect_output "allowed_secrets: GITHUB を単語として含む鍵名は指定できる" 0 '検出されませんでした'
  local name
  for name in OPENAI_API_KEY VENDOR_SECRET_KEY HF_TOKEN GITHUB_OPENAI_API_KEY; do
    run_scan "$clean" ALLOWED_SECRETS="$name"
    expect_output "allowed_secrets: 鍵名パターンに合致する名前は設定エラー (${name})" 1 '鍵名パターン'
  done
  run_scan "$clean" ALLOWED_SECRETS=OPENAI_API_KEY ENFORCE=false
  expect_output "allowed_secrets: 設定エラーは enforce: false でも失敗する" 1 '鍵名パターン'
  run_scan "$clean" ALLOWED_SECRETS=bad-name
  expect_output "allowed_secrets: Secret 名として不正な値は設定エラー" 1 '不正な値'

  # --- 走査コマンドの異常終了を「違反なし」にしない ---
  # awk は検出 1 と検出 2 で別々に呼ばれる。常に失敗するスタブだと、片方の呼び出しだけが
  # 異常終了を握りつぶしていても、もう片方で job が失敗して見分けられない。
  # そのため、指定した awk スクリプトの実行だけを失敗させ、他は本物の awk に渡す。
  local saved_path="$run_path" real_awk script
  real_awk="$(PATH="$run_path" command -v awk)"
  # 3 つ目は行内マーカーの除外 (drop_marked)。awk スクリプトのファイルを持たないため、
  # プログラム中のマーカー文字列で見分ける。
  local stub_seq=0 stub_dir
  for script in secrets-ref.awk key-name.awk 'free-policy: allow'; do
    # ディレクトリ名に見分け用の文字列を使わない (: を含むと PATH の区切りと衝突する)。
    stub_seq=$((stub_seq + 1))
    stub_dir="$tmp/stub-awk-$stub_seq"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/awk" <<EOF
#!/bin/sh
case "\$*" in *"$script"*) exit 2 ;; esac
exec "$real_awk" "\$@"
EOF
    chmod +x "$stub_dir/awk"
    run_path="$stub_dir:$saved_path"
    run_scan "$clean"
    expect_abort "awk (${script}) が異常終了したら job が失敗する"
    run_path="$saved_path"
  done

  mkdir -p "$tmp/stub-grep"
  printf '#!/bin/sh\nexit 2\n' > "$tmp/stub-grep/grep"
  chmod +x "$tmp/stub-grep/grep"
  run_path="$tmp/stub-grep:$saved_path"
  run_scan "$clean"
  expect_abort "grep が異常終了したら job が失敗する"
  run_path="$saved_path"
}

# --- awk 実装ごとに実行 -----------------------------------------------------

if [ -n "${FREE_POLICY_TEST_AWKS:-}" ]; then
  read -ra awks <<< "$FREE_POLICY_TEST_AWKS"
else
  awks=()
  for impl in awk gawk mawk; do
    if command -v "$impl" > /dev/null; then
      awks+=("$impl")
    fi
  done
fi

for impl in "${awks[@]}"; do
  if ! impl_path="$(command -v "$impl")"; then
    echo "awk 実装が見つかりません: ${impl}" >&2
    exit 2
  fi
  mkdir -p "$tmp/bin-$impl"
  ln -s "$impl_path" "$tmp/bin-$impl/awk"
  run_path="$tmp/bin-$impl:$PATH"
  label="$impl"
  echo "# awk 実装: ${impl} (${impl_path})"
  run_cases
done

echo ""
echo "${total} 件中 ${failed} 件失敗 (awk 実装: ${awks[*]})"
# awk 実装が 1 つも選ばれないと 1 件も実行しないまま failed が 0 になる。
# 何も検証していない実行を成功にしない。
if [ "$total" -eq 0 ]; then
  echo "テストを 1 件も実行していません (awk 実装が見つかりません)" >&2
  exit 2
fi
[ "$failed" -eq 0 ]
