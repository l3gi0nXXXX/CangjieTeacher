#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export DYLD_LIBRARY_PATH="${MAGIC_PATH}/libs/cangjie-stdx-mac-aarch64-1.0.0.1/darwin_aarch64_llvm/dynamic/stdx:${CANGJIE_HOME}/runtime/lib/darwin_aarch64_llvm:/opt/homebrew/opt/openssl@3/lib:${DYLD_LIBRARY_PATH:-}"
cli="$repo_root/cli/target/release/bin/main"
root=$(mktemp -d /tmp/cangjie-teacher-cli-e2e.XXXXXX)
trap 'rm -rf "$root"' EXIT
dataset="$root/dataset"
artifacts="$root/教师🙂-artifacts"
mkdir -p "$dataset/CJ-HUMANEVAL-000/starter/src" "$dataset/CJ-HUMANEVAL-000/tests"
cat > "$dataset/CJ-HUMANEVAL-000/starter/cjpm.toml" <<'EOF'
[package]
  cjc-version = "1.0.0"
  name = "cangjie_humaneval_000"
  version = "0.1.0"
  output-type = "static"
EOF
cat > "$dataset/CJ-HUMANEVAL-000/starter/src/solution.cj" <<'EOF'
package cangjie_humaneval_000
public func addOne(value: Int64): Int64 { value }
EOF
cat > "$dataset/CJ-HUMANEVAL-000/tests/cjpm.executable.toml" <<'EOF'
[package]
  cjc-version = "1.0.0"
  name = "cangjie_humaneval_000"
  version = "0.1.0"
  output-type = "executable"
EOF
cat > "$dataset/CJ-HUMANEVAL-000/tests/TestMain.cj" <<'EOF'
package cangjie_humaneval_000
main(): Int64 { if (addOne(1) == 2) { 0 } else { 1 } }
EOF
starter_hash=$($cli hash-directory --starter-root "$dataset/CJ-HUMANEVAL-000/starter")
manifest="$root/model.jsonl"
: > "$manifest"
i=0
while test "$i" -lt 164; do
  id=$(printf 'CJ-HUMANEVAL-%03d' "$i")
  printf '%s\n' "{\"schemaVersion\":\"cangjie-humaneval-model-v1\",\"caseId\":\"$id\",\"datasetVersion\":\"fixture-v1\",\"targetVersion\":\"1.0.0\",\"signature\":\"func addOne(value: Int64): Int64\",\"prompt\":\"Return the input plus one.\",\"promptHash\":\"prompt-$i\",\"starterHash\":\"$starter_hash\",\"requiredKnowledgeTags\":[\"Int64\"]}" >> "$manifest"
  i=$((i + 1))
done
checksum=$(sed '${/^$/d;}' "$manifest" | awk 'BEGIN{first=1}{if(!first)printf "\n";printf "%s",$0;first=0}' | shasum -a 256 | awk '{print $1}')
chmod +x "$repo_root/test/fixtures/fake_codex.sh"
output=$($cli run --manifest "$manifest" --checksum "$checksum" --root "$artifacts" --repo-root "$repo_root" --local-only --starter-root "$dataset" --tests-root "$dataset" --codex "$repo_root/test/fixtures/fake_codex.sh" --model gpt-5.6-sol --run-id e2e --case-id CJ-HUMANEVAL-000)
printf '%s\n' "$output"
test "$output" = 'teacher runId=e2e total=1 complete=1'
test "$(stat -f %Lp "$artifacts")" = '700'
test ! -e "$artifacts/runs/e2e/sessions/CJ-HUMANEVAL-000/leak.marker"
test ! -e "$artifacts/runs/e2e/sessions/CJ-HUMANEVAL-000/prompt.marker"
test -f "$artifacts/teacher-solutions/CJ-HUMANEVAL-000/src/solution.cj"
test ! -e "$artifacts/teacher-solutions/CJ-HUMANEVAL-000/src/TestMain.cj"
test -f "$artifacts/runs/e2e/evidence/CJ-HUMANEVAL-000/index.tsv"
grep -q fake_generation_completed "$artifacts/runs/e2e/evidence/CJ-HUMANEVAL-000/generation.txt"
attempt_manifest="$artifacts/runs/e2e/attempts/CJ-HUMANEVAL-000/attempt-1.manifest"
attempt_snapshot="$artifacts/runs/e2e/attempts/CJ-HUMANEVAL-000/attempt-1/src/solution.cj"
test -f "$attempt_manifest"
test -f "$attempt_snapshot"
grep -q 'verified' "$attempt_manifest"
grep -Fq 'value + 1' "$attempt_snapshot"

inside_repo="$repo_root/test/.teacher-artifacts-must-not-exist"
rm -rf "$inside_repo"
if rejected=$($cli run --manifest "$manifest" --checksum "$checksum" --root "$inside_repo" --repo-root "$repo_root" --local-only --starter-root "$dataset" --tests-root "$dataset" --codex "$repo_root/test/fixtures/fake_codex.sh" --model gpt-5.6-sol --run-id rejected --case-id CJ-HUMANEVAL-000 2>&1); then
  printf '%s\n' 'expected repository-contained artifact root to be rejected' >&2
  exit 1
fi
test "$rejected" = 'teacher failed diagnostic=teacher_artifact_root_not_private'
test ! -e "$inside_repo"
